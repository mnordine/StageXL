part of '../../../engine.dart';

class _WebGpuChromaKeyFilterProgram {
  static final program = RenderProgramSimpleWebGPU<Float32List>(
    label: 'StageXL chroma key filter pipeline',
    shaderSource: _shaderSource,
    uniformByteSize: 32,
    writeUniforms: _copyWebGpuUniformData,
  );

  static const _shaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct ChromaKeyUniforms {
      backgroundColor: vec4<f32>,
      thresholds: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> chromaKey: ChromaKeyUniforms;

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
      let pixelColor = textureSample(stageTexture, stageSampler, input.uv);
      let colorDiff = abs(pixelColor.rgb - chromaKey.backgroundColor.rgb);
      let invisibleThreshold = chromaKey.thresholds.y;
      let solidThreshold = chromaKey.thresholds.x;

      if (any(colorDiff > vec3<f32>(solidThreshold))) {
        return pixelColor;
      }

      if (all(colorDiff < vec3<f32>(invisibleThreshold))) {
        return pixelColor * 0.0;
      }

      let thresholdRange = solidThreshold - invisibleThreshold;
      let channelAlpha = clamp(
        (colorDiff - vec3<f32>(invisibleThreshold)) / thresholdRange,
        vec3<f32>(0),
        vec3<f32>(1)
      );
      let alpha = min(channelAlpha.b, min(channelAlpha.r, channelAlpha.g));
      let weight = chromaKey.thresholds.z;
      let correctedColor = pixelColor.rgb - (vec3<f32>(1) - colorDiff) * (1.0 - alpha) *
        chromaKey.backgroundColor.rgb * weight;

      return vec4<f32>(correctedColor, alpha);
    }
  ''';
}
