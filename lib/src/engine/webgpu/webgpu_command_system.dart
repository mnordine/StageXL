part of '../../engine.dart';

class WebGpuCommandSystem {
  final RenderContextWebGPU renderContext;
  GPUCommandEncoder? _encoder;
  GPUTexture? _swapTexture;

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
    final pass = encoder.beginRenderPass(GPURenderPassDescriptor(colorAttachments: [colorAttachment].toJS));
    renderContext.maskSystem.applyScissor(pass);
    return pass;
  }

  void submit() {
    final commandEncoder = _encoder;
    if (commandEncoder == null) return;
    renderContext.device.queue.submit([commandEncoder.finish()].toJS);
    _encoder = null;
  }
}
