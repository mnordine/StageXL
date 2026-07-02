part of '../../engine.dart';

class _WebGpuDepthStencilEntry {
  GPUTexture texture;
  GPUTextureView view;
  int width;
  int height;
  int sampleCount;

  _WebGpuDepthStencilEntry(this.texture, this.view, this.width, this.height, this.sampleCount);
}

class _WebGpuColorEntry {
  GPUTexture texture;
  GPUTextureView view;
  int width;
  int height;
  int sampleCount;

  _WebGpuColorEntry(this.texture, this.view, this.width, this.height, this.sampleCount);
}

class WebGpuCommandSystem {
  final RenderContextWebGPU renderContext;
  GPUCommandEncoder? _encoder;
  GPUTexture? _swapTexture;
  GPUTextureView? _swapTextureView;
  _WebGpuColorEntry? _canvasMultisampleColorEntry;
  _WebGpuDepthStencilEntry? _canvasDepthStencilEntry;
  final _renderTargetDepthStencilEntries = <RenderTexture, _WebGpuDepthStencilEntry>{};

  WebGpuCommandSystem(this.renderContext);

  GPUCommandEncoder get encoder => _encoder ??= renderContext.device.createCommandEncoder();

  GPUTexture get swapTexture => _swapTexture ??= renderContext.canvasContext.getCurrentTexture();

  void beginFrame() {
    _encoder = null;
    _swapTexture = null;
    _swapTextureView = null;
  }

  GPURenderPassEncoder beginColorPass(List<num>? clearColor) {
    final colorAttachment = _getColorAttachment(clearColor);
    renderContext.renderStatistics.webgpuRenderPassCount++;
    final pass = encoder.beginRenderPass(GPURenderPassDescriptor(
      colorAttachments: [colorAttachment].toJS,
      depthStencilAttachment: GPURenderPassDepthStencilAttachment(
        view: _getDepthStencilView(),
        depthLoadOp: clearColor == null ? 'load' : 'clear',
        depthStoreOp: 'store',
        depthClearValue: 1,
        stencilLoadOp: clearColor == null ? 'load' : 'clear',
        stencilStoreOp: 'store',
        stencilClearValue: 0,
      ),
    ));
    renderContext.maskSystem.applyScissor(pass);
    return pass;
  }

  GPURenderPassEncoder beginStencilClearPass() {
    renderContext.renderStatistics.webgpuRenderPassCount++;
    return encoder.beginRenderPass(GPURenderPassDescriptor(
      colorAttachments: [
        _getColorAttachment(null),
      ].toJS,
      depthStencilAttachment: GPURenderPassDepthStencilAttachment(
        view: _getDepthStencilView(),
        depthLoadOp: 'load',
        depthStoreOp: 'store',
        stencilLoadOp: 'clear',
        stencilStoreOp: 'store',
        stencilClearValue: 0,
      ),
    ));
  }

  GPURenderPassColorAttachment _getColorAttachment(List<num>? clearColor) {
    final textureView = _getColorView();
    final attachment = clearColor == null
        ? GPURenderPassColorAttachment(view: textureView, loadOp: 'load', storeOp: 'store')
        : GPURenderPassColorAttachment(
            view: textureView,
            loadOp: 'clear',
            clearValue: GPUColorDict(
              r: clearColor[0],
              g: clearColor[1],
              b: clearColor[2],
              a: clearColor[3],
            ),
            storeOp: 'store',
          );

    if (renderContext.sampleCount > 1 && renderContext.activeRenderTexture == null) {
      attachment.resolveTarget = _swapTextureView ??= swapTexture.createView();
    }
    return attachment;
  }

  GPUTextureView _getColorView() {
    final activeRenderTexture = renderContext.activeRenderTexture;
    if (activeRenderTexture == null && renderContext.sampleCount > 1) {
      return _getCanvasMultisampleColorView();
    }
    return activeRenderTexture == null
        ? (_swapTextureView ??= swapTexture.createView())
        : renderContext.textureSystem.getTextureView(activeRenderTexture);
  }

  GPUTextureView _getCanvasMultisampleColorView() {
    final width = renderContext.viewportWidth;
    final height = renderContext.viewportHeight;
    final sampleCount = renderContext.sampleCount;
    final entry = _canvasMultisampleColorEntry;
    if (entry != null && width == entry.width && height == entry.height && sampleCount == entry.sampleCount) {
      return entry.view;
    }

    entry?.texture.destroy();
    final texture = renderContext.device.createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      format: renderContext.preferredTextureFormat,
      usage: $GPUTextureUsage.RENDER_ATTACHMENT,
      sampleCount: sampleCount,
    ));
    final created = _WebGpuColorEntry(texture, texture.createView(), width, height, sampleCount);
    _canvasMultisampleColorEntry = created;
    return created.view;
  }

  GPUTextureView _getDepthStencilView() {
    final width = renderContext.viewportWidth;
    final height = renderContext.viewportHeight;
    final sampleCount = renderContext.sampleCount;
    final activeRenderTexture = renderContext.activeRenderTexture;
    final entry = activeRenderTexture == null
        ? _canvasDepthStencilEntry
        : _renderTargetDepthStencilEntries[activeRenderTexture];
    if (entry != null && width == entry.width && height == entry.height && sampleCount == entry.sampleCount) {
      return entry.view;
    }

    entry?.texture.destroy();
    final texture = renderContext.device.createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      format: 'depth24plus-stencil8',
      usage: $GPUTextureUsage.RENDER_ATTACHMENT,
      sampleCount: sampleCount,
    ));
    final created = _WebGpuDepthStencilEntry(texture, texture.createView(), width, height, sampleCount);
    if (activeRenderTexture == null) {
      _canvasDepthStencilEntry = created;
    } else {
      _renderTargetDepthStencilEntries[activeRenderTexture] = created;
    }
    return created.view;
  }

  void submit() {
    final commandEncoder = _encoder;
    if (commandEncoder == null) return;
    final stopwatch = Stopwatch()..start();
    renderContext.device.queue.submit([commandEncoder.finish()].toJS);
    renderContext.renderStatistics.webgpuSubmitMicroseconds += stopwatch.elapsedMicroseconds;
    _encoder = null;
  }

  void disposeRenderTexture(RenderTexture renderTexture) {
    final entry = _renderTargetDepthStencilEntries.remove(renderTexture);
    entry?.texture.destroy();
  }
}
