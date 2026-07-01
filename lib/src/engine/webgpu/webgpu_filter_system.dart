part of '../../engine.dart';

class WebGpuFilterSystem {
  static const _floatsPerVertex = 6;
  static const _bytesPerVertex = _floatsPerVertex * 4;
  static const _normalMapFloatsPerVertex = 8;
  static const _normalMapBytesPerVertex = _normalMapFloatsPerVertex * 4;
  static const _alphaMaskFloatsPerVertex = 8;
  static const _alphaMaskBytesPerVertex = _alphaMaskFloatsPerVertex * 4;
  static const _displacementMapUniformBytes = 80;

  final RenderContextWebGPU renderContext;
  late final GPUBindGroupLayout _colorMatrixBindGroupLayout;
  late final GPUPipelineLayout _colorMatrixPipelineLayout;
  late final GPUBindGroupLayout _normalMapBindGroupLayout;
  late final GPUPipelineLayout _normalMapPipelineLayout;
  late final GPUBindGroupLayout _displacementMapBindGroupLayout;
  late final GPUPipelineLayout _displacementMapPipelineLayout;
  late final GPUBindGroupLayout _alphaMaskBindGroupLayout;
  late final GPUPipelineLayout _alphaMaskPipelineLayout;
  late final GPUShaderModule _colorMatrixShaderModule;
  late final GPUShaderModule _blurShaderModule;
  late final GPUShaderModule _dropShadowShaderModule;
  late final GPUShaderModule _glowShaderModule;
  late final GPUShaderModule _chromaKeyShaderModule;
  late final GPUShaderModule _normalMapShaderModule;
  late final GPUShaderModule _displacementMapShaderModule;
  late final GPUShaderModule _alphaMaskShaderModule;
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  late GPUBuffer _normalMapVertexBuffer;
  late GPUBuffer _alphaMaskVertexBuffer;
  late GPUBuffer _uniformBuffer;
  late GPUBuffer _blurUniformBuffer;
  late GPUBuffer _dropShadowUniformBuffer;
  late GPUBuffer _glowUniformBuffer;
  late GPUBuffer _chromaKeyUniformBuffer;
  late GPUBuffer _normalMapUniformBuffer;
  late GPUBuffer _displacementMapUniformBuffer;
  late GPUBuffer _alphaMaskUniformBuffer;
  final _colorMatrixPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _blurPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _dropShadowPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _glowPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _chromaKeyPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _normalMapPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _displacementMapPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _alphaMaskPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  var _vertexCapacity = 0;
  var _indexCapacity = 0;
  var _normalMapVertexCapacity = 0;
  var _alphaMaskVertexCapacity = 0;

