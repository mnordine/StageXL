part of '../../../engine.dart';

class _WebGpuDisplacementMapFilterProgram {
  static const layoutKey = 3;
  static const uniformByteSize = 80;

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
        label: 'StageXL displacement map filter pipeline',
        layout: pipelineLayout,
        vertex: GPUVertexState(
          module: shaderModule,
          entryPoint: 'vs_main',
          buffers: [
            GPUVertexBufferLayout(
              arrayStride: WebGpuFilterSystem._bytesPerVertex,
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
        depthStencil: depthStencilState,
        multisample: GPUMultisampleState(count: renderContext.sampleCount),
      ));

  static const _shaderSource = '''
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
}
