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

class RenderProgramBatchWebGL extends RenderProgramWebGL<void> {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexColor:      Float32(r), Float32(g), Float32(b), Float32(a)
  // aVertexTexIndex:   Float32(textureIndex)

  static var _maxTextures = 8; // Default value, will be updated at runtime
  static JSUint32Array? _samplerIndices;
  final bool _dualSourceShader;
  final bool _shaderScissor;

  RenderProgramBatchWebGL()
      : _dualSourceShader = false,
        _shaderScissor = false;

  RenderProgramBatchWebGL.dualSource()
      : _dualSourceShader = true,
        _shaderScissor = false;

  RenderProgramBatchWebGL.shaderScissor()
      : _dualSourceShader = false,
        _shaderScissor = true;

  RenderProgramBatchWebGL.dualSourceShaderScissor()
      : _dualSourceShader = true,
        _shaderScissor = true;

  static int initializeMaxTextures(WebGL renderingContext, {required bool isWebGL2}) {
    _maxTextures = (renderingContext.getParameter(WebGL.MAX_TEXTURE_IMAGE_UNITS) as JSNumber?)?.toDartInt ?? 8;

    // Cap max texture units, else a large number could result in excessive if/else chains, and the 
    // shader will fail to compile with an "expression too complex" error.
    _maxTextures = math.min(_maxTextures, 16);

    // Pre-calculate the sampler indices list for WebGL 2
    if (isWebGL2) {
      _samplerIndices = Uint32List.fromList(.generate(_maxTextures, (i) => i, growable: false)).toJS;
    }

    return _maxTextures;
  }

  late final List<RenderTexture?> _textures = .filled(_maxTextures, null);
  
  final _drawCommands = <_DrawCommand>[];
  RenderContextWebGL? _renderContextWebGL;
  var _executingBatch = false;

  @override
  String get vertexShaderSource {
    final clipAttribute = _shaderScissor && isWebGL2 ? 'in vec4 aVertexClipRect;' : '';
    final clipOutput = _shaderScissor && isWebGL2 ? 'flat out vec4 vClipRect;' : '';
    final clipAssignment = _shaderScissor && isWebGL2 ? 'vClipRect = aVertexClipRect;' : '';
    final blendOutput = _dualSourceShader
        ? isWebGL2
            ? 'flat out int vBlendMode;'
            : 'varying float vBlendMode;'
        : isWebGL2
            ? 'flat out float vAlphaMultiplier;'
            : 'varying float vAlphaMultiplier;';
    final blendDecode = _dualSourceShader
        ? isWebGL2
            ? '''
      int blendMode = encodedTextureIndex / $_maxTextures;
      vTexIndex = encodedTextureIndex - blendMode * $_maxTextures;
      vBlendMode = blendMode;'''
            : '''
      float blendMode = floor(aVertexTexIndex / ${_maxTextures.toDouble()} + 0.1);
      vTexIndex = aVertexTexIndex - blendMode * ${_maxTextures.toDouble()};
      vBlendMode = blendMode;'''
        : isWebGL2
            ? '''
      int additive = encodedTextureIndex / $_maxTextures;
      vTexIndex = encodedTextureIndex - additive * $_maxTextures;
      vAlphaMultiplier = 1.0 - float(additive);'''
            : '''
      float additive = step(${_maxTextures - 0.5}, aVertexTexIndex);
      vTexIndex = aVertexTexIndex - additive * ${_maxTextures.toDouble()};
      vAlphaMultiplier = 1.0 - additive;''';

    return isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;
    in vec4 aVertexColor;
    in float aVertexTexIndex;
    $clipAttribute

    out vec2 vTextCoord;
    out vec4 vColor;
    flat out int vTexIndex;
    $blendOutput
    $clipOutput

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      int encodedTextureIndex = int(aVertexTexIndex + 0.5);
      $blendDecode
      $clipAssignment
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
    $blendOutput

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      $blendDecode
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';
  }

