part of '../engine.dart';

/// Retains backend-neutral draw operations for Canvas2D and WebGL.
///
/// WebGPU uses its specialized instruction system because its upload and command
/// encoding phases own additional GPU resources.
final class _RetainedInstructionSystem {
  final RenderContext renderContext;
  final _instructionSets = Expando<InstructionSet>('StageXL retained render plans');
  final _instructionPipes = InstructionPipeRegistry();
  late final _commandPipe = _RetainedCommandPipe(renderContext);
  late InstructionSet _instructionSet;
  var _cursor = 0;
  var _oldInstructionCount = 0;
  var _structureChanged = true;
  var _isCollecting = false;

  _RetainedInstructionSystem(this.renderContext) {
    _instructionPipes.register(_commandPipe);
  }

  bool get isCollecting => _isCollecting;

  void collect(RenderState renderState, RenderObject renderObject) {
    _instructionSet = _instructionSets[renderObject] ??= InstructionSet();
    _oldInstructionCount = _instructionSet.instructionCount;
    _cursor = 0;
    _structureChanged = _oldInstructionCount == 0;
    _isCollecting = true;
    renderState.renderObject(renderObject);
    _isCollecting = false;

    if (_cursor != _oldInstructionCount) _structureChanged = true;
    for (var i = _cursor; i < _oldInstructionCount; i++) {
      final instruction = _instructionSet._instructions[i];
      if (instruction != null) _instructionPipes.dispose(instruction);
      _instructionSet._instructions[i] = null;
    }
    _instructionSet._instructionCount = _cursor;

    final statistics = renderContext.renderStatistics;
    statistics.retainedInstructionCount += _cursor;
    if (_structureChanged) {
      _instructionSet._buildCount++;
      statistics.retainedInstructionBuildCount++;
    } else {
      _instructionSet._reuseCount++;
      statistics.retainedInstructionReuseCount++;
    }
  }

  void execute() {
    for (var i = 0; i < _instructionSet.instructionCount; i++) {
      _instructionPipes.upload(_instructionSet.instructionAt(i));
    }
    for (var i = 0; i < _instructionSet.instructionCount; i++) {
      _instructionPipes.execute(_instructionSet.instructionAt(i));
    }
    renderContext.flush();
  }

  void recordTextureQuad(
    RenderState state,
    RenderTextureQuad quad, [
    num red = 1,
    num green = 1,
    num blue = 1,
    num alpha = 1,
  ]) {
    final old = _instructionAtCursor;
    final command = old is _RetainedTextureQuadCommand
        ? old
        : _RetainedTextureQuadCommand(renderContext);
    if (!identical(old, command)) _replace(command);
    command.update(state, quad, red, green, blue, alpha);
    _cursor++;
  }

  void recordTextureMesh(
    RenderState state,
    RenderTexture texture,
    Int16List indices,
    Float32List vertices, [
    num red = 1,
    num green = 1,
    num blue = 1,
    num alpha = 1,
  ]) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedTextureMeshCommand && old.matches(texture, indices, vertices);
    final command = reusable ? old : _RetainedTextureMeshCommand(renderContext, texture, indices, vertices);
    if (!reusable) _replace(command);
    command.update(state, texture, indices, vertices, red, green, blue, alpha);
    _cursor++;
  }

  void recordTextureMapping(
    RenderState state,
    RenderTexture texture,
    Matrix mappingMatrix,
    Int16List indices,
    Float32List vertices,
  ) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedTextureMappingCommand && old.matches(texture, indices, vertices);
    final command = reusable ? old : _RetainedTextureMappingCommand(renderContext, texture, indices, vertices);
    if (!reusable) _replace(command);
    command.update(state, texture, mappingMatrix, indices, vertices);
    _cursor++;
  }

  void recordTriangle(
    RenderState state,
    num x1,
    num y1,
    num x2,
    num y2,
    num x3,
    num y3,
    int color,
  ) {
    final old = _instructionAtCursor;
    final command = old is _RetainedTriangleCommand ? old : _RetainedTriangleCommand(renderContext);
    if (!identical(old, command)) _replace(command);
    command.update(state, x1, y1, x2, y2, x3, y3, color);
    _cursor++;
  }

  void recordTriangleMesh(RenderState state, Int16List indices, Float32List vertices, int color) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedTriangleMeshCommand && old.matches(indices, vertices);
    final command = reusable ? old : _RetainedTriangleMeshCommand(renderContext, indices, vertices);
    if (!reusable) _replace(command);
    command.update(state, indices, vertices, color);
    _cursor++;
  }

  void recordMask(RenderState state, RenderMask mask, {required bool begin}) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedMaskCommand && old.begin == begin && identical(old.mask, mask);
    final command = reusable ? old : _RetainedMaskCommand(renderContext, mask, begin);
    if (!reusable) _replace(command);
    command.updateState(state);
    _cursor++;
  }

  void recordFilteredQuad(RenderState state, RenderTextureQuad quad, List<RenderFilter> filters) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedFilteredQuadCommand && old.matches(filters);
    final command = reusable ? old : _RetainedFilteredQuadCommand(renderContext);
    if (!reusable) _replace(command);
    command.update(state, quad, filters);
    _cursor++;
  }

  void recordFilteredObject(RenderState state, RenderObject renderObject) {
    final filters = renderObject.filters;
    final old = _instructionAtCursor;
    final reusable = old is _RetainedFilteredObjectCommand &&
        identical(old.renderObject, renderObject) &&
        old.matches(filters);
    final command = reusable ? old : _RetainedFilteredObjectCommand(renderContext);
    if (!reusable) _replace(command);
    command.update(state, renderObject, filters);
    _cursor++;
  }

  void recordProjection(Matrix3D matrix) {
    final old = _instructionAtCursor;
    final command = old is _RetainedProjectionCommand ? old : _RetainedProjectionCommand(renderContext);
    if (!identical(old, command)) _replace(command);
    command.matrix.copyFrom(matrix);
    _cursor++;
  }

  RenderInstruction? get _instructionAtCursor =>
      _cursor < _oldInstructionCount ? _instructionSet._instructions[_cursor] : null;

  void _replace(_RetainedCommand command) {
    if (_cursor == _instructionSet._instructions.length) {
      _instructionSet._instructions.add(command);
    } else {
      final old = _instructionSet._instructions[_cursor];
      if (old != null) _instructionPipes.dispose(old);
      _instructionSet._instructions[_cursor] = command;
    }
    _structureChanged = true;
  }
}

