part of '../../engine.dart';

class _WebGpuTextureEntry {
  GPUTexture texture;
  GPUTextureView? view;
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

class _WebGpuBatchBindGroupKey {
  final List<RenderTexture> textures;
  final List<_WebGpuSamplerKey> samplerKeys;
  late final int _hashCode = Object.hashAll([
    for (var i = 0; i < textures.length; i++) ...[
      identityHashCode(textures[i]),
      samplerKeys[i],
    ],
  ]);

  _WebGpuBatchBindGroupKey(List<RenderTexture> textures)
      : textures = List<RenderTexture>.unmodifiable(textures),
        samplerKeys = List<_WebGpuSamplerKey>.unmodifiable(textures.map(_WebGpuSamplerKey.new));

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! _WebGpuBatchBindGroupKey || other.textures.length != textures.length) return false;
    for (var i = 0; i < textures.length; i++) {
      if (!identical(textures[i], other.textures[i])) return false;
      if (samplerKeys[i] != other.samplerKeys[i]) return false;
    }
    return true;
  }
}

class _WebGpuSamplerKey {
  final int filtering;
  final int wrappingX;
  final int wrappingY;

  _WebGpuSamplerKey(RenderTexture renderTexture)
      : filtering = renderTexture.filtering.value,
        wrappingX = renderTexture.wrappingX.value,
        wrappingY = renderTexture.wrappingY.value;

  @override
  int get hashCode => Object.hash(filtering, wrappingX, wrappingY);

  @override
  bool operator ==(Object other) =>
      other is _WebGpuSamplerKey &&
      other.filtering == filtering &&
      other.wrappingX == wrappingX &&
      other.wrappingY == wrappingY;
}

class WebGpuTextureSystem {
  final RenderContextWebGPU renderContext;
  final _textures = <RenderTexture, _WebGpuTextureEntry>{};
  final _samplers = <_WebGpuSamplerKey, GPUSampler>{};
  final _batchBindGroups = <_WebGpuBatchBindGroupKey, GPUBindGroup>{};
  final _transparentPixel = JSUint8Array.withLength(4).toDart;
  var _bindGroupGeneration = 0;

  WebGpuTextureSystem(this.renderContext);

  int get bindGroupGeneration => _bindGroupGeneration;

  GPUBindGroup getBindGroup(RenderTexture renderTexture) => getBatchBindGroup([renderTexture]);

  GPUBindGroup getBatchBindGroup(List<RenderTexture> textures) {
    if (textures.isEmpty) {
      throw StateError('WebGPU batch bind group requires at least one texture.');
    }

    for (final renderTexture in textures) {
      _getEntry(renderTexture);
    }

    final key = _WebGpuBatchBindGroupKey(textures);
    final bindGroup = _batchBindGroups[key];
    if (bindGroup != null) return bindGroup;

    final entries = <GPUBindGroupEntry>[];
    for (var i = 0; i < renderContext.pipelineSystem.maxBatchTextures; i++) {
      final renderTexture = i < textures.length ? textures[i] : textures[0];
      final view = getTextureView(renderTexture);
      final sampler = getSampler(renderTexture);
      entries
        ..add(GPUBindGroupEntry(binding: i * 2, resource: sampler))
        ..add(GPUBindGroupEntry(binding: i * 2 + 1, resource: view));
    }

    final created = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: renderContext.pipelineSystem.textureBindGroupLayout,
      entries: entries.toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;
    _batchBindGroups[key] = created;
    return created;
  }

  GPUSampler getSampler(RenderTexture renderTexture) {
    final key = _WebGpuSamplerKey(renderTexture);
    return _samplers.putIfAbsent(key, () => renderContext.device.createSampler(GPUSamplerDescriptor(
          magFilter: _filterMode(renderTexture.filtering),
          minFilter: _filterMode(renderTexture.filtering),
          mipmapFilter: _filterMode(renderTexture.filtering),
          addressModeU: _addressMode(renderTexture.wrappingX),
          addressModeV: _addressMode(renderTexture.wrappingY),
        )));
  }

  String _filterMode(RenderTextureFiltering filtering) =>
      filtering.value == RenderTextureFiltering.NEAREST.value ? 'nearest' : 'linear';

