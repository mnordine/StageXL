@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

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
}
