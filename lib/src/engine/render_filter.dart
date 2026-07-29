part of '../engine.dart';

/// The abstract [RenderFilter] class defines the interface for filters
/// that can be rendered by the engine.
///
abstract class RenderFilter {
  Rectangle<int> get overlap;
  List<int> get renderPassSources;
  List<int> get renderPassTargets;

  List<int> renderPassSourcesFor(RenderEngine renderEngine) => renderPassSources;

  List<int> renderPassTargetsFor(RenderEngine renderEngine) => renderPassTargets;

  bool get isSimple {
    final overlap = this.overlap;
    final rps = renderPassSources;
    return overlap.width == 0 && overlap.height == 0 && rps.length == 1;
  }

  RenderProgramSet<Object?> get renderPrograms;

  bool get rendersInWebGpuBatch => false;

  void applyWebGpuBatchColorScale(Float32List colorScale) {}

  void renderFilter(RenderFilterContext context);
}

class RenderProgramSet<TParameters> {
  final RenderProgramWebGL<TParameters>? webGL;
  final RenderProgramWebGPU<TParameters>? webGPU;

  RenderProgramSet({this.webGL, this.webGPU}) {
    if (webGL == null && webGPU == null) {
      throw ArgumentError('At least one render program is required.');
    }
  }

  bool supports(RenderEngine renderEngine) => switch (renderEngine) {
        .WebGL || .WebGL2 => webGL != null,
        .WebGPU => webGPU != null,
        .Canvas2D => false,
      };
}

class RenderFilterContext {
  final RenderState renderState;
  final RenderTextureQuad renderTextureQuad;
  final int pass;

  RenderFilterContext({
    required this.renderState,
    required this.renderTextureQuad,
    required this.pass,
  });

  RenderContext get renderContext => renderState.renderContext;

  void render<TParameters>(RenderProgramSet<TParameters> programs, TParameters parameters) {
    switch (renderContext) {
      case RenderContextWebGL():
        final program = programs.webGL;
        if (program == null) throw UnsupportedError('The filter does not support WebGL.');
        program.renderFilter(this, parameters);
      case RenderContextWebGPU():
        final program = programs.webGPU;
        if (program == null) throw UnsupportedError('The filter does not support WebGPU.');
        program.renderFilter(this, parameters);
      default:
        throw UnsupportedError('Render programs are not available for $renderContext.');
    }
  }
}
