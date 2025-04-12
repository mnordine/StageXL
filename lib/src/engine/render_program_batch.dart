part of '../engine.dart';

class RenderProgramBatch extends RenderProgram {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexColor:      Float32(r), Float32(g), Float32(b), Float32(a)
  // aVertexTexIndex:   WebGL2: Int32(textureIndex), WebGL1: Float32(textureIndex)

  static int _maxTextures = 8; // Default value, will be updated at runtime
  // Reintroduce sampler indices cache for WebGL 2 sampler array uniform
  static Uint32List? _samplerIndices;

  static void initializeMaxTextures(WebGL renderingContext) {
    _maxTextures = (renderingContext.getParameter(WebGL.MAX_TEXTURE_IMAGE_UNITS) as JSNumber?)?.toDartInt ?? 8;
    // Limit max textures if necessary (optional)
    // _maxTextures = math.min(_maxTextures, 16);
    print('StageXL Batch Renderer - Max texture units: $_maxTextures');
    // Pre-calculate the sampler indices list for WebGL 2
    _samplerIndices = Uint32List.fromList(List.generate(_maxTextures, (i) => i, growable: false));
  }

  late final List<RenderTexture?> _textures = List.filled(_maxTextures, null);

  // Cache for Int32List view to avoid recreation
  Int32List? _vxDataIntView;

  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;
    in vec4 aVertexColor;
    in int aVertexTexIndex; // Use int for texture index in WebGL 2

    out vec2 vTextCoord;
    out vec4 vColor;
    flat out int vTexIndex; // Use flat interpolation for integer varying

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      vTexIndex = aVertexTexIndex;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    attribute vec2 aVertexPosition;
    attribute vec2 aVertexTextCoord;
    attribute vec4 aVertexColor;
    attribute float aVertexTexIndex;
    varying vec2 vTextCoord;
    varying vec4 vColor;
    varying float vTexIndex;

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      vTexIndex = aVertexTexIndex;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  @override
  String get fragmentShaderSource {
    final sb = StringBuffer();

    if (isWebGL2) {
      // WebGL 2: Use sampler array declaration but with branching for lookup
      final samplerDeclaration = 'uniform sampler2D uSamplers[$_maxTextures];';

      for (var i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        // Use branching to access the sampler array element
        sb.write('''
        if (vTexIndex == $i) {
          fragColor = texture(uSamplers[$i], vTextCoord) * vColor;
        }''');
      }
      // Fallback (Magenta for debugging)
      sb.write('''
        else {
          fragColor = vec4(1.0, 0.0, 1.0, 1.0);
        }''');

      return '''
      #version 300 es

      precision ${RenderProgram.fragmentPrecision} float;

      $samplerDeclaration // Use sampler array

      in vec2 vTextCoord;
      in vec4 vColor;
      flat in int vTexIndex;

      out vec4 fragColor;

      void main() {
        $sb
      }
      ''';
    } else {
      // WebGL 1: Use individual samplers and float range comparison (unchanged)
      final samplerDeclarations = List.generate(_maxTextures, (i) => 'uniform sampler2D uSampler$i;').join('\n');

      for (var i = 0; i < _maxTextures; i++) {
        final iFloat = i.toDouble();
        if (i > 0) sb.write('else ');
        sb.write('''
        if (vTexIndex >= ${iFloat - 0.1} && vTexIndex <= ${iFloat + 0.1}) {
          gl_FragColor = texture2D(uSampler$i, vTextCoord) * vColor;
        }''');
      }
      // Fallback (Magenta for debugging)
      sb.write('''
        else {
          gl_FragColor = vec4(1.0, 0.0, 1.0, 1.0);
        }''');

      return '''
      precision ${RenderProgram.fragmentPrecision} float;

      $samplerDeclarations // Use individual samplers

      varying vec2 vTextCoord;
      varying vec4 vColor;
      varying float vTexIndex;

      void main() {
        $sb
      }
      ''';
    }
  }

  //---------------------------------------------------------------------------

