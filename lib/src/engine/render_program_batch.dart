part of '../engine.dart';

class _DrawCommand {
  final int indexCount;
  final int indexOffset;
  final BlendMode blendMode;
  final RenderTexture texture;
  final int textureIndex;

  _DrawCommand({
    required this.indexCount,
    required this.indexOffset,
    required this.blendMode,
    required this.texture,
    required this.textureIndex,
  });
}

class RenderProgramBatch extends RenderProgram {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexColor:      Float32(r), Float32(g), Float32(b), Float32(a)
  // aVertexTexIndex:   Float32(textureIndex)

  static int _maxTextures = 8; // Default value, will be updated at runtime
  static JSUint32Array? _samplerIndices;

  static int initializeMaxTextures(WebGL renderingContext, {required bool isWebGL2}) {
    _maxTextures = (renderingContext.getParameter(WebGL.MAX_TEXTURE_IMAGE_UNITS) as JSNumber?)?.toDartInt ?? 8;

    // Cap max texture units, else a large number could result in excessive if/else chains, and the 
    // shader will fail to compile with an "expression too complex" error.
    _maxTextures = math.min(_maxTextures, 16);

    // Pre-calculate the sampler indices list for WebGL 2
    if (isWebGL2) {
      _samplerIndices = Uint32List.fromList(List.generate(_maxTextures, (i) => i, growable: false)).toJS;
    }

    return _maxTextures;
  }

  late final List<RenderTexture?> _textures = List.filled(_maxTextures, null);
  
  final _drawCommands = <_DrawCommand>[];
  RenderContextWebGL? _renderContextWebGL;

  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;
    in vec4 aVertexColor;
    in float aVertexTexIndex;

