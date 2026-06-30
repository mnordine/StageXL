part of '../../engine.dart';

class WebGpuCommandSystem {
  final RenderContextWebGPU renderContext;
  GPUCommandEncoder? _encoder;
  GPUTexture? _swapTexture;
  GPUTexture? _depthStencilTexture;
  GPUTextureView? _depthStencilView;
  var _depthStencilWidth = 0;
  var _depthStencilHeight = 0;

  WebGpuCommandSystem(this.renderContext);

  GPUCommandEncoder get encoder => _encoder ??= renderContext.device.createCommandEncoder();

  GPUTexture get swapTexture => _swapTexture ??= renderContext.canvasContext.getCurrentTexture();

  void beginFrame() {
    _encoder = null;
    _swapTexture = null;
  }

  GPURenderPassEncoder beginColorPass(List<num>? clearColor) {
    final textureView = swapTexture.createView();
    final colorAttachment = clearColor == null
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
    final textureView = swapTexture.createView();
    renderContext.renderStatistics.webgpuRenderPassCount++;
    return encoder.beginRenderPass(GPURenderPassDescriptor(
      colorAttachments: [
        GPURenderPassColorAttachment(view: textureView, loadOp: 'load', storeOp: 'store'),
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

  GPUTextureView _getDepthStencilView() {
    final width = renderContext.viewportWidth;
    final height = renderContext.viewportHeight;
    final texture = _depthStencilTexture;
    if (texture != null && width == _depthStencilWidth && height == _depthStencilHeight) {
      return _depthStencilView!;
    }

    texture?.destroy();
    _depthStencilWidth = width;
    _depthStencilHeight = height;
    _depthStencilTexture = renderContext.device.createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      format: 'depth24plus-stencil8',
      usage: $GPUTextureUsage.RENDER_ATTACHMENT,
    ));
    return _depthStencilView = _depthStencilTexture!.createView();
  }

  void submit() {
    final commandEncoder = _encoder;
    if (commandEncoder == null) return;
    renderContext.device.queue.submit([commandEncoder.finish()].toJS);
    _encoder = null;
  }
}
