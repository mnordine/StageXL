part of '../../engine.dart';

class _BindGroupKey {
  final int layout;
  final int textureGeneration;
  final RenderTexture texture;
  final RenderTexture? secondTexture;
  final GPUBuffer uniformBuffer;
  final _WebGpuSamplerKey samplerKey;
  final _WebGpuSamplerKey? secondSamplerKey;
  late final _hashCode = Object.hash(
    layout,
    textureGeneration,
    identityHashCode(texture),
    identityHashCode(secondTexture),
    identityHashCode(uniformBuffer),
    samplerKey,
    secondSamplerKey,
  );

  _BindGroupKey({
    required this.layout,
    required this.textureGeneration,
    required this.texture,
    required this.secondTexture,
    required this.uniformBuffer,
  })  : samplerKey = _WebGpuSamplerKey(texture),
        secondSamplerKey = secondTexture == null ? null : _WebGpuSamplerKey(secondTexture);

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) =>
      other is _BindGroupKey &&
      other.layout == layout &&
      other.textureGeneration == textureGeneration &&
      identical(other.texture, texture) &&
      identical(other.secondTexture, secondTexture) &&
      identical(other.uniformBuffer, uniformBuffer) &&
      other.samplerKey == samplerKey &&
      other.secondSamplerKey == secondSamplerKey;
}

class WebGpuFilterSystem {
  static const _floatsPerVertex = 6;
  static const _bytesPerVertex = _floatsPerVertex * 4;
  static const _normalMapFloatsPerVertex = 8;
  static const _normalMapBytesPerVertex = _normalMapFloatsPerVertex * 4;
  static const _alphaMaskFloatsPerVertex = 8;
  static const _alphaMaskBytesPerVertex = _alphaMaskFloatsPerVertex * 4;
  static const _displacementMapUniformBytes = 80;
  static const _singleTextureBindGroupLayout = 1;
  static const _normalMapBindGroupLayoutKey = 2;
  static const _displacementMapBindGroupLayoutKey = 3;
  static const _alphaMaskBindGroupLayoutKey = 4;

