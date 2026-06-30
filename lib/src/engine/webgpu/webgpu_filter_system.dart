part of '../../engine.dart';

class WebGpuFilterSystem {
  static const _floatsPerVertex = 6;
  static const _bytesPerVertex = _floatsPerVertex * 4;

  final RenderContextWebGPU renderContext;
  late final GPUBindGroupLayout _colorMatrixBindGroupLayout;
  late final GPUPipelineLayout _colorMatrixPipelineLayout;
  late final GPUShaderModule _colorMatrixShaderModule;
  late final GPUShaderModule _blurShaderModule;
  late final GPUShaderModule _glowShaderModule;
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  late GPUBuffer _uniformBuffer;
  late GPUBuffer _blurUniformBuffer;
  late GPUBuffer _glowUniformBuffer;
  final _colorMatrixPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _blurPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  final _glowPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  var _vertexCapacity = 0;
  var _indexCapacity = 0;

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
    _colorMatrixShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _colorMatrixShaderSource));
    _blurShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _blurShaderSource));
    _glowShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _glowShaderSource));
    _vertexBuffer = _createVertexBuffer(_bytesPerVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
    _uniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 80,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _blurUniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 16,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
    _glowUniformBuffer = device.createBuffer(GPUBufferDescriptor(
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

    if (firstFilter != null && firstFilter.supportsWebGPU) {
      renderObjectFiltered(renderState, _RenderTextureQuadObject(renderTextureQuad, renderFilters));
      return;
    }

    _throwUnsupported();
  }

  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    final filters = renderObject.filters;
    final firstFilter = filters.length == 1 ? filters[0] : null;
    if (filters.isEmpty) return;
    if (firstFilter == null || !firstFilter.supportsWebGPU) {
      _throwUnsupported();
    }

    final bounds = renderObject.bounds;
    final pixelRatio = math.sqrt(renderState.globalMatrix.det.abs());

    var boundsLeft = bounds.left.floor();
    var boundsTop = bounds.top.floor();
    var boundsRight = bounds.right.ceil();
    var boundsBottom = bounds.bottom.ceil();

    final overlap = firstFilter.overlap;
    boundsLeft += overlap.left;
    boundsTop += overlap.top;
    boundsRight += overlap.right;
    boundsBottom += overlap.bottom;

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
    final renderTexture = RenderTexture.rawWebGL(boundsWidth, boundsHeight);
    renderTextures[0] = renderTexture;

    try {
      final filterProjectionMatrix = Matrix3D.fromIdentity();
      filterProjectionMatrix.scale(2 / boundsWidth, 2 / boundsHeight, 1);
      filterProjectionMatrix.translate(-1, -1, 0);

      final filterRenderState = RenderState(renderContext);
      filterRenderState.globalMatrix.scale(pixelRatio, pixelRatio);
      filterRenderState.globalMatrix.translate(-boundsLeft, -boundsTop);

      renderContext.activateRenderTexture(renderTexture);
      renderContext.activateProjectionMatrix(filterProjectionMatrix);
      renderContext.clearActiveRenderTexture(0);
      renderObject.render(filterRenderState);
      renderContext.flush();
      renderContext.maskSystem.resetFrame();

      if (firstFilter.isSimple) {
        final sourceRenderTextureQuad = _createFilterSourceQuad(
          renderTexture,
          boundsLeft,
          boundsTop,
          boundsWidth,
          boundsHeight,
          pixelRatio,
        );
        renderContext.activateRenderTexture(initialRenderTexture);
        renderContext.activateProjectionMatrix(initialProjectionMatrix);
        renderContext.maskSystem._restore(maskSnapshot);
        firstFilter.renderFilter(renderState, sourceRenderTextureQuad, 0);
      } else {
        _renderFilterPasses(
          firstFilter,
          renderState,
          filterRenderState,
          initialRenderTexture,
          initialProjectionMatrix,
          filterProjectionMatrix,
          maskSnapshot,
          renderTextures,
          boundsLeft,
          boundsTop,
          boundsWidth,
          boundsHeight,
          pixelRatio,
        );
      }
    } finally {
      renderContext.activateRenderTexture(initialRenderTexture);
      renderContext.activateProjectionMatrix(initialProjectionMatrix);
      renderContext.maskSystem._restore(maskSnapshot);
      for (final renderTexture in renderTextures.values) {
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
    int boundsLeft,
    int boundsTop,
    int boundsWidth,
    int boundsHeight,
    num pixelRatio,
  ) {
    final renderPassSources = filter.renderPassSources;
    final renderPassTargets = filter.renderPassTargets;

    for (var pass = 0; pass < renderPassSources.length; pass++) {
      final source = renderTextures[renderPassSources[pass]];
      if (source == null) throw StateError('Invalid renderPassSource!');

      final targetId = renderPassTargets[pass];
      final isFinalPass = targetId == renderPassTargets.last;
      final RenderState passRenderState;
      if (isFinalPass) {
        passRenderState = finalRenderState;
        renderContext.activateRenderTexture(initialRenderTexture);
        renderContext.activateProjectionMatrix(initialProjectionMatrix);
        renderContext.maskSystem._restore(maskSnapshot);
      } else {
        passRenderState = filterRenderState;
        final target = renderTextures.putIfAbsent(targetId, () => RenderTexture.rawWebGL(boundsWidth, boundsHeight));
        renderContext.activateRenderTexture(target);
        renderContext.activateProjectionMatrix(filterProjectionMatrix);
        renderContext.clearActiveRenderTexture(0);
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
}
