@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' hide Float32List;

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
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..dualSourceBlending = true;

    expect(options.clone().renderEngine, RenderEngine.WebGPU);
    expect(options.clone().dualSourceBlending, isTrue);
  });

  test('WebGPU can share an externally owned device and canvas context when available', () async {
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final owner = await Stage.create(
      canvas,
      width: 64,
      height: 64,
      options: StageOptions()
        ..renderEngine = .WebGPU
        ..stageRenderMode = .AUTO
        ..maxPixelRatio = 1,
    );
    if (owner.renderEngine != .WebGPU) return;

    final ownerContext = owner.renderContext as RenderContextWebGPU;
    final sharedContext = SharedWebGPUContext(
      device: ownerContext.device,
      canvasContext: ownerContext.canvasContext,
      textureFormat: ownerContext.preferredTextureFormat,
    );
    final overlayOptions = StageOptions()
      ..renderEngine = .WebGPU
      ..sharedWebGPUContext = sharedContext
      ..clearBeforeRender = false
      ..stageRenderMode = .ONCE
      ..maxPixelRatio = 1;
    final overlay = await Stage.create(canvas, width: 64, height: 64, options: overlayOptions);
    final overlayContext = overlay.renderContext as RenderContextWebGPU;

    expect(overlayContext.device, same(ownerContext.device));
    expect(overlayContext.canvasContext, same(ownerContext.canvasContext));
    expect(overlayOptions.clone().sharedWebGPUContext, same(sharedContext));

    overlay
      ..addChild(Bitmap(BitmapData(16, 16, Color.Red)))
      ..materialize(0, 16)
      ..dispose();

    expect(() => owner.materialize(16, 16), returnsNormally);
    owner.dispose();
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

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..mask = Mask.circle(24, 24, 20);
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(2));
  });

  test('WebGPU uploads untouched transparent canvas textures when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(canvas, width: 32, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    stage.addChild(Bitmap(BitmapData(16, 16, Color.Transparent)));

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuTextureUploadCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU evicts disposed render textures when available', () async {
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(
      canvas,
      width: 32,
      height: 32,
      options: StageOptions()
        ..renderEngine = .WebGPU
        ..stageRenderMode = .ONCE,
    );

    if (stage.renderEngine != .WebGPU) {
      stage.dispose();
      return;
    }

    final baseline = ResourceDiagnostics.snapshot();
    final renderTexture = RenderTexture(16, 16, Color.Red);
    stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(renderTexture.quad)));
    stage.materialize(0, 16);

    expect(
      ResourceDiagnostics.snapshot()[StageXLResourceType.webgpuTexture],
      baseline[StageXLResourceType.webgpuTexture] + 1,
    );

    renderTexture.dispose();

    expect(
      ResourceDiagnostics.snapshot()[StageXLResourceType.webgpuTexture],
      baseline[StageXLResourceType.webgpuTexture],
    );

    stage.dispose();
  });

  test('WebGPU reuses instructions and only uploads dirty batch data when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(16, 16, Color.Red);
    final bitmap = Bitmap(bitmapData);
    stage.addChild(bitmap);

    stage.materialize(0, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadBytes, 152);

    stage.materialize(16, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadBytes, 0);

    bitmap.x = 8;
    stage.materialize(32, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadBytes, 48);

    stage.addChild(Bitmap(bitmapData)..x = 32);
    stage.materialize(48, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 1);
  });

  test('WebGPU captures custom render-pipe draws in display-list order when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    options.renderPipes.register(_TintedPipeBitmap.pipeId, const _TintedBitmapPipe());
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(16, 16, Color.Red);
    stage
      ..addChild(Bitmap(bitmapData))
      ..addChild(_TintedPipeBitmap(bitmapData)..x = 16)
      ..addChild(Bitmap(bitmapData)..x = 32);

    stage.materialize(0, 16);

    final renderContext = stage.renderContext as RenderContextWebGPU;
    expect(renderContext.renderStatistics.drawCount, 1);
    expect(renderContext.renderStatistics.webgpuInstructionBuildCount, 1);

    stage.materialize(16, 16);
    expect(renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
  });

  test('WebGPU fuses ordered normal and additive draws on opaque stages when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Black
      ..dualSourceBlending = true
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(canvas, width: 32, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(32, 32);
    stage
      ..addChild(Bitmap(bitmapData)..alpha = 0.25)
      ..addChild(Bitmap(bitmapData)
        ..alpha = 0.25
        ..blendMode = .ADD)
      ..addChild(Bitmap(bitmapData)..alpha = 0.25);

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchBlendBreakCount, 0);
  });

  test('WebGPU preserves normal and additive runs on transparent stages when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..transparent = true
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(canvas, width: 32, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(32, 32);
    stage
      ..addChild(Bitmap(bitmapData)..alpha = 0.25)
      ..addChild(Bitmap(bitmapData)
        ..alpha = 0.25
        ..blendMode = .ADD)
      ..addChild(Bitmap(bitmapData)..alpha = 0.25);

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.drawCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuBatchBlendBreakCount, 2);
  });

  test('WebGPU promotes mixed retained blend modes into one dual-source batch when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Black
      ..dualSourceBlending = true
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(canvas, width: 32, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(32, 32);
    stage
      ..addChild(Bitmap(bitmapData)..alpha = 0.25)
      ..addChild(Bitmap(bitmapData)
        ..alpha = 0.25
        ..blendMode = .ADD)
      ..addChild(Bitmap(bitmapData)
        ..alpha = 0.25
        ..blendMode = .SCREEN)
      ..addChild(Bitmap(bitmapData)
        ..alpha = 0.25
        ..blendMode = .MULTIPLY)
      ..addChild(Bitmap(bitmapData)..alpha = 0.25);

    stage.materialize(0, 16);

    final context = stage.renderContext as RenderContextWebGPU;
    expect(context.renderStatistics.drawCount, context.dualSourceBlending ? 1 : 4);
    expect(context.renderStatistics.webgpuBatchRunCount, context.dualSourceBlending ? 1 : 4);
    expect(context.renderStatistics.webgpuBatchBlendBreakCount, context.dualSourceBlending ? 0 : 3);
  });

  test('WebGPU retains nested render groups independently when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(16, 16, Color.Red);
    final group = Sprite()
      ..isRenderGroup = true
      ..addChild(Bitmap(bitmapData));
    stage.addChild(group);

    stage.materialize(0, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 2);

    group.x = 8;
    stage.materialize(16, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 2);
    expect(stage.renderContext.renderStatistics.webgpuInstructionUploadCount, 0);

    group.addChild(Bitmap(bitmapData)..x = 16);
    stage.materialize(32, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
  });

  test('WebGPU releases retained root and group resources when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final group = Sprite()
      ..isRenderGroup = true
      ..addChild(Bitmap(BitmapData(16, 16, Color.Red)));
    stage.addChild(group);

    stage.materialize(0, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 2);

    stage.releaseRenderPlan();
    stage.materialize(16, 16);

    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 2);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 0);
  });

  test('WebGPU Stage disposal releases the device context when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final stage = await Stage.create(canvas, width: 32, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) {
      stage.dispose();
      return;
    }

    stage.addChild(Bitmap(BitmapData(16, 16, Color.Red)));
    stage.materialize(0, 16);
    final renderContext = stage.renderContext as RenderContextWebGPU;

    expect(stage.dispose, returnsNormally);
    expect(stage.isDisposed, isTrue);
    expect(renderContext.isDisposed, isTrue);
    expect(() => stage.materialize(16, 16), returnsNormally);
    expect(stage.dispose, returnsNormally);
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

    if (stage.renderEngine != .WebGPU) return;

    final container = Sprite()
      ..x = 4
      ..y = 4
      ..mask = .circle(28, 28, 26);

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 4
      ..y = 4
      ..mask = .circle(24, 24, 18);

    container.addChild(bitmap);
    stage.addChild(container);

    expect(() => stage.materialize(0, 16), returnsNormally);
  });

  test('WebGPU renders graphics gradient fills and strokes when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 96
      ..height = 96;
    final stage = await Stage.create(canvas, width: 96, height: 96, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final linear = GraphicsGradient.linear(0, 0, 40, 0)
      ..addColorStop(0, Color.Red)
      ..addColorStop(1, Color.Blue);
    final radial = GraphicsGradient.radial(68, 24, 0, 68, 24, 20)
      ..addColorStop(0, Color.White)
      ..addColorStop(1, Color.Black);
    final stroke = GraphicsGradient.linear(8, 70, 88, 70)
      ..addColorStop(0, Color.Green)
      ..addColorStop(1, Color.Yellow);
    final shape = Shape();
    shape.graphics
      ..rect(8, 8, 40, 32)
      ..fillGradient(linear)
      ..circle(68, 24, 20)
      ..fillGradient(radial)
      ..beginPath()
      ..moveTo(8, 70)
      ..lineTo(88, 70)
      ..strokeGradient(stroke, 8);
    stage.addChild(shape);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(3));
  });

  test('WebGPU batches solid graphics with adjacent texture quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 32;
    final stage = await Stage.create(canvas, width: 64, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final shape = Shape();
    shape.graphics
      ..rect(0, 0, 16, 16)
      ..fillColor(Color.Red);
    stage
      ..addChild(shape)
      ..addChild(Bitmap(BitmapData(16, 16, Color.Blue))..x = 24);

    stage.materialize(0, 16);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);

    shape.x = 4;
    stage.materialize(16, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
  });

  test('WebGPU materializes uncached text into retained batches when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO;
    final canvas = HTMLCanvasElement()
      ..width = 96
      ..height = 32;
    final stage = await Stage.create(canvas, width: 96, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final text = TextField('retained', TextFormat('Arial', 12, Color.White))
      ..cacheAsBitmap = false;
    stage.addChild(text);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 1);

    text.x = 4;
    stage.materialize(16, 16);
    expect(stage.renderContext.renderStatistics.webgpuInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.webgpuInstructionReuseCount, 1);
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

    if (stage.renderEngine != .WebGPU) return;

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

    if (stage.renderEngine != .WebGPU) return;

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

    if (stage.renderEngine != .WebGPU) return;

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

    if (stage.renderEngine != .WebGPU) return;

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
        ..blendMode = .ADD
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

    if (stage.renderEngine != .WebGPU) return;

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

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(48, 48, 0xFF00FF00)..fillRect(Rectangle<num>(12, 12, 24, 24), Color.Red);
    final bitmap = Bitmap(bitmapData)
      ..x = 8
      ..y = 8
      ..filters = [ChromaKeyFilter()];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU renders custom one-texture filter programs when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [_CustomTintFilter(0.25, 0.5, 1, 1)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  for (final renderEngine in [RenderEngine.WebGL, RenderEngine.WebGL2]) {
    test('$renderEngine renders custom one-texture filter programs', () {
      final options = StageOptions()
        ..renderEngine = renderEngine
        ..backgroundColor = Color.Transparent
        ..stageRenderMode = .ONCE;
      final canvas = HTMLCanvasElement()
        ..width = 64
        ..height = 64;
      final stage = Stage(canvas, width: 64, height: 64, options: options);
      if (stage.renderEngine != renderEngine) return;

      final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
        ..x = 8
        ..y = 8
        ..filters = [_CustomTintFilter(0.25, 0.5, 1, 0.75)];
      stage.addChild(bitmap);

      expect(() => stage.materialize(0, 16), returnsNormally);
      expect(stage.renderContext.renderStatistics.drawCount, greaterThanOrEqualTo(1));
    });
  }

  test('WebGPU batches batch-preserving filtered display objects when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final sprite = Sprite()
      ..blendMode = .ADD
      ..filters = [TintFilter.fromColor(0xFF66CCFF)];
    for (var i = 0; i < 24; i++) {
      sprite.addChild(Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16);
    }
    stage.addChild(sprite);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
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

    if (stage.renderEngine != .WebGPU) return;

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

  test('WebGPU keeps scissor-separated retained batches in one render pass when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 32;
    final stage = await Stage.create(canvas, width: 64, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final texture = BitmapData(32, 32, Color.Red);
    stage
      ..addChild(Bitmap(texture)..mask = .rectangle(0, 0, 24, 32))
      ..addChild(Bitmap(texture)
        ..x = 32
        ..mask = .rectangle(8, 0, 24, 32));

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.drawCount, 2);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, 1);
  });

  test('WebGPU batches retained axis-aligned scissor masks in the shader when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 32;
    final stage = await Stage.create(canvas, width: 64, height: 32, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final texture = BitmapData(32, 32, Color.Red);
    stage
      ..addChild(Bitmap(texture)..mask = .shaderRect(0, 0, 24, 32))
      ..addChild(Bitmap(texture)
        ..x = 32
        ..mask = .shaderRect(8, 0, 24, 32));

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, 1);
  });

  test('WebGPU switches between normal and shader-scissored retained batches when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 16;
    final stage = await Stage.create(canvas, width: 64, height: 16, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final texture = BitmapData(16, 16, Color.Red);
    stage
      ..addChild(Bitmap(texture))
      ..addChild(Bitmap(texture)
        ..x = 16
        ..mask = .shaderRect(0, 0, 16, 16))
      ..addChild(Bitmap(texture)
        ..x = 32
        ..mask = .shaderRect(0, 0, 16, 16))
      ..addChild(Bitmap(texture)..x = 48);

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.drawCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 3);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, 1);
  });

  test('WebGPU reuses stable batch render bundles when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO
      ..renderBundles = true;
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

    for (var frame = 0; frame < 31; frame++) {
      expect(() => stage.materialize(frame * 16, 16), returnsNormally);
    }
    expect(stage.renderContext.renderStatistics.webgpuRenderBundleCacheHitCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU defers render bundles for structurally unstable batches', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO
      ..renderBundles = true;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final texture = BitmapData(24, 24, Color.Red);
    final changingBitmap = Bitmap(texture)..x = 32;
    stage
      ..addChild(Bitmap(texture))
      ..addChild(changingBitmap);

    var buildCount = 0;
    for (var frame = 0; frame < 120; frame++) {
      if (frame % 10 == 0) changingBitmap.visible = !changingBitmap.visible;
      stage.materialize(frame * 16, 16);
      buildCount += stage.renderContext.renderStatistics.webgpuRenderBundleBuildCount;
    }

    expect(buildCount, 0);
  });

  test('WebGPU backs off after a short-lived render bundle', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .AUTO
      ..renderBundles = true;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final texture = BitmapData(24, 24, Color.Red);
    final changingBitmap = Bitmap(texture)..x = 32;
    stage
      ..addChild(Bitmap(texture))
      ..addChild(changingBitmap);

    var buildCount = 0;
    for (var frame = 0; frame < 30; frame++) {
      stage.materialize(frame * 16, 16);
      buildCount += stage.renderContext.renderStatistics.webgpuRenderBundleBuildCount;
    }
    expect(buildCount, 1);

    changingBitmap.visible = false;
    stage.materialize(30 * 16, 16);
    buildCount += stage.renderContext.renderStatistics.webgpuRenderBundleBuildCount;
    expect(stage.renderContext.renderStatistics.webgpuRenderBundleBackoffCount, 1);

    for (var frame = 31; frame < 61; frame++) {
      stage.materialize(frame * 16, 16);
      buildCount += stage.renderContext.renderStatistics.webgpuRenderBundleBuildCount;
    }
    expect(buildCount, 1);
  });
}

