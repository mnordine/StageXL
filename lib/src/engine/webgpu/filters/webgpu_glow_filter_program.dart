part of '../../../engine.dart';

class _WebGpuGlowFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL glow filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 32,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct GlowUniforms {
      radius: vec2<f32>,
      sourceAlpha: f32,
      sourceMode: f32,
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
      let sideWeight = 0.300474132757172;
      let centerWeight = 0.399051734485656;
      var alpha = textureSample(stageTexture, stageSampler, input.uv - radius).a * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(0.0, -radius.y)).a
          * centerWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(radius.x, -radius.y)).a
          * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-radius.x, 0.0)).a
          * sideWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv).a * centerWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(radius.x, 0.0)).a
          * sideWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-radius.x, radius.y)).a
          * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(0.0, radius.y)).a
          * centerWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, input.uv + radius).a * sideWeight * sideWeight;
      alpha *= glow.color.a;
      var effect = vec4<f32>(glow.color.rgb * alpha, alpha);
      let source = textureSample(stageTexture, stageSampler, input.uv);
      if (glow.sourceMode > 1.5) {
        effect *= 1.0 - source.a;
      } else if (glow.sourceMode > 0.5) {
        let sourceScaled = source * glow.sourceAlpha;
        effect = sourceScaled + effect * (1.0 - sourceScaled.a);
      }
      return effect;
    }
  ''';
}