abstract base class _RetainedCommand implements RenderInstruction {
  static const pipeId = InstructionPipeId<_RetainedCommand>('retained.command');

  final RenderState state;

  _RetainedCommand(RenderContext renderContext) : state = RenderState(renderContext);

  @override
  InstructionPipeId<_RetainedCommand> get instructionPipeId => pipeId;

  void updateState(RenderState source) {
    state
      ..copyFrom(source)
      ..currentTime = source.currentTime
      ..deltaTime = source.deltaTime;
  }

  void execute(RenderContext renderContext);
}

final class _RetainedCommandPipe implements InstructionPipe<_RetainedCommand> {
  final RenderContext renderContext;

  _RetainedCommandPipe(this.renderContext);

  @override
  InstructionPipeId<_RetainedCommand> get id => _RetainedCommand.pipeId;

  @override
  void upload(_RetainedCommand instruction) {}

  @override
  void execute(_RetainedCommand instruction) => instruction.execute(renderContext);

  @override
  void dispose(_RetainedCommand instruction) {}
}

final class _RetainedTextureQuadCommand extends _RetainedCommand {
  late RenderTextureQuad quad;
  var red = 1.0;
  var green = 1.0;
  var blue = 1.0;
  var alpha = 1.0;

  _RetainedTextureQuadCommand(super.renderContext);

  void update(RenderState source, RenderTextureQuad quad, num red, num green, num blue, num alpha) {
    updateState(source);
    this.quad = quad;
    this.red = red.toDouble();
    this.green = green.toDouble();
    this.blue = blue.toDouble();
    this.alpha = alpha.toDouble();
  }

  @override
  void execute(RenderContext renderContext) =>
      renderContext.renderTextureQuadTinted(state, quad, red, green, blue, alpha);
}

final class _RetainedTextureMeshCommand extends _RetainedCommand {
  RenderTexture texture;
  final Int16List indices;
  final Float32List vertices;
  var red = 1.0;
  var green = 1.0;
  var blue = 1.0;
  var alpha = 1.0;

  _RetainedTextureMeshCommand(
    super.renderContext,
    this.texture,
    Int16List sourceIndices,
    Float32List sourceVertices,
  )   : indices = Int16List(sourceIndices.length),
        vertices = Float32List(sourceVertices.length);

  bool matches(RenderTexture texture, Int16List indices, Float32List vertices) =>
      identical(this.texture, texture) &&
      this.indices.length == indices.length &&
      this.vertices.length == vertices.length;

  void update(
    RenderState source,
    RenderTexture texture,
    Int16List sourceIndices,
    Float32List sourceVertices,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    updateState(source);
    this.texture = texture;
    indices.setAll(0, sourceIndices);
    vertices.setAll(0, sourceVertices);
    this.red = red.toDouble();
    this.green = green.toDouble();
    this.blue = blue.toDouble();
    this.alpha = alpha.toDouble();
  }

  @override
  void execute(RenderContext renderContext) =>
      renderContext.renderTextureMeshTinted(state, texture, indices, vertices, red, green, blue, alpha);
}

final class _RetainedTextureMappingCommand extends _RetainedCommand {
  RenderTexture texture;
  final mappingMatrix = Matrix.fromIdentity();
  final Int16List indices;
  final Float32List vertices;