typedef _TintParameters = ({double red, double green, double blue, double alpha});

class _TintedPipeBitmap extends Bitmap {
  static const pipeId = RenderPipeId<_TintedPipeBitmap>('test.tinted-bitmap');

  _TintedPipeBitmap(super.bitmapData);

  @override
  RenderPipeId get renderPipeId => pipeId;
}

class _TintedBitmapPipe implements RenderPipe<_TintedPipeBitmap> {
  const _TintedBitmapPipe();

  @override
  void addRenderable(_TintedPipeBitmap renderable, RenderBuildContext context) {
    final quad = renderable.bitmapData!.renderTextureQuad;
    context.addTextureMesh(
      quad.renderTexture,
      quad.ixList,
      quad.vxList,
      red: 0.75,
      green: 0.5,
    );
  }
}

class _CustomTintFilter extends BitmapFilter {
  static const _webGPUShaderSource = '''
      @group(0) @binding(0) var stageSampler: sampler;
      @group(0) @binding(1) var stageTexture: texture_2d<f32>;

      struct TintUniforms {
        colorScale: vec4<f32>,
      };

      @group(0) @binding(2) var<uniform> tint: TintUniforms;

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
        return textureSample(stageTexture, stageSampler, input.uv) * tint.colorScale;
      }
    ''';
  static final _webGPUProgram = _TintProgramWebGPU();
  static final _programs = RenderProgramSet<_TintParameters>(
    webGL: _TintProgramWebGL(),
    webGPU: _webGPUProgram,
  );

