part of '../engine.dart';

/// Identifies the [RenderPipe] responsible for a scene renderable.
final class RenderPipeId<T extends RenderObject> {
  final String name;

  const RenderPipeId(this.name);

  @override
  String toString() => 'RenderPipeId($name)';
}

/// Backend-neutral access used by scene [RenderPipe] implementations.
///
/// A render pipe describes what should be rendered. It cannot access WebGL or
/// WebGPU systems and therefore cannot encode commands during display-tree
/// traversal.
final class RenderBuildContext {
  final RenderState _renderState;

  RenderBuildContext._(this._renderState);

  num get currentTime => _renderState.currentTime;
  num get deltaTime => _renderState.deltaTime;
  Matrix get globalMatrix => _renderState.globalMatrix;
  double get globalAlpha => _renderState.globalAlpha;
  double get globalColorScaleR => _renderState.globalColorScaleR;
  double get globalColorScaleG => _renderState.globalColorScaleG;
  double get globalColorScaleB => _renderState.globalColorScaleB;
  double get globalColorScaleA => _renderState.globalColorScaleA;
  BlendMode get globalBlendMode => _renderState.globalBlendMode;

  void addRenderable(RenderObject renderable) => _renderState.renderObject(renderable);

  void addTextureQuad(
    RenderTextureQuad quad, {
    num red = 1,
    num green = 1,
    num blue = 1,
    num alpha = 1,
    BlendMode? blendMode,
  }) =>
      _renderState.renderTextureQuadTinted(quad, red, green, blue, alpha, blendMode: blendMode);

  void addTextureMesh(
    RenderTexture texture,
    Int16List indices,
    Float32List vertices, {
    num red = 1,
    num green = 1,
    num blue = 1,
    num alpha = 1,
    BlendMode? blendMode,
  }) =>
      _renderState.renderTextureMeshTinted(
        texture,
        indices,
        vertices,
        red,
        green,
        blue,
        alpha,
        blendMode: blendMode,
      );

  void addTextureMapping(RenderTexture texture, Matrix mappingMatrix, Int16List indices, Float32List vertices) =>
      _renderState.renderTextureMapping(texture, mappingMatrix, indices, vertices);

  void addTriangle(num x1, num y1, num x2, num y2, num x3, num y3, int color) =>
      _renderState.renderTriangle(x1, y1, x2, y2, x3, y3, color);

  void addTriangleMesh(Int16List indices, Float32List vertices, int color) =>
      _renderState.renderTriangleMesh(indices, vertices, color);

  void beginMask(RenderMask mask) => _renderState._renderContext._beginRenderMask(_renderState, mask);

  void endMask(RenderMask mask) => _renderState._renderContext._endRenderMask(_renderState, mask);

  void push(Matrix matrix, num alpha, [BlendMode? blendMode]) => _renderState.push(matrix, alpha, blendMode);

  void pop() => _renderState.pop();
}

/// Converts a scene renderable into backend-neutral render operations.
abstract interface class RenderPipe<T extends RenderObject> {
  void addRenderable(T renderable, RenderBuildContext context);
}

/// Lets an extension install its pipe lazily into the renderer that encounters it.
abstract interface class RenderPipeProvider {
  void registerRenderPipe(RenderPipeRegistry registry);
}

/// Registry used to resolve scene renderables to [RenderPipe] instances.
final class RenderPipeRegistry {
  final _pipes = <RenderPipeId, _RenderPipeEntry>{};

  RenderPipeRegistry() {
    register(RenderObject.defaultRenderPipeId, const _DefaultRenderPipe());
  }

  bool register<T extends RenderObject>(RenderPipeId<T> id, RenderPipe<T> pipe) {
    final previous = _pipes[id]?.pipe;
    if (previous != null && !identical(previous, pipe)) {
      throw StateError('A render pipe is already registered for ${id.name}.');
    }
    _pipes[id] = _TypedRenderPipeEntry(pipe);
    return true;
  }

  void copyFrom(RenderPipeRegistry other) {
    _pipes
      ..clear()
      ..addAll(other._pipes);
  }

  void addRenderable(RenderObject renderable, RenderBuildContext context) {
    final id = renderable.renderPipeId;
    var entry = _pipes[id];
    if (entry == null) {
      if (renderable case final RenderPipeProvider provider) {
        provider.registerRenderPipe(this);
        entry = _pipes[id];
      }
    }
    if (entry == null) throw StateError('No render pipe is registered for ${id.name}.');
    entry.addRenderable(renderable, context);
  }
}

abstract interface class _RenderPipeEntry {
  RenderPipe get pipe;

  void addRenderable(RenderObject renderable, RenderBuildContext context);
}

final class _TypedRenderPipeEntry<T extends RenderObject> implements _RenderPipeEntry {
  @override
  final RenderPipe<T> pipe;

  _TypedRenderPipeEntry(this.pipe);

  @override
  void addRenderable(RenderObject renderable, RenderBuildContext context) {
    if (renderable case final T typedRenderable) {
      pipe.addRenderable(typedRenderable, context);
      return;
    }
    throw StateError(
      'Renderable ${renderable.runtimeType} does not match pipe ${renderable.renderPipeId.name} ($T).',
    );
  }
}

