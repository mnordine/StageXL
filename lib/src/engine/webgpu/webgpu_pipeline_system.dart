part of '../../engine.dart';

class WebGpuPipelineSystem {
  static const _vertexStride = 40;

  final RenderContextWebGPU renderContext;
  late final GPUBindGroupLayout textureBindGroupLayout;
  late final GPUPipelineLayout pipelineLayout;
  late final GPUShaderModule shaderModule;
  final _pipelineCache = <BlendMode, GPURenderPipeline>{};

  WebGpuPipelineSystem(this.renderContext) {
    final device = renderContext.device;
    textureBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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
    ].toJS));
    pipelineLayout =
        device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [textureBindGroupLayout].toJS));
    shaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _shaderSource));
  }

  GPURenderPipeline getPipeline(BlendMode blendMode) =>
      _pipelineCache.putIfAbsent(blendMode, () => _createPipeline(blendMode));

  GPURenderPipeline _createPipeline(BlendMode blendMode) {
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
            arrayStride: _vertexStride,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x4', offset: 16, shaderLocation: 1),
              GPUVertexAttribute(format: 'float32x2', offset: 32, shaderLocation: 2),
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
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      multisample: GPUMultisampleState(count: 1),
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

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) color: vec4<f32>,
      @location(2) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) color: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.color = input.color;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      return textureSample(stageTexture, stageSampler, input.uv) * input.color;
    }
  ''';
}