  @override
  void activate(RenderContextWebGL renderContext) {
    super.activate(renderContext);

    // --- Set Sampler Uniforms ---
    if (isWebGL2) {
      // WebGL 2: Set the sampler array uniform 'uSamplers'
      // Find the location (might be named 'uSamplers' or 'uSamplers[0]')
      final location = uniforms['uSamplers[0]'] ?? uniforms['uSamplers'];
      if (location != null && _samplerIndices != null) {
        // Pass the array [0, 1, 2, ..., maxTextures-1] to the uniform
        (renderingContext as WebGL2RenderingContext).uniform1iv(location, _samplerIndices!.toJS);
      } else if (location == null) {
         print("Warning: 'uSamplers' uniform not found in WebGL 2 batch program.");
      }
    } else {
      // WebGL 1: Set individual sampler uniforms 'uSampler0', 'uSampler1', ...
      for (var i = 0; i < _maxTextures; i++) {
        final uniformName = 'uSampler$i';
        if (uniforms.containsKey(uniformName)) {
          renderingContext.uniform1i(uniforms[uniformName], i);
        }
      }
    }

    _clearTextures();

    // Invalidate Int32List view cache if context changes
    _vxDataIntView = null;
  }

  @override
  void setupAttributes() {
    // Stride is 36 bytes (vec2 pos, vec2 texCoord, vec4 color, float/int texIndex)
    // 2*4 + 2*4 + 4*4 + 1*4 = 8 + 8 + 16 + 4 = 36
    const stride = 36;
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, stride, 0);  // offset 0 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexTextCoord'], 2, stride, 8); // offset 8 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexColor'], 4, stride, 16); // offset 16 bytes

    final location = attributes['aVertexTexIndex'];
    if (location == null) return; // Optimized out, batching likely unused