  final RenderContextWebGPU renderContext;
  late final GPUBindGroupLayout _colorMatrixBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 1,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 2,
      visibility: $GPUShaderStage.FRAGMENT,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  late final GPUPipelineLayout _colorMatrixPipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(
    bindGroupLayouts: [_colorMatrixBindGroupLayout].toJS,
  ));
  late final GPUBindGroupLayout _normalMapBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 1,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 2,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 3,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 4,
      visibility: $GPUShaderStage.FRAGMENT,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  late final GPUPipelineLayout _normalMapPipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(
    bindGroupLayouts: [_normalMapBindGroupLayout].toJS,
  ));
  late final GPUBindGroupLayout _displacementMapBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 1,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 2,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 3,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 4,
      visibility: $GPUShaderStage.FRAGMENT,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  late final GPUPipelineLayout _displacementMapPipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(
    bindGroupLayouts: [_displacementMapBindGroupLayout].toJS,
  ));
  late final GPUBindGroupLayout _alphaMaskBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 1,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 2,
      visibility: $GPUShaderStage.FRAGMENT,
      sampler: GPUSamplerBindingLayout(type: 'filtering'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 3,
      visibility: $GPUShaderStage.FRAGMENT,
      texture: GPUTextureBindingLayout(sampleType: 'float'),
    ),
    GPUBindGroupLayoutEntry(
      binding: 4,
      visibility: $GPUShaderStage.FRAGMENT,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  late final GPUPipelineLayout _alphaMaskPipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(
    bindGroupLayouts: [_alphaMaskBindGroupLayout].toJS,
  ));
  late final GPUShaderModule _colorMatrixShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _colorMatrixShaderSource));
  late final GPUShaderModule _blurShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _blurShaderSource));
  late final GPUShaderModule _dropShadowShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _dropShadowShaderSource));
  late final GPUShaderModule _glowShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _glowShaderSource));
  late final GPUShaderModule _chromaKeyShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _chromaKeyShaderSource));
  late final GPUShaderModule _fxaaShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _fxaaShaderSource));
  late final GPUShaderModule _normalMapShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _normalMapShaderSource));
  late final GPUShaderModule _displacementMapShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _displacementMapShaderSource));
  late final GPUShaderModule _alphaMaskShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _alphaMaskShaderSource));
  GPUBuffer? _vertexBuffer;
  GPUBuffer? _indexBuffer;
  GPUBuffer? _normalMapVertexBuffer;
  GPUBuffer? _alphaMaskVertexBuffer;
  late final GPUBuffer _uniformBuffer = _createUniformBuffer(80);
  late final GPUBuffer _blurUniformBuffer = _createUniformBuffer(16);
  late final GPUBuffer _dropShadowUniformBuffer = _createUniformBuffer(32);
  late final GPUBuffer _glowUniformBuffer = _createUniformBuffer(32);
  late final GPUBuffer _chromaKeyUniformBuffer = _createUniformBuffer(32);
  late final GPUBuffer _fxaaUniformBuffer = _createUniformBuffer(16);
  late final GPUBuffer _normalMapUniformBuffer = _createUniformBuffer(80);
  late final GPUBuffer _displacementMapUniformBuffer = _createUniformBuffer(_displacementMapUniformBytes);
  late final GPUBuffer _alphaMaskUniformBuffer = _createUniformBuffer(32);
  final _colorMatrixPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _blurPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _dropShadowPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _glowPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _chromaKeyPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _fxaaPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _normalMapPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _displacementMapPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _alphaMaskPipelines = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _filterBindGroups = <_BindGroupKey, GPUBindGroup>{};
  var _filterBindGroupGeneration = -1;
  var _vertexCapacity = 0;
  var _indexCapacity = 0;
  var _normalMapVertexCapacity = 0;
  var _alphaMaskVertexCapacity = 0;

  WebGpuFilterSystem(this.renderContext);

  void _syncFilterBindGroupGeneration() {
    final generation = renderContext.textureSystem.bindGroupGeneration;
    if (_filterBindGroupGeneration == generation) return;
    _filterBindGroupGeneration = generation;
    _filterBindGroups.clear();
  }

  GPUBindGroup _getSingleTextureBindGroup(RenderTexture texture, GPUBuffer uniformBuffer, int uniformByteSize) {
    final textureSystem = renderContext.textureSystem;
    final sampler = textureSystem.getSampler(texture);
    final view = textureSystem.getTextureView(texture);
    _syncFilterBindGroupGeneration();

    final key = _BindGroupKey(
      layout: _singleTextureBindGroupLayout,
      textureGeneration: _filterBindGroupGeneration,
      texture: texture,
      secondTexture: null,
      uniformBuffer: uniformBuffer,
    );
    final cached = _filterBindGroups[key];
    if (cached != null) return cached;

    final created = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _colorMatrixBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: sampler),
        GPUBindGroupEntry(binding: 1, resource: view),
        GPUBindGroupEntry(
          binding: 2,
          resource: GPUBufferBinding(buffer: uniformBuffer, offset: 0, size: uniformByteSize),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;
    _filterBindGroups[key] = created;
    return created;
  }

  GPUBindGroup _getTwoTextureBindGroup({
    required int layoutKey,
    required GPUBindGroupLayout layout,
    required RenderTexture texture,
    required RenderTexture secondTexture,
    required GPUBuffer uniformBuffer,
    required int uniformByteSize,
  }) {
    final textureSystem = renderContext.textureSystem;
    final sampler = textureSystem.getSampler(texture);
    final view = textureSystem.getTextureView(texture);
    final secondSampler = textureSystem.getSampler(secondTexture);
    final secondView = textureSystem.getTextureView(secondTexture);
    _syncFilterBindGroupGeneration();

    final key = _BindGroupKey(
      layout: layoutKey,
      textureGeneration: _filterBindGroupGeneration,
      texture: texture,
      secondTexture: secondTexture,
      uniformBuffer: uniformBuffer,
    );
    final cached = _filterBindGroups[key];
    if (cached != null) return cached;

    final created = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: layout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: sampler),
        GPUBindGroupEntry(binding: 1, resource: view),
        GPUBindGroupEntry(binding: 2, resource: secondSampler),
        GPUBindGroupEntry(binding: 3, resource: secondView),
        GPUBindGroupEntry(
          binding: 4,
          resource: GPUBufferBinding(buffer: uniformBuffer, offset: 0, size: uniformByteSize),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;
    _filterBindGroups[key] = created;
    return created;
  }

  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    final firstFilter = renderFilters.length == 1 ? renderFilters[0] : null;

    if (renderFilters.isEmpty) return;
    if (_canRenderInWebGpuBatch(renderFilters)) {
      final colorScale = _webGpuBatchColorScale(renderFilters);
      renderContext.batchSystem.renderTextureQuad(
        renderState,
        renderTextureQuad,
        colorScale[0],
        colorScale[1],
        colorScale[2],
        colorScale[3],
      );
      return;
    }

    if (firstFilter != null && firstFilter.isSimple && firstFilter.supportsWebGPU) {
      if (!firstFilter.rendersInWebGpuBatch) renderContext.flush();
      firstFilter.renderFilter(renderState, renderTextureQuad, 0);
      return;
    }

    if (renderFilters.every((filter) => filter.supportsWebGPU)) {
      renderObjectFiltered(renderState, _RenderTextureQuadObject(renderTextureQuad, renderFilters));
      return;
    }

    _throwUnsupported();
  }

  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    final filters = renderObject.filters;
    if (filters.isEmpty) return;
    if (!filters.every((filter) => filter.supportsWebGPU)) {
      _throwUnsupported();
    }

    if (_canRenderInWebGpuBatch(filters)) {
      renderState.pushColorScale(_webGpuBatchColorScale(filters));
      renderObject.render(renderState);
      renderState.pop();
      return;
    }

    final bounds = renderObject.bounds;
    final pixelRatio = math.sqrt(renderState.globalMatrix.det.abs());

    var boundsLeft = bounds.left.floor();
    var boundsTop = bounds.top.floor();
    var boundsRight = bounds.right.ceil();
    var boundsBottom = bounds.bottom.ceil();

    for (final filter in filters) {
      final overlap = filter.overlap;
      boundsLeft += overlap.left;
      boundsTop += overlap.top;
      boundsRight += overlap.right;
      boundsBottom += overlap.bottom;
    }

    boundsLeft = (boundsLeft * pixelRatio).floor();
    boundsTop = (boundsTop * pixelRatio).floor();
    boundsRight = (boundsRight * pixelRatio).ceil();
    boundsBottom = (boundsBottom * pixelRatio).ceil();

    final boundsWidth = boundsRight - boundsLeft;
    final boundsHeight = boundsBottom - boundsTop;
    if (boundsWidth <= 0 || boundsHeight <= 0) return;

    final initialRenderTexture = renderContext.activeRenderTexture;
    final initialProjectionMatrix = renderContext.activeProjectionMatrix.clone();
    final maskSnapshot = renderContext.maskSystem._detach();
    final renderTextures = <int, RenderTexture>{};
    final disposableRenderTextures = <RenderTexture>{};
    final renderTexture = RenderTexture.rawWebGL(boundsWidth, boundsHeight);
    renderTextures[0] = renderTexture;
    disposableRenderTextures.add(renderTexture);

    try {
      final filterProjectionMatrix = Matrix3D.fromIdentity();
      filterProjectionMatrix.scale(2 / boundsWidth, -2 / boundsHeight, 1);
      filterProjectionMatrix.translate(-1, 1, 0);

      final filterRenderState = RenderState(renderContext);
      filterRenderState.globalMatrix.scale(pixelRatio, pixelRatio);
      filterRenderState.globalMatrix.translate(-boundsLeft, -boundsTop);

      renderContext.activateRenderTexture(renderTexture);
      renderContext.activateProjectionMatrix(filterProjectionMatrix);
      renderContext.clearActiveRenderTexture(0);
      renderObject.render(filterRenderState);
      renderContext.flush();
      renderContext.maskSystem.resetFrame();

      for (var i = 0; i < filters.length; i++) {
        _renderFilterPasses(
          filters[i],
          renderState,
          filterRenderState,
          initialRenderTexture,
          initialProjectionMatrix,
          filterProjectionMatrix,
          maskSnapshot,
          renderTextures,
          disposableRenderTextures,
          boundsLeft,
          boundsTop,
          boundsWidth,
          boundsHeight,
          pixelRatio,
          i == filters.length - 1,
        );
      }
    } finally {
      renderContext.activateRenderTexture(initialRenderTexture);
      renderContext.activateProjectionMatrix(initialProjectionMatrix);
      renderContext.maskSystem._restore(maskSnapshot);
      for (final renderTexture in disposableRenderTextures) {
        _disposeRenderTextureAfterSubmittedWork(renderTexture);
      }
    }
  }

  void _disposeRenderTextureAfterSubmittedWork(RenderTexture renderTexture) {
    unawaited(renderContext.device.queue.onSubmittedWorkDone().toDart.then((_) {
      renderContext.commandSystem.disposeRenderTexture(renderTexture);
      renderContext.textureSystem.disposeTexture(renderTexture);
      renderTexture.dispose();
    }));
  }

  bool _canRenderInWebGpuBatch(List<RenderFilter> filters) =>
      filters.every((filter) => filter.isSimple && filter.supportsWebGPU && filter.rendersInWebGpuBatch);

  Float32List _webGpuBatchColorScale(List<RenderFilter> filters) {
    final colorScale = Float32List.fromList([1.0, 1.0, 1.0, 1.0]);
    for (final filter in filters) {
      filter.applyWebGpuBatchColorScale(colorScale);
    }
    return colorScale;
  }

  void _renderFilterPasses(
    RenderFilter filter,
    RenderState finalRenderState,
    RenderState filterRenderState,
    RenderTexture? initialRenderTexture,
    Matrix3D initialProjectionMatrix,
    Matrix3D filterProjectionMatrix,
    _WebGpuMaskSnapshot maskSnapshot,
    Map<int, RenderTexture> renderTextures,
    Set<RenderTexture> disposableRenderTextures,
    int boundsLeft,
    int boundsTop,
    int boundsWidth,
    int boundsHeight,
    num pixelRatio,
    bool renderToFinalTarget,
  ) {
    final renderPassSources = filter.renderPassSources;
    final renderPassTargets = filter.renderPassTargets;

    for (var pass = 0; pass < renderPassSources.length; pass++) {
      final source = renderTextures[renderPassSources[pass]];
      if (source == null) throw StateError('Invalid renderPassSource!');

      final targetId = renderPassTargets[pass];
      final isOutputPass = targetId == renderPassTargets.last;
      final isFinalPass = renderToFinalTarget && isOutputPass;
      final RenderState passRenderState;
      if (isFinalPass) {
        passRenderState = finalRenderState;
        renderContext.activateRenderTexture(initialRenderTexture);
        renderContext.activateProjectionMatrix(initialProjectionMatrix);
        renderContext.maskSystem._restore(maskSnapshot);
      } else {
        passRenderState = filterRenderState;
        final targetExists = renderTextures.containsKey(targetId);
        final target = renderTextures.putIfAbsent(targetId, () {
          final renderTexture = RenderTexture.rawWebGL(boundsWidth, boundsHeight);
          disposableRenderTextures.add(renderTexture);
          return renderTexture;
        });
        renderContext.activateRenderTexture(target);
        renderContext.activateProjectionMatrix(filterProjectionMatrix);
        if (!targetExists) {
          renderContext.clearActiveRenderTexture(0);
        }
      }

      final sourceRenderTextureQuad = _createFilterSourceQuad(
        source,
        boundsLeft,
        boundsTop,
        boundsWidth,
        boundsHeight,
        pixelRatio,
      );
      filter.renderFilter(passRenderState, sourceRenderTextureQuad, pass);
    }

    if (!renderToFinalTarget) {
      final output = renderTextures[renderPassTargets.last];
      if (output == null) throw StateError('Invalid renderPassTarget!');
      renderTextures
        ..clear()
        ..[0] = output;
    }
  }

  RenderTextureQuad _createFilterSourceQuad(
    RenderTexture renderTexture,
    int boundsLeft,
    int boundsTop,
    int boundsWidth,
    int boundsHeight,
    num pixelRatio,
  ) =>
      RenderTextureQuad(
        renderTexture,
        Rectangle<int>(0, 0, boundsWidth, boundsHeight),
        Rectangle<int>(-boundsLeft, -boundsTop, boundsWidth, boundsHeight),
        0,
        pixelRatio,
      );

  void renderColorMatrixFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List colorMatrixList,
    Float32List colorOffsetList,
  ) {
    final uniformData = Float32List(20);
    final alpha = renderState.globalAlpha;
    uniformData
      ..setRange(0, 12, colorMatrixList, 0)
      ..setRange(12, 16, [
        colorMatrixList[12] * alpha,
        colorMatrixList[13] * alpha,
        colorMatrixList[14] * alpha,
        colorMatrixList[15] * alpha,
      ])
      ..setRange(16, 20, [
        colorOffsetList[0] / 255,
        colorOffsetList[1] / 255,
        colorOffsetList[2] / 255,
        colorOffsetList[3] / 255 * alpha,
      ]);

    _renderTextureQuadWithColorMatrixUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderTintFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    num factorR,
    num factorG,
    num factorB,
    num factorA,
  ) {
    final alpha = renderState.globalAlpha;
    final uniformData = Float32List(20);
    uniformData[0] = factorR.toDouble();
    uniformData[5] = factorG.toDouble();
    uniformData[10] = factorB.toDouble();
    uniformData[15] = factorA.toDouble() * alpha;
    _renderTextureQuadWithColorMatrixUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderChromaKeyFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    int backgroundColor,
    int solidThreshold,
    int invisibleThreshold,
  ) {
    final uniformData = Float32List.fromList([
      colorGetR(backgroundColor) / 255.0,
      colorGetG(backgroundColor) / 255.0,
      colorGetB(backgroundColor) / 255.0,
      1,
      solidThreshold / 255.0,
      invisibleThreshold / 255.0,
      0.8,
      0,
    ]);
    _renderTextureQuadWithChromaKeyUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderBlurFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    num alpha,
    num radiusX,
    num radiusY,
  ) {
    final uniformData = Float32List.fromList([
      radiusX.toDouble(),
      radiusY.toDouble(),
      alpha.toDouble(),
      0,
    ]);
    _renderTextureQuadWithBlurUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderFxaaFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
  ) {
    final texture = renderTextureQuad.renderTexture;
    final uniformData = Float32List.fromList([
      1.0 / texture.width,
      1.0 / texture.height,
      renderState.globalAlpha,
      0,
    ]);
    _renderTextureQuadWithFxaaUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderGlowFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    int color,
    num alpha,
    num radiusX,
    num radiusY,
  ) {
    final uniformData = Float32List.fromList([
      radiusX.toDouble(),
      radiusY.toDouble(),
      0,
      0,
      colorGetR(color) / 255.0,
      colorGetG(color) / 255.0,
      colorGetB(color) / 255.0,
      colorGetA(color) / 255.0 * alpha.toDouble(),
    ]);
    _renderTextureQuadWithGlowUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderDropShadowFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    int color,
    num alpha,
    num shiftX,
    num shiftY,
    num radiusX,
    num radiusY,
  ) {
    final uniformData = Float32List.fromList([
      shiftX.toDouble(),
      shiftY.toDouble(),
      radiusX.toDouble(),
      radiusY.toDouble(),
      colorGetR(color) / 255.0,
      colorGetG(color) / 255.0,
      colorGetB(color) / 255.0,
      colorGetA(color) / 255.0 * alpha.toDouble(),
    ]);
    _renderTextureQuadWithDropShadowUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderNormalMapFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    RenderTextureQuad normalMapRenderTextureQuad,
    int ambientColor,
    int lightColor,
    num lightX,
    num lightY,
    num lightZ,
    num lightRadius,
  ) {
    final ixList = renderTextureQuad.ixList;
    final vxList = renderTextureQuad.vxList;
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final texture = renderTextureQuad.renderTexture;
    final mapTexture = normalMapRenderTextureQuad.renderTexture;
    final texMatrix = renderContext.textureSystem.scaledSamplerMatrix(texture, renderTextureQuad.samplerMatrix);
    final mapMatrix = renderContext.textureSystem.scaledSamplerMatrix(
      mapTexture,
      normalMapRenderTextureQuad.samplerMatrix,
    );
    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);

    final lightSamplerX = texMatrix.tx + lightX * texMatrix.a + lightY * texMatrix.c;
    final lightSamplerY = texMatrix.ty + lightX * texMatrix.b + lightY * texMatrix.d;
    final lightScale = math.sqrt(texMatrix.det);
    final lightSamplerZ = lightScale * lightZ;
    final lightSamplerRadius = lightScale * lightRadius;

    final uniformData = Float32List(20)
      ..setRange(0, 4, [
        colorGetA(ambientColor) / 255.0,
        colorGetR(ambientColor) / 255.0,
        colorGetG(ambientColor) / 255.0,
        colorGetB(ambientColor) / 255.0,
      ])
      ..setRange(4, 8, [
        colorGetA(lightColor) / 255.0,
        colorGetR(lightColor) / 255.0,
        colorGetG(lightColor) / 255.0,
        colorGetB(lightColor) / 255.0,
      ])
      ..setRange(8, 12, [
        lightSamplerX,
        lightSamplerY,
        lightSamplerZ,
        lightSamplerRadius,
      ])
      ..setRange(12, 16, [
        renderState.globalAlpha,
        0,
        0,
        0,
      ])
      ..setRange(16, 20, [0, 0, 0, 0]);

    final vertices = Float32List(vertexCount * _normalMapFloatsPerVertex);
    final indices = Uint32List(ixList.length);

    var vertexIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;
      vertices[vertexIndex++] = clipX;
      vertices[vertexIndex++] = clipY;
      vertices[vertexIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[vertexIndex++] = clipW;
      vertices[vertexIndex++] = texMatrix.tx + x * texMatrix.a + y * texMatrix.c;
      vertices[vertexIndex++] = texMatrix.ty + x * texMatrix.b + y * texMatrix.d;
      vertices[vertexIndex++] = mapMatrix.tx + x * mapMatrix.a + y * mapMatrix.c;
      vertices[vertexIndex++] = mapMatrix.ty + x * mapMatrix.b + y * mapMatrix.d;
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureNormalMapVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    final normalMapVertexBuffer = _normalMapVertexBuffer!;
    final indexBuffer = _indexBuffer!;
    final normalMapUniformBuffer = _normalMapUniformBuffer;
    renderContext.device.queue
      ..writeBuffer(normalMapVertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(normalMapUniformBuffer, 0, uniformData.buffer.toJS);

    final bindGroup = _getTwoTextureBindGroup(
      layoutKey: _normalMapBindGroupLayoutKey,
      layout: _normalMapBindGroupLayout,
      texture: texture,
      secondTexture: mapTexture,
      uniformBuffer: normalMapUniformBuffer,
      uniformByteSize: 80,
    );

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getNormalMapPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, normalMapVertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(indexBuffer, 'uint32', 0, indexBytes);
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    pass.drawIndexed(ixList.length, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();

    final statistics = renderContext.renderStatistics;
    statistics.drawCount++;
    statistics.vertexCount += vertexCount;
    statistics.indexCount += ixList.length;
  }

  void renderDisplacementMapFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    RenderTextureQuad mapRenderTextureQuad,
    Matrix mapMatrix,
    Matrix disMatrix,
  ) {
    final ixList = renderTextureQuad.ixList;
    final vxList = renderTextureQuad.vxList;
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);
    final texture = renderTextureQuad.renderTexture;
    final mapTexture = mapRenderTextureQuad.renderTexture;
    final scaledMapMatrix =
        renderContext.textureSystem.scaledSamplerMatrix(mapTexture, mapMatrix, inputTexture: texture);
    final scaledDisMatrix = renderContext.textureSystem.scaledSamplerMatrix(texture, disMatrix);

    final uniformData = Float32List(20)
      ..setRange(0, 4, [scaledMapMatrix.a, scaledMapMatrix.c, scaledMapMatrix.tx, 0])
      ..setRange(4, 8, [scaledMapMatrix.b, scaledMapMatrix.d, scaledMapMatrix.ty, 0])
      ..setRange(8, 12, [scaledDisMatrix.a, scaledDisMatrix.c, 0, 0])
      ..setRange(12, 16, [scaledDisMatrix.b, scaledDisMatrix.d, 0, 0])
      ..setRange(16, 20, [renderState.globalAlpha, 0, 0, 0]);

    final vertices = Float32List(vertexCount * _floatsPerVertex);
    final indices = Uint32List(ixList.length);

    var vertexIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;
      vertices[vertexIndex++] = clipX;
      vertices[vertexIndex++] = clipY;
      vertices[vertexIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[vertexIndex++] = clipW;
      vertexIndex = renderContext.textureSystem.writeTextureCoordinates(
        texture,
        vxList,
        sourceIndex,
        vertices,
        vertexIndex,
      );
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    final vertexBuffer = _vertexBuffer!;
    final indexBuffer = _indexBuffer!;
    final displacementMapUniformBuffer = _displacementMapUniformBuffer;
    renderContext.device.queue
      ..writeBuffer(vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(displacementMapUniformBuffer, 0, uniformData.buffer.toJS);

    final bindGroup = _getTwoTextureBindGroup(
      layoutKey: _displacementMapBindGroupLayoutKey,
      layout: _displacementMapBindGroupLayout,
      texture: texture,
      secondTexture: mapTexture,
      uniformBuffer: displacementMapUniformBuffer,
      uniformByteSize: _displacementMapUniformBytes,
    );

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getDisplacementMapPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(indexBuffer, 'uint32', 0, indexBytes);
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    pass.drawIndexed(ixList.length, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();

    final statistics = renderContext.renderStatistics;
    statistics.drawCount++;
    statistics.vertexCount += vertexCount;
    statistics.indexCount += ixList.length;
  }

  void renderAlphaMaskFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    RenderTextureQuad maskRenderTextureQuad,
    Matrix maskMatrix,
  ) {
    final ixList = renderTextureQuad.ixList;
    final vxList = renderTextureQuad.vxList;
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final bounds = maskRenderTextureQuad.vxList;
    final mskBoundsX1 = bounds[2] < bounds[10] ? bounds[2] : bounds[10];
    final mskBoundsX2 = bounds[2] > bounds[10] ? bounds[2] : bounds[10];
    final mskBoundsY1 = bounds[3] < bounds[11] ? bounds[3] : bounds[11];
    final mskBoundsY2 = bounds[3] > bounds[11] ? bounds[3] : bounds[11];

    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);
    final texture = renderTextureQuad.renderTexture;
    final maskTexture = maskRenderTextureQuad.renderTexture;
    final scaledMaskMatrix = renderContext.textureSystem.scaledSamplerMatrix(maskTexture, maskMatrix);

    final uniformData = Float32List.fromList([
      mskBoundsX1,
      mskBoundsY1,
      mskBoundsX2,
      mskBoundsY2,
      renderState.globalAlpha,
      0,
      0,
      0,
    ]);

    final vertices = Float32List(vertexCount * _alphaMaskFloatsPerVertex);
    final indices = Uint32List(ixList.length);

    var vertexIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;
      vertices[vertexIndex++] = clipX;
      vertices[vertexIndex++] = clipY;
      vertices[vertexIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[vertexIndex++] = clipW;
      vertexIndex = renderContext.textureSystem.writeTextureCoordinates(
        texture,
        vxList,
        sourceIndex,
        vertices,
        vertexIndex,
      );
      vertices[vertexIndex++] = scaledMaskMatrix.tx + x * scaledMaskMatrix.a + y * scaledMaskMatrix.c;
      vertices[vertexIndex++] = scaledMaskMatrix.ty + x * scaledMaskMatrix.b + y * scaledMaskMatrix.d;
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureAlphaMaskVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    final alphaMaskVertexBuffer = _alphaMaskVertexBuffer!;
    final indexBuffer = _indexBuffer!;
    final alphaMaskUniformBuffer = _alphaMaskUniformBuffer;
    renderContext.device.queue
      ..writeBuffer(alphaMaskVertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(alphaMaskUniformBuffer, 0, uniformData.buffer.toJS);

    final bindGroup = _getTwoTextureBindGroup(
      layoutKey: _alphaMaskBindGroupLayoutKey,
      layout: _alphaMaskBindGroupLayout,
      texture: texture,
      secondTexture: maskTexture,
      uniformBuffer: alphaMaskUniformBuffer,
      uniformByteSize: 32,
    );

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getAlphaMaskPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, alphaMaskVertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(indexBuffer, 'uint32', 0, indexBytes);
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    pass.drawIndexed(ixList.length, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();

    final statistics = renderContext.renderStatistics;
    statistics.drawCount++;
    statistics.vertexCount += vertexCount;
    statistics.indexCount += ixList.length;
  }

  void _renderTextureQuadWithColorMatrixUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _uniformBuffer,
      _getColorMatrixPipeline,
      80,
    );
  }

  void _renderTextureQuadWithBlurUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _blurUniformBuffer,
      _getBlurPipeline,
      16,
    );
  }

  void _renderTextureQuadWithGlowUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _glowUniformBuffer,
      _getGlowPipeline,
      32,
    );
  }

  void _renderTextureQuadWithDropShadowUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _dropShadowUniformBuffer,
      _getDropShadowPipeline,
      32,
    );
  }

  void _renderTextureQuadWithChromaKeyUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _chromaKeyUniformBuffer,
      _getChromaKeyPipeline,
      32,
    );
  }

  void _renderTextureQuadWithFxaaUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    _renderTextureQuadWithUniform(
      renderState,
      renderTextureQuad,
      uniformData,
      _fxaaUniformBuffer,
      _getFxaaPipeline,
      16,
    );
  }

  void _renderTextureQuadWithUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
    GPUBuffer uniformBuffer,
    GPURenderPipeline Function(BlendMode blendMode, bool stencilTest) getPipeline,
    int uniformByteSize,
  ) {
    final ixList = renderTextureQuad.ixList;
    final vxList = renderTextureQuad.vxList;
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final vertices = Float32List(vertexCount * _floatsPerVertex);
    final indices = Uint32List(ixList.length);
    final texture = renderTextureQuad.renderTexture;
    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);

    var vertexIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;
      vertices[vertexIndex++] = clipX;
      vertices[vertexIndex++] = clipY;
      vertices[vertexIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[vertexIndex++] = clipW;
      vertexIndex = renderContext.textureSystem.writeTextureCoordinates(
        texture,
        vxList,
        sourceIndex,
        vertices,
        vertexIndex,
      );
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    final vertexBuffer = _vertexBuffer!;
    final indexBuffer = _indexBuffer!;
    renderContext.device.queue
      ..writeBuffer(vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(uniformBuffer, 0, uniformData.buffer.toJS);

    final bindGroup = _getSingleTextureBindGroup(texture, uniformBuffer, uniformByteSize);

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(getPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(indexBuffer, 'uint32', 0, indexBytes);
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    pass.drawIndexed(ixList.length, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();

    final statistics = renderContext.renderStatistics;
    statistics.drawCount++;
    statistics.vertexCount += vertexCount;
    statistics.indexCount += ixList.length;
  }

  GPURenderPipeline _getColorMatrixPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _colorMatrixPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createColorMatrixPipeline(blendMode, stencilTest),
    );
  }

  GPURenderPipeline _getBlurPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _blurPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(_pipelineKey(stencilTest), () => _createBlurPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getGlowPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _glowPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(_pipelineKey(stencilTest), () => _createGlowPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getDropShadowPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _dropShadowPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createDropShadowPipeline(blendMode, stencilTest),
    );
  }

  GPURenderPipeline _getChromaKeyPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _chromaKeyPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createChromaKeyPipeline(blendMode, stencilTest),
    );
  }

  GPURenderPipeline _getFxaaPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _fxaaPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(_pipelineKey(stencilTest), () => _createFxaaPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getNormalMapPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _normalMapPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createNormalMapPipeline(blendMode, stencilTest),
    );
  }

  GPURenderPipeline _getDisplacementMapPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _displacementMapPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createDisplacementMapPipeline(blendMode, stencilTest),
    );
  }

  GPURenderPipeline _getAlphaMaskPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _alphaMaskPipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      _pipelineKey(stencilTest),
      () => _createAlphaMaskPipeline(blendMode, stencilTest),
    );
  }

  int _pipelineKey(bool stencilTest) => (renderContext.sampleCount << 1) | (stencilTest ? 1 : 0);

  GPURenderPipeline _createColorMatrixPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL color matrix filter pipeline',
        _colorMatrixShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createBlurPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL blur filter pipeline',
        _blurShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createGlowPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL glow filter pipeline',
        _glowShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createDropShadowPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL drop shadow filter pipeline',
        _dropShadowShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createChromaKeyPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL chroma key filter pipeline',
        _chromaKeyShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createFxaaPipeline(BlendMode blendMode, bool stencilTest) => _createFilterPipeline(
        'StageXL fxaa filter pipeline',
        _fxaaShaderModule,
        blendMode,
        stencilTest,
      );

  GPURenderPipeline _createNormalMapPipeline(BlendMode blendMode, bool stencilTest) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL normal map filter pipeline',
      layout: _normalMapPipelineLayout,
      vertex: GPUVertexState(
        module: _normalMapShaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _normalMapBytesPerVertex,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
              GPUVertexAttribute(format: 'float32x2', offset: 24, shaderLocation: 2),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: _normalMapShaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            blend: renderContext.pipelineSystem.getBlendState(blendMode),
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilTest),
      multisample: GPUMultisampleState(count: renderContext.sampleCount),
    ));
  }

  GPURenderPipeline _createDisplacementMapPipeline(BlendMode blendMode, bool stencilTest) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL displacement map filter pipeline',
      layout: _displacementMapPipelineLayout,
      vertex: GPUVertexState(
        module: _displacementMapShaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _bytesPerVertex,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: _displacementMapShaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            blend: renderContext.pipelineSystem.getBlendState(blendMode),
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilTest),
      multisample: GPUMultisampleState(count: renderContext.sampleCount),
    ));
  }

  GPURenderPipeline _createAlphaMaskPipeline(BlendMode blendMode, bool stencilTest) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL alpha mask filter pipeline',
      layout: _alphaMaskPipelineLayout,
      vertex: GPUVertexState(
        module: _alphaMaskShaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _alphaMaskBytesPerVertex,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
              GPUVertexAttribute(format: 'float32x2', offset: 24, shaderLocation: 2),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: _alphaMaskShaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            blend: renderContext.pipelineSystem.getBlendState(blendMode),
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilTest),
      multisample: GPUMultisampleState(count: renderContext.sampleCount),
    ));
  }

  GPURenderPipeline _createFilterPipeline(
    String label,
    GPUShaderModule shaderModule,
    BlendMode blendMode,
    bool stencilTest,
  ) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: label,
      layout: _colorMatrixPipelineLayout,
      vertex: GPUVertexState(
        module: shaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _bytesPerVertex,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: shaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            blend: renderContext.pipelineSystem.getBlendState(blendMode),
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilTest),
      multisample: GPUMultisampleState(count: renderContext.sampleCount),
    ));
  }

  GPUDepthStencilState _depthStencilState(bool stencilTest) {
    final stencilFace = stencilTest
        ? GPUStencilFaceState(compare: 'equal', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep')
        : GPUStencilFaceState(compare: 'always', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep');
    return GPUDepthStencilState(
      format: 'depth24plus-stencil8',
      depthWriteEnabled: false,
      depthCompare: 'always',
      stencilFront: stencilFace,
      stencilBack: stencilFace,
      stencilReadMask: 0xFF,
      stencilWriteMask: 0,
    );
  }

  GPUBuffer _createVertexBuffer(int size) {
    _vertexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
    ));
  }

  GPUBuffer _createIndexBuffer(int size) {
    _indexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.INDEX,
    ));
  }

  GPUBuffer _createNormalMapVertexBuffer(int size) {
    _normalMapVertexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
    ));
  }

  GPUBuffer _createAlphaMaskVertexBuffer(int size) {
    _alphaMaskVertexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
    ));
  }

  GPUBuffer _createUniformBuffer(int size) => renderContext.device.createBuffer(GPUBufferDescriptor(
        size: size,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
      ));

  void _ensureVertexCapacity(int size) {
    final buffer = _vertexBuffer;
    if (buffer != null && size <= _vertexCapacity) return;
    buffer?.destroy();
    _vertexBuffer = _createVertexBuffer(size * 2);
  }

  void _ensureIndexCapacity(int size) {
    final buffer = _indexBuffer;
    if (buffer != null && size <= _indexCapacity) return;
    buffer?.destroy();
    _indexBuffer = _createIndexBuffer(size * 2);
  }

  void _ensureNormalMapVertexCapacity(int size) {
    final buffer = _normalMapVertexBuffer;
    if (buffer != null && size <= _normalMapVertexCapacity) return;
    buffer?.destroy();
    _normalMapVertexBuffer = _createNormalMapVertexBuffer(size * 2);
  }

  void _ensureAlphaMaskVertexCapacity(int size) {
    final buffer = _alphaMaskVertexBuffer;
    if (buffer != null && size <= _alphaMaskVertexCapacity) return;
    buffer?.destroy();
    _alphaMaskVertexBuffer = _createAlphaMaskVertexBuffer(size * 2);
  }

  Never _throwUnsupported() {
    renderContext.renderStatistics.addWebGpuFallbackCause('unsupported filter');
    throw UnsupportedError('WebGPU filter parity requires the WGSL multi-pass filter implementation.');
  }

  static const _colorMatrixShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct ColorMatrixUniforms {
      matrixR: vec4<f32>,
      matrixG: vec4<f32>,
      matrixB: vec4<f32>,
      matrixA: vec4<f32>,
      offset: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> colorMatrix: ColorMatrixUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let sampleColor = textureSample(stageTexture, stageSampler, input.uv);
      let safeAlpha = max(sampleColor.a, 0.000001);
      let color = vec4<f32>(sampleColor.rgb / safeAlpha, sampleColor.a);
      let transformed = colorMatrix.offset + vec4<f32>(
        dot(color, colorMatrix.matrixR),
        dot(color, colorMatrix.matrixG),
        dot(color, colorMatrix.matrixB),
        dot(color, colorMatrix.matrixA)
      );
      return vec4<f32>(transformed.rgb * transformed.a, transformed.a);
    }
  ''';

  static const _blurShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct BlurUniforms {
      radius: vec2<f32>,
      alpha: f32,
      padding: f32,
    };

    @group(0) @binding(2) var<uniform> blur: BlurUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let radius = blur.radius;
      var sum = vec4<f32>(0.0);
      sum += textureSample(stageTexture, stageSampler, input.uv - radius * 1.2) * 0.00443;
      sum += textureSample(stageTexture, stageSampler, input.uv - radius * 0.8) * 0.05399;
      sum += textureSample(stageTexture, stageSampler, input.uv - radius * 0.4) * 0.24197;
      sum += textureSample(stageTexture, stageSampler, input.uv) * 0.39894;
      sum += textureSample(stageTexture, stageSampler, input.uv + radius * 0.4) * 0.24197;
      sum += textureSample(stageTexture, stageSampler, input.uv + radius * 0.8) * 0.05399;
      sum += textureSample(stageTexture, stageSampler, input.uv + radius * 1.2) * 0.00443;
      return sum * blur.alpha;
    }
  ''';

  static const _chromaKeyShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct ChromaKeyUniforms {
      backgroundColor: vec4<f32>,
      thresholds: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> chromaKey: ChromaKeyUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let pixelColor = textureSample(stageTexture, stageSampler, input.uv);
      let colorDiff = abs(pixelColor.rgb - chromaKey.backgroundColor.rgb);
      let invisibleThreshold = chromaKey.thresholds.y;
      let solidThreshold = chromaKey.thresholds.x;

      if (any(colorDiff > vec3<f32>(solidThreshold))) {
        return pixelColor;
      }

      if (all(colorDiff < vec3<f32>(invisibleThreshold))) {
        return pixelColor * 0.0;
      }

      let thresholdRange = solidThreshold - invisibleThreshold;
      let channelAlpha = clamp(
        (colorDiff - vec3<f32>(invisibleThreshold)) / thresholdRange,
        vec3<f32>(0),
        vec3<f32>(1)
      );
      let alpha = min(channelAlpha.b, min(channelAlpha.r, channelAlpha.g));
      let weight = chromaKey.thresholds.z;
      let correctedColor = pixelColor.rgb - (vec3<f32>(1) - colorDiff) * (1.0 - alpha) *
        chromaKey.backgroundColor.rgb * weight;

      return vec4<f32>(correctedColor, alpha);
    }
  ''';

  static const _fxaaShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct FxaaUniforms {
      texel: vec2<f32>,
      alpha: f32,
      padding: f32,
    };

    @group(0) @binding(2) var<uniform> fxaa: FxaaUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let texel = fxaa.texel;
      let color = textureSample(stageTexture, stageSampler, input.uv);
      let rgbTL = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-1.0, -1.0) * texel).rgb;
      let rgbTR = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(1.0, -1.0) * texel).rgb;
      let rgbBL = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-1.0, 1.0) * texel).rgb;
      let rgbBR = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(1.0, 1.0) * texel).rgb;
      let rgbXY = color.rgb;
      let luma = vec3<f32>(0.299, 0.587, 0.114);

      let lumaTL = dot(rgbTL, luma);
      let lumaTR = dot(rgbTR, luma);
      let lumaBL = dot(rgbBL, luma);
      let lumaBR = dot(rgbBR, luma);
      let lumaXY = dot(rgbXY, luma);
      let lumaMin = min(lumaXY, min(min(lumaTL, lumaTR), min(lumaBL, lumaBR)));
      let lumaMax = max(lumaXY, max(max(lumaTL, lumaTR), max(lumaBL, lumaBR)));

      var dir = vec2<f32>(
        lumaBL + lumaBR - lumaTL - lumaTR,
        lumaTL + lumaBL - lumaTR - lumaBR,
      );
      let dirReduce = max((lumaTL + lumaTR + lumaBL + lumaBR) * (0.25 * (1.0 / 8.0)), 1.0 / 128.0);
      let dirMin = min(abs(dir.x), abs(dir.y)) + dirReduce;
      dir = clamp(dir / dirMin, vec2<f32>(-8.0, -8.0), vec2<f32>(8.0, 8.0)) * texel;

      let rgbA = 0.5 * (
        textureSample(stageTexture, stageSampler, input.uv - dir * 0.16666).rgb +
        textureSample(stageTexture, stageSampler, input.uv + dir * 0.16666).rgb
      );
      let rgbB = 0.25 * (
        textureSample(stageTexture, stageSampler, input.uv - dir * 0.5).rgb +
        textureSample(stageTexture, stageSampler, input.uv + dir * 0.5).rgb
      ) + rgbA * 0.5;

      let lumaB = dot(rgbB, luma);
      let conditionLT = max(sign(lumaMin - lumaB), 0.0);
      let conditionGT = max(sign(lumaB - lumaMax), 0.0);
      let conditionOR = min(conditionLT + conditionGT, 1.0);
      return vec4<f32>((rgbA - rgbB) * conditionOR + rgbB, color.a) * fxaa.alpha;
    }
  ''';

  static const _glowShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct GlowUniforms {
      radius: vec2<f32>,
      padding0: vec2<f32>,
      color: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> glow: GlowUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let radius = glow.radius;
      var alpha = 0.0;
      alpha += textureSample(stageTexture, stageSampler, input.uv - radius * 1.2).a * 0.00443;
      alpha += textureSample(stageTexture, stageSampler, input.uv - radius * 0.8).a * 0.05399;
      alpha += textureSample(stageTexture, stageSampler, input.uv - radius * 0.4).a * 0.24197;
      alpha += textureSample(stageTexture, stageSampler, input.uv).a * 0.39894;
      alpha += textureSample(stageTexture, stageSampler, input.uv + radius * 0.4).a * 0.24197;
      alpha += textureSample(stageTexture, stageSampler, input.uv + radius * 0.8).a * 0.05399;
      alpha += textureSample(stageTexture, stageSampler, input.uv + radius * 1.2).a * 0.00443;
      alpha *= glow.color.a;
      return vec4<f32>(glow.color.rgb * alpha, alpha);
    }
  ''';

  static const _dropShadowShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct DropShadowUniforms {
      shift: vec2<f32>,
      radius: vec2<f32>,
      color: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> dropShadow: DropShadowUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let texCoord = input.uv - dropShadow.shift;
      let radius = dropShadow.radius;
      var alpha = 0.0;
      alpha += textureSample(stageTexture, stageSampler, texCoord - radius * 1.2).a * 0.00443;
      alpha += textureSample(stageTexture, stageSampler, texCoord - radius * 0.8).a * 0.05399;
      alpha += textureSample(stageTexture, stageSampler, texCoord - radius * 0.4).a * 0.24197;
      alpha += textureSample(stageTexture, stageSampler, texCoord).a * 0.39894;
      alpha += textureSample(stageTexture, stageSampler, texCoord + radius * 0.4).a * 0.24197;
      alpha += textureSample(stageTexture, stageSampler, texCoord + radius * 0.8).a * 0.05399;
      alpha += textureSample(stageTexture, stageSampler, texCoord + radius * 1.2).a * 0.00443;
      alpha *= dropShadow.color.a;
      return vec4<f32>(dropShadow.color.rgb * alpha, alpha);
    }
  ''';

  static const _normalMapShaderSource = '''
    @group(0) @binding(0) var texSampler: sampler;
    @group(0) @binding(1) var texTexture: texture_2d<f32>;
    @group(0) @binding(2) var mapSampler: sampler;
    @group(0) @binding(3) var mapTexture: texture_2d<f32>;

    struct NormalMapUniforms {
      ambientColor: vec4<f32>,
      lightColor: vec4<f32>,
      lightCoord: vec4<f32>,
      alpha: f32,
      padding0: vec3<f32>,
    };

    @group(0) @binding(4) var<uniform> normalMap: NormalMapUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) texCoord: vec2<f32>,
      @location(2) mapCoord: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) texCoord: vec2<f32>,
      @location(1) mapCoord: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.texCoord = input.texCoord;
      output.mapCoord = input.mapCoord;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let texColor = textureSample(texTexture, texSampler, input.texCoord);
      let mapColor = textureSample(mapTexture, mapSampler, input.mapCoord);
      let mapVector = vec3<f32>(mapColor.r, 1.0 - mapColor.g, mapColor.b);
      let mapNormal = normalize(mapVector * 2.0 - 1.0);

      let lightDelta = vec3<f32>(normalMap.lightCoord.xy - input.texCoord.xy, normalMap.lightCoord.z);
      let lightNormal = normalize(lightDelta);

      let diffuse = max(dot(mapNormal, lightNormal), 0.0);
      let diffuseColor = normalMap.lightColor.rgb * normalMap.lightColor.a * diffuse;
      let ambientColor = normalMap.ambientColor.rgb * normalMap.ambientColor.a;

      let distance = length(lightDelta.xy);
      let radius = normalMap.lightCoord.w;
      let temp = clamp(1.0 - (distance * distance) / (radius * radius), 0.0, 1.0);
      let attenuation = temp * temp;

      let color = texColor.rgb * (ambientColor + diffuseColor * attenuation);
      return vec4<f32>(color.rgb, texColor.a) * normalMap.alpha;
    }
  ''';

  static const _displacementMapShaderSource = '''
    @group(0) @binding(0) var texSampler: sampler;
    @group(0) @binding(1) var texTexture: texture_2d<f32>;
    @group(0) @binding(2) var mapSampler: sampler;
    @group(0) @binding(3) var mapTexture: texture_2d<f32>;

    struct DisplacementUniforms {
      map0: vec4<f32>,
      map1: vec4<f32>,
      dis0: vec4<f32>,
      dis1: vec4<f32>,
      alpha: vec4<f32>,
    };

    @group(0) @binding(4) var<uniform> displacement: DisplacementUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) texCoord: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) texCoord: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.texCoord = input.texCoord;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let mapCoord = vec2<f32>(
        input.texCoord.x * displacement.map0.x + input.texCoord.y * displacement.map0.y + displacement.map0.z,
        input.texCoord.x * displacement.map1.x + input.texCoord.y * displacement.map1.y + displacement.map1.z
      );
      let mapColor = textureSample(mapTexture, mapSampler, mapCoord);
      let mapDelta = mapColor.rg - vec2<f32>(0.5, 0.5);
      let dis = vec2<f32>(
        mapDelta.x * displacement.dis0.x + mapDelta.y * displacement.dis0.y,
        mapDelta.x * displacement.dis1.x + mapDelta.y * displacement.dis1.y
      );
      return textureSample(texTexture, texSampler, input.texCoord + dis) * displacement.alpha.x;
    }
  ''';

  static const _alphaMaskShaderSource = '''
    @group(0) @binding(0) var texSampler: sampler;
    @group(0) @binding(1) var texTexture: texture_2d<f32>;
    @group(0) @binding(2) var mskSampler: sampler;
    @group(0) @binding(3) var mskTexture: texture_2d<f32>;

    struct AlphaMaskUniforms {
      mskLimit: vec4<f32>,
      alpha: vec4<f32>,
    };

    @group(0) @binding(4) var<uniform> alphaMask: AlphaMaskUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) texCoord: vec2<f32>,
      @location(2) mskCoord: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) texCoord: vec2<f32>,
      @location(1) mskCoord: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.texCoord = input.texCoord;
      output.mskCoord = input.mskCoord;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let texColor = textureSample(texTexture, texSampler, input.texCoord);
      let mskColor = textureSample(mskTexture, mskSampler, input.mskCoord);
      let s1 = step(alphaMask.mskLimit.xy, input.mskCoord.xy);
      let s2 = step(input.mskCoord.xy, alphaMask.mskLimit.zw);
      let sAlpha = s1.x * s1.y * s2.x * s2.y;
      return texColor * (mskColor.a * alphaMask.alpha.x * sAlpha);
    }
  ''';
}
