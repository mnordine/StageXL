part of '../../../engine.dart';

class _WebGpuAlphaMaskFilterProgram {
  static const layoutKey = 4;
  static const floatsPerVertex = 8;
  static const bytesPerVertex = floatsPerVertex * 4;
  static const uniformByteSize = 32;

  static GPUBindGroupLayout createBindGroupLayout(GPUDevice device) =>
      device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
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

  static GPUPipelineLayout createPipelineLayout(GPUDevice device, GPUBindGroupLayout bindGroupLayout) =>
      device.createPipelineLayout(GPUPipelineLayoutDescriptor(
        bindGroupLayouts: [bindGroupLayout].toJS,
      ));

  static GPUShaderModule createShaderModule(GPUDevice device) =>
      device.createShaderModule(GPUShaderModuleDescriptor(code: _shaderSource));

  static GPURenderPipeline createPipeline({
    required RenderContextWebGPU renderContext,
    required GPUPipelineLayout pipelineLayout,
    required GPUShaderModule shaderModule,
    required BlendMode blendMode,
    required GPUDepthStencilState depthStencilState,
  }) =>
      renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
        label: 'StageXL alpha mask filter pipeline',
        layout: pipelineLayout,
        vertex: GPUVertexState(
          module: shaderModule,
          entryPoint: 'vs_main',
          buffers: [
            GPUVertexBufferLayout(
              arrayStride: bytesPerVertex,
              attributes: [
                GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
                GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
                GPUVertexAttribute(format: 'float32x2', offset: 24, shaderLocation: 2),
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
        depthStencil: depthStencilState,
        multisample: GPUMultisampleState(count: renderContext.sampleCount),
      ));

  static const _shaderSource = '''
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
