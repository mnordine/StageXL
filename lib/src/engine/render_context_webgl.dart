part of '../engine.dart';

class RenderContextWebGL extends RenderContext {
  static int _globalContextIdentifier = 0;
  final HTMLCanvasElement _canvasElement;

  late final WebGL _renderingContext;
  final Matrix3D _projectionMatrix = Matrix3D.fromIdentity();
  final List<_MaskState> _maskStates = <_MaskState>[];

  late RenderProgram _activeRenderProgram;
  RenderFrameBuffer? _activeRenderFrameBuffer;
  RenderStencilBuffer? _activeRenderStencilBuffer;
  BlendMode? _activeBlendMode;

  bool _contextValid = true;
  int _contextIdentifier = 0;
  late final bool _isWebGL2;

  bool get isWebGL2 => _isWebGL2;
  static const int _maxContextRestoreRetries = 5;
  static const Duration _contextRestoreRetryDelay = Duration(milliseconds: 16);
  int _contextRestoreRetryCount = 0;
  bool _contextRestoreRetryScheduled = false;
  bool _contextRestorePending = false;

  OES_vertex_array_object? _vaoExtension;

  // Simple full-screen quad for mask operations
  final _maskQuadIndices = Int16List.fromList([0, 1, 2, 0, 2, 3]);
  final _maskQuadVertices = Float32List.fromList([
    -1.0, -1.0,  // Bottom-left
     1.0, -1.0,  // Bottom-right
     1.0,  1.0,  // Top-right
    -1.0,  1.0   // Top-left
  ]);
  WebGLTexture? _fallbackTexture;

  //---------------------------------------------------------------------------

  final RenderProgramTinted renderProgramTinted = RenderProgramTinted();
  final RenderProgramTriangle renderProgramTriangle = RenderProgramTriangle();
  final RenderProgramBatch renderProgramBatch = RenderProgramBatch();

  final RenderBufferIndex renderBufferIndex = RenderBufferIndex(16384 * 2);
  final RenderBufferVertex renderBufferVertex = RenderBufferVertex(32768 * 2);

  late final List<RenderTexture?> _activeRenderTextures;
  final List<RenderFrameBuffer> _renderFrameBufferPool = <RenderFrameBuffer>[];
  final Map<String, RenderProgram> _renderPrograms = <String, RenderProgram>{};

  final bool _resetScissorTest;
  final bool _resetStencilTest;
  final bool _resetColor;

  //---------------------------------------------------------------------------

  RenderContextWebGL(
    HTMLCanvasElement canvasElement, {
    required PowerPreference powerPreference,
    bool alpha = false,
    bool antialias = false,
    bool forceWebGL1 = false,
    bool resetScissorTest = true,
    bool resetStencilTest = true,
    bool resetColor = true,
  }) : _canvasElement = canvasElement,
       _resetScissorTest = resetScissorTest,
       _resetStencilTest = resetStencilTest,
       _resetColor = resetColor {
    _canvasElement.onWebGlContextLost.listen(_onContextLost);
    _canvasElement.onWebGlContextRestored.listen(_onContextRestored);

    WebGLRenderingContext? renderingContext;

    if (!forceWebGL1) {
      renderingContext = _canvasElement.getContext('webgl2', {
        'alpha': alpha,
        'antialias': antialias,
        'depth': false,
        'powerPreference': powerPreference.value,
        'stencil': true,
      }.jsify()) as WebGL?;
    }

    _isWebGL2 = renderingContext != null;

    renderingContext ??= _canvasElement.getContext3d(
        alpha: alpha, antialias: antialias, depth: false, stencil: true) as WebGL?;

    if (renderingContext == null) {
      throw StateError('Failed to get WebGL context.');
    }

    _renderingContext = renderingContext;

    final maxTextureUnits =
        RenderProgramBatch.initializeMaxTextures(_renderingContext, isWebGL2: _isWebGL2);
    _activeRenderTextures = List.filled(maxTextureUnits, null);

    _contextValid = true;
    _contextIdentifier = ++_globalContextIdentifier;

    _initializeAfterContextChange();

    reset();
  }

