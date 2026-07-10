part of '../../../engine.dart';

class _WebGpuFxaaFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL fxaa filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 16,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct FxaaUniforms {
      texel: vec2<f32>,
      alpha: f32,
      padding: f32,
    };

    @group(0) @binding(2) var<uniform> fxaa: FxaaUniforms;

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
      let texel = fxaa.texel;
      let color = textureSample(stageTexture, stageSampler, input.uv);
      let rgbTL = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-1.0, -1.0) * texel).rgb;
      let rgbTR = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(1.0, -1.0) * texel).rgb;
      let rgbBL = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(-1.0, 1.0) * texel).rgb;
      let rgbBR = textureSample(stageTexture, stageSampler, input.uv + vec2<f32>(1.0, 1.0) * texel).rgb;
      let rgbXY = color.rgb;
      let luma = vec3<f32>(0.299, 0.587, 0.114);

      let lumaTL = dot(rgbTL, luma);
      let lumaTR = dot(rgbTR, luma);
      let lumaBL = dot(rgbBL, luma);
      let lumaBR = dot(rgbBR, luma);
      let lumaXY = dot(rgbXY, luma);
      let lumaMin = min(lumaXY, min(min(lumaTL, lumaTR), min(lumaBL, lumaBR)));
      let lumaMax = max(lumaXY, max(max(lumaTL, lumaTR), max(lumaBL, lumaBR)));

      var dir = vec2<f32>(
        lumaBL + lumaBR - lumaTL - lumaTR,
        lumaTL + lumaBL - lumaTR - lumaBR,
      );
      let dirReduce = max((lumaTL + lumaTR + lumaBL + lumaBR) * (0.25 * (1.0 / 8.0)), 1.0 / 128.0);
      let dirMin = min(abs(dir.x), abs(dir.y)) + dirReduce;
      dir = clamp(dir / dirMin, vec2<f32>(-8.0, -8.0), vec2<f32>(8.0, 8.0)) * texel;

      let rgbA = 0.5 * (
        textureSample(stageTexture, stageSampler, input.uv - dir * 0.16666).rgb +
        textureSample(stageTexture, stageSampler, input.uv + dir * 0.16666).rgb
      );
      let rgbB = 0.25 * (
        textureSample(stageTexture, stageSampler, input.uv - dir * 0.5).rgb +
        textureSample(stageTexture, stageSampler, input.uv + dir * 0.5).rgb
      ) + rgbA * 0.5;

      let lumaB = dot(rgbB, luma);
      let conditionLT = max(sign(lumaMin - lumaB), 0.0);
      let conditionGT = max(sign(lumaB - lumaMax), 0.0);
      let conditionOR = min(conditionLT + conditionGT, 1.0);
      return vec4<f32>((rgbA - rgbB) * conditionOR + rgbB, color.a) * fxaa.alpha;
    }
  ''';
}