/// Marks a scene subtree as an independently retained render group.
abstract interface class RenderGroupRenderable {
  bool get isRenderGroup;
}

final class _DefaultRenderPipe implements RenderPipe<RenderObject> {
  const _DefaultRenderPipe();

  @override
  void addRenderable(RenderObject renderable, RenderBuildContext context) =>
      renderable.renderLegacy(context._renderState);
}

/// A retained command that can be uploaded and executed by an [InstructionPipe].
abstract interface class RenderInstruction {
  InstructionPipeId get instructionPipeId;
}

/// Identifies the [InstructionPipe] responsible for one retained instruction type.
final class InstructionPipeId<T extends RenderInstruction> {
  final String name;

  const InstructionPipeId(this.name);

  @override
  String toString() => 'InstructionPipeId($name)';
}

/// A typed value retained alongside an [InstructionSet].
abstract base class RetainedSlot {
  const RetainedSlot();
}

/// Adds or updates backend-owned retained instructions.
abstract interface class InstructionBuilderPipe<T extends RetainedSlot> {
  void addRenderable(T renderable, InstructionSet instructionSet);
  void updateRenderable(T renderable);
  bool validateRenderable(T renderable);
}

/// Owns backend resources and executes instructions built during traversal.
abstract interface class InstructionPipe<T extends RenderInstruction> {
  InstructionPipeId<T> get id;

  void upload(T instruction);
  void execute(T instruction);
  void dispose(T instruction);
}

/// Resolves retained instructions to strongly typed upload and execution pipes.
final class InstructionPipeRegistry {
  final _pipes = <InstructionPipeId, _InstructionPipeEntry>{};

  bool register<T extends RenderInstruction>(InstructionPipe<T> pipe) {
    final id = pipe.id;
    final previous = _pipes[id];
    if (previous != null && !identical(previous.pipe, pipe)) {
      throw StateError('An instruction pipe is already registered for ${id.name}.');
    }
    _pipes[id] = _TypedInstructionPipeEntry(pipe);
    return true;
  }

  void upload(RenderInstruction instruction) => _resolve(instruction).upload(instruction);

  void execute(RenderInstruction instruction) => _resolve(instruction).execute(instruction);

  void dispose(RenderInstruction instruction) => _resolve(instruction).dispose(instruction);

  _InstructionPipeEntry _resolve(RenderInstruction instruction) {
    final id = instruction.instructionPipeId;
    return _pipes[id] ?? (throw StateError('No instruction pipe is registered for ${id.name}.'));
  }
}

abstract interface class _InstructionPipeEntry {
  InstructionPipe get pipe;

  void upload(RenderInstruction instruction);
  void execute(RenderInstruction instruction);
  void dispose(RenderInstruction instruction);
}

final class _TypedInstructionPipeEntry<T extends RenderInstruction> implements _InstructionPipeEntry {
  @override
  final InstructionPipe<T> pipe;

  _TypedInstructionPipeEntry(this.pipe);

  @override
  void upload(RenderInstruction instruction) => pipe.upload(_cast(instruction));

  @override
  void execute(RenderInstruction instruction) => pipe.execute(_cast(instruction));

  @override
  void dispose(RenderInstruction instruction) => pipe.dispose(_cast(instruction));

  T _cast(RenderInstruction instruction) {
    if (instruction case final T typedInstruction) return typedInstruction;
    throw StateError(
      'Instruction ${instruction.runtimeType} does not match pipe ${pipe.id.name} ($T).',
    );
  }
}

/// A reusable list of render instructions and the typed slots that produced them.
///
/// The backing lists retain their capacity when [reset] is called. Consumers must
/// use [instructionCount] and [slotCount] rather than the retained capacities.
final class InstructionSet {
  static var _nextUid = 0;

  final int uid = _nextUid++;
  final _instructions = <RenderInstruction?>[];
  final _slots = <RetainedSlot?>[];
  var _instructionCount = 0;
  var _slotCount = 0;
  var _buildCount = 0;
  var _reuseCount = 0;

  int get instructionCount => _instructionCount;
  int get slotCount => _slotCount;
  int get instructionCapacity => _instructions.length;
  int get slotCapacity => _slots.length;
  int get buildCount => _buildCount;
  int get reuseCount => _reuseCount;

  RenderInstruction instructionAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', _instructionCount);
    return _instructions[index]!;
  }

  RetainedSlot slotAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', _slotCount);
    return _slots[index]!;
  }

  void addInstruction(RenderInstruction instruction) {
    if (_instructionCount == _instructions.length) {
      _instructions.add(instruction);
    } else {
      _instructions[_instructionCount] = instruction;
    }
    _instructionCount++;
  }

  void addSlot(RetainedSlot slot) {
    if (_slotCount == _slots.length) {
      _slots.add(slot);
    } else {
      _slots[_slotCount] = slot;
    }
    _slotCount++;
  }

  void reset() {
    _instructionCount = 0;
    _slotCount = 0;
  }
}
