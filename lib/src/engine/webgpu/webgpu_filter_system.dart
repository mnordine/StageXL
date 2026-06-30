part of '../../engine.dart';

class WebGpuFilterSystem {
  final RenderContextWebGPU renderContext;

  WebGpuFilterSystem(this.renderContext);

  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    if (renderFilters.isEmpty) return;

    renderContext.renderStatistics.webgpuFallbackCount++;
    throw UnsupportedError('WebGPU filter parity requires the WGSL filter-pass implementation.');
  }

  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    if (renderObject.filters.isEmpty) return;

    renderContext.renderStatistics.webgpuFallbackCount++;
    throw UnsupportedError('WebGPU filter parity requires the WGSL filter-pass implementation.');
  }
}