  @override
  String get fragmentShaderSource {
    final sb = StringBuffer();
    final sampleTarget = _dualSourceShader ? 'color' : isWebGL2 ? 'fragColor' : 'gl_FragColor';
    final clipInput = _shaderScissor && isWebGL2 ? 'flat in vec4 vClipRect;' : '';
    final clipDiscard = _shaderScissor && isWebGL2
        ? '''
        if (gl_FragCoord.x < vClipRect.x || gl_FragCoord.y < vClipRect.y ||
            gl_FragCoord.x >= vClipRect.z || gl_FragCoord.y >= vClipRect.w) {
          discard;
        }'''
        : '';

    if (isWebGL2) {
      // WebGL 2: Use sampler array declaration but with branching for lookup
      final samplerDeclaration = 'uniform sampler2D uSamplers[$_maxTextures];';

      for (var i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        // Use branching to access the sampler array element
        sb.write('''
        if (textureIndex == $i) {
          $sampleTarget = texture(uSamplers[$i], vTextCoord) * vColor;
        }''');
      }
      // Fallback (Magenta for debugging)
      sb.write('''
        else {
          $sampleTarget = vec4(1.0, 0.0, 1.0, 1.0);
        }''');

      final extension = _dualSourceShader ? '#extension GL_EXT_blend_func_extended : require' : '';
      final blendInput = _dualSourceShader ? 'flat in int vBlendMode;' : 'flat in float vAlphaMultiplier;';
      final outputs = _dualSourceShader
          ? '''
      layout(location = 0, index = 0) out vec4 fragColor;
      layout(location = 0, index = 1) out vec4 secondaryColor;'''
          : 'out vec4 fragColor;';
      final blendResult = _dualSourceShader
          ? '''
        fragColor = color;
        if (vBlendMode == 1) {
          secondaryColor = vec4(1.0);
        } else if (vBlendMode == 2) {
          secondaryColor = vec4(vec3(1.0) - color.rgb, 1.0 - color.a);
        } else if (vBlendMode == 3) {
          fragColor = vec4(0.0);
          secondaryColor = vec4(color.rgb + vec3(1.0 - color.a), 1.0);
        } else {
          secondaryColor = vec4(1.0 - color.a);
        }'''
          : 'fragColor.a *= vAlphaMultiplier;';
      final colorVariable = _dualSourceShader ? 'vec4 color;' : '';

      return '''
      #version 300 es
      $extension

      precision ${RenderProgramWebGL.fragmentPrecision} float;

      $samplerDeclaration

      in vec2 vTextCoord;
      in vec4 vColor;
      flat in int vTexIndex;
      $blendInput
      $clipInput

      $outputs

      void main() {
        $clipDiscard
        $colorVariable
        int textureIndex = vTexIndex;
        $sb
        $blendResult
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
          $sampleTarget = texture2D(uSampler$i, vTextCoord) * vColor;
        }''');
      }
      // Fallback (Magenta for debugging)
      sb.write('''
        else {
          $sampleTarget = vec4(1.0, 0.0, 1.0, 1.0);
        }''');

      final extension = _dualSourceShader ? '#extension GL_EXT_blend_func_extended : require' : '';
      final blendInput = _dualSourceShader ? 'varying float vBlendMode;' : 'varying float vAlphaMultiplier;';
      final blendResult = _dualSourceShader
          ? '''
        gl_FragColor = color;
        if (vBlendMode >= 0.5 && vBlendMode < 1.5) {
          gl_SecondaryFragColorEXT = vec4(1.0);
        } else if (vBlendMode >= 1.5 && vBlendMode < 2.5) {
          gl_SecondaryFragColorEXT = vec4(vec3(1.0) - color.rgb, 1.0 - color.a);
        } else if (vBlendMode >= 2.5) {
          gl_FragColor = vec4(0.0);
          gl_SecondaryFragColorEXT = vec4(color.rgb + vec3(1.0 - color.a), 1.0);
        } else {
          gl_SecondaryFragColorEXT = vec4(1.0 - color.a);
        }'''
          : 'gl_FragColor.a *= vAlphaMultiplier;';
      final colorVariable = _dualSourceShader ? 'vec4 color;' : '';

