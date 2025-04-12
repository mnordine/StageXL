part of '../engine.dart';

class RenderProgramBatch extends RenderProgram {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexColor:      Float32(r), Float32(g), Float32(b), Float32(a)
  // aVertexTexIndex:   Float32(textureIndex)

  static int _maxTextures = 8; // Default value, will be updated at runtime

  static void initializeMaxTextures(WebGL renderingContext) {
    _maxTextures = (renderingContext.getParameter(WebGL.MAX_TEXTURE_IMAGE_UNITS) as JSNumber?)?.toDartInt ?? 8;
    print('max texture units: $_maxTextures');
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
    // CHANGE: Use int for texture index in WebGL 2
    in int aVertexTexIndex;

    out vec2 vTextCoord;
    out vec4 vColor;
    // CHANGE: Use flat interpolation for integer varying
    flat out int vTexIndex;

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
    if (isWebGL2) {
      // For WebGL2, use individual samplers for clarity and compatibility
      // Use simple integer equality to select texture sampler
      final sb = StringBuffer();
      for (var i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        sb.write('''
        if (vTexIndex == $i) { // Direct integer comparison
          vec4 textureColor = texture(uSampler$i, vTextCoord);
          fragColor = textureColor * vColor;
        }''');
      }
      // We still need a fallback case, but now just use transparent black
      sb.write('''
        else {
          fragColor = vec4(0.0, 0.0, 0.0, 0.0);
        }''');

      final samplerDeclarations = List.generate(_maxTextures, (i) => 'uniform sampler2D uSampler$i;').join('\n');

      return '''
      #version 300 es

      precision ${RenderProgram.fragmentPrecision} float;

      $samplerDeclarations

      in vec2 vTextCoord;
      in vec4 vColor;
      flat in int vTexIndex;

      out vec4 fragColor;

      void main() {
        $sb
      }
      ''';
    } else {
      final sb = StringBuffer();
      for (var i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        sb.write('''
        if (int(vTexIndex+0.1) == $i) {
          vec4 textureColor = texture2D(uSampler$i, vTextCoord);
          gl_FragColor = textureColor * vColor;
        }''');
      }
      // We still need a fallback case, but now just use transparent black
      sb.write('''
        else {
          gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        }''');

      final samplerDeclarations = List.generate(_maxTextures, (i) => 'uniform sampler2D uSampler$i;').join('\n');

      return '''
      precision ${RenderProgram.fragmentPrecision} float;

      $samplerDeclarations

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

    if (isWebGL2) {
      // In WebGL 2, use individual samplers for clarity and compatibility
      for (var i = 0; i < _maxTextures; i++) {
        final uniformName = 'uSampler$i';
        if (uniforms.containsKey(uniformName)) {
          renderingContext.uniform1i(uniforms[uniformName], i);
        }
      }
    } else {
      // In WebGL 1, we need to set each sampler separately
      for (var i = 0; i < _maxTextures; i++) {
        renderingContext.uniform1i(uniforms['uSampler$i'], i);
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
    if (location == null) {
      // This can happen if the attribute is unused and optimized out by the shader compiler.
      // It's not necessarily an error, but indicates the batching logic might not be fully utilized.
      // print("Warning: aVertexTexIndex attribute location not found. Shader might have optimized it out.");
      return;
    }

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
      // Update Int32List view cache before flushing if needed
      if (isWebGL2 && _vxDataIntView == null) {
         _vxDataIntView = renderBufferVertex.data.buffer.asInt32List();
      }
      super.flush(); // This handles the actual drawing
      _clearTextures();
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
  
  void _bindTextureToSlot(RenderContextWebGL renderContext, RenderTexture texture, int index) {
    _textures[index] = texture;
    // Use the context's activation method which handles flushing if needed,
    // although ideally we flushed *before* calling this if index was 0.
    // It also ensures the texture is correctly activated on the GPU texture unit.
    renderContext.activateRenderTextureAt(texture, index);
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
    
    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(texture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush(); // Flush if no slots (or this specific texture) are available
      textureIndex = 0; // After flush, slot 0 is always available
      // We MUST bind the texture now after the flush
      _bindTextureToSlot(renderContext, texture, textureIndex);
    } else if (_textures[textureIndex] == null) {
      // Texture slot is available but not yet bound for this texture
      _bindTextureToSlot(renderContext, texture, textureIndex);
    }
    // If textureIndex >= 0 and _textures[textureIndex] is already the correct texture, do nothing.

    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;
    const vertexFloatCount = 9; // Stride in floats

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) {
       flush();
       // Re-bind texture after flush if needed (textureIndex might change, but will be 0)
       textureIndex = 0;
       _bindTextureToSlot(renderContext, texture, textureIndex);
    }

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
     // Check based on float count
    if (vxPosition + vxListCount * vertexFloatCount >= vxData.length) {
       flush();
       // Re-bind texture after flush if needed
       textureIndex = 0;
       _bindTextureToSlot(renderContext, texture, textureIndex);
    }

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
    // currentVxIndex += vertexFloatCount; // No need to increment after last vertex

    renderBufferVertex.position += vxListCount * vertexFloatCount;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTexture renderTexture, Int16List ixList, Float32List vxList,
      num r, num g, num b, num a) {

    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(renderTexture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush();
      textureIndex = 0;
      _bindTextureToSlot(renderContext, renderTexture, textureIndex);
    } else if (_textures[textureIndex] == null) {
      _bindTextureToSlot(renderContext, renderTexture, textureIndex);
    }

    final matrix = renderState.globalMatrix;
    final alpha = renderState.globalAlpha;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2; // Input vxList has 4 floats (x,y,u,v)
    const vertexFloatCount = 9; // Output vertex has 9 floats

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) {
       flush();
       textureIndex = 0;
       _bindTextureToSlot(renderContext, renderTexture, textureIndex);
    }

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * vertexFloatCount >= vxData.length) {
       flush();
       textureIndex = 0;
       _bindTextureToSlot(renderContext, renderTexture, textureIndex);
    }

    // Get potentially updated buffer positions and counts after flush checks
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

  //---------------------------------------------------------------------------

  /// Render a quad with a color tint
  void renderTextureQuadTinted(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTextureQuad renderTextureQuad, num r, num g, num b, num a) {

    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, renderContext,
          renderTextureQuad.renderTexture, ixList, vxList, r, g, b, a);
      return;
    }

    final texture = renderTextureQuad.renderTexture;
    
    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(texture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush();
      textureIndex = 0; // After flushing, slot 0 is guaranteed to be available
    }
    
    // Now we can bind the texture to a slot
    if (_textures[textureIndex] == null) {
      _bindTextureToSlot(renderContext, texture, textureIndex);
    }
    
    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 9 >= vxData.length) flush();

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
    final texIdx = textureIndex.toDouble();

    // Vertex 0
    vxData[vxIndex + 00] = ma1 + mc1;                       // x
    vxData[vxIndex + 01] = mb1 + md1;                       // y
    vxData[vxIndex + 02] = vxList[2];                       // u
    vxData[vxIndex + 03] = vxList[3];                       // v
    vxData[vxIndex + 04] = colorR;                          // r
    vxData[vxIndex + 05] = colorG;                          // g
    vxData[vxIndex + 06] = colorB;                          // b
    vxData[vxIndex + 07] = colorA;                          // a
    vxData[vxIndex + 08] = texIdx;                          // texture index

    // Vertex 1
    vxData[vxIndex + 09] = ma2 + mc1;                       // x
    vxData[vxIndex + 10] = mb2 + md1;                       // y
    vxData[vxIndex + 11] = vxList[6];                       // u
    vxData[vxIndex + 12] = vxList[7];                       // v
    vxData[vxIndex + 13] = colorR;                          // r
    vxData[vxIndex + 14] = colorG;                          // g
    vxData[vxIndex + 15] = colorB;                          // b
    vxData[vxIndex + 16] = colorA;                          // a
    vxData[vxIndex + 17] = texIdx;                          // texture index

    // Vertex 2
    vxData[vxIndex + 18] = ma2 + mc2;                       // x
    vxData[vxIndex + 19] = mb2 + md2;                       // y
    vxData[vxIndex + 20] = vxList[10];                      // u
    vxData[vxIndex + 21] = vxList[11];                      // v
    vxData[vxIndex + 22] = colorR;                          // r
    vxData[vxIndex + 23] = colorG;                          // g
    vxData[vxIndex + 24] = colorB;                          // b
    vxData[vxIndex + 25] = colorA;                          // a
    vxData[vxIndex + 26] = texIdx;                          // texture index

    // Vertex 3
    vxData[vxIndex + 27] = ma1 + mc2;                       // x
    vxData[vxIndex + 28] = mb1 + md2;                       // y
    vxData[vxIndex + 29] = vxList[14];                      // u
    vxData[vxIndex + 30] = vxList[15];                      // v
    vxData[vxIndex + 31] = colorR;                          // r
    vxData[vxIndex + 32] = colorG;                          // g
    vxData[vxIndex + 33] = colorB;                          // b
    vxData[vxIndex + 34] = colorA;                          // a
    vxData[vxIndex + 35] = texIdx;                          // texture index

    renderBufferVertex.position += vxListCount * 9;
    renderBufferVertex.count += vxListCount;
  }

  // Helper to write texture index based on WebGL version
  void _writeTextureIndex(Float32List vxData, int floatIndex, int textureIndex) {
    if (isWebGL2) {
      // Ensure the Int32List view is available
      _vxDataIntView ??= vxData.buffer.asInt32List();
      // Write the integer value directly using the Int32List view.
      // The floatIndex corresponds directly to the intIndex here because
      // both Float32 and Int32 are 4 bytes.
      _vxDataIntView![floatIndex] = textureIndex;
    } else {
      // Write the index as a float for WebGL 1
      vxData[floatIndex] = textureIndex.toDouble();
    }
  }
}
