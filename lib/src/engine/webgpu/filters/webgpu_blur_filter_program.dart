part of '../../../engine.dart';

class _WebGpuBlurFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL blur filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 16,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
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
      let sideWeight = 0.300474132757172;
      let centerWeight = 0.399051734485656;
      var sum = textureSample(stageTexture, stageSampler, input.uv - radius) * sideWeight * sideWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(0.0, -radius.y))
          * centerWeight * sideWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(radius.x, -radius.y))
          * sideWeight * sideWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-radius.x, 0.0))
          * sideWeight * centerWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv) * centerWeight * centerWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(radius.x, 0.0))
          * sideWeight * centerWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-radius.x, radius.y))
          * sideWeight * sideWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(0.0, radius.y))
          * centerWeight * sideWeight;
      sum += textureSample(stageTexture, stageSampler, input.uv + radius) * sideWeight * sideWeight;
      return sum * blur.alpha;
    }
  ''';
}
