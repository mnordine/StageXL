part of '../../../engine.dart';

class _WebGpuColorMatrixFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL color matrix filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 80,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct ColorMatrixUniforms {
      matrixR: vec4<f32>,
      matrixG: vec4<f32>,
      matrixB: vec4<f32>,
      matrixA: vec4<f32>,
      offset: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> colorMatrix: ColorMatrixUniforms;

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
      let sampleColor = textureSample(stageTexture, stageSampler, input.uv);
      let safeAlpha = max(sampleColor.a, 0.000001);
      let color = vec4<f32>(sampleColor.rgb / safeAlpha, sampleColor.a);
      let transformed = colorMatrix.offset + vec4<f32>(
        dot(color, colorMatrix.matrixR),
        dot(color, colorMatrix.matrixG),
        dot(color, colorMatrix.matrixB),
        dot(color, colorMatrix.matrixA)
      );
      return vec4<f32>(transformed.rgb * transformed.a, transformed.a);
    }
  ''';
}
