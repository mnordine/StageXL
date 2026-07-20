part of '../engine.dart';

/// A retained command that can be uploaded and executed by an [InstructionPipe].
abstract interface class RenderInstruction {
  String get renderPipeId;
  bool get canBundle;
}

/// Converts a renderable into retained render instructions.
abstract interface class RenderPipe<TRenderable> {
  void addRenderable(TRenderable renderable, InstructionSet instructionSet);
  void updateRenderable(TRenderable renderable);
  bool validateRenderable(TRenderable renderable);
}

/// Owns backend resources and executes instructions produced by a [RenderPipe].
abstract interface class InstructionPipe<TInstruction extends RenderInstruction> {
  void upload(InstructionSet instructionSet);
  void execute(TInstruction instruction);
}

/// A reusable list of render instructions and the renderables that produced them.
///
/// The backing lists retain their capacity when [reset] is called. Consumers must
/// use [instructionSize] and [renderableSize] rather than the backing list lengths.
class InstructionSet {
  static var _nextUid = 0;

  final int uid = _nextUid++;
  final List<RenderInstruction?> instructions = [];
  final List<Object?> renderables = [];
  var instructionSize = 0;
  var renderableSize = 0;
  var buildCount = 0;
  var reuseCount = 0;

  void add(RenderInstruction instruction) {
    if (instructionSize == instructions.length) {
      instructions.add(instruction);
    } else {
      instructions[instructionSize] = instruction;
    }
    instructionSize++;
  }

  void addRenderable(Object renderable) {
    if (renderableSize == renderables.length) {
      renderables.add(renderable);
    } else {
      renderables[renderableSize] = renderable;
    }
    renderableSize++;
  }

  void reset() {
    instructionSize = 0;
    renderableSize = 0;
  }
}
