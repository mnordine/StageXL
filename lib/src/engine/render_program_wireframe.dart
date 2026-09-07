part of '../engine.dart';

/// Debug-only line renderer sharing the normal renderer's uploaded vertices.
/// Owns only a shader, a VAO (when supported), and a reusable edge index buffer.
class RenderProgramWireframe {
  final RenderContextWebGL _context;
  final WebGL _gl;
  final bool _isWebGL2;
  late final WebGLProgram _program;
  late final WebGLBuffer _indexBuffer;
  WebGLVertexArrayObject? _vao;
  WebGLVertexArrayObjectOES? _vaoOes;
  late final int _position;
  late final int _clipPosition;
  WebGLUniformLocation? _uniformClipped;
  WebGLUniformLocation? _uniformColor;
  WebGLUniformLocation? _uniformProjection;
  var _indices = Int16List(0);

  RenderProgramWireframe(this._context)
      : _gl = _context.rawContext,
        _isWebGL2 = _context.isWebGL2 {
    _program = _buildProgram(_gl, _vertexShader, _fragmentShader);
    _position = _gl.getAttribLocation(_program, 'aPosition');
    _clipPosition = _gl.getAttribLocation(_program, 'aClipRect');
    _uniformClipped = _gl.getUniformLocation(_program, 'uClipped');
    _uniformColor = _gl.getUniformLocation(_program, 'uColor');
    _uniformProjection = _gl.getUniformLocation(_program, 'uProjectionMatrix');
    _indexBuffer = _gl.createBuffer() ?? (throw StateError('Failed to create wireframe index buffer.'));
    if (_isWebGL2) {
      _vao = (_gl as WebGL2RenderingContext).createVertexArray();
    } else {
      _vaoOes = _context.vaoExtension?.createVertexArrayOES();
    }
    ResourceDiagnostics.register(.webglProgram);
    ResourceDiagnostics.register(.webglBuffer);
    if (_vao != null || _vaoOes != null) ResourceDiagnostics.register(.webglVertexArray);
  }

