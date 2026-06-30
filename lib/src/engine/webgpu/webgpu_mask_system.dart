part of '../../engine.dart';

class WebGpuMaskSystem {
  final RenderContextWebGPU renderContext;
  final _scissorStack = <Rectangle<num>>[];
  Rectangle<num>? _activeScissor;

  WebGpuMaskSystem(this.renderContext);

  void resetFrame() {
    _scissorStack.clear();
    _activeScissor = null;
  }

  void beginMask(RenderState renderState, RenderMask mask) {
    if (mask is ScissorRenderMask) {
      final rectangle = mask.getScissorRectangle(renderState);
      if (rectangle == null) return;
      _activeScissor = _activeScissor == null ? rectangle : _activeScissor!.intersection(rectangle);
      _scissorStack.add(_activeScissor!);
      return;
    }

    renderContext.renderStatistics.webgpuFallbackCount++;
    throw UnsupportedError('WebGPU non-scissor masks require the stencil pass implementation.');
  }

  void endMask(RenderState renderState, RenderMask mask) {
    if (mask is! ScissorRenderMask) return;
    if (_scissorStack.isNotEmpty) _scissorStack.removeLast();
    _activeScissor = _scissorStack.isEmpty ? null : _scissorStack.last;
  }

  void applyScissor(GPURenderPassEncoder pass) {
    final scissor = _activeScissor;
    if (scissor == null) return;

    var left = scissor.left.floor();
    var top = scissor.top.floor();
    var width = scissor.width.ceil();
    var height = scissor.height.ceil();

    if (left < 0) {
      width += left;
      left = 0;
    }
    if (top < 0) {
      height += top;
      top = 0;
    }

    width = math.min(width, renderContext.viewportWidth - left);
    height = math.min(height, renderContext.viewportHeight - top);
    if (width <= 0 || height <= 0) return;
    pass.setScissorRect(left, top, width, height);
  }
}
