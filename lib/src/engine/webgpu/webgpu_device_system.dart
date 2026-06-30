part of '../../engine.dart';

extension type _StageXLGpuSupportedFeatures._(JSObject _) implements JSObject {
  external bool has(String feature);
}

class WebGpuDeviceSystem {
  final HTMLCanvasElement canvas;
  final GPUDevice device;
  final GPUCanvasContext canvasContext;
  final GPUTextureFormat preferredTextureFormat;
  final Set<String> enabledFeatures;
  final bool antialias;

  WebGpuDeviceSystem._({
    required this.canvas,
    required this.device,
    required this.canvasContext,
    required this.preferredTextureFormat,
    required this.enabledFeatures,
    required this.antialias,
  });

  static Future<WebGpuDeviceSystem?> create(
    HTMLCanvasElement canvas, {
    required PowerPreference powerPreference,
    required bool alpha,
    required bool antialias,
  }) async {
    final gpu = window.navigator.gpu;
    if (gpu == null) return null;

    final adapterOptions = GPURequestAdapterOptions(
      powerPreference: switch (powerPreference) {
        PowerPreference.lowPower => 'low-power',
        PowerPreference.normal || PowerPreference.highPerformance => 'high-performance',
      },
    );
    final adapter = await gpu.requestAdapter(adapterOptions).toDart;
    if (adapter == null) return null;

    final requestedFeatures = <String>[];
    final enabledFeatures = <String>{};
    final supportedFeatures = adapter.features as _StageXLGpuSupportedFeatures;
    for (final feature in const [
      'texture-compression-astc',
      'texture-compression-bc',
      'texture-compression-etc2',
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
    canvasContext.configure(GPUCanvasConfiguration(
      device: device,
      format: preferredTextureFormat,
      alphaMode: alpha ? 'premultiplied' : 'opaque',
    ));

    return WebGpuDeviceSystem._(
      canvas: canvas,
      device: device,
      canvasContext: canvasContext,
      preferredTextureFormat: preferredTextureFormat,
      enabledFeatures: enabledFeatures,
      antialias: antialias,
    );
  }

  int? get maxTextureSize => device.limits.maxTextureDimension2D;
}