  WebGpuFilterSystem(this.renderContext) {
    final device = renderContext.device;
    _colorMatrixBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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
    _colorMatrixPipelineLayout =
        device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [_colorMatrixBindGroupLayout].toJS));
    _normalMapBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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
    _normalMapPipelineLayout =
        device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [_normalMapBindGroupLayout].toJS));
    _displacementMapBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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
    _displacementMapPipelineLayout = device
        .createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [_displacementMapBindGroupLayout].toJS));
    _alphaMaskBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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
    _alphaMaskPipelineLayout =
        device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [_alphaMaskBindGroupLayout].toJS));
    _colorMatrixShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _colorMatrixShaderSource));
    _blurShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _blurShaderSource));
    _dropShadowShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _dropShadowShaderSource));
    _glowShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _glowShaderSource));
    _chromaKeyShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _chromaKeyShaderSource));
    _normalMapShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _normalMapShaderSource));
    _displacementMapShaderModule =
      device.createShaderModule(GPUShaderModuleDescriptor(code: _displacementMapShaderSource));
    _alphaMaskShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _alphaMaskShaderSource));
    _vertexBuffer = _createVertexBuffer(_bytesPerVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
    _normalMapVertexBuffer = _createNormalMapVertexBuffer(_normalMapBytesPerVertex * 4);
    _alphaMaskVertexBuffer = _createAlphaMaskVertexBuffer(_alphaMaskBytesPerVertex * 4);
    _uniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 80,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _blurUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 16,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _dropShadowUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 32,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _glowUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 32,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _chromaKeyUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 32,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _normalMapUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 80,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _displacementMapUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: _displacementMapUniformBytes,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _alphaMaskUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 32,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
  }

  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    final firstFilter = renderFilters.length == 1 ? renderFilters[0] : null;

    if (renderFilters.isEmpty) return;
    if (firstFilter != null && firstFilter.isSimple && firstFilter.supportsWebGPU) {
      renderContext.flush();
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

    final texMatrix = renderTextureQuad.samplerMatrix;
    final mapMatrix = normalMapRenderTextureQuad.samplerMatrix;
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
    final indices = Uint16List(ixList.length.isOdd ? ixList.length + 1 : ixList.length);

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
    renderContext.device.queue
      ..writeBuffer(_normalMapVertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(_normalMapUniformBuffer, 0, uniformData.buffer.toJS);

    final texture = renderTextureQuad.renderTexture;
    final mapTexture = normalMapRenderTextureQuad.renderTexture;
    final bindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _normalMapBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: renderContext.textureSystem.getSampler(texture)),
        GPUBindGroupEntry(binding: 1, resource: renderContext.textureSystem.getTextureView(texture)),
        GPUBindGroupEntry(binding: 2, resource: renderContext.textureSystem.getSampler(mapTexture)),
        GPUBindGroupEntry(binding: 3, resource: renderContext.textureSystem.getTextureView(mapTexture)),
        GPUBindGroupEntry(
          binding: 4,
          resource: GPUBufferBinding(buffer: _normalMapUniformBuffer, offset: 0, size: 80),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getNormalMapPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, _normalMapVertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);
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

    final uniformData = Float32List(20)
      ..setRange(0, 4, [mapMatrix.a, mapMatrix.c, mapMatrix.tx, 0])
      ..setRange(4, 8, [mapMatrix.b, mapMatrix.d, mapMatrix.ty, 0])
      ..setRange(8, 12, [disMatrix.a, disMatrix.c, 0, 0])
      ..setRange(12, 16, [disMatrix.b, disMatrix.d, 0, 0])
      ..setRange(16, 20, [renderState.globalAlpha, 0, 0, 0]);

    final vertices = Float32List(vertexCount * _floatsPerVertex);
    final indices = Uint16List(ixList.length.isOdd ? ixList.length + 1 : ixList.length);

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
      vertices[vertexIndex++] = vxList[sourceIndex + 2];
      vertices[vertexIndex++] = vxList[sourceIndex + 3];
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(_displacementMapUniformBuffer, 0, uniformData.buffer.toJS);

    final texture = renderTextureQuad.renderTexture;
    final mapTexture = mapRenderTextureQuad.renderTexture;
    final bindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _displacementMapBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: renderContext.textureSystem.getSampler(texture)),
        GPUBindGroupEntry(binding: 1, resource: renderContext.textureSystem.getTextureView(texture)),
        GPUBindGroupEntry(binding: 2, resource: renderContext.textureSystem.getSampler(mapTexture)),
        GPUBindGroupEntry(binding: 3, resource: renderContext.textureSystem.getTextureView(mapTexture)),
        GPUBindGroupEntry(
          binding: 4,
          resource: GPUBufferBinding(
            buffer: _displacementMapUniformBuffer,
            offset: 0,
            size: _displacementMapUniformBytes,
          ),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getDisplacementMapPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);
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
    final indices = Uint16List(ixList.length.isOdd ? ixList.length + 1 : ixList.length);

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
      vertices[vertexIndex++] = vxList[sourceIndex + 2];
      vertices[vertexIndex++] = vxList[sourceIndex + 3];
      vertices[vertexIndex++] = maskMatrix.tx + x * maskMatrix.a + y * maskMatrix.c;
      vertices[vertexIndex++] = maskMatrix.ty + x * maskMatrix.b + y * maskMatrix.d;
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureAlphaMaskVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_alphaMaskVertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(_alphaMaskUniformBuffer, 0, uniformData.buffer.toJS);

    final texture = renderTextureQuad.renderTexture;
    final maskTexture = maskRenderTextureQuad.renderTexture;
    final bindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _alphaMaskBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: renderContext.textureSystem.getSampler(texture)),
        GPUBindGroupEntry(binding: 1, resource: renderContext.textureSystem.getTextureView(texture)),
        GPUBindGroupEntry(binding: 2, resource: renderContext.textureSystem.getSampler(maskTexture)),
        GPUBindGroupEntry(binding: 3, resource: renderContext.textureSystem.getTextureView(maskTexture)),
        GPUBindGroupEntry(
          binding: 4,
          resource: GPUBufferBinding(buffer: _alphaMaskUniformBuffer, offset: 0, size: 32),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(_getAlphaMaskPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, _alphaMaskVertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);
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
    final indices = Uint16List(ixList.length.isOdd ? ixList.length + 1 : ixList.length);
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
      vertices[vertexIndex++] = vxList[sourceIndex + 2];
      vertices[vertexIndex++] = vxList[sourceIndex + 3];
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(uniformBuffer, 0, uniformData.buffer.toJS);

    final texture = renderTextureQuad.renderTexture;
    final bindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _colorMatrixBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: renderContext.textureSystem.getSampler(texture)),
        GPUBindGroupEntry(binding: 1, resource: renderContext.textureSystem.getTextureView(texture)),
        GPUBindGroupEntry(
          binding: 2,
          resource: GPUBufferBinding(buffer: uniformBuffer, offset: 0, size: uniformByteSize),
        ),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(renderContext.consumeClearColor());
    pass
      ..setPipeline(getPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);
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
    final blendPipelines = _colorMatrixPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createColorMatrixPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getBlurPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _blurPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createBlurPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getGlowPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _glowPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createGlowPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getDropShadowPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _dropShadowPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createDropShadowPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getChromaKeyPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _chromaKeyPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createChromaKeyPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getNormalMapPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _normalMapPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createNormalMapPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getDisplacementMapPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _displacementMapPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createDisplacementMapPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _getAlphaMaskPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _alphaMaskPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createAlphaMaskPipeline(blendMode, stencilTest));
  }

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
      multisample: GPUMultisampleState(count: 1),
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
      multisample: GPUMultisampleState(count: 1),
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
      multisample: GPUMultisampleState(count: 1),
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
      multisample: GPUMultisampleState(count: 1),
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

  void _ensureVertexCapacity(int size) {
    if (size <= _vertexCapacity) return;
    _vertexBuffer.destroy();
    _vertexBuffer = _createVertexBuffer(size * 2);
  }

  void _ensureIndexCapacity(int size) {
    if (size <= _indexCapacity) return;
    _indexBuffer.destroy();
    _indexBuffer = _createIndexBuffer(size * 2);
  }

  void _ensureNormalMapVertexCapacity(int size) {
    if (size <= _normalMapVertexCapacity) return;
    _normalMapVertexBuffer.destroy();
    _normalMapVertexBuffer = _createNormalMapVertexBuffer(size * 2);
  }

  void _ensureAlphaMaskVertexCapacity(int size) {
    if (size <= _alphaMaskVertexCapacity) return;
    _alphaMaskVertexBuffer.destroy();
    _alphaMaskVertexBuffer = _createAlphaMaskVertexBuffer(size * 2);
  }

  Never _throwUnsupported() {
    renderContext.renderStatistics.webgpuFallbackCount++;
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
