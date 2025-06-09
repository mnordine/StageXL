part of '../engine.dart';

extension type WebGLProvokingVertex._(JSObject _) {
  external GLenum get FIRST_VERTEX_CONVENTION_WEBGL; // ignore: non_constant_identifier_names
  external void provokingVertexWEBGL(GLenum value);
}

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

  OES_vertex_array_object? _vaoExtension;

  // Simple full-screen quad for mask operations
  final _maskQuadIndices = Int16List.fromList([0, 1, 2, 0, 2, 3]);
  final _maskQuadVertices = Float32List.fromList([
    -1.0, -1.0,  // Bottom-left
     1.0, -1.0,  // Bottom-right
     1.0,  1.0,  // Top-right
    -1.0,  1.0   // Top-left
  ]);

  // WebGL 2 specific properties
  WebGLVertexArrayObject? _maskQuadVao;
  WebGLProgram? _maskProgram;

  WebGLVertexArrayObjectOES? _maskQuadVAOWebGL1;

  //---------------------------------------------------------------------------

  final RenderProgramTinted renderProgramTinted = RenderProgramTinted();
  final RenderProgramTriangle renderProgramTriangle = RenderProgramTriangle();

  final RenderBufferIndex renderBufferIndex = RenderBufferIndex(16384);
  final RenderBufferVertex renderBufferVertex = RenderBufferVertex(32768);

  final List<RenderTexture?> _activeRenderTextures = List.filled(8, null);
  final List<RenderFrameBuffer> _renderFrameBufferPool = <RenderFrameBuffer>[];
  final Map<String, RenderProgram> _renderPrograms = <String, RenderProgram>{};

  //---------------------------------------------------------------------------

  RenderContextWebGL(HTMLCanvasElement canvasElement,
      {required PowerPreference powerPreference, bool alpha = false, bool antialias = false, bool forceWebGL1 = false})
      : _canvasElement = canvasElement {
    _canvasElement.onWebGlContextLost.listen(_onContextLost);
    _canvasElement.onWebGlContextRestored.listen(_onContextRestored);

    WebGLRenderingContext? renderingContext;

    if (!forceWebGL1) {
      // Try WebGL 2 first
      renderingContext = _canvasElement.getContext('webgl2', {
        'alpha': alpha,
        'antialias': antialias,
        'depth': false,
        'powerPreference': powerPreference.value,
        'stencil': true,
      }.jsify()) as WebGL?;
    }

    _isWebGL2 = renderingContext != null;

    // Fall back to WebGL 1 if WebGL 2 is not available
    renderingContext ??= _canvasElement.getContext3d(
        alpha: alpha, antialias: antialias, depth: false, stencil: true) as WebGL?;

    if (renderingContext == null) {
      throw StateError('Failed to get WebGL context.');
    }

    _renderingContext = renderingContext;
    _renderingContext.enable(WebGL.BLEND);
    _renderingContext.disable(WebGL.STENCIL_TEST);
    _renderingContext.disable(WebGL.DEPTH_TEST);
    _renderingContext.disable(WebGL.CULL_FACE);
    _renderingContext.pixelStorei(WebGL.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
    _renderingContext.blendFunc(WebGL.ONE, WebGL.ONE_MINUS_SRC_ALPHA);

    _activeRenderProgram = renderProgramTinted;
    _activeRenderProgram.activate(this);

    _contextValid = true;
    _contextIdentifier = ++_globalContextIdentifier;

    CompressedTexture.initExtensions(_renderingContext);

    if (!isWebGL2) {
      _vaoExtension = renderingContext.getExtension('OES_vertex_array_object') as OES_vertex_array_object?;

      _setupWebGL1Features();
    }

    if (_isWebGL2) _setupWebGL2Features();

    reset();
  }

  // Add this method to set up VAO for WebGL 1
  void _setupWebGL1Features() {
    if (_vaoExtension == null) return;

    final maskProgram = _maskProgram = _createMaskProgram();

    final positionLocation = _renderingContext.getAttribLocation(maskProgram, 'aPosition');

    // Create a VAO for mask quad using the extension
    _maskQuadVAOWebGL1 = _vaoExtension!.createVertexArrayOES() as WebGLVertexArrayObjectOES;
    _vaoExtension!.bindVertexArrayOES(_maskQuadVAOWebGL1);

    // Set up vertex buffer
    final vertexBuffer = _renderingContext.createBuffer();
    _renderingContext.bindBuffer(WebGL.ARRAY_BUFFER, vertexBuffer);
    _renderingContext.bufferData(WebGL.ARRAY_BUFFER, _maskQuadVertices.toJS, WebGL.STATIC_DRAW);

    // Set up index buffer
    final indexBuffer = _renderingContext.createBuffer();
    _renderingContext.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, indexBuffer);
    _renderingContext.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, _maskQuadIndices.toJS, WebGL.STATIC_DRAW);

    _renderingContext.enableVertexAttribArray(positionLocation);
    _renderingContext.vertexAttribPointer(positionLocation, 2, WebGL.FLOAT, false, 8, 0);

    // Save the program for later use
    _renderingContext.useProgram(_maskProgram);

    // Unbind VAO
    _vaoExtension!.bindVertexArrayOES(null);

    // Restore previous program
    _activeRenderProgram.activate(this);
  }

  void _setupWebGL2Features() {
    final gl2 = _renderingContext as WebGL2RenderingContext;

    // Create a VAO for our mask quad
    _maskQuadVao = gl2.createVertexArray();
    gl2.bindVertexArray(_maskQuadVao);

    // Set up vertex buffer
    final vertexBuffer = gl2.createBuffer();
    gl2.bindBuffer(WebGL.ARRAY_BUFFER, vertexBuffer);
    gl2.bufferData(WebGL.ARRAY_BUFFER, _maskQuadVertices.toJS, WebGL.STATIC_DRAW);

    // Set up index buffer
    final indexBuffer = gl2.createBuffer();
    gl2.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, indexBuffer);
    gl2.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, _maskQuadIndices.toJS, WebGL.STATIC_DRAW);

    // Create minimal program for mask operations
    _maskProgram = _createMaskProgram();
    gl2.useProgram(_maskProgram);

    // Set up vertex attributes
    gl2.enableVertexAttribArray(0);
    gl2.vertexAttribPointer(0, 2, WebGL.FLOAT, false, 8, 0);

    // Unbind VAO to prevent accidental modifications
    gl2.bindVertexArray(null);

    // Restore previous program
    _activeRenderProgram.activate(this);

    // https://registry.khronos.org/webgl/extensions/WEBGL_provoking_vertex/
    // Modern APIs, such as Metal, Vulkan, Direct3D 12, use the first vertex 
    // as the provoking vertex, whereas WebGL API uses last. This can cause 
    // performance degradation as, behind the scenes, workarounds are done to 
    // switch from first vertex to last vertex in the implementation.

    // Note this is only for flat shading, or solid colors.

    // It seems there is no reason not to set this for WebGL2.
    final ext = gl2.getExtension('WEBGL_provoking_vertex') as WebGLProvokingVertex?;
    ext?.provokingVertexWEBGL(ext.FIRST_VERTEX_CONVENTION_WEBGL);
  }

  // Create a minimal shader program for mask operations
  WebGLProgram _createMaskProgram() {
    final gl = _renderingContext;

    // Vertex shader - just pass through positions
    final vShader = gl.createShader(WebGL.VERTEX_SHADER)!;
    if (isWebGL2) {
      gl.shaderSource(vShader, '''
        #version 300 es
        layout(location = 0) in vec2 aPosition;
        void main() {
          gl_Position = vec4(aPosition, 0.0, 1.0);
        }
      ''');
    } else {
      gl.shaderSource(vShader, '''
        attribute vec2 aPosition;
        void main() {
          gl_Position = vec4(aPosition, 0.0, 1.0);
        }
      ''');
    }
    gl.compileShader(vShader);

    // Fragment shader - outputs nothing (we only care about stencil)
    final fShader = gl.createShader(WebGL.FRAGMENT_SHADER)!;
    if (isWebGL2) {
      gl.shaderSource(fShader, '''
        #version 300 es
        precision mediump float;
        out vec4 fragColor;
        void main() {
          fragColor = vec4(0.0);
        }
      ''');
    } else {
      gl.shaderSource(fShader, '''
        precision mediump float;
        void main() {
          gl_FragColor = vec4(0.0);
        }
      ''');
    }
    gl.compileShader(fShader);

    // Create and link program
    final program = gl.createProgram()!;
    gl.attachShader(program, vShader);
    gl.attachShader(program, fShader);
    gl.linkProgram(program);

    // Check for compilation errors
    if (!(gl.getProgramParameter(program, WebGL.LINK_STATUS) as JSBoolean).toDart) {
      final error = gl.getProgramInfoLog(program);
      gl.deleteProgram(program);
      throw StateError('Failed to link mask program: $error');
    }

    // Clean up shaders
    gl.deleteShader(vShader);
    gl.deleteShader(fShader);

    return program;
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

  @override
  void reset() {
    final viewportWidth = _canvasElement.width;
    final viewportHeight = _canvasElement.height;
    _activeRenderFrameBuffer = null;
    _renderingContext.bindFramebuffer(WebGL.FRAMEBUFFER, null);
    _renderingContext.viewport(0, 0, viewportWidth, viewportHeight);
    _projectionMatrix.setIdentity();
    _projectionMatrix.scale(2.0 / viewportWidth, -2.0 / viewportHeight, 1.0);
    _projectionMatrix.translate(-1.0, 1.0, 0.0);
    _activeRenderProgram.projectionMatrix = _projectionMatrix;
  }

  @override
  void clear(int color) {
    _getMaskStates().clear();
    _updateScissorTest(null);
    _updateStencilTest(0);
    final num r = colorGetR(color) / 255.0;
    final num g = colorGetG(color) / 255.0;
    final num b = colorGetB(color) / 255.0;
    final num a = colorGetA(color) / 255.0;
    _renderingContext.colorMask(true, true, true, true);
    _renderingContext.clearColor(r * a, g * a, b * a, a);
    _renderingContext
        .clear(WebGL.COLOR_BUFFER_BIT | WebGL.STENCIL_BUFFER_BIT);
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

      if (_vaoExtension != null && _maskQuadVAOWebGL1 != null) {
        // Save current program state
        final currentProgram = _renderingContext.getParameter(WebGL.CURRENT_PROGRAM) as WebGLProgram?;

        // Use triangle program for the quad
        activateRenderProgram(renderProgramTriangle);

        // Use VAO for efficient rendering
        _vaoExtension!.bindVertexArrayOES(_maskQuadVAOWebGL1);
        _renderingContext.drawElements(WebGL.TRIANGLES, 6, WebGL.UNSIGNED_SHORT, 0);
        _vaoExtension!.bindVertexArrayOES(null);

        // Restore previous program if there was one
        if (currentProgram != null) {
          _renderingContext.useProgram(currentProgram);
        }
      } else {
        // Fall back to original method if VAO not available
        activateRenderProgram(renderProgramTriangle);
        activateBlendMode(BlendMode.NONE);

        renderProgramTriangle.renderTriangleMesh(
          RenderState(this),
          _maskQuadIndices,
          _maskQuadVertices,
          0x00000000
        );
      }
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

      // Save current program
      final currentProgram = gl2.getParameter(WebGL.CURRENT_PROGRAM) as WebGLProgram;

      // Use our minimal mask program and VAO
      gl2.useProgram(_maskProgram);
      gl2.bindVertexArray(_maskQuadVao);

      // Draw the quad
      gl2.drawElements(WebGL.TRIANGLES, 6, WebGL.UNSIGNED_SHORT, 0);

      // Restore state
      gl2.bindVertexArray(null);
      gl2.useProgram(currentProgram);
    } else {
      gl2.clearStencil(0);
      gl2.clear(WebGL.STENCIL_BUFFER_BIT);
    }
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  @override
  void renderTextureQuad(
      RenderState renderState, RenderTextureQuad renderTextureQuad) {
    activateRenderProgram(renderProgramTinted);
    activateBlendMode(renderState.globalBlendMode);
    activateRenderTexture(renderTextureQuad.renderTexture);
    renderProgramTinted.renderTextureQuad(renderState, renderTextureQuad, 1, 1, 1, 1);
  }

  @override
  void renderTextureMesh(RenderState renderState, RenderTexture renderTexture,
      Int16List ixList, Float32List vxList) {
    activateRenderProgram(renderProgramTinted);
    activateBlendMode(renderState.globalBlendMode);
    activateRenderTexture(renderTexture);
    renderProgramTinted.renderTextureMesh(renderState, ixList, vxList, 1, 1, 1, 1);
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
      if (identical(renderTexture, _activeRenderTextures[i])) {
        _activeRenderTextures[i] = null;
        _renderingContext.activeTexture(WebGL.TEXTURE0 + i);
        _renderingContext.bindTexture(WebGL.TEXTURE_2D, null);
      }
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
      _activeRenderProgram.flush();
      _activeBlendMode = blendMode;
      _activeBlendMode!.blend(_renderingContext);
    }
  }

  void activateRenderTexture(RenderTexture renderTexture) {
    if (!identical(renderTexture, _activeRenderTextures[0])) {
      _activeRenderProgram.flush();
      _activeRenderTextures[0] = renderTexture;
      renderTexture.activate(this, WebGL.TEXTURE0);
    }
  }

  void activateRenderTextureAt(RenderTexture renderTexture, int index) {
    if (!identical(renderTexture, _activeRenderTextures[index])) {
      _activeRenderProgram.flush();
      _activeRenderTextures[index] = renderTexture;
      renderTexture.activate(this, WebGL.TEXTURE0 + index);
    }
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

    // Clean up WebGL 2 resources
    if (_isWebGL2) {
      _maskQuadVao = null;
      _maskProgram = null;
    }  else if (_vaoExtension != null) {
      _maskQuadVAOWebGL1 = null;
    }

    _contextLostEvent.add(RenderContextEvent());
  }

  void _onContextRestored(WebGLContextEvent contextEvent) {
    _contextValid = true;
    _contextIdentifier = ++_globalContextIdentifier;

    // Re-initialize WebGL 2 features
    if (_isWebGL2) {
      _setupWebGL2Features();
    }  else if (_vaoExtension != null) {
      _setupWebGL1Features();
    }

    _contextRestoredEvent.add(RenderContextEvent());
  }
}