  String get _vertexShader => _isWebGL2 ? '''
    #version 300 es
    uniform mat4 uProjectionMatrix;
    in vec2 aPosition;
    in vec4 aClipRect;
    flat out vec4 vClipRect;
    void main() {
      vClipRect = aClipRect;
      gl_Position = vec4(aPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''
    uniform mat4 uProjectionMatrix;
    attribute vec2 aPosition;
    attribute vec4 aClipRect;
    varying vec4 vClipRect;
    void main() {
      vClipRect = aClipRect;
      gl_Position = vec4(aPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  String get _fragmentShader => _isWebGL2 ? '''
    #version 300 es
    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform vec4 uColor;
    flat in vec4 vClipRect;
    uniform bool uClipped;
    out vec4 fragColor;
    void main() {
      if (uClipped && (gl_FragCoord.x < vClipRect.x || gl_FragCoord.y < vClipRect.y ||
          gl_FragCoord.x >= vClipRect.z || gl_FragCoord.y >= vClipRect.w)) discard;
      fragColor = uColor;
    }
    ''' : '''
    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform vec4 uColor;
    uniform bool uClipped;
    varying vec4 vClipRect;
    void main() {
      if (uClipped && (gl_FragCoord.x < vClipRect.x || gl_FragCoord.y < vClipRect.y ||
          gl_FragCoord.x >= vClipRect.z || gl_FragCoord.y >= vClipRect.w)) discard;
      gl_FragColor = uColor;
    }
    ''';

  WebGLProgram _buildProgram(
      WebGL gl, String vsSource, String fsSource) {
    final program = gl.createProgram();
    if (program == null) {
      throw StateError('Failed to create wireframe program.');
    }

    final vShader = _createShader(gl, vsSource, WebGL.VERTEX_SHADER);
    final fShader = _createShader(gl, fsSource, WebGL.FRAGMENT_SHADER);

    gl.attachShader(program, vShader);
    gl.attachShader(program, fShader);
    gl.linkProgram(program);

    final status =
        (gl.getProgramParameter(program, WebGL.LINK_STATUS) as JSBoolean?)
            ?.toDart;
    if (status != true) {
      final log = gl.getProgramInfoLog(program);
      gl.deleteProgram(program);
      throw StateError('Failed to link wireframe program: $log');
    }

    gl.deleteShader(vShader);
    gl.deleteShader(fShader);
    return program;
  }

  WebGLShader _createShader(WebGL gl, String source, int type) {
    final shader = gl.createShader(type);
    if (shader == null) {
      throw StateError('Failed to create wireframe shader.');
    }
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    final status =
        (gl.getShaderParameter(shader, WebGL.COMPILE_STATUS) as JSBoolean?)
            ?.toDart;
    if (status != true) {
      final log = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw StateError('Failed to compile wireframe shader: $log');
    }
    return shader;
  }

  void draw(RenderProgramWebGL<Object?> source, int offset, int count, int stride, {
    WebGLBuffer? vertices,
    WebGLBuffer? elements,
    List<int>? indices,
    int vertexByteOffset = 0,
    bool shaderScissor = false,
  }) {
    if (count == 0) return;
    final gl = _gl;
    final edgeCount = count * 2;
    final grow = edgeCount > _indices.length;
    if (grow) _indices = Int16List(math.max(edgeCount, _indices.length * 2));

    // Preserve the unsigned 16-bit index bit patterns, including indices above 32767.
    final triangles = indices ?? source.renderBufferIndex.data;
    for (var i = 0; i < count; i += 3) {
      final a = triangles[offset + i];
      final b = triangles[offset + i + 1];
      final c = triangles[offset + i + 2];
      final edge = i * 2;
      _indices[edge] = a;
      _indices[edge + 1] = b;
      _indices[edge + 2] = b;
      _indices[edge + 3] = c;
      _indices[edge + 4] = c;
      _indices[edge + 5] = a;
    }

    final hasVao = _vao != null || _vaoOes != null;
    if (_vao != null) {
      (gl as WebGL2RenderingContext).bindVertexArray(_vao);
      RenderProgramWebGL.currentVao = _vao;
    } else if (_vaoOes != null) {
      _context.vaoExtension!.bindVertexArrayOES(_vaoOes);
      RenderProgramWebGL.currentVaoOes = _vaoOes;
    }

    try {
      // Bind our VAO before touching ELEMENT_ARRAY_BUFFER: that binding belongs to the VAO.
      gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _indexBuffer);
      if (grow) gl.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, _indices.lengthInBytes.toJS, WebGL.DYNAMIC_DRAW);
      final update = Int16List.view(_indices.buffer, 0, edgeCount);
      gl.bufferSubData(WebGL.ELEMENT_ARRAY_BUFFER, 0, update.toJS);

      gl.bindBuffer(WebGL.ARRAY_BUFFER, vertices ?? source.renderBufferVertex._buffer);
      gl.vertexAttribPointer(_position, 2, WebGL.FLOAT, false, stride * 4, vertexByteOffset);
      if (shaderScissor) {
        gl.vertexAttribPointer(_clipPosition, 4, WebGL.FLOAT, false, stride * 4, vertexByteOffset + 36);
        gl.enableVertexAttribArray(_clipPosition);
      } else {
        gl.disableVertexAttribArray(_clipPosition);
      }
      gl.enableVertexAttribArray(_position);
      gl.useProgram(_program);
      gl.uniform1i(_uniformClipped, shaderScissor ? 1 : 0);
      final color = debug_draw.debugDraw.wireframeColor;
      final alpha = colorGetA(color) / 255.0;
      gl.uniform4f(_uniformColor, colorGetR(color) / 255.0 * alpha,
          colorGetG(color) / 255.0 * alpha, colorGetB(color) / 255.0 * alpha, alpha);
      gl.uniformMatrix4fv(_uniformProjection, false, _context.activeProjectionMatrix.data.toJS);
      gl.drawElements(WebGL.LINES, edgeCount, WebGL.UNSIGNED_SHORT, 0);
    } finally {
      gl.useProgram(source.program);
      if (hasVao) {
        source._bindVAO();
      } else {
        // Without VAOs the overlay changed the source's global attribute and index bindings.
        if (!source.attributes.containsValue(_position)) gl.disableVertexAttribArray(_position);
        if (!source.attributes.containsValue(_clipPosition)) gl.disableVertexAttribArray(_clipPosition);
        for (final attribute in source.attributes.values) {
          gl.enableVertexAttribArray(attribute);
        }
        gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, elements ?? source.renderBufferIndex._buffer);
        if (vertices == null) {
          source.setupAttributes();
        } else {
          (source as RenderProgramBatchWebGL)
            .._bindRetainedAttribute('aVertexPosition', 2, stride, vertexByteOffset)
            .._bindRetainedAttribute('aVertexTextCoord', 2, stride, vertexByteOffset + 8)
            .._bindRetainedAttribute('aVertexColor', 4, stride, vertexByteOffset + 16)
            .._bindRetainedAttribute('aVertexTexIndex', 1, stride, vertexByteOffset + 32)
            .._bindRetainedAttribute('aVertexClipRect', 4, stride, vertexByteOffset + 36);
        }
      }
    }
  }

  void dispose() {
    ResourceDiagnostics.unregister(.webglProgram);
    ResourceDiagnostics.unregister(.webglBuffer);
    if (_vao != null || _vaoOes != null) ResourceDiagnostics.unregister(.webglVertexArray);
    _gl.deleteBuffer(_indexBuffer);
    if (_vao != null) (_gl as WebGL2RenderingContext).deleteVertexArray(_vao);
    if (_vaoOes != null) _context.vaoExtension?.deleteVertexArrayOES(_vaoOes);
    _gl.deleteProgram(_program);
  }
}
