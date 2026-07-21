@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' hide WebGL;

class _Instruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_Instruction>('test.instruction');

  final int value;

  _Instruction(this.value);

  @override
  InstructionPipeId<_Instruction> get instructionPipeId => pipeId;
}

final class _Slot extends RetainedSlot {
  final int value;

  const _Slot(this.value);
}

final class _InstructionPipe implements InstructionPipe<_Instruction> {
  var uploadCount = 0;
  var executeCount = 0;
  var disposeCount = 0;

  @override
  InstructionPipeId<_Instruction> get id => _Instruction.pipeId;

  @override
  void upload(_Instruction instruction) => uploadCount += instruction.value;

  @override
  void execute(_Instruction instruction) => executeCount += instruction.value;

  @override
  void dispose(_Instruction instruction) => disposeCount += instruction.value;
}

class _UnusedBitmapPipe implements RenderPipe<Bitmap> {
  const _UnusedBitmapPipe();

  @override
  void addRenderable(Bitmap renderable, RenderBuildContext context) {}
}

class _ConflictingBitmapPipe implements RenderPipe<Bitmap> {
  const _ConflictingBitmapPipe();

  @override
  void addRenderable(Bitmap renderable, RenderBuildContext context) {}
}

class _PipeBitmap extends Bitmap implements RenderPipeProvider {
  static const pipeId = RenderPipeId<_PipeBitmap>('test.pipe-bitmap');

  _PipeBitmap(super.bitmapData);

  @override
  RenderPipeId get renderPipeId => pipeId;

  @override
  void registerRenderPipe(RenderPipeRegistry registry) => registry.register(pipeId, const _CountingBitmapPipe());
}

class _CountingBitmapPipe implements RenderPipe<_PipeBitmap> {
  static var addCount = 0;

  const _CountingBitmapPipe();

  @override
  void addRenderable(_PipeBitmap renderable, RenderBuildContext context) {
    addCount++;
    context.addTextureQuad(renderable.bitmapData!.renderTextureQuad);
  }
}