  static void _writeUniforms(_TintParameters parameters, Float32List uniformData) {
    uniformData[0] = parameters.red;
    uniformData[1] = parameters.green;
    uniformData[2] = parameters.blue;
    uniformData[3] = parameters.alpha;
  }

  final double factorR;
  final double factorG;
  final double factorB;
  final double factorA;

  _CustomTintFilter(this.factorR, this.factorG, this.factorB, this.factorA);

  @override
  RenderProgramSet<_TintParameters> get renderPrograms => _programs;

  @override
  BitmapFilter clone() => _CustomTintFilter(factorR, factorG, factorB, factorA);

  @override
  void renderFilter(RenderFilterContext context) {
    context.render(
      _programs,
      (
        red: factorR,
        green: factorG,
        blue: factorB,
        alpha: factorA * context.renderState.globalAlpha,
      ),
    );
  }
}

final class _TintProgramWebGL extends RenderProgramSimpleWebGL<_TintParameters> {
  @override
  String get fragmentShaderSourceWebGL2 => '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec4 uTint;
    in vec2 vTextCoord;
    out vec4 fragColor;

    void main() {
      fragColor = texture(uSampler, vTextCoord) * uTint;
    }
    ''';

  @override
  String get fragmentShaderSourceWebGL1 => '''
    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec4 uTint;
    varying vec2 vTextCoord;

    void main() {
      gl_FragColor = texture2D(uSampler, vTextCoord) * uTint;
    }
    ''';

  @override
  void uploadParameters(_TintParameters parameters) {
    renderingContext.uniform4f(
      uniforms['uTint'],
      parameters.red,
      parameters.green,
      parameters.blue,
      parameters.alpha,
    );
  }
}

final class _TintProgramWebGPU extends RenderProgramSimpleWebGPU<_TintParameters> {
  _TintProgramWebGPU()
      : super(
          label: 'StageXL custom test tint filter pipeline',
          shaderSource: _CustomTintFilter._webGPUShaderSource,
          uniformByteSize: 16,
          writeUniforms: _CustomTintFilter._writeUniforms,
        );
}
