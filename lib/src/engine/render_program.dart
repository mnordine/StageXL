part of '../engine.dart';

abstract class RenderProgram {
  int _contextIdentifier = -1;

  late WebGL _renderingContext;
  late WebGLProgram _program;
  WebGLVertexArrayObject? _vao;
  WebGLVertexArrayObjectOES? _vaoOes;
  bool _supportsVao = false;
  OES_vertex_array_object? _vaoExtension;

  final Map<String, int> _attributes;
  final Map<String, WebGLUniformLocation> _uniforms;
  RenderBufferIndex _renderBufferIndex;
  RenderBufferVertex _renderBufferVertex;
  RenderStatistics _renderStatistics;

  static var fragmentPrecision = 'mediump';

  bool get isWebGL2 => _renderingContext.isA<WebGL2RenderingContext>();

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
        _vaoExtension = _renderingContext.getExtension('OES_vertex_array_object') as OES_vertex_array_object?;
        _supportsVao = _vaoExtension != null;
      }

      _program = _createProgram(_renderingContext);
      _updateAttributes(_renderingContext, _program);
      _updateUniforms(_renderingContext, _program);

      _createVao();
      _bindVAO();
      _renderBufferIndex.activate(renderContext);
      _renderBufferVertex.activate(renderContext);
      setupAttributes();
      _unbindVAO();
    }

    renderingContext.useProgram(program);
  }

  void _createVao() {
    if (!_supportsVao) return;

    if (isWebGL2) {
      _vao = (_renderingContext as WebGL2RenderingContext).createVertexArray() as WebGLVertexArrayObject;
    } else {
      _vaoOes = _vaoExtension?.createVertexArrayOES() as WebGLVertexArrayObjectOES;
    }
  }

  void _bindVAO() {
    if (!_supportsVao) return;

    if (isWebGL2) {
      (_renderingContext as WebGL2RenderingContext).bindVertexArray(_vao);
    } else {
      _vaoExtension?.bindVertexArrayOES(_vaoOes);
    }
  }

  void _unbindVAO() {
    if (!_supportsVao) return;

    if (isWebGL2) {
      (_renderingContext as WebGL2RenderingContext).bindVertexArray(null);
    } else {
      _vaoExtension?.bindVertexArrayOES(null);
    }
  }

  void setupAttributes();

  //---------------------------------------------------------------------------

  void dispose() {
    if (_vao != null) {
      if (isWebGL2) {
        (_renderingContext as WebGL2RenderingContext).deleteVertexArray(_vao);
      } else if (_vaoExtension != null) {
        _vaoExtension?.deleteVertexArrayOES(_vaoOes);
      }
      _vao = null;
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
      _unbindVAO();
    }
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  WebGLProgram _createProgram(WebGL rc) {
    final program = rc.createProgram()!;
    final vShader =
        _createShader(rc, vertexShaderSource, WebGL.VERTEX_SHADER);
    final fShader =
        _createShader(rc, fragmentShaderSource, WebGL.FRAGMENT_SHADER);

    rc.attachShader(program, vShader);
    rc.attachShader(program, fShader);
    rc.linkProgram(program);

    final status = (rc.getProgramParameter(program, WebGL.LINK_STATUS) as JSBoolean).toDart;
    if (status == true) return program;

    final cl = rc.isContextLost();
    throw StateError(cl ? 'ContextLost' : rc.getProgramInfoLog(program)!);
  }

  //---------------------------------------------------------------------------

  WebGLShader _createShader(WebGL rc, String source, int type) {
    final shader = rc.createShader(type)!;
    rc.shaderSource(shader, source);
    rc.compileShader(shader);

    final status = (rc.getShaderParameter(shader, WebGL.COMPILE_STATUS) as JSBoolean).toDart;
    if (status == true) return shader;

    final cl = rc.isContextLost();
    throw StateError(cl ? 'ContextLost' : rc.getShaderInfoLog(shader)!);
  }

  //---------------------------------------------------------------------------

  void _updateAttributes(WebGL rc, WebGLProgram program) {
    _attributes.clear();
    final count =
        (rc.getProgramParameter(program, WebGL.ACTIVE_ATTRIBUTES)! as JSNumber).toDartInt;

    for (var i = 0; i < count; i++) {
      final activeInfo = rc.getActiveAttrib(program, i)!;
      final location = rc.getAttribLocation(program, activeInfo.name);
      rc.enableVertexAttribArray(location);
      _attributes[activeInfo.name] = location;
    }
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