  String _addressMode(RenderTextureWrapping wrapping) =>
      wrapping.value == RenderTextureWrapping.REPEAT.value ? 'repeat' : 'clamp-to-edge';

  void _clearBindGroups() {
    _batchBindGroups.clear();
    _bindGroupGeneration++;
  }

  GPUTexture _createTexture(GPUTextureDescriptor descriptor) {
    final texture = renderContext.device.createTexture(descriptor);
    ResourceDiagnostics.register(.webgpuTexture);
    return texture;
  }

  void _cacheEntry(RenderTexture renderTexture, _WebGpuTextureEntry entry) {
    _textures[renderTexture] = entry;
    renderTexture._webGpuTextureSystems.add(this);
  }

  void _disposeEntry(RenderTexture renderTexture) {
    final entry = _textures.remove(renderTexture);
    if (entry == null) return;
    renderTexture._webGpuTextureSystems.remove(this);
    entry.texture.destroy();
    ResourceDiagnostics.unregister(.webgpuTexture);
  }

  GPUTextureView getTextureView(RenderTexture renderTexture) {
    final entry = _getEntry(renderTexture);
    return entry.view ??= entry.texture.createView();
  }

  int writeTextureCoordinates(
    RenderTexture renderTexture,
    Float32List source,
    int sourceIndex,
    Float32List target,
    int targetIndex,
  ) {
    target[targetIndex++] = source[sourceIndex + 2] * _textureCoordinateScaleX(renderTexture);
    target[targetIndex++] = source[sourceIndex + 3] * _textureCoordinateScaleY(renderTexture);
    return targetIndex;
  }

  Matrix scaledSamplerMatrix(RenderTexture renderTexture, Matrix matrix, {RenderTexture? inputTexture}) {
    final scaled = matrix.clone();
    final inputScaleX = inputTexture == null ? 1.0 : _textureCoordinateScaleX(inputTexture);
    final inputScaleY = inputTexture == null ? 1.0 : _textureCoordinateScaleY(inputTexture);
    final outputScaleX = _textureCoordinateScaleX(renderTexture);
    final outputScaleY = _textureCoordinateScaleY(renderTexture);
    scaled
      ..a = scaled.a / inputScaleX * outputScaleX
      ..b = scaled.b / inputScaleX * outputScaleY
      ..c = scaled.c / inputScaleY * outputScaleX
      ..d = scaled.d / inputScaleY * outputScaleY
      ..tx *= outputScaleX
      ..ty *= outputScaleY;
    return scaled;
  }

  double _textureCoordinateScaleX(RenderTexture renderTexture) {
    final compressedTexture = renderTexture._compressedTexture;
    return compressedTexture == null ? 1.0 : renderTexture.width / compressedTexture.webGpuWidth;
  }

  double _textureCoordinateScaleY(RenderTexture renderTexture) {
    final compressedTexture = renderTexture._compressedTexture;
    return compressedTexture == null ? 1.0 : renderTexture.height / compressedTexture.webGpuHeight;
  }

  _WebGpuTextureEntry _getEntry(RenderTexture renderTexture) {
    final compressedTexture = renderTexture._compressedTexture;
    if (compressedTexture != null && !compressedTexture.supportsWebGpu(renderContext.deviceSystem.enabledFeatures)) {
      renderContext.renderStatistics.addWebGpuFallbackCause('compressed texture unsupported on device');
      return _createUnsupportedCompressedEntry(renderTexture);
    }

    final cached = _textures[renderTexture];
    final expectedWidth = renderTexture.width;
    final expectedHeight = renderTexture.height;
    final version = renderTexture._webGpuVersion;
    final needsTexture = cached == null || cached.width != expectedWidth || cached.height != expectedHeight;

    final entry = needsTexture
        ? _createEntry(renderTexture, expectedWidth, expectedHeight, version, compressedTexture)
        : cached;

    if (entry.version != version || needsTexture) {
      if (compressedTexture == null && renderTexture.source == null && renderTexture.imageBitmap == null) {
        entry.version = version;
        entry.view = null;
        _clearBindGroups();
        return entry;
      }

      if (compressedTexture != null) {
        _uploadCompressed(compressedTexture, entry.texture);
      } else {
        _upload(renderTexture, entry.texture);
      }
      entry.version = version;
      entry.view = null;
      _clearBindGroups();
    }

    return entry;
  }

