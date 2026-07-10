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
abstract class RenderProgramWebGPU<TParameters>
    extends RenderProgram<RenderContextWebGPU, TParameters> {
  const RenderProgramWebGPU();

  factory RenderProgramWebGPU.callback(
    void Function(RenderFilterContext context, TParameters parameters) render,
  ) = _RenderProgramWebGPUCallback<TParameters>;

  void renderFilter(RenderFilterContext context, TParameters parameters);
}

final class _RenderProgramWebGPUCallback<TParameters> extends RenderProgramWebGPU<TParameters> {
  final void Function(RenderFilterContext context, TParameters parameters) _render;

  const _RenderProgramWebGPUCallback(this._render);

  @override
  void renderFilter(RenderFilterContext context, TParameters parameters) => _render(context, parameters);
}

class RenderProgramSimpleWebGPU<TParameters> extends RenderProgramWebGPU<TParameters> {
  final String label;
  final String shaderSource;
  final int uniformByteSize;

  final void Function(TParameters parameters, Float32List uniformData) writeUniforms;

  RenderProgramSimpleWebGPU({
    required this.label,
    required this.shaderSource,
    required this.uniformByteSize,
    required this.writeUniforms,
  });

  @override
  void renderFilter(RenderFilterContext context, TParameters parameters) {
    final renderContext = context.renderContext as RenderContextWebGPU;
    renderContext.filterSystem.renderTextureQuadWithProgram(
      context.renderState,
      context.renderTextureQuad,
      this,
      parameters,
    );
  }
}

/// A reusable WebGPU program for filters that sample the source texture and
/// one additional texture. Its WGSL resources use sampler/texture bindings
/// 0-3 and a uniform buffer at binding 4.
class RenderProgramTwoTextureWebGPU<TParameters> extends RenderProgramWebGPU<TParameters> {
  final String label;
  final String shaderSource;
  final int uniformByteSize;
  final RenderTexture Function(TParameters parameters) secondTexture;
  final void Function(TParameters parameters, Float32List uniformData) writeUniforms;

  RenderProgramTwoTextureWebGPU({
    required this.label,
    required this.shaderSource,
    required this.uniformByteSize,
    required this.secondTexture,
    required this.writeUniforms,
  });

  @override
  void renderFilter(RenderFilterContext context, TParameters parameters) {
    final renderContext = context.renderContext as RenderContextWebGPU;
    renderContext.filterSystem.renderTextureQuadWithTwoTextureProgram(
      context.renderState,
      context.renderTextureQuad,
      this,
      parameters,
    );
  }
}

void _copyWebGpuUniformData(Float32List parameters, Float32List uniformData) {
  uniformData.setAll(0, parameters);
}

class _RenderProgramWebGPUResources {
  final WebGpuFilterSystem filterSystem;
  final RenderProgramSimpleWebGPU<dynamic> program;
  final pipelines = <BlendMode, Map<int, GPURenderPipeline>>{};

  late final shaderModule = filterSystem.renderContext.device.createShaderModule(
    GPUShaderModuleDescriptor(code: program.shaderSource),
  );

  late final GPUBuffer uniformBuffer = filterSystem._createUniformBuffer(program.uniformByteSize);

  final Float32List uniformData;

  _RenderProgramWebGPUResources(this.filterSystem, this.program)
      : uniformData = Float32List(program.uniformByteSize ~/ 4);

  GPURenderPipeline getPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = pipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      filterSystem._pipelineKey(stencilTest),
      () => filterSystem._createFilterPipeline(program.label, shaderModule, blendMode, stencilTest),
    );
  }
}

class _RenderProgramTwoTextureWebGPUResources {
  final WebGpuFilterSystem filterSystem;
  final RenderProgramTwoTextureWebGPU<dynamic> program;
  final pipelines = <BlendMode, Map<int, GPURenderPipeline>>{};

  late final shaderModule = filterSystem.renderContext.device.createShaderModule(
    GPUShaderModuleDescriptor(code: program.shaderSource),
  );

  late final GPUBuffer uniformBuffer = filterSystem._createUniformBuffer(program.uniformByteSize);
  final Float32List uniformData;

  _RenderProgramTwoTextureWebGPUResources(this.filterSystem, this.program)
      : uniformData = Float32List(program.uniformByteSize ~/ 4);

  GPURenderPipeline getPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = pipelines.putIfAbsent(blendMode, () => <int, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(
      filterSystem._pipelineKey(stencilTest),
      () => filterSystem._createTwoTextureFilterPipeline(program.label, shaderModule, blendMode, stencilTest),
    );
  }
}