    if (isWebGL2) {
      // Use vertexAttribIPointer for integer attributes in WebGL 2
      (renderingContext as WebGL2RenderingContext).vertexAttribIPointer(
          location, 1, WebGL.INT, stride, 32); // offset 32 bytes
    } else {
      // Use vertexAttribPointer for float attribute in WebGL 1
      renderBufferVertex.bindAttribute(location, 1, stride, 32); // offset 32 bytes
    }
  }

  //---------------------------------------------------------------------------

  void _clearTextures() {
    for (var i = 0; i < _maxTextures; i++) {
      _textures[i] = null;
    }
  }

  @override
  void flush() {
    if (renderBufferIndex.position > 0) {
      // Update Int32List view cache before flushing if needed (WebGL2 only)
      if (isWebGL2 && _vxDataIntView == null && renderBufferVertex.position > 0) {
         _vxDataIntView = renderBufferVertex.data.buffer.asInt32List(
             renderBufferVertex.data.offsetInBytes,
             renderBufferVertex.position); // More precise view
      }
      super.flush(); // Handles buffer updates and draw call
      _clearTextures(); // Clear local texture tracking for the new batch
      // Reset Int32List view cache after flush
      _vxDataIntView = null;
    }
  }

  //---------------------------------------------------------------------------

  /// Checks if the given texture is already in a slot or if there's an empty slot.
  /// Returns the texture index if available, or -1 if no slots are available.
  int _getTextureIndexIfAvailable(RenderTexture texture) {
    // First check if the texture is already bound
    for (var i = 0; i < _maxTextures; i++) {
      if (identical(_textures[i], texture)) {
        return i;
      }
    }

    // Find an empty slot
    for (var i = 0; i < _maxTextures; i++) {
      if (_textures[i] == null) {
        return i;
      }
    }

    // No slots available
    return -1;
  }

  //---------------------------------------------------------------------------

  void renderTextureQuad(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTextureQuad renderTextureQuad, [num r = 1, num g = 1, num b = 1, num a = 1]) {

    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, renderContext,
          renderTextureQuad.renderTexture, ixList, vxList, r, g, b, a);
      return;
    }

    final texture = renderTextureQuad.renderTexture;
    var textureIndex = _getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex < 0) {
      // No slot available OR texture not found -> Need to Flush
      needsFlush = true;
      textureIndex = 0; // Will use slot 0 after flush
    } else if (_textures[textureIndex] == null) {
      // Slot is available but empty -> Assign and activate texture directly (NO FLUSH)
      _textures[textureIndex] = texture;
      // Activate texture in its assigned GPU slot without flushing batch
      texture.activate(renderContext, WebGL.TEXTURE0 + textureIndex);
    }
    // Else: Texture is already in the slot and active, do nothing for texture binding.

    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;
    const vertexFloatCount = 9; // Stride in floats

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (!needsFlush && ixPosition + ixListCount >= ixData.length) {
       needsFlush = true;
       textureIndex = 0; // Will use slot 0 after flush
    }

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (!needsFlush && vxPosition + vxListCount * vertexFloatCount >= vxData.length) {
       needsFlush = true;
       textureIndex = 0; // Will use slot 0 after flush
    }

    // --- Flush if Needed ---
    if (needsFlush) {
        flush(); // Flush the current batch
        // Now, assign and activate the texture for the *new* batch in slot 0
        _textures[textureIndex] = texture; // textureIndex is 0 here
        texture.activate(renderContext, WebGL.TEXTURE0 + textureIndex);
        // Buffer positions/counts are reset internally by flush/super.flush
    }

    // Get potentially updated buffer positions and counts AFTER flush checks
    final ixIndex = renderBufferIndex.position;
    final vxIndex = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // copy index list
    ixData[ixIndex + 0] = vxCount + 0;
    ixData[ixIndex + 1] = vxCount + 1;
    ixData[ixIndex + 2] = vxCount + 2;
    ixData[ixIndex + 3] = vxCount + 0;
    ixData[ixIndex + 4] = vxCount + 2;
    ixData[ixIndex + 5] = vxCount + 3;

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list
    final ma1 = vxList[0] * matrix.a + matrix.tx;
    final ma2 = vxList[8] * matrix.a + matrix.tx;
    final mb1 = vxList[0] * matrix.b + matrix.ty;
    final mb2 = vxList[8] * matrix.b + matrix.ty;
    final mc1 = vxList[1] * matrix.c;
    final mc2 = vxList[9] * matrix.c;
    final md1 = vxList[1] * matrix.d;
    final md2 = vxList[9] * matrix.d;

    final colorA = a * alpha;
    final colorR = r * colorA;
    final colorG = g * colorA;
    final colorB = b * colorA;

    // --- Write Vertex Data ---
    var currentVxIndex = vxIndex; // Use a temporary index for writing

    // Vertex 0
    vxData[currentVxIndex + 0] = ma1 + mc1; // x
    vxData[currentVxIndex + 1] = mb1 + md1; // y
    vxData[currentVxIndex + 2] = vxList[2]; // u
    vxData[currentVxIndex + 3] = vxList[3]; // v
    vxData[currentVxIndex + 4] = colorR;    // r
    vxData[currentVxIndex + 5] = colorG;    // g
    vxData[currentVxIndex + 6] = colorB;    // b
    vxData[currentVxIndex + 7] = colorA;    // a
    // Write texture index (float or int bits) at offset 8
    _writeTextureIndex(vxData, currentVxIndex + 8, textureIndex);
    currentVxIndex += vertexFloatCount;

    // Vertex 1
    vxData[currentVxIndex + 0] = ma2 + mc1; // x
    vxData[currentVxIndex + 1] = mb2 + md1; // y
    vxData[currentVxIndex + 2] = vxList[6]; // u
    vxData[currentVxIndex + 3] = vxList[7]; // v
    vxData[currentVxIndex + 4] = colorR;    // r
    vxData[currentVxIndex + 5] = colorG;    // g
    vxData[currentVxIndex + 6] = colorB;    // b
    vxData[currentVxIndex + 7] = colorA;    // a
    _writeTextureIndex(vxData, currentVxIndex + 8, textureIndex);
    currentVxIndex += vertexFloatCount;

    // Vertex 2
    vxData[currentVxIndex + 0] = ma2 + mc2; // x
    vxData[currentVxIndex + 1] = mb2 + md2; // y
    vxData[currentVxIndex + 2] = vxList[10];// u
    vxData[currentVxIndex + 3] = vxList[11];// v
    vxData[currentVxIndex + 4] = colorR;    // r
    vxData[currentVxIndex + 5] = colorG;    // g
    vxData[currentVxIndex + 6] = colorB;    // b
    vxData[currentVxIndex + 7] = colorA;    // a
    _writeTextureIndex(vxData, currentVxIndex + 8, textureIndex);
    currentVxIndex += vertexFloatCount;

    // Vertex 3
    vxData[currentVxIndex + 0] = ma1 + mc2; // x
    vxData[currentVxIndex + 1] = mb1 + md2; // y
    vxData[currentVxIndex + 2] = vxList[14];// u
    vxData[currentVxIndex + 3] = vxList[15];// v
    vxData[currentVxIndex + 4] = colorR;    // r
    vxData[currentVxIndex + 5] = colorG;    // g
    vxData[currentVxIndex + 6] = colorB;    // b
    vxData[currentVxIndex + 7] = colorA;    // a
    _writeTextureIndex(vxData, currentVxIndex + 8, textureIndex);

    renderBufferVertex.position += vxListCount * vertexFloatCount;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTexture renderTexture, Int16List ixList, Float32List vxList,
      num r, num g, num b, num a) {

    final texture = renderTexture; // Use consistent naming
    var textureIndex = _getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex < 0) {
      needsFlush = true;
      textureIndex = 0;
    } else if (_textures[textureIndex] == null) {
      _textures[textureIndex] = texture;
      texture.activate(renderContext, WebGL.TEXTURE0 + textureIndex);
    }

    final matrix = renderState.globalMatrix;
    final alpha = renderState.globalAlpha;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2; // Input vxList has 4 floats (x,y,u,v)
    const vertexFloatCount = 9; // Output vertex has 9 floats

    // --- Buffer Size Checks ---
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (!needsFlush && ixPosition + ixListCount >= ixData.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (!needsFlush && vxPosition + vxListCount * vertexFloatCount >= vxData.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    // --- Flush if Needed ---
    if (needsFlush) {
        flush();
        _textures[textureIndex] = texture; // textureIndex is 0
        texture.activate(renderContext, WebGL.TEXTURE0 + textureIndex);
    }

    // Get potentially updated buffer positions and counts AFTER flush checks
    final ixIndex = renderBufferIndex.position;
    var vxIndex = renderBufferVertex.position; // Base float index for this mesh
    final vxCount = renderBufferVertex.count;

    // copy index list
    for (var i = 0; i < ixListCount; i++) {
      ixData[ixIndex + i] = vxCount + ixList[i];
    }

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list
    final ma = matrix.a;
    final mb = matrix.b;
    final mc = matrix.c;
    final md = matrix.d;
    final mx = matrix.tx;
    final my = matrix.ty;

    final colorA = a * alpha;
    final colorR = r * colorA;
    final colorG = g * colorA;
    final colorB = b * colorA;

    for (var i = 0, o = 0; i < vxListCount; i++, o += 4) {
      final x = vxList[o + 0];
      final y = vxList[o + 1];
      vxData[vxIndex + 0] = mx + ma * x + mc * y; // x
      vxData[vxIndex + 1] = my + mb * x + md * y; // y
      vxData[vxIndex + 2] = vxList[o + 2];        // u
      vxData[vxIndex + 3] = vxList[o + 3];        // v
      vxData[vxIndex + 4] = colorR;               // r
      vxData[vxIndex + 5] = colorG;               // g
      vxData[vxIndex + 6] = colorB;               // b
      vxData[vxIndex + 7] = colorA;               // a
      // Write texture index (float or int bits) at offset 8
      _writeTextureIndex(vxData, vxIndex + 8, textureIndex);
      vxIndex += vertexFloatCount;
    }

    renderBufferVertex.position += vxListCount * vertexFloatCount;
    renderBufferVertex.count += vxListCount;
  }

  // Helper to write texture index based on WebGL version
  void _writeTextureIndex(Float32List vxData, int floatIndex, int textureIndex) {
    if (isWebGL2) {
      // Ensure the Int32List view is available and correctly sized
      // We get the view just before writing if it's null or potentially stale
      _vxDataIntView ??= vxData.buffer.asInt32List(vxData.offsetInBytes);

      // Write the integer value directly using the Int32List view.
      // floatIndex corresponds directly to the intIndex (Float32/Int32 are 4 bytes).
      // Check bounds defensively, though ideally buffer checks prevent this.
      if (floatIndex < _vxDataIntView!.length) {
         _vxDataIntView![floatIndex] = textureIndex;
      } else {
         print('Warning: Attempted to write texture index out of bounds.');
      }
    } else {
      // Write the index as a float for WebGL 1
      vxData[floatIndex] = textureIndex.toDouble();
    }
  }
}
