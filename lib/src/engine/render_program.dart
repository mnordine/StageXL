part of '../engine.dart';

abstract class RenderProgram {
  var _contextIdentifier = -1;

  late WebGL _renderingContext;
  late WebGLProgram _program;
  WebGLVertexArrayObject? _vao;
  WebGLVertexArrayObjectOES? _vaoOes;
  var _supportsVao = false;
  OES_vertex_array_object? _vaoExtension;

  final Map<String, int> _attributes;
  final Map<String, WebGLUniformLocation> _uniforms;
  RenderBufferIndex _renderBufferIndex;
  RenderBufferVertex _renderBufferVertex;
  RenderStatistics _renderStatistics;

  static var fragmentPrecision = 'mediump';

  static WebGLVertexArrayObject? currentVao;
  static WebGLVertexArrayObjectOES? currentVaoOes;

  // Track enabled vertex attrib arrays globally so we can disable those
  // that are not used by the newly activated program. This avoids
  // leftover vertex attribute state from other programs (for example
  // filter programs) causing incorrect vertex attribute pointers.
  static final _enabledVertexAttribArrays = <int>{};

  bool? _isWebGL2;
  bool get isWebGL2 => 
    _isWebGL2 ??= _renderingContext.isA<WebGL2RenderingContext>();

  RenderProgram()
      : _attributes = <String, int>{},
        _uniforms = <String, WebGLUniformLocation>{},
        _renderBufferIndex = RenderBufferIndex(0),
        _renderBufferVertex = RenderBufferVertex(0),
        _renderStatistics = RenderStatistics();

  //---------------------------------------------------------------------------

  String get vertexShaderSource;
  String get fragmentShaderSource;

  int get contextIdentifier => _contextIdentifier;
  RenderBufferIndex get renderBufferIndex => _renderBufferIndex;
  RenderBufferVertex get renderBufferVertex => _renderBufferVertex;
  RenderStatistics get renderStatistics => _renderStatistics;
  WebGL get renderingContext => _renderingContext;
  WebGLProgram get program => _program;

  Map<String, int> get attributes => _attributes;
  Map<String, WebGLUniformLocation> get uniforms => _uniforms;

  //---------------------------------------------------------------------------

  set projectionMatrix(Matrix3D matrix) {
    final location = uniforms['uProjectionMatrix'];
    renderingContext.uniformMatrix4fv(location, false, matrix.data.toJS);
  }

  //---------------------------------------------------------------------------

  void activate(RenderContextWebGL renderContext) {
    if (contextIdentifier != renderContext.contextIdentifier) {
      _contextIdentifier = renderContext.contextIdentifier;
      _renderingContext = renderContext.rawContext;
      _renderStatistics = renderContext.renderStatistics;
      _renderBufferIndex = renderContext.renderBufferIndex;
      _renderBufferVertex = renderContext.renderBufferVertex;
      
      // Check for VAO support
      _supportsVao = isWebGL2;
      if (!_supportsVao) {
        _vaoExtension = renderContext.vaoExtension;
        _supportsVao = _vaoExtension != null;
      }

      _createVao();
      _bindVAO();

      _program = _createProgram(_renderingContext);
      _updateAttributes(_renderingContext, _program);
      _updateUniforms(_renderingContext, _program);

      _renderBufferIndex.activate(renderContext);
      _renderBufferVertex.activate(renderContext);
      setupAttributes();
    }

    if (!_supportsVao) {
      _renderBufferIndex.activate(renderContext);
      _renderBufferVertex.activate(renderContext);
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
    if (!_supportsVao) return;

    if (isWebGL2) {
      final vao = (_renderingContext as WebGL2RenderingContext).createVertexArray();
      if (vao == null) {
        throw StateError(_renderingContext.isContextLost() ? 'ContextLost' : 'Failed to create WebGL vertex array.');
      }
      _vao = vao;
    } else {
      final vao = _vaoExtension?.createVertexArrayOES();
      if (vao == null) {
        throw StateError(_renderingContext.isContextLost() ? 'ContextLost' : 'Failed to create WebGL vertex array.');
      }
      _vaoOes = vao;
    }
  }

  void _bindVAO() {
    if (!_supportsVao) return;

    if (isWebGL2) {
      if (currentVao != _vao) {
        (_renderingContext as WebGL2RenderingContext).bindVertexArray(_vao);
        currentVao = _vao;
      }
    } else {
      if (currentVaoOes != _vaoOes) {
        _vaoExtension?.bindVertexArrayOES(_vaoOes);
        currentVaoOes = _vaoOes;
      }
    }
  }

  void setupAttributes();

  //---------------------------------------------------------------------------

  void dispose() {
    if (_vao != null) {
      (_renderingContext as WebGL2RenderingContext).deleteVertexArray(_vao);
      _vao = null;
    } 
    
    if (_vaoOes != null) {
      _vaoExtension?.deleteVertexArrayOES(_vaoOes);
      _vaoOes = null;
    }
  }

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

    _clearWebGlErrors(rc);
    rc.attachShader(program, vShader);
    rc.attachShader(program, fShader);
    rc.linkProgram(program);

    final status = (rc.getProgramParameter(program, WebGL.LINK_STATUS) as JSBoolean?)?.toDart;
    if (status == true) return program;

    if (rc.isContextLost()) throw StateError('ContextLost');

    final infoLog = rc.getProgramInfoLog(program) ?? '';
    if (infoLog.isNotEmpty) throw StateError(infoLog);

    final error = rc.getError();
    if (error != WebGL.NO_ERROR) throw StateError('Failed to link program. WebGL error: $error');

    throw StateError('Failed to link WebGL program.');
  }