void main() {
  test('InstructionSet reuses typed instruction and slot storage', () {
    final instructionSet = InstructionSet();
    final firstInstruction = _Instruction(1);
    const firstSlot = _Slot(1);

    instructionSet
      ..addInstruction(firstInstruction)
      ..addSlot(firstSlot);

    expect(instructionSet.instructionCount, 1);
    expect(instructionSet.slotCount, 1);
    expect(instructionSet.instructionCapacity, 1);
    expect(instructionSet.slotCapacity, 1);

    instructionSet.reset();
    final secondInstruction = _Instruction(2);
    const secondSlot = _Slot(2);
    instructionSet
      ..addInstruction(secondInstruction)
      ..addSlot(secondSlot);

    expect(instructionSet.instructionCapacity, 1);
    expect(instructionSet.slotCapacity, 1);
    expect(instructionSet.instructionAt(0), same(secondInstruction));
    expect(instructionSet.slotAt(0), same(secondSlot));
  });

  test('InstructionPipeRegistry dispatches typed lifecycle operations', () {
    final registry = InstructionPipeRegistry();
    final pipe = _InstructionPipe();
    final instruction = _Instruction(2);

    expect(registry.register(pipe), isTrue);
    registry
      ..upload(instruction)
      ..execute(instruction)
      ..dispose(instruction);

    expect(pipe.uploadCount, 2);
    expect(pipe.executeCount, 2);
    expect(pipe.disposeCount, 2);
  });

  test('display objects separate data and structural invalidation', () {
    final sprite = Sprite();
    final structureVersion = sprite.renderStructureVersion;
    final dataVersion = sprite.renderDataVersion;

    sprite.x = 10;
    expect(sprite.renderStructureVersion, structureVersion);
    expect(sprite.renderDataVersion, greaterThan(dataVersion));

    final transformedDataVersion = sprite.renderDataVersion;
    sprite.visible = false;
    expect(sprite.renderStructureVersion, greaterThan(structureVersion));
    expect(sprite.renderDataVersion, greaterThan(transformedDataVersion));

    final visibleStructureVersion = sprite.renderStructureVersion;
    sprite.addChild(Bitmap());
    expect(sprite.renderStructureVersion, greaterThan(visibleStructureVersion));

    final childStructureVersion = sprite.renderStructureVersion;
    sprite.isRenderGroup = true;
    expect(sprite.renderStructureVersion, greaterThan(childStructureVersion));
  });

  test('display objects track independent retained dirty categories', () {
    final sprite = Sprite();
    final dirty = sprite.renderDirtyState;

    final transformVersion = dirty.transformVersion;
    final colorVersion = dirty.colorVersion;
    sprite.x = 10;
    expect(dirty.transformVersion, greaterThan(transformVersion));
    expect(dirty.colorVersion, colorVersion);

    final structureVersion = dirty.structureVersion;
    final maskVersion = dirty.maskVersion;
    sprite.mask = Mask.rectangle(0, 0, 10, 10);
    expect(dirty.structureVersion, greaterThan(structureVersion));
    expect(dirty.maskVersion, greaterThan(maskVersion));

    final blendVersion = dirty.blendVersion;
    sprite.blendMode = .ADD;
    expect(dirty.blendVersion, greaterThan(blendVersion));
  });

  test('render pipe IDs are unique registry keys', () {
    final registry = RenderPipeRegistry();
    const id = RenderPipeId<Bitmap>('test.registry-bitmap');
    expect(registry.register(id, const _UnusedBitmapPipe()), isTrue);
    expect(
      () => registry.register(id, const _ConflictingBitmapPipe()),
      throwsStateError,
    );
  });

  test('registered render pipes receive backend-neutral build contexts', () {
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final options = StageOptions()..renderEngine = .Canvas2D;
    final stage = Stage(
      canvas,
      width: 32,
      height: 32,
      options: options,
    );
    _CountingBitmapPipe.addCount = 0;
    final bitmap = _PipeBitmap(BitmapData(16, 16, Color.Red));
    stage.addChild(bitmap);

    stage.materialize(0, 16);

    expect(_CountingBitmapPipe.addCount, 1);
    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 1);
    expect(stage.renderContext.renderStatistics.retainedInstructionCount, 1);

    bitmap.x = 4;
    stage.materialize(16, 16);

    expect(_CountingBitmapPipe.addCount, 2);
    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.retainedInstructionReuseCount, 1);
  });

  test('retained Canvas2D commands preserve custom-pipe display order', () {
    final canvas = HTMLCanvasElement()
      ..width = 16
      ..height = 16;
    final options = StageOptions()
      ..renderEngine = .Canvas2D
      ..backgroundColor = Color.Transparent;
    final stage = Stage(canvas, width: 16, height: 16, options: options)
      ..addChild(Bitmap(BitmapData(16, 16, Color.Blue)))
      ..addChild(_PipeBitmap(BitmapData(16, 16, Color.Red)))
      ..addChild(Bitmap(BitmapData(16, 16, Color.Green)));

    stage.materialize(0, 16);

    final pixel = (canvas.getContext('2d') as CanvasRenderingContext2D).getImageData(8, 8, 1, 1).data.toDart;
    expect(pixel[0], 0);
    expect(pixel[1], 128);
    expect(pixel[2], 0);
    expect(pixel[3], 255);
  });

  test('Canvas2D retains BitmapContainer transforms and shadow boundaries', () {
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 16;
    final options = StageOptions()
      ..renderEngine = .Canvas2D
      ..backgroundColor = Color.Transparent;
    final bitmaps = BitmapContainer()
      ..x = 4
      ..addChild(Bitmap(BitmapData(8, 8, Color.Red))..x = 4);
    final stage = Stage(canvas, width: 32, height: 16, options: options)
      ..addChild(CanvasShadowWrapper(bitmaps, Color.Black, 2, 0, 0));

    stage.materialize(0, 16);

    final context = canvas.getContext('2d') as CanvasRenderingContext2D;
    final inside = context.getImageData(9, 2, 1, 1).data.toDart;
    final outside = context.getImageData(2, 2, 1, 1).data.toDart;
    expect(inside[0], 255);
    expect(inside[3], 255);
    expect(outside[3], 0);
    expect(stage.renderContext.renderStatistics.retainedInstructionCount, 3);

    stage.materialize(16, 16);
    expect(stage.renderContext.renderStatistics.retainedInstructionReuseCount, 1);
  });

  test('Canvas2D retains Sprite graphics before child instructions', () {
    final canvas = HTMLCanvasElement()
      ..width = 24
      ..height = 16;
    final options = StageOptions()
      ..renderEngine = .Canvas2D
      ..backgroundColor = Color.Transparent;
    final sprite = Sprite();
    sprite.graphics
      ..rect(0, 0, 16, 16)
      ..fillColor(Color.Red);
    sprite.addChild(Bitmap(BitmapData(8, 8, Color.Blue))
      ..x = 4
      ..y = 4);
    final stage = Stage(canvas, width: 24, height: 16, options: options)..addChild(sprite);

    stage.materialize(0, 16);

    final context = canvas.getContext('2d') as CanvasRenderingContext2D;
    final background = context.getImageData(2, 2, 1, 1).data.toDart;
    final foreground = context.getImageData(6, 6, 1, 1).data.toDart;
    expect(background.sublist(0, 4), [255, 0, 0, 255]);
    expect(foreground.sublist(0, 4), [0, 0, 255, 255]);
    expect(stage.renderContext.renderStatistics.retainedInstructionCount, 2);

    sprite.x = 8;
    stage.materialize(16, 16);

    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.retainedInstructionReuseCount, 1);
    final movedBackground = context.getImageData(10, 2, 1, 1).data.toDart;
    final movedForeground = context.getImageData(14, 6, 1, 1).data.toDart;
    expect(movedBackground.sublist(0, 4), [255, 0, 0, 255]);
    expect(movedForeground.sublist(0, 4), [0, 0, 255, 255]);
  });

  test('Canvas2D retains native text without rebuilding for transforms', () {
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 24;
    final options = StageOptions()
      ..renderEngine = .Canvas2D
      ..backgroundColor = Color.Transparent;
    final text = TextField('retained', TextFormat('Arial', 12, Color.Red))
      ..cacheAsBitmap = false;
    final stage = Stage(canvas, width: 64, height: 24, options: options)..addChild(text);

    stage.materialize(0, 16);

    expect(stage.renderContext.renderStatistics.retainedInstructionCount, 1);
    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 1);

    text.x = 4;
    stage.materialize(16, 16);

    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 0);
    expect(stage.renderContext.renderStatistics.retainedInstructionReuseCount, 1);
  });

  test('WebGL1 retained batches upload only changed buffer data when available', () {
    _expectWebGlRetainedUploads(.WebGL);
  });

  test('WebGL2 retained batches upload only changed buffer data when available', () {
    _expectWebGlRetainedUploads(.WebGL2);
  });

  test('WebGL1 immediate uploads do not overwrite retained buffers', () {
    _expectWebGlImmediateUploadsDoNotOverwriteRetainedBuffers(.WebGL);
  });

  test('WebGL2 immediate uploads do not overwrite retained buffers', () {
    _expectWebGlImmediateUploadsDoNotOverwriteRetainedBuffers(.WebGL2);
  });

  test('Stage releases and recreates retained render plans', () {
    final canvas = HTMLCanvasElement()
      ..width = 16
      ..height = 16;
    final options = StageOptions()..renderEngine = .Canvas2D;
    final stage = Stage(canvas, width: 16, height: 16, options: options)
      ..addChild(Bitmap(BitmapData(16, 16, Color.Red)));

    stage.materialize(0, 16);
    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 1);

    stage.releaseRenderPlan();
    stage.materialize(16, 16);

    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 1);
    expect(stage.renderContext.renderStatistics.retainedInstructionReuseCount, 0);
  });

  test('Stage disposal releases its context and prevents later rendering', () {
    final canvas = HTMLCanvasElement()
      ..width = 16
      ..height = 16;
    final options = StageOptions()..renderEngine = .Canvas2D;
    final stage = Stage(canvas, width: 16, height: 16, options: options)
      ..addChild(Bitmap(BitmapData(16, 16, Color.Red)));
    final renderLoop = RenderLoop()..addStage(stage);

    stage.materialize(0, 16);
    final buildCount = stage.renderContext.renderStatistics.retainedInstructionBuildCount;
    stage.dispose();

    expect(stage.isDisposed, isTrue);
    expect(stage.renderContext.isDisposed, isTrue);
    expect(stage.renderLoop, isNull);
    expect(() => stage.materialize(16, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, buildCount);
    expect(stage.dispose, returnsNormally);
    renderLoop.stop();
  });
}

