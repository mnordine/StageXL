part of '../../../engine.dart';

class _WebGpuDropShadowFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL drop shadow filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 48,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct DropShadowUniforms {
      shift: vec2<f32>,
      radius: vec2<f32>,
      color: vec4<f32>,
      sourceAlpha: f32,
      sourceMode: f32,
      padding: vec2<f32>,
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
      let sideWeight = 0.300474132757172;
      let centerWeight = 0.399051734485656;
      var alpha = textureSample(stageTexture, stageSampler, texCoord - radius).a * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(0.0, -radius.y)).a
          * centerWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(radius.x, -radius.y)).a
          * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(-radius.x, 0.0)).a
          * sideWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord).a * centerWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(radius.x, 0.0)).a
          * sideWeight * centerWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(-radius.x, radius.y)).a
          * sideWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + vec2<f32>(0.0, radius.y)).a
          * centerWeight * sideWeight;
      alpha += textureSample(stageTexture, stageSampler, texCoord + radius).a * sideWeight * sideWeight;
      alpha *= dropShadow.color.a;
      var effect = vec4<f32>(dropShadow.color.rgb * alpha, alpha);
      let source = textureSample(stageTexture, stageSampler, input.uv);
      if (dropShadow.sourceMode > 1.5) {
        effect *= 1.0 - source.a;
      } else if (dropShadow.sourceMode > 0.5) {
        let sourceScaled = source * dropShadow.sourceAlpha;
        effect = sourceScaled + effect * (1.0 - sourceScaled.a);
      }
      return effect;
    }
  ''';
}