  void _initializeAfterContextChange() {
    _configureRenderingContext();
    _invalidateCachedState();
    _initializeFallbackTexture();

    if (!isWebGL2) {
      _vaoExtension =
          _renderingContext.getExtension('OES_vertex_array_object') as OES_vertex_array_object?;
    }

    _activeRenderProgram = renderProgramBatch;
    _activeRenderProgram.activate(this);

    CompressedTexture.initExtensions(_renderingContext);
  }

  void _configureRenderingContext() {
    _renderingContext.enable(WebGL.BLEND);
    _renderingContext.disable(WebGL.STENCIL_TEST);
    _renderingContext.disable(WebGL.DEPTH_TEST);
    _renderingContext.disable(WebGL.CULL_FACE);
    _renderingContext.pixelStorei(WebGL.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
    _renderingContext.blendFunc(WebGL.ONE, WebGL.ONE_MINUS_SRC_ALPHA);
    _renderingContext.blendEquation(WebGL.FUNC_ADD);
  }

  void _initializeFallbackTexture() {
    final fallbackTexture = _renderingContext.createTexture();
    if (fallbackTexture == null) {
      throw StateError(_renderingContext.isContextLost() ? 'ContextLost' : 'Failed to create fallback texture.');
    }

    final activeTexture =
        (_renderingContext.getParameter(WebGL.ACTIVE_TEXTURE) as JSNumber).toDartInt;
    final pixel = Uint8List.fromList([0, 0, 0, 0]);

    _fallbackTexture = fallbackTexture;

    for (var i = 0; i < _activeRenderTextures.length; i++) {
      _renderingContext.activeTexture(WebGL.TEXTURE0 + i);
      _renderingContext.bindTexture(WebGL.TEXTURE_2D, fallbackTexture);
      _renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, WebGL.CLAMP_TO_EDGE);
      _renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, WebGL.CLAMP_TO_EDGE);
      _renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.NEAREST);
      _renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, WebGL.NEAREST);
      _renderingContext.texImage2D(
          WebGL.TEXTURE_2D,
          0,
          WebGL.RGBA,
          1.toJS,
          1.toJS,
          0.toJS,
          WebGL.RGBA,
          WebGL.UNSIGNED_BYTE,
          pixel.toJS);
    }

    _renderingContext.activeTexture(activeTexture);
  }

  void _invalidateCachedState() {
    _activeRenderFrameBuffer = null;
    _activeRenderStencilBuffer = null;
    _activeBlendMode = null;
    _viewportWidth = null;
    _viewportHeight = null;
    renderBufferIndex.position = 0;
    renderBufferIndex.count = 0;
    renderBufferVertex.position = 0;
    renderBufferVertex.count = 0;

    renderProgramBatch._clearBatchData();

    _maskStates.clear();
    for (final renderFrameBuffer in _renderFrameBufferPool) {
      renderFrameBuffer._maskStates.clear();
    }

    for (var i = 0; i < _activeRenderTextures.length; i++) {
      _activeRenderTextures[i] = null;
    }

    RenderProgram.currentVao = null;
    RenderProgram.currentVaoOes = null;
  }

  OES_vertex_array_object? get vaoExtension => _vaoExtension;

  //---------------------------------------------------------------------------

  GLContext get rawContext => _renderingContext;

  @override
  RenderEngine get renderEngine => _isWebGL2 ? RenderEngine.WebGL2 : RenderEngine.WebGL;

  @override
  Object? get maxTextureSize =>
    _renderingContext.getParameter(WebGL.MAX_TEXTURE_SIZE);

  RenderTexture? get activeRenderTexture => _activeRenderTextures[0];
  RenderProgram get activeRenderProgram => _activeRenderProgram;
  RenderFrameBuffer? get activeRenderFrameBuffer => _activeRenderFrameBuffer;
  Matrix3D get activeProjectionMatrix => _projectionMatrix;
  BlendMode? get activeBlendMode => _activeBlendMode;

  bool get contextValid => _contextValid;
  int get contextIdentifier => _contextIdentifier;

  //---------------------------------------------------------------------------
  @override
  Object? getParameter(int parameter) =>
      _renderingContext.getParameter(parameter);

  int? _viewportWidth;
  int? _viewportHeight; 

  @override
  void reset() {
    if (_activeRenderFrameBuffer != null) {
      _activeRenderFrameBuffer = null;
      _renderingContext.bindFramebuffer(WebGL.FRAMEBUFFER, null);
    }

    final viewportWidth = _canvasElement.width;
    final viewportHeight = _canvasElement.height;
    if (viewportWidth != _viewportWidth || viewportHeight != _viewportHeight) {
      _viewportWidth = viewportWidth;
      _viewportHeight = viewportHeight;
      _renderingContext.viewport(0, 0, viewportWidth, viewportHeight);

      _projectionMatrix.setIdentity();
      _projectionMatrix.scale(2.0 / viewportWidth, -2.0 / viewportHeight, 1.0);
      _projectionMatrix.translate(-1.0, 1.0, 0.0);
      _activeRenderProgram.projectionMatrix = _projectionMatrix;
    }

    if (_activeBlendMode != BlendMode.NORMAL) {
      _activeBlendMode = BlendMode.NORMAL;
      _renderingContext.blendFunc(WebGL.ONE, WebGL.ONE_MINUS_SRC_ALPHA);
    }
  }

  @override
  void clear(int color) {
    _getMaskStates().clear();

    if (_resetScissorTest) _updateScissorTest(null);
    if (_resetStencilTest) _updateStencilTest(0);

    if (_resetColor) {
      final num r = colorGetR(color) / 255.0;
      final num g = colorGetG(color) / 255.0;
      final num b = colorGetB(color) / 255.0;
      final num a = colorGetA(color) / 255.0;
      _renderingContext.colorMask(true, true, true, true);
      _renderingContext.clearColor(r * a, g * a, b * a, a);
    }

    _renderingContext.clear(WebGL.COLOR_BUFFER_BIT | WebGL.STENCIL_BUFFER_BIT);
  }

  @override
  void flush() {
    _activeRenderProgram.flush();
  }

  //---------------------------------------------------------------------------

  @override
  void beginRenderMask(RenderState renderState, RenderMask mask) {
    _activeRenderProgram.flush();

    // try to use the scissor rectangle for this mask

    if (mask is ScissorRenderMask) {
      final scissor = mask.getScissorRectangle(renderState);
      if (scissor != null) {
        final last = _getLastScissorValue();
        final next = last == null ? scissor : scissor.intersection(last);
        _getMaskStates().add(_ScissorMaskState(mask, next));
        _updateScissorTest(next);
        return;
      }
    }

    // update the stencil buffer for this mask

    final stencil = _getLastStencilValue() + 1;

    // Single setup for the stencil buffer
    _renderingContext.enable(WebGL.STENCIL_TEST);

    // Only write to stencil buffer, not color buffer
    _renderingContext.colorMask(false, false, false, false);

    // Always pass stencil test during mask rendering
    _renderingContext.stencilFunc(WebGL.ALWAYS, stencil, 0xFF);

    // Write stencil reference value where the mask is rendered
    _renderingContext.stencilOp(WebGL.KEEP, WebGL.KEEP, WebGL.REPLACE);

    // Render the mask shape to the stencil buffer
    mask.renderMask(renderState);
    _activeRenderProgram.flush();

    // Set up stencil test to only draw where mask was rendered
    _renderingContext.stencilFunc(WebGL.EQUAL, stencil, 0xFF);
    _renderingContext.stencilOp(WebGL.KEEP, WebGL.KEEP, WebGL.KEEP);
    _renderingContext.colorMask(true, true, true, true);

    _getMaskStates().add(_StencilMaskState(mask, stencil));
  }

  @override
  void endRenderMask(RenderState renderState, RenderMask mask) {
    _activeRenderProgram.flush();

    final maskState = _getMaskStates().removeLast();
    if (maskState is _ScissorMaskState) {
      _updateScissorTest(_getLastScissorValue());
    } else if (maskState is _StencilMaskState) {
      // Restore previous stencil state instead of re-rendering the mask
      final previousStencilValue = _getLastStencilValue();

      if (_isWebGL2) {
        _renderFullScreenQuadWebGL2(previousStencilValue);
      } else {
        _renderFullScreenQuadWebGL1(previousStencilValue);
      }

      // Restore normal rendering state
      _renderingContext.colorMask(true, true, true, true);
      _updateStencilTest(previousStencilValue);
    }
  }

  // WebGL 1 version of full-screen quad rendering
  void _renderFullScreenQuadWebGL1(int stencilValue) {
    _renderingContext.enable(WebGL.STENCIL_TEST);
    _renderingContext.colorMask(false, false, false, false);

    if (stencilValue > 0) {
      _renderingContext.stencilFunc(WebGL.ALWAYS, stencilValue, 0xFF);
      _renderingContext.stencilOp(WebGL.KEEP, WebGL.KEEP, WebGL.REPLACE);
      _renderFullScreenQuadFallback();
    } else {
      _renderingContext.clearStencil(0);
      _renderingContext.clear(WebGL.STENCIL_BUFFER_BIT);
    }

    // Restore normal rendering state
    _renderingContext.colorMask(true, true, true, true);
  }

  // WebGL 2 optimized version using VAOs
  void _renderFullScreenQuadWebGL2(int stencilValue) {
    final gl2 = _renderingContext as WebGL2RenderingContext;
    gl2.enable(WebGL.STENCIL_TEST);
    gl2.colorMask(false, false, false, false);

    if (stencilValue > 0) {
      gl2.stencilFunc(WebGL.ALWAYS, stencilValue, 0xFF);
      gl2.stencilOp(WebGL.KEEP, WebGL.KEEP, WebGL.REPLACE);
      _renderFullScreenQuadFallback();
    } else {
      gl2.clearStencil(0);
      gl2.clear(WebGL.STENCIL_BUFFER_BIT);
    }
  }

  void _renderFullScreenQuadFallback() {
    activateRenderProgram(renderProgramTriangle);
    activateBlendMode(BlendMode.NONE);

    renderProgramTriangle.renderTriangleMesh(
      RenderState(this),
      _maskQuadIndices,
      _maskQuadVertices,
      0x00000000,
    );
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  @override
  void renderTextureQuad(
      RenderState renderState, RenderTextureQuad renderTextureQuad) {
    activateRenderProgram(renderProgramBatch);
    renderProgramBatch.renderTextureQuad(renderState, this, renderTextureQuad);
  }

  @override
  void renderTextureMesh(RenderState renderState, RenderTexture renderTexture,
      Int16List ixList, Float32List vxList) {
    activateRenderProgram(renderProgramBatch);
    renderProgramBatch.renderTextureMesh(
      renderState, this, renderTexture, ixList, vxList, 1, 1, 1, 1);
  }

  @override
  void renderTextureMapping(
      RenderState renderState,
      RenderTexture renderTexture,
      Matrix mappingMatrix,
      Int16List ixList,
      Float32List vxList) {
    activateRenderProgram(renderProgramTinted);
    activateBlendMode(renderState.globalBlendMode);
    activateRenderTexture(renderTexture);
    renderProgramTinted.renderTextureMapping(
      renderState, mappingMatrix, ixList, vxList, 1, 1, 1, 1);
  }

  //---------------------------------------------------------------------------

  @override
  void renderTriangle(RenderState renderState, num x1, num y1, num x2, num y2,
      num x3, num y3, int color) {
    activateRenderProgram(renderProgramTriangle);
    activateBlendMode(renderState.globalBlendMode);
    renderProgramTriangle.renderTriangle(
      renderState, x1, y1, x2, y2, x3, y3, color);
  }

  //---------------------------------------------------------------------------

  @override
  void renderTriangleMesh(RenderState renderState, Int16List ixList,
      Float32List vxList, int color) {
    activateRenderProgram(renderProgramTriangle);
    activateBlendMode(renderState.globalBlendMode);
    renderProgramTriangle.renderTriangleMesh(
      renderState, ixList, vxList, color);
  }

  //---------------------------------------------------------------------------

  @override
  void renderTextureQuadFiltered(RenderState renderState,
      RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    final firstFilter = renderFilters.length == 1 ? renderFilters[0] : null;

    if (renderFilters.isEmpty) {
      // Don't render anything
    } else if (firstFilter is RenderFilter && firstFilter.isSimple) {
      firstFilter.renderFilter(renderState, renderTextureQuad, 0);
    } else {
      final renderObject =
          _RenderTextureQuadObject(renderTextureQuad, renderFilters);
      renderObjectFiltered(renderState, renderObject);
    }
  }

  //---------------------------------------------------------------------------

  @override
  void renderObjectFiltered(
      RenderState renderState, RenderObject renderObject) {
    final bounds = renderObject.bounds;
    var filters = renderObject.filters;
    final pixelRatio = math.sqrt(renderState.globalMatrix.det.abs());

    var boundsLeft = bounds.left.floor();
    var boundsTop = bounds.top.floor();
    var boundsRight = bounds.right.ceil();
    var boundsBottom = bounds.bottom.ceil();

    for (var i = 0; i < filters.length; i++) {
      final overlap = filters[i].overlap;
      boundsLeft += overlap.left;
      boundsTop += overlap.top;
      boundsRight += overlap.right;
      boundsBottom += overlap.bottom;
    }

    boundsLeft = (boundsLeft * pixelRatio).floor();
    boundsTop = (boundsTop * pixelRatio).floor();
    boundsRight = (boundsRight * pixelRatio).ceil();
    boundsBottom = (boundsBottom * pixelRatio).ceil();

    final boundsWidth = boundsRight - boundsLeft;
    final boundsHeight = boundsBottom - boundsTop;

    final initialRenderFrameBuffer = activeRenderFrameBuffer;
    final initialProjectionMatrix = activeProjectionMatrix.clone();
    RenderFrameBuffer? filterRenderFrameBuffer =
        getRenderFrameBuffer(boundsWidth, boundsHeight);

    final filterProjectionMatrix = Matrix3D.fromIdentity();
    filterProjectionMatrix.scale(2.0 / boundsWidth, 2.0 / boundsHeight, 1.0);
    filterProjectionMatrix.translate(-1.0, -1.0, 0.0);

    var filterRenderState = RenderState(this);
    filterRenderState.globalMatrix.scale(pixelRatio, pixelRatio);
    filterRenderState.globalMatrix.translate(-boundsLeft, -boundsTop);

    final renderFrameBufferMap = <int, RenderFrameBuffer?>{};
    renderFrameBufferMap[0] = filterRenderFrameBuffer;

    //----------------------------------------------

    activateRenderFrameBuffer(filterRenderFrameBuffer);
    activateProjectionMatrix(filterProjectionMatrix);
    activateBlendMode(BlendMode.NORMAL);
    clear(0);

    if (filters.isEmpty) {
      // Don't render anything
    } else if (filters[0].isSimple &&
        renderObject is _RenderTextureQuadObject) {
      final renderTextureQuad = renderObject.renderTextureQuad;
      renderTextureQuadFiltered(
          filterRenderState, renderTextureQuad, [filters[0]]);
      filters = filters.sublist(1);
    } else {
      renderObject.render(filterRenderState);
    }

    //----------------------------------------------

    for (var i = 0; i < filters.length; i++) {
      RenderTextureQuad sourceRenderTextureQuad;
      final filter = filters[i];

      final renderPassSources = filter.renderPassSources;
      final renderPassTargets = filter.renderPassTargets;

      for (var pass = 0; pass < renderPassSources.length; pass++) {
        final renderPassSource = renderPassSources[pass];
        final renderPassTarget = renderPassTargets[pass];

        final RenderFrameBuffer sourceRenderFrameBuffer;

        // get sourceRenderTextureQuad

        if (renderFrameBufferMap.containsKey(renderPassSource)) {
          sourceRenderFrameBuffer = renderFrameBufferMap[renderPassSource]!;
          if (sourceRenderFrameBuffer.renderTexture == null) {
            throw StateError('Invalid renderPassSource!');
          }
          sourceRenderTextureQuad = RenderTextureQuad(
              sourceRenderFrameBuffer.renderTexture!,
              Rectangle<int>(0, 0, boundsWidth, boundsHeight),
              Rectangle<int>(
                  -boundsLeft, -boundsTop, boundsWidth, boundsHeight),
              0,
              pixelRatio);
        } else {
          throw StateError('Invalid renderPassSource!');
        }

        // get targetRenderFrameBuffer

        if (i == filters.length - 1 &&
            renderPassTarget == renderPassTargets.last) {
          filterRenderFrameBuffer = null;
          filterRenderState = renderState;
          activateRenderFrameBuffer(initialRenderFrameBuffer);
          activateProjectionMatrix(initialProjectionMatrix);
          activateBlendMode(filterRenderState.globalBlendMode);
        } else if (renderFrameBufferMap.containsKey(renderPassTarget)) {
          filterRenderFrameBuffer = renderFrameBufferMap[renderPassTarget];
          activateRenderFrameBuffer(filterRenderFrameBuffer);
          activateBlendMode(BlendMode.NORMAL);
        } else {
          filterRenderFrameBuffer =
              getRenderFrameBuffer(boundsWidth, boundsHeight);
          renderFrameBufferMap[renderPassTarget] = filterRenderFrameBuffer;
          activateRenderFrameBuffer(filterRenderFrameBuffer);
          activateBlendMode(BlendMode.NORMAL);
          clear(0);
        }

        // render filter

        filter.renderFilter(filterRenderState, sourceRenderTextureQuad, pass);

        // release obsolete source RenderFrameBuffer

        if (renderPassSources
            .skip(pass + 1)
            .every((rps) => rps != renderPassSource)) {
          renderFrameBufferMap.remove(renderPassSource);
          releaseRenderFrameBuffer(sourceRenderFrameBuffer);
        }
      }

      renderFrameBufferMap.clear();
      renderFrameBufferMap[0] = filterRenderFrameBuffer;
    }
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  T getRenderProgram<T extends RenderProgram>(
          String name, T Function() ifAbsent) =>
      _renderPrograms.putIfAbsent(name, ifAbsent) as T;

  RenderFrameBuffer getRenderFrameBuffer(int width, int height) {
    if (_renderFrameBufferPool.isEmpty) {
      return RenderFrameBuffer.rawWebGL(width, height);
    } else {
      final renderFrameBuffer = _renderFrameBufferPool.removeLast();
      final renderTexture = renderFrameBuffer.renderTexture!;
      final renderStencilBuffer = renderFrameBuffer.renderStencilBuffer;
      if (renderTexture.width != width || renderTexture.height != height) {
        releaseRenderTexture(renderTexture);
        renderTexture.resize(width, height);
        renderStencilBuffer!.resize(width, height);
      }
      return renderFrameBuffer;
    }
  }

  void releaseRenderFrameBuffer(RenderFrameBuffer renderFrameBuffer) {
    _activeRenderProgram.flush();
    _renderFrameBufferPool.add(renderFrameBuffer);
  }

  void releaseRenderTexture(RenderTexture renderTexture) {
    for (var i = 0; i < _activeRenderTextures.length; i++) {
      if (identical(renderTexture, _activeRenderTextures[i])) _unbindTextureAt(i);
    }
  }

  //---------------------------------------------------------------------------

  void activateRenderFrameBuffer(RenderFrameBuffer? renderFrameBuffer) {
    if (!identical(renderFrameBuffer, _activeRenderFrameBuffer)) {
      if (renderFrameBuffer is RenderFrameBuffer) {
        _activeRenderProgram.flush();
        _activeRenderFrameBuffer = renderFrameBuffer;
        _activeRenderFrameBuffer!.activate(this);
        _renderingContext.viewport(
            0, 0, renderFrameBuffer.width!, renderFrameBuffer.height!);
      } else {
        _activeRenderProgram.flush();
        _activeRenderFrameBuffer = null;
        _renderingContext.bindFramebuffer(WebGL.FRAMEBUFFER, null);
        _renderingContext.viewport(
            0, 0, _canvasElement.width, _canvasElement.height);

        // Reset texture state when switching back to the canvas frame buffer
        for (var i = 0; i < _activeRenderTextures.length; i++) {
          _unbindTextureAt(i);
        }
      }
      _updateScissorTest(_getLastScissorValue());
      _updateStencilTest(_getLastStencilValue());
    }
  }

  void activateRenderStencilBuffer(RenderStencilBuffer renderStencilBuffer) {
    if (!identical(renderStencilBuffer, _activeRenderStencilBuffer)) {
      _activeRenderProgram.flush();
      _activeRenderStencilBuffer = renderStencilBuffer;
      _activeRenderStencilBuffer!.activate(this);
    }
  }

  void activateRenderProgram(RenderProgram renderProgram) {
    if (!identical(renderProgram, _activeRenderProgram)) {
      _activeRenderProgram.flush();
      _activeRenderProgram = renderProgram;
      _activeRenderProgram.activate(this);
      _activeRenderProgram.projectionMatrix = _projectionMatrix;
    }
  }

  void activateBlendMode(BlendMode blendMode) {
    if (!identical(blendMode, _activeBlendMode)) {
      // Batch renderer manages its own flushing/drawing.
      if (_activeRenderProgram is! RenderProgramBatch) {
        _activeRenderProgram.flush();
      }

      _activeBlendMode = blendMode;

      if (_activeRenderProgram is! RenderProgramBatch) {
        // Batch renderer program has its own blend handling.
        _renderingContext.blendFunc(blendMode.srcFactor, blendMode.dstFactor);
      }
    }
  }

  void activateRenderTexture(RenderTexture renderTexture) {
    if (!identical(renderTexture, _activeRenderTextures[0])) {
      _activeRenderProgram.flush();
      _activeRenderTextures[0] = renderTexture;
      renderTexture.activate(this, WebGL.TEXTURE0);
    }
  }

  void activateRenderTextureAt(RenderTexture renderTexture, int index, {bool flush = true}) {
    if (!identical(renderTexture, _activeRenderTextures[index])) {
      if (flush) _activeRenderProgram.flush();
      _activeRenderTextures[index] = renderTexture;
      renderTexture.activate(this, WebGL.TEXTURE0 + index);
    }
  }

  void _unbindTextureAt(int index) {
    _renderingContext.activeTexture(WebGL.TEXTURE0 + index);
    _renderingContext.bindTexture(WebGL.TEXTURE_2D, _fallbackTexture);
    _activeRenderTextures[index] = null;
  }

  void activateProjectionMatrix(Matrix3D matrix) {
    _projectionMatrix.copyFrom(matrix);
    _activeRenderProgram.flush();
    _activeRenderProgram.projectionMatrix = _projectionMatrix;
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  List<_MaskState> _getMaskStates() {
    final rfb = _activeRenderFrameBuffer;
    return rfb is RenderFrameBuffer ? rfb._maskStates : _maskStates;
  }

  int _getLastStencilValue() {
    final maskStates = _getMaskStates();
    for (var i = maskStates.length - 1; i >= 0; i--) {
      final maskState = maskStates[i];
      if (maskState is _StencilMaskState) return maskState.value;
    }
    return 0;
  }

  Rectangle<num>? _getLastScissorValue() {
    final maskStates = _getMaskStates();
    for (var i = maskStates.length - 1; i >= 0; i--) {
      final maskState = maskStates[i];
      if (maskState is _ScissorMaskState) return maskState.value;
    }
    return null;
  }

  void _updateStencilTest(int value) {
    if (value == 0) {
      _renderingContext.disable(WebGL.STENCIL_TEST);
    } else {
      _renderingContext.enable(WebGL.STENCIL_TEST);
      _renderingContext.stencilFunc(WebGL.EQUAL, value, 0xFF);
    }
  }

  void _updateScissorTest(Rectangle<num>? value) {
    if (value == null) {
      _renderingContext.disable(WebGL.SCISSOR_TEST);
    } else if (_activeRenderFrameBuffer is RenderFrameBuffer) {
      final x1 = value.left.round();
      final y1 = value.top.round();
      final x2 = value.right.round();
      final y2 = value.bottom.round();
      _renderingContext.enable(WebGL.SCISSOR_TEST);
      _renderingContext.scissor(
          x1, y1, math.max(x2 - x1, 0), math.max(y2 - y1, 0));
    } else {
      final x1 = value.left.round();
      final y1 = _canvasElement.height - value.bottom.round();
      final x2 = value.right.round();
      final y2 = _canvasElement.height - value.top.round();
      _renderingContext.enable(WebGL.SCISSOR_TEST);
      _renderingContext.scissor(
          x1, y1, math.max(x2 - x1, 0), math.max(y2 - y1, 0));
    }
  }

  //---------------------------------------------------------------------------

  void _onContextLost(WebGLContextEvent contextEvent) {
    contextEvent.preventDefault();
    _contextValid = false;
    _contextRestoreRetryCount = 0;
    _contextRestoreRetryScheduled = false;
    _contextRestorePending = false;
    _invalidateCachedState();
    _disposeContextResources();

    _contextLostEvent.add(RenderContextEvent());
  }

  void _onContextRestored(WebGLContextEvent contextEvent) {
    _contextRestorePending = true;
  }

  void _restoreContext() {
    _contextValid = true;
    _contextIdentifier = ++_globalContextIdentifier;

    try {
      _initializeAfterContextChange();
      reset();
    } on StateError catch (e) { // ignore: avoid_catching_errors
      if (!_shouldRetryContextRestore(e) || _contextRestoreRetryCount >= _maxContextRestoreRetries) rethrow;

      _contextValid = false;
      _invalidateCachedState();
      _disposeContextResources();
      _scheduleContextRestoreRetry();
      return;
    }

    _contextRestoreRetryCount = 0;
    _contextRestoreRetryScheduled = false;
    _contextRestorePending = false;

    _contextRestoredEvent.add(RenderContextEvent());
  }

  bool _shouldRetryContextRestore(StateError error) {
    final message = error.message;
    return message == 'ContextLost' || message == 'ProgramLinkFailed' || message == 'ShaderCompileFailed';
  }

  void _scheduleContextRestoreRetry() {
    if (_contextRestoreRetryScheduled) return;

    _contextRestoreRetryScheduled = true;
    _contextRestoreRetryCount += 1;

    Timer(_contextRestoreRetryDelay * _contextRestoreRetryCount, () {
      _contextRestoreRetryScheduled = false;
      _restoreContext();
    });
  }

  void restoreIfPending() {
    if (!_contextRestorePending || _contextRestoreRetryScheduled) return;
    _restoreContext();
  }

  void _disposeContextResources() {
    _vaoExtension = null;
    _fallbackTexture = null;
  }
}
