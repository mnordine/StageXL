part of '../engine.dart';

class DrawCommand {
  final int indexCount;
  final int indexOffset;
  final BlendMode blendMode;
  final RenderTexture texture;
  final int textureIndex;

  DrawCommand({
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
  // Reintroduce sampler indices cache for WebGL 2 sampler array uniform
  static JSUint32Array? _samplerIndices;

  static int initializeMaxTextures(WebGL renderingContext) {
    _maxTextures = (renderingContext.getParameter(WebGL.MAX_TEXTURE_IMAGE_UNITS) as JSNumber?)?.toDartInt ?? 8;
    // Limit max textures if necessary (optional)
    // _maxTextures = math.min(_maxTextures, 16);
    print('StageXL Batch Renderer - Max texture units: $_maxTextures');
    // Pre-calculate the sampler indices list for WebGL 2
    _samplerIndices = Uint32List.fromList(List.generate(_maxTextures, (i) => i, growable: false)).toJS;

    return _maxTextures;
  }

  late final List<RenderTexture?> _textures = List.filled(_maxTextures, null);
  
  // Batching infrastructure
  final List<DrawCommand> _drawCommands = <DrawCommand>[];
  final List<double> _aggregateVertexData = <double>[];
  final List<int> _aggregateIndexData = <int>[];
  RenderContextWebGL? _renderContextWebGL;
  bool _executingBatch = false;

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

      $samplerDeclaration // Use sampler array

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
    
    // Store reference to render context for batch operations
    _renderContextWebGL = renderContext;

    // --- Set Sampler Uniforms ---
    if (isWebGL2) {
      // WebGL 2: Set the sampler array uniform 'uSamplers'
      // Find the location (might be named 'uSamplers' or 'uSamplers[0]')
      final location = uniforms['uSamplers[0]'] ?? uniforms['uSamplers'];
      if (location != null && _samplerIndices != null) {
        // Pass the array [0, 1, 2, ..., maxTextures-1] to the uniform
        (renderingContext as WebGL2RenderingContext).uniform1iv(location, _samplerIndices!);
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
  }

  @override
  void setupAttributes() {
    // Stride is 36 bytes (vec2 pos, vec2 texCoord, vec4 color, float texIndex)
    // 2*4 + 2*4 + 4*4 + 1*4 = 8 + 8 + 16 + 4 = 36
    const stride = 36;
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, stride, 0);  // offset 0 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexTextCoord'], 2, stride, 8); // offset 8 bytes
    renderBufferVertex.bindAttribute(attributes['aVertexColor'], 4, stride, 16); // offset 16 bytes

    final location = attributes['aVertexTexIndex'];
    if (location == null) return; // Optimized out, batching likely unused

    renderBufferVertex.bindAttribute(location, 1, stride, 32); // offset 32 bytes
  }

  //---------------------------------------------------------------------------

  void _clearTextures() {
    for (var i = 0; i < _maxTextures; i++) {
      _textures[i] = null;
    }
  }

  void _clearBatchData() {
    _drawCommands.clear();
    _aggregateVertexData.clear();
    _aggregateIndexData.clear();
    _executingBatch = false;
  }

  @override
  void flush() {
    if (_executingBatch) {
      // Prevent recursion during batch execution
      return;
    }
    
    if (_drawCommands.isNotEmpty) {
      _executeBatchedCommands();
    } else if (renderBufferIndex.position > 0) {
      super.flush(); // Handles buffer updates and draw call
    }
    _clearTextures(); // Clear local texture tracking for the new batch
    _clearBatchData();
  }

  void _executeBatchedCommands() {
    if (_drawCommands.isEmpty) return;

    _executingBatch = true;

    // Upload all vertex data at once
    final vertexData = Float32List.fromList(_aggregateVertexData);
    final indexData = Int16List.fromList(_aggregateIndexData);
    
    // Copy to actual buffers
    renderBufferVertex.data.setRange(0, vertexData.length, vertexData);
    renderBufferIndex.data.setRange(0, indexData.length, indexData);

    // Set positions for update
    renderBufferVertex.position = vertexData.length;
    renderBufferVertex.count = vertexData.length ~/ 9; // 9 floats per vertex
    renderBufferIndex.position = indexData.length;
    renderBufferIndex.count = indexData.length;

    // Update GPU buffers
    renderBufferVertex.update();
    renderBufferIndex.update();

    // Execute draw commands with optimized blend mode switching
    BlendMode? currentBlendMode;
    
    for (final command in _drawCommands) {
      // Activate texture if needed
      _renderContextWebGL!.activateRenderTextureAt(command.texture, command.textureIndex, flush: false);
      
      // Change blend mode only if different
      if (!identical(command.blendMode, currentBlendMode)) {
        _renderContextWebGL!.activateBlendMode(command.blendMode);
        currentBlendMode = command.blendMode;
      }
      
      // Draw with offset
      renderingContext.drawElements(WebGL.TRIANGLES, command.indexCount, 
          WebGL.UNSIGNED_SHORT, command.indexOffset * 2); // * 2 for byte offset
    }
    
    // Reset buffer positions after batched rendering
    renderBufferVertex.position = 0;
    renderBufferVertex.count = 0;
    renderBufferIndex.position = 0;
    renderBufferIndex.count = 0;
    
    _executingBatch = false;
  }

  //---------------------------------------------------------------------------

  /// Checks if the given texture is already in a slot or if there's an empty slot.
  /// Returns the texture index if available, or -1 if no slots are available.
  int getTextureIndexIfAvailable(RenderTexture texture) {
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
    var textureIndex = getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex < 0) {
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
    if (!needsFlush && _aggregateIndexData.length + ixListCount >= renderBufferIndex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    if (!needsFlush && _aggregateVertexData.length + vxListCount * vertexFloatCount >= renderBufferVertex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    // --- Flush if Needed ---
    if (needsFlush) {
      flush(); // Flush the current batch
    }

    // Update our internal tracking
    _textures[textureIndex] ??= texture;

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

    // Add indices to aggregate data
    final vertexOffset = _aggregateVertexData.length ~/ 9; // 9 floats per vertex
    _aggregateIndexData.addAll([
      vertexOffset + 0,
      vertexOffset + 1,
      vertexOffset + 2,
      vertexOffset + 0,
      vertexOffset + 2,
      vertexOffset + 3,
    ]);

    // Add vertices to aggregate data
    _aggregateVertexData.addAll([
      // Vertex 0
      ma1 + mc1, mb1 + md1, vxList[2], vxList[3], colorR, colorG, colorB, colorA, textureIndex.toDouble(),
      // Vertex 1
      ma2 + mc1, mb2 + md1, vxList[6], vxList[7], colorR, colorG, colorB, colorA, textureIndex.toDouble(),
      // Vertex 2
      ma2 + mc2, mb2 + md2, vxList[10], vxList[11], colorR, colorG, colorB, colorA, textureIndex.toDouble(),
      // Vertex 3
      ma1 + mc2, mb1 + md2, vxList[14], vxList[15], colorR, colorG, colorB, colorA, textureIndex.toDouble(),
    ]);

    // Create draw command
    final drawCommand = DrawCommand(
      indexCount: ixListCount,
      indexOffset: _aggregateIndexData.length - ixListCount,
      blendMode: renderState.globalBlendMode,
      texture: texture,
      textureIndex: textureIndex,
    );

    _drawCommands.add(drawCommand);
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTexture renderTexture, Int16List ixList, Float32List vxList,
      num r, num g, num b, num a) {

    final texture = renderTexture; // Use consistent naming
    var textureIndex = getTextureIndexIfAvailable(texture);
    var needsFlush = false;

    // --- Texture Slot Management ---
    if (textureIndex < 0) {
      needsFlush = true;
      textureIndex = 0;
    } 

    final matrix = renderState.globalMatrix;
    final alpha = renderState.globalAlpha;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2; // Input vxList has 4 floats (x,y,u,v)
    const vertexFloatCount = 9; // Output vertex has 9 floats

    // Check if we need to flush due to buffer size limits
    if (!needsFlush && _aggregateIndexData.length + ixListCount >= renderBufferIndex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    if (!needsFlush && _aggregateVertexData.length + vxListCount * vertexFloatCount >= renderBufferVertex.data.length) {
       needsFlush = true;
       textureIndex = 0;
    }

    // --- Flush if Needed ---
    if (needsFlush) {
      flush();
    }

    // Update our internal tracking
    _textures[textureIndex] ??= texture;

    // Add indices to aggregate data
    final vertexOffset = _aggregateVertexData.length ~/ 9; // 9 floats per vertex
    for (var i = 0; i < ixListCount; i++) {
      _aggregateIndexData.add(vertexOffset + ixList[i]);
    }

    // Transform and add vertices to aggregate data
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
      _aggregateVertexData.addAll([
        mx + ma * x + mc * y, // x
        my + mb * x + md * y, // y
        vxList[o + 2],        // u
        vxList[o + 3],        // v
        colorR,               // r
        colorG,               // g
        colorB,               // b
        colorA,               // a
        textureIndex.toDouble(),
      ]);
    }

    // Create draw command
    final drawCommand = DrawCommand(
      indexCount: ixListCount,
      indexOffset: _aggregateIndexData.length - ixListCount,
      blendMode: renderState.globalBlendMode,
      texture: texture,
      textureIndex: textureIndex,
    );

    _drawCommands.add(drawCommand);
  }
}
