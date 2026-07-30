part of '../engine.dart';

typedef RenderProgramCallback<TParameters> = void Function(RenderFilterContext context, TParameters parameters);

abstract class RenderProgram<TContext extends RenderContext, TParameters> {
  const RenderProgram();
}

abstract class RenderProgramWebGL<TParameters> extends RenderProgram<RenderContextWebGL, TParameters> {
  late _Resources _resources;
  RenderContextWebGL? _activeRenderContext;
  var _hasResources = false;

  static var fragmentPrecision = 'mediump';

  static WebGLVertexArrayObject? currentVao;
  static WebGLVertexArrayObjectOES? currentVaoOes;

  bool get isWebGL2 => _resources.driver.isWebGL2;

  RenderProgramWebGL();

  factory RenderProgramWebGL.callback(RenderProgramCallback<TParameters> render) = _WebGLCallback<TParameters>;

  //---------------------------------------------------------------------------

  String get vertexShaderSource;
  String get fragmentShaderSource;

  int get contextIdentifier => _resources.renderContext.contextIdentifier;
  RenderBufferIndex get renderBufferIndex => _resources.renderContext.renderBufferIndex;
  RenderBufferVertex get renderBufferVertex => _resources.renderContext.renderBufferVertex;
  RenderStatistics get renderStatistics => _resources.renderContext.renderStatistics;
  WebGL get renderingContext => _resources.renderingContext;
  WebGLProgram get program => _resources.program!;

  Map<String, int> get attributes => _resources.attributes;
  Map<String, WebGLUniformLocation> get uniforms => _resources.uniforms;

  void renderFilter(RenderFilterContext context, TParameters parameters) {
    throw UnsupportedError('$runtimeType cannot render a filter pass.');
  }

  //---------------------------------------------------------------------------

  set projectionMatrix(Matrix3D matrix) {
    final location = uniforms['uProjectionMatrix'];
    renderingContext.uniformMatrix4fv(location, false, matrix.data.toJS);
  }

  //---------------------------------------------------------------------------

  void activate(RenderContextWebGL renderContext) {
    _resources = renderContext._resourcesForProgram(this);
    _activeRenderContext = renderContext;
    _hasResources = true;
    if (!_resources.initialized) {
      _createVao();
      _bindVAO();

      _resources.program = _createProgram(renderingContext);
      _resources.programAllocated = true;
      ResourceDiagnostics.register(.webglProgram);
      _updateAttributes(renderingContext, program);
      _updateUniforms(renderingContext, program);

      renderBufferIndex.activate(renderContext);
      renderBufferVertex.activate(renderContext);
      setupAttributes();
      _resources.initialized = true;
    }

    if (!_resources.driver.supportsVao) {
      renderBufferIndex.activate(renderContext);
      renderBufferVertex.activate(renderContext);
      setupAttributes();
    }

    // Always bind this program's VAO when VAOs are supported. This ensures
    // that attribute bindings saved in the VAO are restored even when the
    // program was previously initialized and another program (for example
    // a filter) may have bound a different VAO in the meantime.
    _bindVAO();

    renderingContext.useProgram(program);
  }

  void _createVao() {
    _resources.driver.createVao();
    if (_resources.driver.vao != null) {
      _resources.vertexArrayAllocated = true;
      ResourceDiagnostics.register(.webglVertexArray);
    }
  }

  void _bindVAO() => _resources.driver.bindVao();

  void setupAttributes();

  //---------------------------------------------------------------------------

  void dispose() {
    if (!_hasResources) return;
    _resources.dispose();
    _activeRenderContext = null;
    _hasResources = false;
  }

  bool hasActiveResourcesFor(RenderContextWebGL renderContext) => identical(_activeRenderContext, renderContext);

