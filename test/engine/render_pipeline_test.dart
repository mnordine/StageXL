@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

class _Instruction implements RenderInstruction {
  final int value;

  _Instruction(this.value);

  @override
  bool get canBundle => true;

  @override
  String get renderPipeId => 'test';
}

void main() {
  test('InstructionSet reuses its instruction and renderable storage', () {
    final instructionSet = InstructionSet();
    final firstInstruction = _Instruction(1);
    final firstRenderable = Object();

    instructionSet
      ..add(firstInstruction)
      ..addRenderable(firstRenderable);

    expect(instructionSet.instructionSize, 1);
    expect(instructionSet.renderableSize, 1);
    expect(instructionSet.instructions, hasLength(1));
    expect(instructionSet.renderables, hasLength(1));

    instructionSet.reset();
    final secondInstruction = _Instruction(2);
    final secondRenderable = Object();
    instructionSet
      ..add(secondInstruction)
      ..addRenderable(secondRenderable);

    expect(instructionSet.instructions, hasLength(1));
    expect(instructionSet.renderables, hasLength(1));
    expect(instructionSet.instructions.single, same(secondInstruction));
    expect(instructionSet.renderables.single, same(secondRenderable));
  });
}
