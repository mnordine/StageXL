part of '../../../engine.dart';

class _WebGpuNormalMapFilterProgram {
  static const layoutKey = 2;
  static const floatsPerVertex = 8;
  static const bytesPerVertex = floatsPerVertex * 4;
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
        label: 'StageXL normal map filter pipeline',
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
}