  //---------------------------------------------------------------------------

  WebGLShader _createShader(WebGL rc, String source, int type) {
    final shader = rc.createShader(type);
    if (shader == null) {
      throw StateError(rc.isContextLost() ? 'ContextLost' : 'Failed to create WebGL shader.');
    }

    _clearWebGlErrors(rc);
    rc.shaderSource(shader, source);
    rc.compileShader(shader);

    final status = (rc.getShaderParameter(shader, WebGL.COMPILE_STATUS) as JSBoolean?)?.toDart;
    if (status == true) return shader;

    if (rc.isContextLost()) throw StateError('ContextLost');

    final infoLog = rc.getShaderInfoLog(shader) ?? '';
    if (infoLog.isNotEmpty) throw StateError(infoLog);

    final error = rc.getError();
    if (error != WebGL.NO_ERROR) throw StateError('Failed to compile shader. WebGL error: $error');

    throw StateError('Failed to compile WebGL shader.');
  }

  void _clearWebGlErrors(WebGL rc) {
    if (rc.isContextLost()) return;

    while (rc.getError() != WebGL.NO_ERROR) {}
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
    if (_supportsVao) {
      _attributes.clear();
      for (var i = 0; i < count; i++) {
        final activeInfo = rc.getActiveAttrib(program, i)!;
        final location = rc.getAttribLocation(program, activeInfo.name);
        try {
          rc.enableVertexAttribArray(location);
        } catch (_) {}
        _attributes[activeInfo.name] = location;
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

    for (final loc in _enabledVertexAttribArrays.toList()) {
      if (!newLocations.contains(loc)) {
        try {
          rc.disableVertexAttribArray(loc);
        } catch (_) {
          // ignore errors when disabling invalid locations
        }
        _enabledVertexAttribArrays.remove(loc);
      }
    }

    _attributes.clear();
    newAttributes.forEach((name, location) {
      try {
        rc.enableVertexAttribArray(location);
      } catch (_) {}
      _enabledVertexAttribArrays.add(location);
      _attributes[name] = location;
    });
  }

  //---------------------------------------------------------------------------

  void _updateUniforms(WebGL rc, WebGLProgram program) {
    _uniforms.clear();
    final count =
        (rc.getProgramParameter(program, WebGL.ACTIVE_UNIFORMS)! as JSNumber).toDartInt;

    for (var i = 0; i < count; i++) {
      final activeInfo = rc.getActiveUniform(program, i)!;
      final location = rc.getUniformLocation(program, activeInfo.name)!;
      _uniforms[activeInfo.name] = location;
    }
  }
}