    out vec2 vTextCoord;
    out vec4 vColor;
    flat out float vTexIndex;

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
        if (textureIndex == $i) {
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

      $samplerDeclaration

      in vec2 vTextCoord;
      in vec4 vColor;
      flat in float vTexIndex;

      out vec4 fragColor;

      void main() {
        int textureIndex = int(vTexIndex);
        $sb
      }
      ''';
    } else {
      // WebGL 1: Use individual samplers and float range comparison.
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
    
    // Store reference to render context for batch operations
    _renderContextWebGL = renderContext;

    if (isWebGL2) {
      // Set the sampler array uniform 'uSamplers'
      // Find the location (might be named 'uSamplers' or 'uSamplers[0]')
      final location = uniforms['uSamplers[0]'] ?? uniforms['uSamplers'];
      if (location != null && _samplerIndices != null) {
        // Pass the array [0, 1, 2, ..., maxTextures-1] to the uniform
        (renderingContext as WebGL2RenderingContext).uniform1iv(location, _samplerIndices!);
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
  }

  @override
  void setupAttributes() {
    // Stride is 36 bytes (vec2 pos, vec2 texCoord, vec4 color, float texIndex)
    // 2*4 + 2*4 + 4*4 + 1*4 = 8 + 8 + 16 + 4 = 36
    const stride = 36;
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, stride, 0);  // offset 0 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexTextCoord'], 2, stride, 8); // offset 8 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexColor'], 4, stride, 16); // offset 16 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexTexIndex'], 1, stride, 32); // offset 32 bytes
  }

  //---------------------------------------------------------------------------

  void _clearTextures() {
    for (var i = 0; i < _maxTextures; i++) {
      _textures[i] = null;
    }
  }

  void _clearBatchData() {
    _drawCommands.clear();
  }

  @override
  void flush() {
    if (_drawCommands.isNotEmpty) {
      _executeBatchedCommands();
    } else if (renderBufferIndex.position > 0) {
      super.flush(); // Handles buffer updates and draw call
    }
    _clearTextures(); // Clear local texture tracking for the new batch
    _clearBatchData();

    final lastBlendMode = _lastBlendMode;
    if (lastBlendMode.srcFactor != BlendMode.NORMAL.srcFactor ||
         lastBlendMode.dstFactor != BlendMode.NORMAL.dstFactor) {
      _renderingContext.blendFunc(BlendMode.NORMAL.srcFactor, BlendMode.NORMAL.dstFactor);
      _lastBlendMode = BlendMode.NORMAL;
    }
  }

  var _lastBlendMode = BlendMode.NORMAL;

  void _executeBatchedCommands() {
    if (_drawCommands.isEmpty) return;

    // Upload all vertex and index data that was accumulated.
    renderBufferVertex.update();
    renderBufferIndex.update();

    final gl = _renderContextWebGL!.rawContext;
    var cmdIndex = 0;
    while (cmdIndex < _drawCommands.length) {
      final first = _drawCommands[cmdIndex];
      final groupBlend = first.blendMode;

      // --- Group consecutive commands ---
      var groupOffset = first.indexOffset;
      var groupCount = first.indexCount;
      final uniqueTextures = {first.textureIndex: first.texture};

      var lookahead = cmdIndex + 1;
      while (lookahead < _drawCommands.length) {
        final next = _drawCommands[lookahead];

        // Conditions to break the group:
        // 1. Blend mode is different.
        final sameBlend = next.blendMode.srcFactor == groupBlend.srcFactor &&
            next.blendMode.dstFactor == groupBlend.dstFactor;
        if (!sameBlend) break;

        // 2. Indices are not contiguous.
        final contiguous = next.indexOffset == groupOffset + groupCount;
        if (!contiguous) break;

        // 3. The number of unique textures would exceed the hardware limit.
        if (!uniqueTextures.containsKey(next.textureIndex) &&
            uniqueTextures.length >= _maxTextures) {
          break;
        }

        uniqueTextures[next.textureIndex] = next.texture;
        groupCount += next.indexCount;
        lookahead++;
      }

      // --- Set state and draw the group ---

      // 1. Activate blend mode for the group (if it changed).
      if (_lastBlendMode.srcFactor != groupBlend.srcFactor ||
          _lastBlendMode.dstFactor != groupBlend.dstFactor) {
        gl.blendFunc(groupBlend.srcFactor, groupBlend.dstFactor);
        _lastBlendMode = groupBlend;
      }

      // 2. Bind all unique textures required by this group.
      for (final entry in uniqueTextures.entries) {
        _renderContextWebGL!.activateRenderTextureAt(entry.value, entry.key, flush: false);
      }

      // 3. Issue the grouped draw call.
      gl.drawElements(WebGL.TRIANGLES, groupCount, WebGL.UNSIGNED_SHORT, groupOffset * 2);
      renderStatistics.drawCount += 1;

      // Advance to the next command after the group.
      cmdIndex = lookahead;
    }

    // Reset buffer positions for the next batch.
    renderBufferVertex.position = 0;
    renderBufferVertex.count = 0;
    renderBufferIndex.position = 0;
    renderBufferIndex.count = 0;
  }

  //---------------------------------------------------------------------------

  /// Checks if the given texture is already in a slot or if there's an empty slot.
  /// Returns the texture index if available, or -1 if no slots are available.
  int? getTextureIndexIfAvailable(RenderTexture texture) {
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
    return null;
  }

  //---------------------------------------------------------------------------

  void renderTextureQuad(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTextureQuad renderTextureQuad, [num r = 1, num g = 1, num b = 1, num a = 1]) {
    // Ensure we have a reference to the active RenderContextWebGL. Some
    // integrations (for example stagexl_spine) call this method directly on
    // the program instance. In those cases the program may not have been
    // activated via RenderContext.activateRenderProgram, so _renderContextWebGL
    // could be null. Use the provided renderContext parameter to be resilient
    // to that usage pattern.
    _renderContextWebGL = renderContext;
    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, renderContext,
          renderTextureQuad.renderTexture, ixList, vxList, r, g, b, a);
      return;
    }

    final texture = renderTextureQuad.renderTexture;
    var textureIndex = getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex == null) {
      // No slot available OR texture not found -> Need to Flush
      needsFlush = true;
      textureIndex = 0; // Will use slot 0 after flush
    }

    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;
    const vertexFloatCount = 9; // Stride in floats

    // Check if we need to flush due to buffer size limits
    if (!needsFlush && renderBufferIndex.position + ixListCount >= renderBufferIndex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    if (!needsFlush && renderBufferVertex.position + vxListCount * vertexFloatCount >= renderBufferVertex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    // --- Flush if Needed ---
    if (needsFlush) {
      flush(); // Flush the current batch
    }

    // Update our internal tracking
    _textures[textureIndex] ??= texture;

    // Get current buffer positions and data
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // Calculate vertex data
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

    // Add indices directly to buffer
    ixData[ixPosition + 0] = vxCount + 0;
    ixData[ixPosition + 1] = vxCount + 1;
    ixData[ixPosition + 2] = vxCount + 2;
    ixData[ixPosition + 3] = vxCount + 0;
    ixData[ixPosition + 4] = vxCount + 2;
    ixData[ixPosition + 5] = vxCount + 3;

    // Add vertices directly to buffer
    var vPos = vxPosition;
    vxData[vPos++] = ma1 + mc1; vxData[vPos++] = mb1 + md1; vxData[vPos++] = vxList[2]; vxData[vPos++] = vxList[3]; vxData[vPos++] = colorR; vxData[vPos++] = colorG; vxData[vPos++] = colorB; vxData[vPos++] = colorA; vxData[vPos++] = textureIndex.toDouble();
    vxData[vPos++] = ma2 + mc1; vxData[vPos++] = mb2 + md1; vxData[vPos++] = vxList[6]; vxData[vPos++] = vxList[7]; vxData[vPos++] = colorR; vxData[vPos++] = colorG; vxData[vPos++] = colorB; vxData[vPos++] = colorA; vxData[vPos++] = textureIndex.toDouble();
    vxData[vPos++] = ma2 + mc2; vxData[vPos++] = mb2 + md2; vxData[vPos++] = vxList[10]; vxData[vPos++] = vxList[11]; vxData[vPos++] = colorR; vxData[vPos++] = colorG; vxData[vPos++] = colorB; vxData[vPos++] = colorA; vxData[vPos++] = textureIndex.toDouble();
    vxData[vPos++] = ma1 + mc2; vxData[vPos++] = mb1 + md2; vxData[vPos++] = vxList[14]; vxData[vPos++] = vxList[15]; vxData[vPos++] = colorR; vxData[vPos++] = colorG; vxData[vPos++] = colorB; vxData[vPos++] = colorA; vxData[vPos++] = textureIndex.toDouble();

    // Create draw command
    final drawCommand = _DrawCommand(
      indexCount: ixListCount,
      indexOffset: ixPosition,
      blendMode: renderState.globalBlendMode,
      texture: texture,
      textureIndex: textureIndex,
    );

    _drawCommands.add(drawCommand);

    // Update buffer positions
    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;
    renderBufferVertex.position += vxListCount * vertexFloatCount;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState,
      RenderContextWebGL renderContext,
      RenderTexture renderTexture,
      Int16List ixList,
      Float32List vxList,
      num r,
      num g,
      num b,
      num a,
      {BlendMode? blendMode}) {
    _renderContextWebGL = renderContext;

    final texture = renderTexture; // Use consistent naming
    var textureIndex = getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex == null) {
      needsFlush = true;
      textureIndex = 0;
    } 

    final matrix = renderState.globalMatrix;
    final alpha = renderState.globalAlpha;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2; // Input vxList has 4 floats (x,y,u,v)
    const vertexFloatCount = 9; // Output vertex has 9 floats

    blendMode ??= renderState.globalBlendMode;

    // Check if we need to flush due to buffer size limits
    if (!needsFlush && renderBufferIndex.position + ixListCount >= renderBufferIndex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    if (!needsFlush && renderBufferVertex.position + vxListCount * vertexFloatCount >= renderBufferVertex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    // --- Flush if Needed ---
    if (needsFlush) {
      flush();
    }

    // Update our internal tracking
    _textures[textureIndex] ??= texture;

    // Get current buffer positions and data
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    final vxData = renderBufferVertex.data;
    var vxPosition = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // Add indices directly to buffer
    for (var i = 0; i < ixListCount; i++) {
      ixData[ixPosition + i] = vxCount + ixList[i];
    }

    // Transform and add vertices directly to buffer
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
      vxData[vxPosition++] = mx + ma * x + mc * y; // x
      vxData[vxPosition++] = my + mb * x + md * y; // y
      vxData[vxPosition++] = vxList[o + 2];        // u
      vxData[vxPosition++] = vxList[o + 3];        // v
      vxData[vxPosition++] = colorR;               // r
      vxData[vxPosition++] = colorG;               // g
      vxData[vxPosition++] = colorB;               // b
      vxData[vxPosition++] = colorA;               // a
      vxData[vxPosition++] = textureIndex.toDouble();
    }

    // Create draw command
    final drawCommand = _DrawCommand(
      indexCount: ixListCount,
      indexOffset: ixPosition,
      blendMode: blendMode,
      texture: texture,
      textureIndex: textureIndex,
    );

    _drawCommands.add(drawCommand);

    // Update buffer positions
    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;
    renderBufferVertex.position += vxListCount * vertexFloatCount;
    renderBufferVertex.count += vxListCount;
  }
}