  void flush() {
    if (renderBufferIndex.position > 0 && renderBufferVertex.position > 0) {
      _bindVAO();
      final count = renderBufferIndex.position;
      renderBufferIndex.update();
      renderBufferIndex.position = 0;
      renderBufferIndex.count = 0;
      renderBufferVertex.update();
      renderBufferVertex.position = 0;
      renderBufferVertex.count = 0;
      renderingContext.drawElements(
          WebGL.TRIANGLES, count, WebGL.UNSIGNED_SHORT, 0);
      renderStatistics.drawCount += 1;
    }
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  WebGLProgram _createProgram(WebGL rc) {
    final program = rc.createProgram();
    if (program == null) {
      throw StateError(rc.isContextLost() ? 'ContextLost' : 'Failed to create WebGL program.');
    }

    final vShader =
        _createShader(rc, vertexShaderSource, WebGL.VERTEX_SHADER);
    final fShader =
        _createShader(rc, fragmentShaderSource, WebGL.FRAGMENT_SHADER);

    rc.attachShader(program, vShader);
    rc.attachShader(program, fShader);
    rc.linkProgram(program);

    final status = (rc.getProgramParameter(program, WebGL.LINK_STATUS) as JSBoolean?)?.toDart;
    if (status == true) return program;

    final cl = rc.isContextLost();
    throw StateError(cl ? 'ContextLost' : rc.getProgramInfoLog(program) ?? 'Failed to link WebGL program.');
  }

  //---------------------------------------------------------------------------

  WebGLShader _createShader(WebGL rc, String source, int type) {
    final shader = rc.createShader(type);
    if (shader == null) {
      throw StateError(rc.isContextLost() ? 'ContextLost' : 'Failed to create WebGL shader.');
    }

    rc.shaderSource(shader, source);
    rc.compileShader(shader);

    final status = (rc.getShaderParameter(shader, WebGL.COMPILE_STATUS) as JSBoolean?)?.toDart;
    if (status == true) return shader;

    final cl = rc.isContextLost();
    throw StateError(cl ? 'ContextLost' : rc.getShaderInfoLog(shader) ?? 'Failed to compile WebGL shader.');
  }

  //---------------------------------------------------------------------------

  void _updateAttributes(WebGL rc, WebGLProgram program) {
    final count =
        (rc.getProgramParameter(program, WebGL.ACTIVE_ATTRIBUTES)! as JSNumber).toDartInt;

    // If VAOs are supported we should not try to globally disable vertex
    // attribute arrays here. VAOs encapsulate attribute state and disabling
    // arrays globally can corrupt other VAOs' state (this was breaking
    // WebGL2 runs). When VAOs are supported we just enable attributes for
    // the currently bound VAO and record their locations.
    if (_resources.driver.supportsVao) {
      attributes.clear();
      for (var i = 0; i < count; i++) {
        final activeInfo = rc.getActiveAttrib(program, i)!;
        final location = rc.getAttribLocation(program, activeInfo.name);
        try {
          rc.enableVertexAttribArray(location);
        } catch (_) {}
        attributes[activeInfo.name] = location;
      }
      return;
    }

    // Fallback for platforms without VAO support: track enabled attribute
    // arrays globally and disable any that aren't used by the new program.
    final newAttributes = <String, int>{};
    final newLocations = <int>{};
    for (var i = 0; i < count; i++) {
      final activeInfo = rc.getActiveAttrib(program, i)!;
      final location = rc.getAttribLocation(program, activeInfo.name);
      newAttributes[activeInfo.name] = location;
      newLocations.add(location);
    }

    final enabledVertexAttribArrays = _resources.renderContext._enabledVertexAttribArrays;
    for (final loc in enabledVertexAttribArrays.toList()) {
      if (!newLocations.contains(loc)) {
        try {
          rc.disableVertexAttribArray(loc);
        } catch (_) {
          // ignore errors when disabling invalid locations
        }
        enabledVertexAttribArrays.remove(loc);
      }
    }

    attributes.clear();
    newAttributes.forEach((name, location) {
      try {
        rc.enableVertexAttribArray(location);
      } catch (_) {}
      enabledVertexAttribArrays.add(location);
      attributes[name] = location;
    });
  }

  //---------------------------------------------------------------------------

  void _updateUniforms(WebGL rc, WebGLProgram program) {
    uniforms.clear();
    final count =
        (rc.getProgramParameter(program, WebGL.ACTIVE_UNIFORMS)! as JSNumber).toDartInt;

    for (var i = 0; i < count; i++) {
      final activeInfo = rc.getActiveUniform(program, i)!;
      final location = rc.getUniformLocation(program, activeInfo.name)!;
      uniforms[activeInfo.name] = location;
    }
  }
}

sealed class _WebGLDriver<TContext extends JSObject, TVao extends JSObject> {
  final TContext renderingContext;
  TVao? vao;