void _expectWebGlRetainedUploads(RenderEngine engine) {
  final canvas = HTMLCanvasElement()
    ..width = 32
    ..height = 16;
  final options = StageOptions()
    ..renderEngine = engine
    ..backgroundColor = Color.Transparent;
  final bitmapData = BitmapData(8, 8, Color.Red);
  final first = Bitmap(bitmapData);
  final vector = Sprite();
  vector.graphics
    ..rect(0, 0, 8, 8)
    ..fillColor(Color.Green);
  final stage = Stage(canvas, width: 32, height: 16, options: options)
    ..addChild(first)
    ..addChild(vector..x = 2)
    ..addChild(Bitmap(BitmapData(8, 8, Color.Blue))..x = 4);
  if (stage.renderEngine != engine) {
    stage.dispose();
    return;
  }

  stage.materialize(0, 16);
  expect(stage.renderContext.renderStatistics.retainedInstructionUploadCount, 2);
  expect(stage.renderContext.renderStatistics.drawCount, 1);
  final gl = (stage.renderContext as RenderContextWebGL).rawContext;
  final pixel = Uint8List(4);
  gl.readPixels(6, 12, 1, 1, WebGL.RGBA, WebGL.UNSIGNED_BYTE, pixel.toJS);
  expect(pixel, [0, 0, 255, 255]);

  stage.materialize(16, 16);
  expect(stage.renderContext.renderStatistics.retainedInstructionUploadCount, 0);

  first.x = 2;
  stage.materialize(32, 16);
  expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 0);
  expect(stage.renderContext.renderStatistics.retainedInstructionUploadCount, 1);

  stage.addChild(Bitmap(BitmapData(8, 8, Color.Yellow))..x = 4);
  stage.materialize(48, 16);
  expect(stage.renderContext.renderStatistics.retainedInstructionBuildCount, 1);
  expect(stage.renderContext.renderStatistics.retainedInstructionUploadCount, 2);
  gl.readPixels(6, 12, 1, 1, WebGL.RGBA, WebGL.UNSIGNED_BYTE, pixel.toJS);
  expect(pixel, [255, 255, 0, 255]);
  stage.dispose();
}

