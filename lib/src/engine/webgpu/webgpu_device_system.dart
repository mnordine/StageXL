part of '../../engine.dart';

extension type _StageXLGpuSupportedFeatures._(JSObject _) implements JSObject {
  external bool has(String feature);
}

extension type _StageXLNavigator(JSObject _) implements JSObject {
  external GPU? get gpu;
}

class WebGpuDeviceSystem {
  static const _hdrCanvasFormat = 'rgba16float';

  final RenderSurface canvas;
  final GPUDevice device;
  final GPUCanvasContext canvasContext;
  final GPUTextureFormat preferredTextureFormat;
  final Set<String> enabledFeatures;
  final bool antialias;
  final bool hdr;
  final int maxBatchTextures;
  final bool _ownsDevice;

  WebGpuDeviceSystem._({
    required this.canvas,
    required this.device,
    required this.canvasContext,
    required this.preferredTextureFormat,
    required this.enabledFeatures,
    required this.antialias,
    required this.hdr,
    required this.maxBatchTextures,
    required this._ownsDevice,
  });

  static Future<WebGpuDeviceSystem?> create(
    RenderSurface canvas, {
    required PowerPreference powerPreference,
    required bool alpha,
    required bool antialias,
    required bool dualSourceBlending,
    bool hdr = false,
  }) async {
    final navigator = _globalScope.getProperty<JSObject>('navigator'.toJS);
    final gpu = _StageXLNavigator(navigator).gpu;
    if (gpu == null) return null;

    final adapterOptions = GPURequestAdapterOptions(
      powerPreference: switch (powerPreference) {
        PowerPreference.lowPower => 'low-power',
        PowerPreference.normal || PowerPreference.highPerformance => 'high-performance',
      },
    );
    final adapter = await gpu.requestAdapter(adapterOptions).toDart;
    if (adapter == null) return null;
    final maxBatchTextures = _resolveMaxBatchTextures(adapter);

    final requestedFeatures = <String>[];
    final enabledFeatures = <String>{};
    final supportedFeatures = adapter.features as _StageXLGpuSupportedFeatures;
    for (final feature in [
      'texture-compression-astc',
      'texture-compression-bc',
      'texture-compression-etc2',
      if (dualSourceBlending) 'dual-source-blending',
    ]) {
      if (supportedFeatures.has(feature)) {
        requestedFeatures.add(feature);
        enabledFeatures.add(feature);
      }
    }

    final descriptor = requestedFeatures.isEmpty
        ? GPUDeviceDescriptor(label: 'StageXL WebGPU')
        : GPUDeviceDescriptor(
            label: 'StageXL WebGPU',
            requiredFeatures: requestedFeatures.map((feature) => feature.toJS).toList(growable: false).toJS,
          );
    final device = await adapter.requestDevice(descriptor).toDart;
    if (device == null) return null;

    final canvasContext = canvas.getContext('webgpu') as GPUCanvasContext?;
    if (canvasContext == null) return null;

    final preferredTextureFormat = gpu.getPreferredCanvasFormat();
    final hdrEnabled = hdr && _configureHdrCanvasContext(canvasContext, device, alpha: alpha);
    if (!hdrEnabled) {
      canvasContext.configure(GPUCanvasConfiguration(
        device: device,
        format: preferredTextureFormat,
        alphaMode: alpha ? 'premultiplied' : 'opaque',
      ));
    }

    return WebGpuDeviceSystem._(
      canvas: canvas,
      device: device,
      canvasContext: canvasContext,
      preferredTextureFormat: hdrEnabled ? _hdrCanvasFormat : preferredTextureFormat,
      enabledFeatures: enabledFeatures,
      antialias: antialias,
      hdr: hdrEnabled,
      maxBatchTextures: maxBatchTextures,
      ownsDevice: true,
    );
  }

  factory WebGpuDeviceSystem.shared(
    RenderSurface canvas, {
    required GPUDevice device,
    required GPUCanvasContext canvasContext,
    required GPUTextureFormat preferredTextureFormat,
    required bool antialias,
  }) {
    final supportedFeatures = device.features as _StageXLGpuSupportedFeatures;
    final enabledFeatures = <String>{
      for (final feature in [
        'texture-compression-astc',
        'texture-compression-bc',
        'texture-compression-etc2',
        'dual-source-blending',
      ])
        if (supportedFeatures.has(feature)) feature,
    };
    return WebGpuDeviceSystem._(
      canvas: canvas,
      device: device,
      canvasContext: canvasContext,
      preferredTextureFormat: preferredTextureFormat,
      enabledFeatures: enabledFeatures,
      antialias: antialias,
      hdr: preferredTextureFormat == _hdrCanvasFormat,
      maxBatchTextures: _resolveMaxBatchTexturesFromLimits(device.limits),
      ownsDevice: false,
    );
  }

  int? get maxTextureSize => device.limits.maxTextureDimension2D;

  void dispose() {
    if (!_ownsDevice) return;
    canvasContext.unconfigure();
    device.destroy();
  }

  /// Configures the canvas for HDR output and returns whether the browser
  /// accepted the HDR configuration.
  ///
  /// HDR canvases use a floating point color format so colors beyond standard
  /// dynamic range are preserved, and an extended tone mapping mode so the
  /// browser maps those colors onto the headroom of HDR capable displays.
  /// Browsers that support neither reject the configuration.
  static bool _configureHdrCanvasContext(GPUCanvasContext canvasContext, GPUDevice device, {required bool alpha}) {
    try {
      canvasContext.configure(GPUCanvasConfiguration(
        device: device,
        format: _hdrCanvasFormat,
        alphaMode: alpha ? 'premultiplied' : 'opaque',
        toneMapping: GPUCanvasToneMapping(mode: 'extended'),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  static int _resolveMaxBatchTextures(GPUAdapter adapter) => _resolveMaxBatchTexturesFromLimits(adapter.limits);

  static int _resolveMaxBatchTexturesFromLimits(GPUSupportedLimits limits) {
    try {
      if (limits.maxSampledTexturesPerShaderStage >= 16 && limits.maxSamplersPerShaderStage >= 16) {
        return 16;
      }
    } catch (_) {
      // Limit probing is best-effort. The 8-texture batch shader is the conservative baseline.
    }
    return 8;
  }
}
