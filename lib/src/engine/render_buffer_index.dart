part of '../engine.dart';

class RenderBufferIndex {
  final Int16List data;
  final int usage;

  int position = 0; // position in data list
  int count = 0; // count of indices

  int _contextIdentifier = -1;
  WebGLBuffer? _buffer;
  WebGL? _renderingContext;
  late RenderStatistics _renderStatistics;

  //---------------------------------------------------------------------------

  RenderBufferIndex(int length)
      : data = Int16List(length),
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
      _renderingContext!.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _buffer);
      _renderingContext!.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, data.toJS, usage);
    } else {
      // When using VAO, the ELEMENT_ARRAY_BUFFER binding is part of the VAO state
      // so we only need to bind when creating a new buffer or when VAOs aren't supported
      _renderingContext!.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _buffer);
    }
  }

  void update() {
    if (position == 0) return;

    final update = Int16List.view(data.buffer, 0, position);

    // Orphan the buffer to avoid GPU sync stalls.
    try { _renderingContext!.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, (data.length * 2).toJS, usage);
    } catch (_) {
      // Fallback: if the driver doesn't accept byte size, skip orphaning.
    }
    _renderingContext!.bufferSubData(WebGL.ELEMENT_ARRAY_BUFFER, 0, update.toJS);
    _renderStatistics.indexCount += count;
  }
}
