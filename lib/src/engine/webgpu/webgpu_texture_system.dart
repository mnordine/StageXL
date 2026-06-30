part of '../../engine.dart';

class _WebGpuTextureEntry {
  GPUTexture texture;
  GPUTextureView? view;
  GPUBindGroup? bindGroup;
  int width;
  int height;
  int version;

  _WebGpuTextureEntry({
    required this.texture,
    required this.width,
    required this.height,
    required this.version,
  });
}

class WebGpuTextureSystem {
  final RenderContextWebGPU renderContext;
  final _textures = <RenderTexture, _WebGpuTextureEntry>{};
  late final GPUSampler linearSampler;
  late final GPUSampler nearestSampler;

  WebGpuTextureSystem(this.renderContext) {
    linearSampler = renderContext.device.createSampler(GPUSamplerDescriptor(
      magFilter: 'linear',
      minFilter: 'linear',
      mipmapFilter: 'linear',
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    ));
    nearestSampler = renderContext.device.createSampler(GPUSamplerDescriptor(
      magFilter: 'nearest',
      minFilter: 'nearest',
      mipmapFilter: 'nearest',
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    ));
  }

  GPUBindGroup getBindGroup(RenderTexture renderTexture) {
    final entry = _getEntry(renderTexture);
    final bindGroup = entry.bindGroup;
    if (bindGroup != null) return bindGroup;

    final view = entry.view ??= entry.texture.createView();
    final sampler = identical(renderTexture.filtering, RenderTextureFiltering.NEAREST) ? nearestSampler : linearSampler;
    final created = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: renderContext.pipelineSystem.textureBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: sampler),
        GPUBindGroupEntry(binding: 1, resource: view),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;
    return entry.bindGroup = created;
  }

  _WebGpuTextureEntry _getEntry(RenderTexture renderTexture) {
    final cached = _textures[renderTexture];
    final expectedWidth = renderTexture.width;
    final expectedHeight = renderTexture.height;
    final version = renderTexture._webGpuVersion;
    final needsTexture = cached == null || cached.width != expectedWidth || cached.height != expectedHeight;

    final entry = needsTexture
        ? _createEntry(renderTexture, expectedWidth, expectedHeight, version)
        : cached;

    if (entry.version != version || needsTexture) {
      _upload(renderTexture, entry.texture);
      entry.version = version;
      entry.bindGroup = null;
      entry.view = null;
    }

    return entry;
  }

  _WebGpuTextureEntry _createEntry(RenderTexture renderTexture, int width, int height, int version) {
    _textures.remove(renderTexture)?.texture.destroy();
    final texture = renderContext.device.createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      format: renderContext.preferredTextureFormat,
      usage: $GPUTextureUsage.COPY_DST | $GPUTextureUsage.TEXTURE_BINDING | $GPUTextureUsage.RENDER_ATTACHMENT,
    ));
    final entry = _WebGpuTextureEntry(texture: texture, width: width, height: height, version: version - 1);
    _textures[renderTexture] = entry;
    return entry;
  }

  void _upload(RenderTexture renderTexture, GPUTexture texture) {
    final source = renderTexture.source ?? renderTexture.imageBitmap;
    if (source == null) {
      throw StateError('WebGPU cannot upload a RenderTexture without an image, canvas, video, or bitmap source.');
    }

    renderContext.device.queue.copyExternalImageToTexture(
      GPUImageCopyExternalImage(source: source),
      GPUImageCopyTextureTagged(texture: texture, premultipliedAlpha: true),
      GPUExtent3DDict(width: renderTexture.width, height: renderTexture.height, depthOrArrayLayers: 1),
    );
    renderContext.renderStatistics.webgpuTextureUploadCount++;
  }

  void disposeTexture(RenderTexture renderTexture) {
    final entry = _textures.remove(renderTexture);
    entry?.texture.destroy();
  }
}