      return '''
      $extension
      precision ${RenderProgramWebGL.fragmentPrecision} float;

      $samplerDeclarations // Use individual samplers

      varying vec2 vTextCoord;
      varying vec4 vColor;
      varying float vTexIndex;
      $blendInput

      void main() {
        $colorVariable
        $sb
        $blendResult
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

    final lastBlendMode = _lastBlendMode;
    if (lastBlendMode.srcFactor != BlendMode.NORMAL.srcFactor ||
         lastBlendMode.dstFactor != BlendMode.NORMAL.dstFactor) {
      renderingContext.blendFunc(BlendMode.NORMAL.srcFactor, BlendMode.NORMAL.dstFactor);
      _lastBlendMode = .NORMAL;
    }
  }

  var _lastBlendMode = BlendMode.NORMAL;

  void _resetCachedBlendMode() => _lastBlendMode = BlendMode.NORMAL;

  void _activateBatchBlendMode(WebGL gl, BlendMode blendMode) {
    if (identical(blendMode, BlendMode._DUAL_SOURCE)) {
      gl.blendFuncSeparate(WebGL.ONE, _src1ColorWebGL, WebGL.ONE, _src1AlphaWebGL);
    } else {
      gl.blendFunc(blendMode.srcFactor, blendMode.dstFactor);
    }
    _lastBlendMode = blendMode;
  }

  RenderProgramBatchWebGL _shaderForBlendMode(
    RenderContextWebGL renderContext,
    BlendMode blendMode, {
    bool shaderScissor = false,
  }) {
    if (shaderScissor) {
      return identical(blendMode, BlendMode._DUAL_SOURCE)
          ? renderContext._renderProgramBatchDualSourceShaderScissor
          : renderContext._renderProgramBatchShaderScissor;
    }
    return identical(blendMode, BlendMode._DUAL_SOURCE) ? renderContext._renderProgramBatchDualSource : this;
  }

  void _activateBatchShader(RenderContextWebGL renderContext, RenderProgramBatchWebGL shader) {
    shader.activate(renderContext);
    shader.projectionMatrix = renderContext.activeProjectionMatrix;
  }

  void _executeBatchedCommands() {
    if (_drawCommands.isEmpty) return;
    _executingBatch = true;
    final renderContext = _renderContextWebGL!;

    _bindVAO();
    renderBufferIndex.activate(renderContext);
    renderBufferVertex.activate(renderContext);
    setupAttributes();

    // Upload all vertex and index data that was accumulated.
    renderBufferVertex.update();
    renderBufferIndex.update();

    final gl = renderContext.rawContext;
    var activeShader = this;
    var cmdIndex = 0;
    while (cmdIndex < _drawCommands.length) {
      final first = _drawCommands[cmdIndex];
      final groupBlend = first.blendMode;

      // --- Group consecutive commands ---
      final groupOffset = first.indexOffset;
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

      final shader = _shaderForBlendMode(renderContext, groupBlend);
      if (!identical(shader, activeShader)) {
        _activateBatchShader(renderContext, shader);
        activeShader = shader;
      }

      // 1. Activate blend mode for the group (if it changed).
      if (_lastBlendMode.srcFactor != groupBlend.srcFactor ||
          _lastBlendMode.dstFactor != groupBlend.dstFactor) {
        _activateBatchBlendMode(gl, groupBlend);
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

    if (!identical(activeShader, this)) _activateBatchShader(renderContext, this);

    // Reset buffer positions for the next batch.
    renderBufferVertex.position = 0;
    renderBufferVertex.count = 0;
    renderBufferIndex.position = 0;
    renderBufferIndex.count = 0;
    
    _executingBatch = false;
  }

  void _executeRetainedBatch(
    RenderContextWebGL renderContext,
    WebGLBuffer vertexBuffer,
    WebGLBuffer indexBuffer,
    _RetainedWebGLBatchSlice slice,
  ) {
    if (_drawCommands.isNotEmpty || renderBufferIndex.position > 0) flush();
    _renderContextWebGL = renderContext;
    _executingBatch = true;
    final gl = renderContext.rawContext;
    final vertexByteOffset = slice.vertexFloatOffset * 4;
    RenderProgramBatchWebGL? activeShader;

    for (var runIndex = 0; runIndex < slice.runCount; runIndex++) {
      final run = slice.runs[runIndex];
      if (run.indexCount == 0) continue;
      final shader = _shaderForBlendMode(
        renderContext,
        run.blendMode,
        shaderScissor: slice.shaderScissor,
      );
      if (!identical(shader, activeShader)) {
        _activateBatchShader(renderContext, shader);
        gl
          ..bindBuffer(WebGL.ARRAY_BUFFER, vertexBuffer)
          ..bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, indexBuffer);
        shader
          .._bindRetainedAttribute('aVertexPosition', 2, slice.vertexFloatStride, vertexByteOffset + 0)
          .._bindRetainedAttribute('aVertexTextCoord', 2, slice.vertexFloatStride, vertexByteOffset + 8)
          .._bindRetainedAttribute('aVertexColor', 4, slice.vertexFloatStride, vertexByteOffset + 16)
          .._bindRetainedAttribute('aVertexTexIndex', 1, slice.vertexFloatStride, vertexByteOffset + 32)
          .._bindRetainedAttribute('aVertexClipRect', 4, slice.vertexFloatStride, vertexByteOffset + 36);
        activeShader = shader;
      }
      if (_lastBlendMode.srcFactor != run.blendMode.srcFactor ||
          _lastBlendMode.dstFactor != run.blendMode.dstFactor) {
        _activateBatchBlendMode(gl, run.blendMode);
      }
      for (var i = 0; i < run.textures.length; i++) {
        renderContext.activateRenderTextureAt(run.textures[i], i, flush: false);
      }
      gl.drawElements(WebGL.TRIANGLES, run.indexCount, WebGL.UNSIGNED_SHORT, run.indexOffset * 2);
      renderStatistics.drawCount++;
      renderStatistics.vertexCount += run.vertexCount;
      renderStatistics.indexCount += run.indexCount;
    }
    if (!identical(activeShader, this)) _activateBatchShader(renderContext, this);
    _executingBatch = false;
  }

  void _bindRetainedAttribute(String name, int size, int stride, int offset) {
    final index = attributes[name];
    if (index == null) return;
    renderingContext
      ..enableVertexAttribArray(index)
      ..vertexAttribPointer(index, size, WebGL.FLOAT, false, stride * 4, offset);
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
    final blendMode = renderState.globalBlendMode;
    final opaqueTarget = renderContext._activeRenderTargetIsOpaque;
    final batchBlendMode = _batchBlendMode(
      blendMode,
      opaqueTarget: opaqueTarget,
      dualSourceBlending: renderContext.dualSourceBlending,
    );
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

    final tIdx = _batchTextureIndex(
      textureIndex,
      blendMode,
      _maxTextures,
      opaqueTarget: opaqueTarget,
      dualSourceBlending: renderContext.dualSourceBlending,
    ).toDouble();
    vxData[vPos++] = ma1 + mc1;
    vxData[vPos++] = mb1 + md1;
    vxData[vPos++] = vxList[2]; 
    vxData[vPos++] = vxList[3]; 
    vxData[vPos++] = colorR;
    vxData[vPos++] = colorG;
    vxData[vPos++] = colorB;
    vxData[vPos++] = colorA;
    vxData[vPos++] = tIdx;

    vxData[vPos++] = ma2 + mc1;
    vxData[vPos++] = mb2 + md1;
    vxData[vPos++] = vxList[6];
    vxData[vPos++] = vxList[7]; 
    vxData[vPos++] = colorR;
    vxData[vPos++] = colorG;
    vxData[vPos++] = colorB;
    vxData[vPos++] = colorA;
    vxData[vPos++] = tIdx;

    vxData[vPos++] = ma2 + mc2;
    vxData[vPos++] = mb2 + md2;
    vxData[vPos++] = vxList[10];
    vxData[vPos++] = vxList[11];
    vxData[vPos++] = colorR;
    vxData[vPos++] = colorG;
    vxData[vPos++] = colorB;
    vxData[vPos++] = colorA;
    vxData[vPos++] = tIdx;
    
    vxData[vPos++] = ma1 + mc2;
    vxData[vPos++] = mb1 + md2;
    vxData[vPos++] = vxList[14];
    vxData[vPos++] = vxList[15];
    vxData[vPos++] = colorR;
    vxData[vPos++] = colorG;
    vxData[vPos++] = colorB;
    vxData[vPos++] = colorA;
    vxData[vPos++] = tIdx;

    // Create draw command
    final drawCommand = _DrawCommand(
      indexCount: ixListCount,
      indexOffset: ixPosition,
      blendMode: batchBlendMode,
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
    final opaqueTarget = renderContext._activeRenderTargetIsOpaque;
    final batchBlendMode = _batchBlendMode(
      blendMode,
      opaqueTarget: opaqueTarget,
      dualSourceBlending: renderContext.dualSourceBlending,
    );

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
    final encodedTextureIndex = _batchTextureIndex(
      textureIndex,
      blendMode,
      _maxTextures,
      opaqueTarget: opaqueTarget,
      dualSourceBlending: renderContext.dualSourceBlending,
    ).toDouble();

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
      vxData[vxPosition++] = encodedTextureIndex;
    }

    // Create draw command
    final drawCommand = _DrawCommand(
      indexCount: ixListCount,
      indexOffset: ixPosition,
      blendMode: batchBlendMode,
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