  _WebGpuTextureEntry _createUnsupportedCompressedEntry(
    RenderTexture renderTexture,
  ) {
    final cached = _textures[renderTexture];
    if (cached != null && cached.width == renderTexture.width && cached.height == renderTexture.height) {
      return cached;
    }

    _disposeEntry(renderTexture);
    _clearBindGroups();

    final texture = _createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: 1, height: 1, depthOrArrayLayers: 1),
      format: renderContext.preferredTextureFormat,
      usage: $GPUTextureUsage.COPY_DST | $GPUTextureUsage.TEXTURE_BINDING,
    ));

    renderContext.device.queue.writeTexture(
      GPUImageCopyTexture(texture: texture),
      _transparentPixel.toJS,
      GPUImageDataLayout(offset: 0, bytesPerRow: 4, rowsPerImage: 1),
      GPUExtent3DDict(width: 1, height: 1, depthOrArrayLayers: 1),
    );

    final entry = _WebGpuTextureEntry(
      texture: texture,
      width: renderTexture.width,
      height: renderTexture.height,
      version: renderTexture._webGpuVersion,
    );
    _cacheEntry(renderTexture, entry);
    return entry;
  }

  _WebGpuTextureEntry _createEntry(
    RenderTexture renderTexture,
    int width,
    int height,
    int version,
    CompressedTexture? compressedTexture,
  ) {
    _disposeEntry(renderTexture);
    final textureFormat = compressedTexture?.webGpuTextureFormat ?? renderContext.preferredTextureFormat;
    final textureWidth = compressedTexture?.webGpuWidth ?? width;
    final textureHeight = compressedTexture?.webGpuHeight ?? height;

    final usage = compressedTexture == null
        ? $GPUTextureUsage.COPY_DST | $GPUTextureUsage.TEXTURE_BINDING | $GPUTextureUsage.RENDER_ATTACHMENT
        : $GPUTextureUsage.COPY_DST | $GPUTextureUsage.TEXTURE_BINDING;

    final texture = _createTexture(GPUTextureDescriptor(
      size: GPUExtent3DDict(width: textureWidth, height: textureHeight, depthOrArrayLayers: 1),
      format: textureFormat,
      mipLevelCount: compressedTexture?.mipLevelCount ?? 1,
      usage: usage,
    ));
    final entry = _WebGpuTextureEntry(
      texture: texture,
      width: width,
      height: height,
      version: version - 1,
    );
    _cacheEntry(renderTexture, entry);
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

  void _uploadCompressed(CompressedTexture compressedTexture, GPUTexture texture) {
    final queue = renderContext.device.queue;
    for (var level = 0; level < compressedTexture.mipLevelCount; level++) {
      final data = compressedTexture.textureDataForMipLevel(level);
      final width = compressedTexture.webGpuWidthForMipLevel(level);
      final height = compressedTexture.webGpuHeightForMipLevel(level);
      queue.writeTexture(
        GPUImageCopyTexture(texture: texture, mipLevel: level),
        data.toJS,
        GPUImageDataLayout(
          offset: 0,
          bytesPerRow: compressedTexture.bytesPerRowForMipLevel(level),
          rowsPerImage: compressedTexture.rowsPerImageForMipLevel(level),
        ),
        GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
      );
    }
    renderContext.renderStatistics.webgpuTextureUploadCount++;
  }

  void disposeTexture(RenderTexture renderTexture) {
    _disposeEntry(renderTexture);
    _clearBindGroups();
  }

  void dispose() {
    for (final MapEntry(key: renderTexture, value: entry) in _textures.entries) {
      renderTexture._webGpuTextureSystems.remove(this);
      entry.texture.destroy();
      ResourceDiagnostics.unregister(.webgpuTexture);
    }
    _textures.clear();
    _samplers.clear();
    _clearBindGroups();
  }
}
