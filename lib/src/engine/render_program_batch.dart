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
  /// Enable to print debug information about batch execution.
  static bool debugBatch = false;

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
      if (debugBatch) print('[Batch] flush -> executing ${_drawCommands.length} drawCommands, vertices=${_aggregateVertexData.length}, indices=${_aggregateIndexData.length}');
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

    // Upload all vertex and index data at once. Avoid creating typed
    // intermediate arrays to reduce allocations: copy directly from the
    // aggregate Dart lists into the underlying typed buffers.

    final vertexCount = _aggregateVertexData.length;
    final indexCount = _aggregateIndexData.length;

    // Copy to actual buffers (this will convert/copy Dart List<num> -> TypedList)
    if (vertexCount > 0) {
      renderBufferVertex.data.setRange(0, vertexCount, _aggregateVertexData);
    }
    if (indexCount > 0) {
      renderBufferIndex.data.setRange(0, indexCount, _aggregateIndexData);
    }

    // Set positions for update
    renderBufferVertex.position = vertexCount;
    renderBufferVertex.count = vertexCount ~/ 9; // 9 floats per vertex
    renderBufferIndex.position = indexCount;
    renderBufferIndex.count = indexCount;

    // Update GPU buffers
    renderBufferVertex.update();
    renderBufferIndex.update();

    // Execute draw commands: draw each command individually while
    // ensuring buffers were uploaded only once above. This guarantees
    // correct per-command blend state and texture binding even when
    // Spine toggles blend modes frequently.
    if (debugBatch) print('[Batch] _executeBatchedCommands: totalCommands=${_drawCommands.length} (drawing per-command)');
    // We'll try to group consecutive commands that share the same
    // blendMode and textureIndex into a single drawElements call. This
    // preserves correct ordering and per-blend correctness while
    // reducing the number of GL draw calls when possible.
    var cmdIndex = 0;
    int? lastBoundTexIndex;
    // BlendMode? lastBoundBlend;
    var lastBoundBlend = BlendMode.NORMAL;
    while (cmdIndex < _drawCommands.length) {
      final first = _drawCommands[cmdIndex];

      // Start grouping from here
      var groupOffset = first.indexOffset;
      var groupCount = first.indexCount;
      final groupTexIndex = first.textureIndex;
      final groupBlend = first.blendMode;

      var lookahead = cmdIndex + 1;
      while (lookahead < _drawCommands.length) {
        final next = _drawCommands[lookahead];
        // Only group if blend and texture match and indices are contiguous
        final contiguous = next.indexOffset == groupOffset + groupCount;
        final sameBlend = next.blendMode.srcFactor == groupBlend.srcFactor && next.blendMode.dstFactor == groupBlend.dstFactor;
        if (next.textureIndex == groupTexIndex && sameBlend && contiguous) {
          groupCount += next.indexCount;
          lookahead++;
        } else {
          break;
        }
      }

      // Activate blend mode for the whole group (if changed)
      final needBlendChange = /*lastBoundBlend == null ||*/
          lastBoundBlend.srcFactor != groupBlend.srcFactor ||
              lastBoundBlend.dstFactor != groupBlend.dstFactor;
      if (needBlendChange) {
        _renderContextWebGL!.activateBlendMode(groupBlend);
        lastBoundBlend = groupBlend;
      }

      // Bind texture for the whole group (if changed)
      final groupTexture = first.texture;
      // Ensure internal slot reflects the texture we will bind.
      _textures[groupTexIndex] ??= groupTexture;
      if (groupTexIndex != lastBoundTexIndex) {
        if (debugBatch) print('[Batch] binding texture index=$groupTexIndex present=true');
        _renderContextWebGL!.activateRenderTextureAt(groupTexture, groupTexIndex, flush: false);
        lastBoundTexIndex = groupTexIndex;
      }

      if (debugBatch) {
        // Query GL state to help debug mismatches between expected
        // blend/texture state and the actual GL state at draw time.
        try {
          final gl = _renderContextWebGL!.rawContext;
          final activeProgram = gl.getParameter(WebGL.CURRENT_PROGRAM);
          final activeTextureEnum = (gl.getParameter(WebGL.ACTIVE_TEXTURE) as JSNumber?)?.toDartInt;
          final boundTexture = gl.getParameter(WebGL.TEXTURE_BINDING_2D);
          final src = gl.getParameter(WebGL.BLEND_SRC_RGB);
          final dst = gl.getParameter(WebGL.BLEND_DST_RGB);
          print('[Batch] GLState before draw: program=$activeProgram activeTexture=$activeTextureEnum boundTexture=$boundTexture blendSrc=$src blendDst=$dst');
        } catch (_) {
          // Ignore errors when querying state in some environments
        }
        // Compute min/max alpha for vertices referenced by this group's indices
        try {
          var minAlpha = double.infinity;
          var maxAlpha = double.negativeInfinity;
          for (var ii = groupOffset; ii < groupOffset + groupCount; ii++) {
            final vertexIndex = _aggregateIndexData[ii];
            final alphaValue = _aggregateVertexData[vertexIndex * 9 + 7]; // alpha is 8th float
            if (alphaValue < minAlpha) minAlpha = alphaValue;
            if (alphaValue > maxAlpha) maxAlpha = alphaValue;
          }
          if (minAlpha == double.infinity) {
            minAlpha = 0.0;
            maxAlpha = 0.0;
          }
          print('[Batch] drawElements(group): offset=$groupOffset, count=$groupCount, tex=$groupTexIndex, blendSrc=${groupBlend.srcFactor}, blendDst=${groupBlend.dstFactor} alpha[min=$minAlpha,max=$maxAlpha]');
        } catch (e) {
          print('[Batch] drawElements(group): offset=$groupOffset, count=$groupCount, tex=$groupTexIndex, blendSrc=${groupBlend.srcFactor}, blendDst=${groupBlend.dstFactor} (alpha-check-failed: $e)');
        }
      }

      // Force the GL blend function for the group immediately before drawing.
      // try {
      final gl = _renderContextWebGL!.rawContext;
      //   // Make absolutely sure the correct texture is bound to the
      //   // expected texture unit. Some drivers can be finicky about the
      //   // active texture unit state; calling this explicitly here is a
      //   // defensive step and cheap compared to the draw.
      //   try {
      //     final webglTex = groupTexture.texture;
      //     if (webglTex != null) {
      //       gl.activeTexture(WebGL.TEXTURE0 + groupTexIndex);
      //       gl.bindTexture(WebGL.TEXTURE_2D, webglTex);
      //     }
      //   } catch (_) {
      //     // ignore
      //   }

      // if (_lastBlendMode != groupBlend) {
      if (needBlendChange) gl.blendFunc(groupBlend.srcFactor, groupBlend.dstFactor);
      //   // Also ensure the blend equation is set (conservative; cheap).
      // gl.blendEquation(WebGL.FUNC_ADD);
      // }
      // } catch (_) {
      //   // ignore
      // }

      renderingContext.drawElements(WebGL.TRIANGLES, groupCount, WebGL.UNSIGNED_SHORT, groupOffset * 2);

      // Advance to next command after the group
      cmdIndex = lookahead;
    }
    
    // Reset buffer positions after batched rendering
    renderBufferVertex.position = 0;
    renderBufferVertex.count = 0;
    renderBufferIndex.position = 0;
    renderBufferIndex.count = 0;
    
    _executingBatch = false;
  }

  /// Public wrapper to execute (flush) the current batched commands now.
  /// This uploads the current aggregated vertex/index data and issues the
  /// drawElements calls for the accumulated draw commands. It's intended
  /// to be called from the render context when an immediate draw is needed
  /// (for example, when switching blend modes from an external library like
  /// spine which expects draws to happen immediately).
  void executeBatchedCommandsNow() {
    if (_executingBatch) return;
    if (_drawCommands.isEmpty) return;
    _executeBatchedCommands();
    // After execution, clear batch data to allow subsequent batches.
    _clearTextures();
    _clearBatchData();
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

    // Check if blend mode changed - flush if so
    // final currentBlendMode = renderState.globalBlendMode;
    // if (currentBlendMode.srcFactor != currentBlendMode.srcFactor ||
    //     currentBlendMode.dstFactor != currentBlendMode.dstFactor) {
    //   needsFlush = true;
    // }

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

  if (debugBatch) print('[Batch] addCommand: off=${drawCommand.indexOffset} cnt=${drawCommand.indexCount} tex=${drawCommand.textureIndex} blendSrc=${drawCommand.blendMode.srcFactor} blendDst=${drawCommand.blendMode.dstFactor}');
    _drawCommands.add(drawCommand);
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
    // Ensure we have a reference to the active RenderContextWebGL. See
    // comment in renderTextureQuad for rationale.
    _renderContextWebGL = renderContext;
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

    blendMode ??= renderState.globalBlendMode;

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
      blendMode: blendMode,
      texture: texture,
      textureIndex: textureIndex,
    );

  if (debugBatch) print('[Batch] addCommand: off=${drawCommand.indexOffset} cnt=${drawCommand.indexCount} tex=${drawCommand.textureIndex} blendSrc=${drawCommand.blendMode.srcFactor} blendDst=${drawCommand.blendMode.dstFactor}');
    _drawCommands.add(drawCommand);
  }
}