  _RetainedTextureMappingCommand(
    super.renderContext,
    this.texture,
    Int16List sourceIndices,
    Float32List sourceVertices,
  )   : indices = Int16List(sourceIndices.length),
        vertices = Float32List(sourceVertices.length);

  bool matches(RenderTexture texture, Int16List indices, Float32List vertices) =>
      identical(this.texture, texture) &&
      this.indices.length == indices.length &&
      this.vertices.length == vertices.length;

  void update(
    RenderState source,
    RenderTexture texture,
    Matrix sourceMappingMatrix,
    Int16List sourceIndices,
    Float32List sourceVertices,
  ) {
    updateState(source);
    this.texture = texture;
    mappingMatrix.copyFrom(sourceMappingMatrix);
    indices.setAll(0, sourceIndices);
    vertices.setAll(0, sourceVertices);
  }

  @override
  void execute(RenderContext renderContext) =>
      renderContext.renderTextureMapping(state, texture, mappingMatrix, indices, vertices);
}

final class _RetainedTriangleCommand extends _RetainedCommand {
  var x1 = 0.0;
  var y1 = 0.0;
  var x2 = 0.0;
  var y2 = 0.0;
  var x3 = 0.0;
  var y3 = 0.0;
  var color = 0;

  _RetainedTriangleCommand(super.renderContext);

  void update(RenderState source, num x1, num y1, num x2, num y2, num x3, num y3, int color) {
    updateState(source);
    this.x1 = x1.toDouble();
    this.y1 = y1.toDouble();
    this.x2 = x2.toDouble();
    this.y2 = y2.toDouble();
    this.x3 = x3.toDouble();
    this.y3 = y3.toDouble();
    this.color = color;
  }

  @override
  void execute(RenderContext renderContext) => renderContext.renderTriangle(state, x1, y1, x2, y2, x3, y3, color);
}

final class _RetainedTriangleMeshCommand extends _RetainedCommand {
  final Int16List indices;
  final Float32List vertices;
  var color = 0;

  _RetainedTriangleMeshCommand(super.renderContext, Int16List sourceIndices, Float32List sourceVertices)
      : indices = Int16List(sourceIndices.length),
        vertices = Float32List(sourceVertices.length);

  bool matches(Int16List indices, Float32List vertices) =>
      this.indices.length == indices.length && this.vertices.length == vertices.length;

  void update(RenderState source, Int16List sourceIndices, Float32List sourceVertices, int color) {
    updateState(source);
    indices.setAll(0, sourceIndices);
    vertices.setAll(0, sourceVertices);
    this.color = color;
  }

  @override
  void execute(RenderContext renderContext) => renderContext.renderTriangleMesh(state, indices, vertices, color);
}

final class _RetainedMaskCommand extends _RetainedCommand {
  final RenderMask mask;
  final bool begin;

  _RetainedMaskCommand(super.renderContext, this.mask, this.begin);

  @override
  void execute(RenderContext renderContext) =>
      begin ? renderContext.beginRenderMask(state, mask) : renderContext.endRenderMask(state, mask);
}

abstract base class _RetainedFilterCommand extends _RetainedCommand {
  final filters = <RenderFilter>[];

  _RetainedFilterCommand(super.renderContext);

  bool matches(List<RenderFilter> other) {
    if (filters.length != other.length) return false;
    for (var i = 0; i < filters.length; i++) {
      if (!identical(filters[i], other[i])) return false;
    }
    return true;
  }

  void updateFilters(List<RenderFilter> source) {
    filters
      ..clear()
      ..addAll(source);
  }
}

final class _RetainedFilteredQuadCommand extends _RetainedFilterCommand {
  late RenderTextureQuad quad;

  _RetainedFilteredQuadCommand(super.renderContext);

  void update(RenderState source, RenderTextureQuad quad, List<RenderFilter> filters) {
    updateState(source);
    this.quad = quad;
    updateFilters(filters);
  }

  @override
  void execute(RenderContext renderContext) => renderContext.renderTextureQuadFiltered(state, quad, filters);
}

final class _RetainedFilteredObjectCommand extends _RetainedFilterCommand {
  late RenderObject renderObject;

  _RetainedFilteredObjectCommand(super.renderContext);

  void update(RenderState source, RenderObject renderObject, List<RenderFilter> filters) {
    updateState(source);
    this.renderObject = renderObject;
    updateFilters(filters);
  }

  @override
  void execute(RenderContext renderContext) => renderContext.renderObjectFiltered(state, renderObject);
}

final class _RetainedProjectionCommand extends _RetainedCommand {
  final matrix = Matrix3D.fromIdentity();

  _RetainedProjectionCommand(super.renderContext);

  @override
  void execute(RenderContext renderContext) => (renderContext as RenderContextWebGL).activateProjectionMatrix(matrix);
}
