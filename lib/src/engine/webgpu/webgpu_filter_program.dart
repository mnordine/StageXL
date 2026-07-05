part of '../../engine.dart';

/// A reusable WebGPU program for filters that render one input texture to one
/// output target.
///
/// The WGSL shader must use the same resource layout as StageXL's built-in
/// one-texture filters:
///
/// * `@group(0) @binding(0)` filtering sampler
/// * `@group(0) @binding(1)` input `texture_2d<f32>`
/// * `@group(0) @binding(2)` uniform buffer
///
/// The vertex entry point must be `vs_main` and accept StageXL's standard
/// filter vertices: `@location(0) clip: vec4<f32>` and
/// `@location(1) uv: vec2<f32>`. The fragment entry point must be `fs_main`.
class WebGpuFilterProgram {
  final String label;
  final String shaderSource;
  final int uniformByteSize;

  WebGpuFilterProgram({
    required this.label,
    required this.shaderSource,
    required this.uniformByteSize,
  });
}

class _WebGpuFilterProgramResources {
  final WebGpuFilterSystem filterSystem;
  final WebGpuFilterProgram program;
  final pipelines = <BlendMode, Map<int, GPURenderPipeline>>{};

  late final shaderModule = filterSystem.renderContext.device.createShaderModule(
    GPUShaderModuleDescriptor(code: program.shaderSource),
  );

  late final GPUBuffer uniformBuffer = filterSystem._createUniformBuffer(program.uniformByteSize);

  _WebGpuFilterProgramResources(this.filterSystem, this.program);

  GPURenderPipeline getPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = pipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      filterSystem._pipelineKey(stencilTest),
      () => filterSystem._createFilterPipeline(program.label, shaderModule, blendMode, stencilTest),
    );
  }
}

/// Context passed to a filter when WebGPU is applying one of its render passes.
///
/// Custom filters can override [RenderFilter.renderWebGpuFilter] and use this
/// context to render a shader pass without reaching into WebGPU internals.
class WebGpuFilterContext {
  final WebGpuFilterSystem filterSystem;
  final RenderState renderState;
  final RenderTextureQuad renderTextureQuad;
  final int pass;

  WebGpuFilterContext({
    required this.filterSystem,
    required this.renderState,
    required this.renderTextureQuad,
    required this.pass,
  });

  RenderContextWebGPU get renderContext => filterSystem.renderContext;

  void renderSingleTextureProgram(WebGpuFilterProgram program, Float32List uniformData) {
    filterSystem.renderTextureQuadWithProgram(renderState, renderTextureQuad, program, uniformData);
  }
}
