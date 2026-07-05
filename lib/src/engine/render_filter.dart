part of '../engine.dart';

/// The abstract [RenderFilter] class defines the interface for filters
/// that can be rendered by the engine.
///
abstract class RenderFilter {
  Rectangle<int> get overlap;
  List<int> get renderPassSources;
  List<int> get renderPassTargets;

  bool get isSimple {
    final overlap = this.overlap;
    final rps = renderPassSources;
    return overlap.width == 0 && overlap.height == 0 && rps.length == 1;
  }

  bool get supportsWebGPU => false;

  bool get rendersInWebGpuBatch => false;

  void applyWebGpuBatchColorScale(Float32List colorScale) {}

  void renderWebGpuFilter(WebGpuFilterContext context) {
    renderFilter(context.renderState, context.renderTextureQuad, context.pass);
  }

  void renderFilter(
      RenderState renderState, RenderTextureQuad renderTextureQuad, int pass);
}
