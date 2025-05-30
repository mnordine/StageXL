part of '../engine.dart';

class RenderBufferVertex {
  final Float32List data;
  final int usage;

  int position = 0; // position in data list
  int count = 0; // count of vertices

  int _contextIdentifier = -1;
  WebGLBuffer? _buffer;
  WebGL? _renderingContext;
  late RenderStatistics _renderStatistics;

  //---------------------------------------------------------------------------

  RenderBufferVertex(int length)
      : data = Float32List(length),
        usage = WebGL.DYNAMIC_DRAW;

  //---------------------------------------------------------------------------

  int get contextIdentifier => _contextIdentifier;

  void dispose() {
    if (_buffer != null && _renderingContext != null) {
      _renderingContext!.deleteBuffer(_buffer);
      _renderingContext = null;
      _buffer = null;
      _contextIdentifier = -1;
    }
  }

  void activate(RenderContextWebGL renderContext) {
    if (_contextIdentifier != renderContext.contextIdentifier) {
      _contextIdentifier = renderContext.contextIdentifier;
      _renderStatistics = renderContext.renderStatistics;
      _renderingContext = renderContext.rawContext;
      _buffer = _renderingContext!.createBuffer();
      _renderingContext!.bindBuffer(WebGL.ARRAY_BUFFER, _buffer);
      _renderingContext!.bufferData(WebGL.ARRAY_BUFFER, data.toJS, usage);
    }

    _renderingContext!.bindBuffer(WebGL.ARRAY_BUFFER, _buffer);
  }

  void update() {
    final update = Float32List.view(data.buffer, 0, position);
    _renderingContext!.bufferSubData(WebGL.ARRAY_BUFFER, 0, update.toJS);
    _renderStatistics.vertexCount += count;
  }

  void bindAttribute(int? index, int size, int stride, int offset) {
    if (index == null) return;
    _renderingContext!.vertexAttribPointer(
        index, size, WebGL.FLOAT, false, stride, offset);
  }
}