void _expectWebGlImmediateUploadsDoNotOverwriteRetainedBuffers(RenderEngine engine) {
  final canvas = HTMLCanvasElement()
    ..width = 16
    ..height = 16;
  final options = StageOptions()
    ..renderEngine = engine
    ..backgroundColor = Color.Transparent;
  final stage = Stage(canvas, width: 16, height: 16, options: options)
    ..addChild(Bitmap(BitmapData(16, 16, Color.Red)));
  if (stage.renderEngine != engine) {
    stage.dispose();
    return;
  }

  final context = stage.renderContext as RenderContextWebGL;
  final immediateState = RenderState(context);

  void uploadImmediateTriangle() {
    immediateState.renderTriangle(100, 100, 101, 100, 100, 101, Color.Blue);
    immediateState.flush();
  }

  stage.materialize(0, 16);
  uploadImmediateTriangle(); // Initialize the immediate program and its shared buffers.
  stage.materialize(16, 16); // Retained execution leaves its private buffers bound.
  expect(context.renderStatistics.retainedInstructionUploadCount, 0);

  uploadImmediateTriangle();
  stage.materialize(32, 16);
  expect(context.renderStatistics.retainedInstructionUploadCount, 0);

  final pixel = Uint8List(4);
  context.rawContext.readPixels(8, 8, 1, 1, WebGL.RGBA, WebGL.UNSIGNED_BYTE, pixel.toJS);
  expect(pixel, [255, 0, 0, 255]);
  stage.dispose();
}
