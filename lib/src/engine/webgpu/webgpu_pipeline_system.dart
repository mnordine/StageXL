part of '../../engine.dart';

class WebGpuPipelineSystem {
  static const _batchVertexStride = 36;
  static const _stencilVertexStride = 16;

  final RenderContextWebGPU renderContext;
  late final int maxBatchTextures = renderContext.deviceSystem.maxBatchTextures;
  late final GPUBindGroupLayout textureBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    for (var i = 0; i < maxBatchTextures; i++) ...[
      GPUBindGroupLayoutEntry(
        binding: i * 2,
        visibility: $GPUShaderStage.FRAGMENT,
        sampler: GPUSamplerBindingLayout(type: 'filtering'),
      ),
      GPUBindGroupLayoutEntry(
        binding: i * 2 + 1,
        visibility: $GPUShaderStage.FRAGMENT,
        texture: GPUTextureBindingLayout(sampleType: 'float'),
      ),
    ],
  ].toJS));
  late final GPUBindGroupLayout projectionBindGroupLayout =
      renderContext.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.VERTEX,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  late final GPUPipelineLayout pipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [
    textureBindGroupLayout,
    projectionBindGroupLayout,
  ].toJS));
  late final GPUPipelineLayout stencilPipelineLayout =
      renderContext.device.createPipelineLayout(GPUPipelineLayoutDescriptor(
    bindGroupLayouts: <GPUBindGroupLayout>[].toJS,
  ));
  late final GPUShaderModule shaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _batchShaderSource(maxBatchTextures)));
  late final GPUShaderModule stencilShaderModule =
      renderContext.device.createShaderModule(GPUShaderModuleDescriptor(code: _stencilShaderSource));
  GPUBuffer? _projectionBuffer;
  GPUBuffer get projectionBuffer => _projectionBuffer ??= renderContext.device.createBuffer(GPUBufferDescriptor(
        size: 64,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
      ));
  late final GPUBindGroup projectionBindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
    layout: projectionBindGroupLayout,
    entries: [
      GPUBindGroupEntry(binding: 0, resource: GPUBufferBinding(buffer: projectionBuffer)),
    ].toJS,
  ));
  final _projectionData = JSFloat32Array.withLength(16).toDart;
  final _pipelineCache = <BlendMode, Map<int, GPURenderPipeline>>{};
  final _stencilWritePipelines = <int, GPURenderPipeline>{};

  WebGpuPipelineSystem(this.renderContext);

  void uploadProjectionMatrix(Matrix3D matrix) {
    _projectionData.setRange(0, 16, matrix.data);
    renderContext.device.queue.writeBuffer(projectionBuffer, 0, _projectionData.toJS, 0, 16);
  }

  GPURenderPipeline getPipeline(BlendMode blendMode, {required bool stencilTest}) {
    final stencilMode = stencilTest ? 1 : 0;
    final sampleCount = renderContext.sampleCount;
    final pipelineKey = stencilMode | (sampleCount << 2);
    final blendPipelines = _pipelineCache.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      pipelineKey,
      () => _createPipeline(blendMode, stencilMode: stencilMode, sampleCount: sampleCount),
    );
  }

  GPURenderPipeline getStencilWritePipeline() =>
      _stencilWritePipelines.putIfAbsent(renderContext.sampleCount, _createStencilWritePipeline);

  GPUBlendState getBlendState(BlendMode blendMode) => _blendFor(blendMode);

  GPURenderPipeline _createPipeline(BlendMode blendMode, {required int stencilMode, required int sampleCount}) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    final blend = _blendFor(blendMode);
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL batch pipeline',
      layout: pipelineLayout,
      vertex: GPUVertexState(
        module: shaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _batchVertexStride,
            attributes: [
              GPUVertexAttribute(format: 'float32x2', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x4', offset: 8, shaderLocation: 1),
              GPUVertexAttribute(format: 'float32x2', offset: 24, shaderLocation: 2),
              GPUVertexAttribute(format: 'float32', offset: 32, shaderLocation: 3),
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
            blend: blend,
            writeMask: stencilMode == 2 ? 0 : $GPUColorWrite.ALL,
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilMode),
      multisample: GPUMultisampleState(count: sampleCount),
    ));
  }

  GPUDepthStencilState _depthStencilState(int stencilMode) {
    final stencilFace = switch (stencilMode) {
      0 => GPUStencilFaceState(compare: 'always', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep'),
      1 => GPUStencilFaceState(compare: 'equal', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep'),
      _ => GPUStencilFaceState(compare: 'always', failOp: 'keep', depthFailOp: 'keep', passOp: 'replace'),
    };
    return GPUDepthStencilState(
      format: 'depth24plus-stencil8',
      depthWriteEnabled: false,
      depthCompare: 'always',
      stencilFront: stencilFace,
      stencilBack: stencilFace,
      stencilReadMask: 0xFF,
      stencilWriteMask: stencilMode == 2 ? 0xFF : 0,
    );
  }

  GPURenderPipeline _createStencilWritePipeline() {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL stencil write pipeline',
      layout: stencilPipelineLayout,
      vertex: GPUVertexState(
        module: stencilShaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _stencilVertexStride,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: stencilShaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            writeMask: 0,
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(2),
      multisample: GPUMultisampleState(count: renderContext.sampleCount),
    ));
  }

  GPUBlendState _blendFor(BlendMode blendMode) {
    var colorSrc = 'one';
    var colorDst = 'one-minus-src-alpha';
    const alphaSrc = 'one';
    var alphaDst = 'one-minus-src-alpha';

    if (identical(blendMode, BlendMode.ADD)) {
      colorDst = 'one';
      alphaDst = 'one';
    } else if (identical(blendMode, BlendMode.MULTIPLY)) {
      colorSrc = 'dst';
      colorDst = 'one-minus-src-alpha';
    } else if (identical(blendMode, BlendMode.SCREEN)) {
      colorDst = 'one-minus-src';
    } else if (identical(blendMode, BlendMode.NONE)) {
      colorDst = 'zero';
      alphaDst = 'zero';
    }

    return GPUBlendState(
      color: GPUBlendComponent(operation: 'add', srcFactor: colorSrc, dstFactor: colorDst),
      alpha: GPUBlendComponent(operation: 'add', srcFactor: alphaSrc, dstFactor: alphaDst),
    );
  }

  static String _batchShaderSource(int textureCount) {
    final bindings = StringBuffer();
    final samplers = StringBuffer();

    for (var i = 0; i < textureCount; i++) {
      bindings.writeln('''
    @group(0) @binding(${i * 2}) var stageSampler$i: sampler;
    @group(0) @binding(${i * 2 + 1}) var stageTexture$i: texture_2d<f32>;
''');
      samplers.write('''
      if (textureIndex == ${i}u) {
        return textureSampleLevel(stageTexture$i, stageSampler$i, uv, 0.0);
      }
''');
    }

    return '''
    $bindings
    @group(1) @binding(0) var<uniform> projectionMatrix: mat4x4<f32>;

    struct VertexInput {
      @location(0) position: vec2<f32>,
      @location(1) color: vec4<f32>,
      @location(2) uv: vec2<f32>,
      @location(3) textureIndex: f32,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) color: vec4<f32>,
      @location(1) uv: vec2<f32>,
      @location(2) @interpolate(flat) textureIndex: u32,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = vec4<f32>(input.position, 0.0, 1.0) * projectionMatrix;
      output.position.z = output.position.z * 0.5 + output.position.w * 0.5;
      output.color = input.color;
      output.uv = input.uv;
      output.textureIndex = u32(input.textureIndex + 0.5);
      return output;
    }

    fn sampleStageTexture(textureIndex: u32, uv: vec2<f32>) -> vec4<f32> {
      $samplers
      return vec4<f32>(1.0, 0.0, 1.0, 1.0);
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      return sampleStageTexture(input.textureIndex, input.uv) * input.color;
    }
  ''';
  }

  static const _stencilShaderSource = '''
    struct VertexInput {
      @location(0) clip: vec4<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> @builtin(position) vec4<f32> {
      return input.clip;
    }

    @fragment
    fn fs_main() -> @location(0) vec4<f32> {
      return vec4<f32>(0.0);
    }
  ''';

  void dispose() {
    _projectionBuffer?.destroy();
    _projectionBuffer = null;
    _pipelineCache.clear();
    _stencilWritePipelines.clear();
  }
}
