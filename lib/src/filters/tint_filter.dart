library;

import 'dart:js_interop';
import 'dart:typed_data';

import '../display.dart';
import '../engine.dart';
import '../geom.dart';
import '../internal/environment.dart' as env;
import '../internal/tools.dart';

class TintFilter extends BitmapFilter {
  static final _programs = RenderProgramSet<TintFilter>(
    webGL: RenderProgramWebGL.callback(_renderWebGL),
    webGPU: RenderProgramWebGPU.callback(_renderWebGPU),
  );

  num factorR;
  num factorG;
  num factorB;
  num factorA;

  TintFilter(this.factorR, this.factorG, this.factorB, this.factorA);

  TintFilter.fromColor(int color)
      : factorR = colorGetR(color) / 255.0,
        factorG = colorGetG(color) / 255.0,
        factorB = colorGetB(color) / 255.0,
        factorA = colorGetA(color) / 255.0;

  @override
  BitmapFilter clone() => TintFilter(factorR, factorG, factorB, factorA);

  @override
  RenderProgramSet<TintFilter> get renderPrograms => _programs;

  @override
  bool get rendersInWebGpuBatch => true;

  @override
  void applyWebGpuBatchColorScale(Float32List colorScale) {
    colorScale[0] *= factorR.toDouble();
    colorScale[1] *= factorG.toDouble();
    colorScale[2] *= factorB.toDouble();
    colorScale[3] *= factorA.toDouble();
  }

  //---------------------------------------------------------------------------

  @override
  void apply(BitmapData bitmapData, [Rectangle<num>? rectangle]) {
    final isLittleEndianSystem = env.isLittleEndianSystem;

    final d0 = ((isLittleEndianSystem ? factorR : factorA) * 65536).round();
    final d1 = ((isLittleEndianSystem ? factorG : factorB) * 65536).round();
    final d2 = ((isLittleEndianSystem ? factorB : factorG) * 65536).round();
    final d3 = ((isLittleEndianSystem ? factorA : factorR) * 65536).round();

    final renderTextureQuad = rectangle == null
        ? bitmapData.renderTextureQuad
        : bitmapData.renderTextureQuad.cut(rectangle);

    final imageData = renderTextureQuad.getImageData();
    final data = imageData.data.toDart;

    for (var index = 0; index <= data.length - 4; index += 4) {
      final c0 = data[index + 0];
      final c1 = data[index + 1];
      final c2 = data[index + 2];
      final c3 = data[index + 3];
      data[index + 0] = ((d0 * c0) | 0) >> 16;
      data[index + 1] = ((d1 * c1) | 0) >> 16;
      data[index + 2] = ((d2 * c2) | 0) >> 16;
      data[index + 3] = ((d3 * c3) | 0) >> 16;
    }

    renderTextureQuad.putImageData(imageData);
  }

  //---------------------------------------------------------------------------

  @override
  void renderFilter(RenderFilterContext context) => context.render(_programs, this);

  static void _renderWebGL(RenderFilterContext context, TintFilter filter) {
    final renderContext = context.renderContext as RenderContextWebGL;
    final renderProgram = renderContext.renderProgramBatch;
    renderContext.activateRenderProgram(renderProgram);
    renderProgram.renderTextureQuad(
      context.renderState,
      renderContext,
      context.renderTextureQuad,
      filter.factorR,
      filter.factorG,
      filter.factorB,
      filter.factorA,
    );
  }

  static void _renderWebGPU(RenderFilterContext context, TintFilter filter) {
    final renderContext = context.renderContext as RenderContextWebGPU;
    renderContext.batchSystem.renderTextureQuad(
      context.renderState,
      context.renderTextureQuad,
      filter.factorR,
      filter.factorG,
      filter.factorB,
      filter.factorA,
    );
  }
}
