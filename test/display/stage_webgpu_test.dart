@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  test('sync Stage constructor rejects WebGPU because device creation is async', () {
    final options = StageOptions()..renderEngine = .WebGPU;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;

    expect(
      () => Stage(canvas, options: options),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Stage.create'),
      )),
    );
  });

  test('StageOptions clone preserves WebGPU render engine', () {
    final options = StageOptions()..renderEngine = .WebGPU;

    expect(options.clone().renderEngine, RenderEngine.WebGPU);
  });

  test('WebGPU renders non-scissor masks through stencil pass when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..mask = Mask.circle(24, 24, 20);
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(2));
  });

  test('WebGPU restores nested stencil masks when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final container = Sprite()
      ..x = 4
      ..y = 4
      ..mask = Mask.circle(28, 28, 26);
    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 4
      ..y = 4
      ..mask = Mask.circle(24, 24, 18);

    container.addChild(bitmap);
    stage.addChild(container);

    expect(() => stage.materialize(0, 16), returnsNormally);
  });

  test('WebGPU renders ColorMatrixFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [ColorMatrixFilter.grayscale()];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU renders TintFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [TintFilter.fromColor(0xFF66CCFF)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU renders simple filtered display objects when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final sprite = Sprite()
      ..x = 8
      ..y = 8
      ..filters = [TintFilter.fromColor(0xFF66CCFF)];
    sprite.addChild(Bitmap(BitmapData(48, 48, Color.Red)));
    stage.addChild(sprite);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(2));
  });
}
