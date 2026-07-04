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

  test('WebGPU batches TintFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = BlendMode.ADD
        ..filters = [TintFilter.fromColor(i.isEven ? 0xFFFFCC44 : 0xFF66CCFF)];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU batches color-scale ColorMatrixFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final amberFilter = ColorMatrixFilter(
      [1, 0, 0, 0, 0, 0.75, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    final blueFilter = ColorMatrixFilter(
      [0.4, 0, 0, 0, 0, 0.8, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = BlendMode.ADD
        ..filters = [
          if (i.isEven) amberFilter else blueFilter,
        ];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU batches stacked color-scale bitmap filters when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final colorScaleFilter = ColorMatrixFilter(
      [1, 0, 0, 0, 0, 0.75, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = BlendMode.ADD
        ..filters = [
          TintFilter.fromColor(i.isEven ? 0xFFFFCC44 : 0xFF66CCFF),
          colorScaleFilter,
        ];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU renders ChromaKeyFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmapData = BitmapData(48, 48, 0xFF00FF00)..fillRect(Rectangle<num>(12, 12, 24, 24), Color.Red);
    final bitmap = Bitmap(bitmapData)
      ..x = 8
      ..y = 8
      ..filters = [ChromaKeyFilter()];
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

  test('WebGPU renders BlurFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(32, 32, Color.Red))
      ..x = 16
      ..y = 16
      ..filters = [BlurFilter(5)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(3));
  });

  test('WebGPU renders stacked bitmap filters when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(32, 32, Color.Red))
      ..x = 16
      ..y = 16
      ..filters = [
        BlurFilter(5),
        TintFilter.fromColor(0xFF66CCFF),
      ];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(4));
  });

  test('WebGPU reuses stable batch render bundles when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final texture = BitmapData(24, 24, Color.Red);
    stage
      ..addChild(Bitmap(texture)
        ..x = 4
        ..y = 4)
      ..addChild(Bitmap(texture)
        ..x = 32
        ..y = 32);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(() => stage.materialize(16, 16), returnsNormally);
    expect(() => stage.materialize(32, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderBundleCacheHitCount, greaterThanOrEqualTo(1));
  });
}