  _WebGLDriver(this.renderingContext);

  bool get isWebGL2;
  bool get supportsVao;

  void createVao();
  void bindVao();
  void dispose();

  Never vaoCreationFailed() => throw StateError(
        isContextLost ? 'ContextLost' : 'Failed to create WebGL vertex array.',
      );

  bool get isContextLost;
}

final class _WebGL1Driver extends _WebGLDriver<WebGLRenderingContext, WebGLVertexArrayObjectOES> {
  final OES_vertex_array_object? extension;

  _WebGL1Driver(super.renderingContext, this.extension);

  @override
  bool get isWebGL2 => false;

  @override
  bool get supportsVao => extension != null;

  @override
  bool get isContextLost => renderingContext.isContextLost();

  @override
  void createVao() {
    if (!supportsVao) return;
    vao = extension!.createVertexArrayOES() ?? vaoCreationFailed();
  }

  @override
  void bindVao() {
    if (!supportsVao || RenderProgramWebGL.currentVaoOes == vao) return;
    extension!.bindVertexArrayOES(vao);
    RenderProgramWebGL.currentVaoOes = vao;
  }

  @override
  void dispose() {
    if (vao == null) return;
    extension?.deleteVertexArrayOES(vao);
    vao = null;
  }
}

final class _WebGL2Driver extends _WebGLDriver<WebGL2RenderingContext, WebGLVertexArrayObject> {
  _WebGL2Driver(super.renderingContext);

  @override
  bool get isWebGL2 => true;

  @override
  bool get supportsVao => true;

  @override
  bool get isContextLost => renderingContext.isContextLost();

  @override
  void createVao() {
    vao = renderingContext.createVertexArray() ?? vaoCreationFailed();
  }

  @override
  void bindVao() {
    if (RenderProgramWebGL.currentVao == vao) return;
    renderingContext.bindVertexArray(vao);
    RenderProgramWebGL.currentVao = vao;
  }

  @override
  void dispose() {
    if (vao == null) return;
    renderingContext.deleteVertexArray(vao);
    vao = null;
  }
}

final class _Resources {
  final RenderContextWebGL renderContext;
  final WebGL renderingContext;
  final _WebGLDriver driver;
  final attributes = <String, int>{};
  final uniforms = <String, WebGLUniformLocation>{};
  WebGLProgram? program;
  var initialized = false;
  var programAllocated = false;
  var vertexArrayAllocated = false;

  _Resources(this.renderContext)
      : renderingContext = renderContext.rawContext,
        driver = renderContext.isWebGL2
            ? _WebGL2Driver(renderContext.rawContext as WebGL2RenderingContext)
            : _WebGL1Driver(renderContext.rawContext, renderContext.vaoExtension);

  void dispose() {
    release(delete: true);
  }

  void release({required bool delete}) {
    if (delete) {
      driver.dispose();
      final program = this.program;
      if (program != null) renderingContext.deleteProgram(program);
    } else {
      driver.vao = null;
    }
    if (vertexArrayAllocated) {
      ResourceDiagnostics.unregister(.webglVertexArray);
      vertexArrayAllocated = false;
    }
    if (programAllocated) {
      ResourceDiagnostics.unregister(.webglProgram);
      programAllocated = false;
    }
    program = null;
    initialized = false;
  }
}

final class _WebGLCallback<TParameters> extends RenderProgramWebGL<TParameters> {
  final RenderProgramCallback<TParameters> _render;

  _WebGLCallback(this._render);

  @override
  String get vertexShaderSource => throw UnsupportedError('Callback programs do not define shaders.');

  @override
  String get fragmentShaderSource => throw UnsupportedError('Callback programs do not define shaders.');

  @override
  void setupAttributes() => throw UnsupportedError('Callback programs do not define attributes.');

  @override
  void renderFilter(RenderFilterContext context, TParameters parameters) => _render(context, parameters);
}
