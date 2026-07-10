part of '../../../engine.dart';

class _WebGpuDropShadowFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL drop shadow filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 32,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
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
}
