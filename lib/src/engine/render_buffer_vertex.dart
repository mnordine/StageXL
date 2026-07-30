part of '../engine.dart';

class RenderBufferVertex {
  final Float32List data;
  final int usage;

  var position = 0; // position in data list
  var count = 0; // count of vertices

  var _contextIdentifier = -1;
  WebGLBuffer? _buffer;
  WebGL? _renderingContext;
  late RenderStatistics _renderStatistics;
  var _disposed = false;
  var _bufferAllocated = false;

  //---------------------------------------------------------------------------

  RenderBufferVertex(int length)
      : data = Float32List(length),
        usage = WebGL.DYNAMIC_DRAW {
    ResourceDiagnostics.register(.renderBuffer);
  }

  //---------------------------------------------------------------------------

  int get contextIdentifier => _contextIdentifier;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseWebGLBuffer(delete: true);
    ResourceDiagnostics.unregister(.renderBuffer);
  }

  void _releaseWebGLBuffer({required bool delete}) {
    if (delete && _buffer != null && _renderingContext != null) {
      _renderingContext!.deleteBuffer(_buffer);
    }
    if (_bufferAllocated) {
      ResourceDiagnostics.unregister(.webglBuffer);
      _bufferAllocated = false;
    }
    _renderingContext = null;
    _buffer = null;
    _contextIdentifier = -1;
  }

  void activate(RenderContextWebGL renderContext) {
    if (_contextIdentifier != renderContext.contextIdentifier) {
      _contextIdentifier = renderContext.contextIdentifier;
      _renderStatistics = renderContext.renderStatistics;
      _renderingContext = renderContext.rawContext;
      _buffer = _renderingContext!.createBuffer();
      if (_buffer != null) {
        ResourceDiagnostics.register(.webglBuffer);
        _bufferAllocated = true;
      }
      _renderingContext!.bindBuffer(WebGL.ARRAY_BUFFER, _buffer);
      _renderingContext!.bufferData(WebGL.ARRAY_BUFFER, data.toJS, usage);
    } else {
      _renderingContext!.bindBuffer(WebGL.ARRAY_BUFFER, _buffer);
    }
  }

  void update() {
    if (position == 0) return;

    final update = Float32List.view(data.buffer, 0, position);
    _renderingContext!.bindBuffer(WebGL.ARRAY_BUFFER, _buffer);
    _renderingContext!.bufferSubData(WebGL.ARRAY_BUFFER, 0, update.toJS);
    _renderStatistics.vertexCount += count;
  }

  void bindAttribute(int? index, int size, int stride, int offset) {
    if (index == null) return;
    _renderingContext!.vertexAttribPointer(
        index, size, WebGL.FLOAT, false, stride, offset);
  }
}
