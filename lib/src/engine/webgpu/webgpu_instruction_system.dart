part of '../../engine.dart';

class _WebGpuInstructionSystem {
  final RenderContextWebGPU renderContext;
  final _renderGroups = Expando<InstructionSet>('StageXL WebGPU render groups');
  final _collectionStates = <_WebGpuCollectionState>[];
  final _groupStack = <RenderObject>[];
  var _collectionDepth = 0;
  var instructionSet = InstructionSet();
  RenderObject? _rootRenderObject;
  late final _scenePipe = _WebGpuScenePipe();
  late final _batchPipe = _WebGpuBatchPipe(renderContext, _takeClearColor);
  late final _maskPipe = _WebGpuMaskPipe(renderContext, _ensureClear);
  late final _filterPipe = _WebGpuFilterPipe(renderContext, _ensureClear);
  late final _projectionPipe = _WebGpuProjectionPipe(renderContext, _ensureClear);
  late final _drawPipe = _WebGpuDrawPipe(renderContext, _ensureClear);
  late final _renderGroupPipe = _WebGpuRenderGroupPipe(this);
  final _instructionPipes = InstructionPipeRegistry();
  var _mappedVertices = Float32List(16);
  final _solidIndices = Int16List.fromList([0, 1, 2]);
  final _solidVertices = Float32List(12);
  var _instructionCursor = 0;
  var _renderableCursor = 0;
  var _oldInstructionSize = 0;
  var _oldRenderableSize = 0;
  var _structureChanged = true;
  var _isCollecting = false;
  _WebGpuBatchInstruction? _activeBatch;
  List<num>? _pendingClearColor;

  _WebGpuInstructionSystem(this.renderContext) {
    _instructionPipes
      ..register(_batchPipe)
      ..register(_maskPipe)
      ..register(_filterPipe)
      ..register(_projectionPipe)
      ..register(_drawPipe)
      ..register(_renderGroupPipe);
  }

  bool get isCollecting => _isCollecting;

  void collect(RenderState renderState, RenderObject renderObject) {
    _rootRenderObject = renderObject;
    instructionSet = _renderGroups[renderObject] ??= InstructionSet();
    _beginCollect();
    renderState.renderObject(renderObject);
    _endCollect();

    _recordCollectionStatistics(instructionSet, _structureChanged);
  }

  void execute() {
    _upload(instructionSet);
    _pendingClearColor = renderContext.consumeClearColor();
    _execute(instructionSet);
    _ensureClear();
  }

  void release(RenderObject renderObject) {
    if (_isCollecting) throw StateError('Cannot release a retained render plan during collection.');
    final instructions = _renderGroups[renderObject];
    if (instructions == null) return;
    _disposeInstructionSet(instructions);
    _clearInstructionSet(instructions);
    _renderGroups[renderObject] = null;
    if (identical(instructionSet, instructions)) instructionSet = InstructionSet();
    if (identical(_rootRenderObject, renderObject)) _rootRenderObject = null;
  }

  void dispose() {
    if (_isCollecting) throw StateError('Cannot dispose WebGPU instructions during collection.');
    final rootRenderObject = _rootRenderObject;
    if (rootRenderObject != null) {
      release(rootRenderObject);
    } else if (instructionSet.instructionCount != 0 || instructionSet.slotCount != 0) {
      _disposeInstructionSet(instructionSet);
      _clearInstructionSet(instructionSet);
      instructionSet = InstructionSet();
    }
    _collectionStates.clear();
    _groupStack.clear();
    _activeBatch = null;
    _pendingClearColor = null;
  }

  void _upload(InstructionSet instructions) {
    for (var i = 0; i < instructions.instructionCount; i++) {
      _instructionPipes.upload(instructions.instructionAt(i));
    }
  }

  void _execute(InstructionSet instructions) {
    for (var i = 0; i < instructions.instructionCount; i++) {
      _instructionPipes.execute(instructions.instructionAt(i));
    }
  }

  void _beginCollect() {
    _oldInstructionSize = instructionSet.instructionCount;
    _oldRenderableSize = instructionSet.slotCount;
    _instructionCursor = 0;
    _renderableCursor = 0;
    _structureChanged = _oldInstructionSize == 0;
    _activeBatch = null;
    _isCollecting = true;
  }

  void _endCollect() {
    flushBatch();
    _isCollecting = false;
    if (_instructionCursor != _oldInstructionSize || _renderableCursor != _oldRenderableSize) {
      _structureChanged = true;
    }
    for (var i = _instructionCursor; i < _oldInstructionSize; i++) {
      _disposeInstruction(instructionSet._instructions[i]);
      instructionSet._instructions[i] = null;
    }
    instructionSet._instructionCount = _instructionCursor;
    instructionSet._slotCount = _renderableCursor;
  }

  void beginRenderable(RenderState renderState, RenderObject renderable) {
    if (!_isCollecting) return;
    if (!identical(renderable, _rootRenderObject) &&
        renderable is RenderGroupRenderable &&
        (renderable as RenderGroupRenderable).isRenderGroup) {
      _beginRenderGroup(renderable, renderState.globalMatrix);
      renderState.globalMatrix.identity();
    }
    final old = _renderableCursor < _oldRenderableSize ? instructionSet._slots[_renderableCursor] : null;
    final reusable = old is _WebGpuSceneRenderable &&
        identical(old.renderable, renderable) &&
        old.pipeId == renderable.renderPipeId &&
        old.structureVersion == renderable.renderStructureVersion &&
        _scenePipe.validateSlot(old);
    if (reusable) {
      old.update();
      _scenePipe.updateSlot(old);
      _renderableCursor++;
    } else {
      _addSlot(_WebGpuSceneRenderable(renderable), _scenePipe);
    }
  }

  void endRenderable(RenderObject renderable) {
    if (_groupStack.isNotEmpty && identical(_groupStack.last, renderable)) _endRenderGroup();
  }

  void _beginRenderGroup(RenderObject renderable, Matrix groupMatrix) {
    flushBatch();
    final old = _instructionAtCursor;
    final groupInstructions = _renderGroups[renderable] ??= InstructionSet();
    final reusable = old is _WebGpuRenderGroupInstruction && identical(old.renderable, renderable);
    final instruction = reusable ? old : _WebGpuRenderGroupInstruction(renderable, groupInstructions);
    if (!reusable) _replaceInstruction(instruction);
    instruction.matrix.copyFrom(groupMatrix);
    _instructionCursor++;

    _pushCollectionState();
    _groupStack.add(renderable);
    instructionSet = groupInstructions;
    _beginCollect();
  }

  void _endRenderGroup() {
    _endCollect();
    _recordCollectionStatistics(instructionSet, _structureChanged);
    _restoreCollectionState(_collectionStates[--_collectionDepth]);
    _groupStack.removeLast();
    _isCollecting = true;
  }

  void _pushCollectionState() {
    final state = _collectionDepth == _collectionStates.length
        ? (_WebGpuCollectionState()..capture(this))
        : (_collectionStates[_collectionDepth]..capture(this));
    if (_collectionDepth == _collectionStates.length) _collectionStates.add(state);
    _collectionDepth++;
  }

  void _restoreCollectionState(_WebGpuCollectionState state) {
    instructionSet = state.instructionSet;
    _instructionCursor = state.instructionCursor;
    _renderableCursor = state.renderableCursor;
    _oldInstructionSize = state.oldInstructionSize;
    _oldRenderableSize = state.oldRenderableSize;
    _structureChanged = state.structureChanged;
    _activeBatch = state.activeBatch;
  }

  void _recordCollectionStatistics(InstructionSet instructions, bool structureChanged) {
    final statistics = renderContext.renderStatistics;
    statistics.webgpuRenderableCount += instructions.slotCount;
    if (structureChanged) {
      instructions._buildCount++;
      statistics.webgpuInstructionBuildCount++;
    } else {
      instructions._reuseCount++;
      statistics.webgpuInstructionReuseCount++;
    }
  }

  void flushBatch() {
    final batch = _activeBatch;
    if (batch == null) return;
    if (batch.finishUpdate()) _structureChanged = true;
    _instructionCursor++;
    _activeBatch = null;
  }

  void recordTextureQuad(
    RenderState state,
    RenderTextureQuad quad, [
    num red = 1,
    num green = 1,
    num blue = 1,
    num alpha = 1,
  ]) {
    recordTextureMesh(
      state,
      quad.renderTexture,
      quad.hasCustomVertices ? quad.ixList : quad.ixListQuad,
      quad.hasCustomVertices ? quad.vxList : quad.vxListQuad,
      red,
      green,
      blue,
      alpha,
    );
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
    final batch = _getBatch();
    final (renderable, rebuilt) =
        batch.addRenderable(state, texture, indices, vertices, red, green, blue, alpha);
    final reusable = !rebuilt &&
        _renderableCursor < _oldRenderableSize &&
        identical(instructionSet._slots[_renderableCursor], renderable) &&
        _batchPipe.validateSlot(renderable);
    if (reusable) {
      _batchPipe.updateSlot(renderable);
      _renderableCursor++;
    } else {
      _addSlot(renderable, _batchPipe);
    }
    if (rebuilt) {
      _structureChanged = true;
    }
  }

  void recordTextureMapping(
    RenderState state,
    RenderTexture texture,
    Matrix mappingMatrix,
    Int16List indices,
    Float32List vertices,
  ) {
    final vertexCount = vertices.length >> 1;
    if (vertexCount == 0 || indices.isEmpty) return;
    _ensureMappedVertexCapacity(vertexCount * 4);
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 2) {
      final x = vertices[sourceIndex + 0];
      final y = vertices[sourceIndex + 1];
      final targetIndex = i * 4;
      _mappedVertices[targetIndex + 0] = x;
      _mappedVertices[targetIndex + 1] = y;
      _mappedVertices[targetIndex + 2] = mappingMatrix.tx + mappingMatrix.a * x + mappingMatrix.c * y;
      _mappedVertices[targetIndex + 3] = mappingMatrix.ty + mappingMatrix.b * x + mappingMatrix.d * y;
    }
    recordTextureMesh(state, texture, indices, Float32List.view(_mappedVertices.buffer, 0, vertexCount * 4));
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
    final vertices = _solidVertices;
    vertices[0] = x1.toDouble();
    vertices[1] = y1.toDouble();
    vertices[4] = x2.toDouble();
    vertices[5] = y2.toDouble();
    vertices[8] = x3.toDouble();
    vertices[9] = y3.toDouble();
    recordTriangleMesh(state, _solidIndices, vertices, color, mapped: true);
  }

  void recordTriangleMesh(
    RenderState state,
    Int16List indices,
    Float32List vertices,
    int color, {
    bool mapped = false,
  }) {
    final vertexCount = mapped ? vertices.length >> 2 : vertices.length >> 1;
    if (vertexCount == 0 || indices.isEmpty) return;
    if (!mapped) {
      _ensureMappedVertexCapacity(vertexCount * 4);
      for (var i = vertexCount - 1; i >= 0; i--) {
        _mappedVertices[i * 4 + 0] = vertices[i * 2 + 0];
        _mappedVertices[i * 4 + 1] = vertices[i * 2 + 1];
        _mappedVertices[i * 4 + 2] = 0;
        _mappedVertices[i * 4 + 3] = 0;
      }
      vertices = Float32List.view(_mappedVertices.buffer, 0, vertexCount * 4);
    }

    const inv255 = 1 / 255;
    recordTextureMesh(
      state,
      renderContext._getSolidFillTexture(),
      indices,
      vertices,
      colorGetR(color) * inv255,
      colorGetG(color) * inv255,
      colorGetB(color) * inv255,
      colorGetA(color) * inv255,
    );
  }

  void recordDrawOperation(RenderState state, RenderDrawOperation operation) {
    flushBatch();
    final old = _instructionAtCursor;
    final reusable = old is _WebGpuDrawInstruction && identical(old.operation, operation);
    final instruction = reusable ? old : _WebGpuDrawInstruction(renderContext, operation);
    if (!reusable) _replaceInstruction(instruction);
    instruction.state
      ..copyFrom(state)
      ..currentTime = state.currentTime
      ..deltaTime = state.deltaTime;
    _instructionCursor++;
  }

  void recordMask(RenderState state, RenderMask mask, {required bool begin}) {
    flushBatch();
    final old = _instructionAtCursor;
    final instruction = old is _WebGpuMaskInstruction && old.begin == begin && identical(old.mask, mask)
        ? old
        : _WebGpuMaskInstruction(renderContext, mask, begin);
    if (!identical(old, instruction)) _replaceInstruction(instruction);
    instruction.state
      ..copyFrom(state)
      ..currentTime = state.currentTime
      ..deltaTime = state.deltaTime;
    if (begin) instruction.captureMask();
    _instructionCursor++;
  }

  void recordFilteredQuad(
    RenderState state,
    RenderTextureQuad quad,
    List<RenderFilter> filters,
  ) {
    final colorScale = renderContext.filterSystem.tryGetBatchColorScale(filters);
    if (colorScale != null) {
      recordTextureMesh(
        state,
        quad.renderTexture,
        quad.hasCustomVertices ? quad.ixList : quad.ixListQuad,
        quad.hasCustomVertices ? quad.vxList : quad.vxListQuad,
        colorScale[0],
        colorScale[1],
        colorScale[2],
        colorScale[3],
      );
      return;
    }

    flushBatch();
    final old = _instructionAtCursor;
    final reusable = old is _WebGpuFilterInstruction && old.matchesQuad(quad, filters);
    final instruction = reusable ? old : _WebGpuFilterInstruction.quad(renderContext, quad, filters);
    if (!reusable) _replaceInstruction(instruction);
    instruction.updateQuad(state, quad, filters);
    _instructionCursor++;
  }

  void recordFilteredObject(RenderState state, RenderObject renderObject) {
    final filters = renderObject.filters;
    final colorScale = renderContext.filterSystem.tryGetBatchColorScale(filters);
    if (colorScale != null) {
      state.pushColorScale(colorScale);
      state._addRenderable(renderObject);
      state.pop();
      return;
    }

    flushBatch();
    final old = _instructionAtCursor;
    final reusable = old is _WebGpuFilterInstruction && old.matchesObject(renderObject, filters);
    final instruction = reusable ? old : _WebGpuFilterInstruction.object(renderContext, renderObject, filters);
    if (!reusable) _replaceInstruction(instruction);
    instruction.updateObject(state, renderObject, filters);
    _instructionCursor++;
  }

  void recordProjection(Matrix3D matrix) {
    flushBatch();
    final old = _instructionAtCursor;
    final instruction = old is _WebGpuProjectionInstruction ? old : _WebGpuProjectionInstruction(renderContext);
    if (!identical(old, instruction)) _replaceInstruction(instruction);
    instruction.matrix.copyFrom(matrix);
    _instructionCursor++;
  }

  _WebGpuBatchInstruction _getBatch() {
    final active = _activeBatch;
    if (active != null) return active;
    final old = _instructionAtCursor;
    final batch = old is _WebGpuBatchInstruction ? old : _WebGpuBatchInstruction(renderContext);
    if (!identical(old, batch)) _replaceInstruction(batch);
    batch.beginUpdate();
    return _activeBatch = batch;
  }

  RenderInstruction? get _instructionAtCursor =>
      _instructionCursor < _oldInstructionSize ? instructionSet._instructions[_instructionCursor] : null;

  void _replaceInstruction(RenderInstruction instruction) {
    if (_instructionCursor == instructionSet._instructions.length) {
      instructionSet._instructions.add(instruction);
    } else {
      _disposeInstruction(instructionSet._instructions[_instructionCursor]);
      instructionSet._instructions[_instructionCursor] = instruction;
    }
    _structureChanged = true;
  }

  void _disposeInstruction(RenderInstruction? instruction) {
    if (instruction != null) _instructionPipes.dispose(instruction);
  }

  void _disposeInstructionSet(InstructionSet instructions) {
    for (var i = 0; i < instructions.instructionCount; i++) {
      _disposeInstruction(instructions.instructionAt(i));
    }
  }

  void _clearInstructionSet(InstructionSet instructions) {
    for (var i = 0; i < instructions.instructionCount; i++) {
      instructions._instructions[i] = null;
    }
    for (var i = 0; i < instructions.slotCount; i++) {
      instructions._slots[i] = null;
    }
    instructions
      .._instructionCount = 0
      .._slotCount = 0;
  }

  void _addSlot<TSlot extends RetainedSlot>(
    TSlot slot,
    RetainedSlotPipe<TSlot> pipe,
  ) {
    instructionSet._slotCount = _renderableCursor;
    pipe.addSlot(slot, instructionSet);
    _renderableCursor = instructionSet.slotCount;
    _structureChanged = true;
  }

  void _ensureMappedVertexCapacity(int length) {
    if (_mappedVertices.length >= length) return;
    _mappedVertices = Float32List(length * 2);
  }

  List<num>? _takeClearColor() {
    final color = _pendingClearColor;
    _pendingClearColor = null;
    return color;
  }

  void _ensureClear() {
    final color = _takeClearColor();
    if (color == null) return;
    renderContext._batchSystem.flush(color);
  }
}

class _WebGpuCollectionState {
  late InstructionSet instructionSet;
  late int instructionCursor;
  late int renderableCursor;
  late int oldInstructionSize;
  late int oldRenderableSize;
  late bool structureChanged;
  _WebGpuBatchInstruction? activeBatch;

  void capture(_WebGpuInstructionSystem system) {
    instructionSet = system.instructionSet;
    instructionCursor = system._instructionCursor;
    renderableCursor = system._renderableCursor;
    oldInstructionSize = system._oldInstructionSize;
    oldRenderableSize = system._oldRenderableSize;
    structureChanged = system._structureChanged;
    activeBatch = system._activeBatch;
  }
}

class _WebGpuRenderGroupInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuRenderGroupInstruction>('webgpu.render-group');

  final RenderObject renderable;
  final InstructionSet instructions;
  final matrix = Matrix.fromIdentity();

  _WebGpuRenderGroupInstruction(this.renderable, this.instructions);

  @override
  InstructionPipeId<_WebGpuRenderGroupInstruction> get instructionPipeId => pipeId;
}

class _WebGpuRenderGroupPipe implements InstructionPipe<_WebGpuRenderGroupInstruction> {
  final _WebGpuInstructionSystem instructionSystem;
  final _savedProjections = <Matrix3D>[];
  final _groupProjections = <Matrix3D>[];
  var _depth = 0;

  _WebGpuRenderGroupPipe(this.instructionSystem);

  @override
  InstructionPipeId<_WebGpuRenderGroupInstruction> get id => _WebGpuRenderGroupInstruction.pipeId;

  @override
  void upload(_WebGpuRenderGroupInstruction instruction) => instructionSystem._upload(instruction.instructions);

  @override
  void execute(_WebGpuRenderGroupInstruction instruction) {
    final renderContext = instructionSystem.renderContext;
    final savedProjection = _matrixAt(_savedProjections, _depth)..copyFrom(renderContext.activeProjectionMatrix);
    final groupProjection = _matrixAt(_groupProjections, _depth)
      ..copyFrom2DAndConcat(instruction.matrix, savedProjection);
    _depth++;
    renderContext.activateProjectionMatrix(groupProjection);
    instructionSystem._execute(instruction.instructions);
    renderContext.activateProjectionMatrix(savedProjection);
    _depth--;
  }

  Matrix3D _matrixAt(List<Matrix3D> matrices, int index) {
    if (index == matrices.length) matrices.add(Matrix3D.fromIdentity());
    return matrices[index];
  }

  @override
  void dispose(_WebGpuRenderGroupInstruction instruction) {
    instructionSystem._disposeInstructionSet(instruction.instructions);
    instructionSystem._clearInstructionSet(instruction.instructions);
    instructionSystem._renderGroups[instruction.renderable] = null;
  }
}

final class _WebGpuBatchRenderable extends RetainedSlot {
  RenderTexture texture;
  BlendMode blendMode;
  late Int16List indices;
  late Float32List vertices;
  var matrixA = 1.0;
  var matrixB = 0.0;
  var matrixC = 0.0;
  var matrixD = 1.0;
  var matrixTx = 0.0;
  var matrixTy = 0.0;
  var red = 1.0;
  var green = 1.0;
  var blue = 1.0;
  var alpha = 1.0;
  var textureScaleX = double.nan;
  var textureScaleY = double.nan;
  var textureIndex = 0;
  var renderableIndex = 0;
  var vertexFloatOffset = 0;
  var metadataFloatOffset = 0;
  var indexOffset = 0;
  var baseVertex = 0;
  var geometryDirty = true;
  var metadataDirty = true;
  var indexDirty = true;

  _WebGpuBatchRenderable(
    RenderState state,
    this.texture,
    Int16List sourceIndices,
    Float32List sourceVertices,
    num red,
    num green,
    num blue,
    num alpha,
  ) : blendMode = state.globalBlendMode {
    indices = Int16List(sourceIndices.length);
    vertices = Float32List(sourceVertices.length);
    update(state, sourceIndices, sourceVertices, red, green, blue, alpha);
  }

  bool matchesStructure(
    RenderState state,
    RenderTexture sourceTexture,
    Int16List sourceIndices,
    Float32List sourceVertices,
  ) =>
      identical(texture, sourceTexture) &&
      identical(blendMode, state.globalBlendMode) &&
      indices.length == sourceIndices.length &&
      vertices.length == sourceVertices.length;

  void update(
    RenderState state,
    Int16List sourceIndices,
    Float32List sourceVertices,
    num tintRed,
    num tintGreen,
    num tintBlue,
    num tintAlpha,
  ) {
    final matrix = state.globalMatrix;
    final nextAlpha = state.globalAlpha * state.globalColorScaleA * tintAlpha;
    final nextRed = state.globalColorScaleR * tintRed * nextAlpha;
    final nextGreen = state.globalColorScaleG * tintGreen * nextAlpha;
    final nextBlue = state.globalColorScaleB * tintBlue * nextAlpha;
    if (matrixA != matrix.a ||
        matrixB != matrix.b ||
        matrixC != matrix.c ||
        matrixD != matrix.d ||
        matrixTx != matrix.tx ||
        matrixTy != matrix.ty ||
        red != nextRed ||
        green != nextGreen ||
        blue != nextBlue ||
        alpha != nextAlpha) {
      matrixA = matrix.a;
      matrixB = matrix.b;
      matrixC = matrix.c;
      matrixD = matrix.d;
      matrixTx = matrix.tx;
      matrixTy = matrix.ty;
      red = nextRed;
      green = nextGreen;
      blue = nextBlue;
      alpha = nextAlpha;
      metadataDirty = true;
    }

    for (var i = 0; i < sourceVertices.length; i++) {
      final value = sourceVertices[i];
      if (vertices[i] == value) continue;
      vertices[i] = value;
      geometryDirty = true;
    }
    for (var i = 0; i < sourceIndices.length; i++) {
      final value = sourceIndices[i];
      if (indices[i] == value) continue;
      indices[i] = value;
      indexDirty = true;
    }
  }

  void updateTextureScale(double scaleX, double scaleY) {
    if (textureScaleX == scaleX && textureScaleY == scaleY) return;
    textureScaleX = scaleX;
    textureScaleY = scaleY;
    geometryDirty = true;
  }

  void updateTextureIndex(int index) {
    if (textureIndex == index) return;
    textureIndex = index;
    metadataDirty = true;
  }

  int get vertexCount => vertices.length >> 2;
}

final class _WebGpuSceneRenderable extends RetainedSlot {
  final RenderObject renderable;
  RenderPipeId pipeId;
  int structureVersion;
  int dataVersion;
  RenderDirtyState? dirtyState;
  var transformVersion = 0;
  var colorVersion = 0;
  var geometryVersion = 0;
  var textureVersion = 0;
  var blendVersion = 0;
  var maskVersion = 0;
  var filterVersion = 0;
  var dirtyFlags = RenderDirtyFlags.all;

  _WebGpuSceneRenderable(this.renderable)
      : pipeId = renderable.renderPipeId,
        structureVersion = renderable.renderStructureVersion,
        dataVersion = renderable.renderDataVersion {
    _captureDirtyState(renderable.renderDirtyState);
  }

  void update() {
    final nextDirtyState = renderable.renderDirtyState;
    var changes = RenderDirtyFlags.none;
    if (nextDirtyState == null || !identical(dirtyState, nextDirtyState)) {
      changes = dataVersion == renderable.renderDataVersion ? RenderDirtyFlags.none : RenderDirtyFlags.allData;
    } else {
      if (transformVersion != nextDirtyState.transformVersion) changes |= RenderDirtyFlags.transform;
      if (colorVersion != nextDirtyState.colorVersion) changes |= RenderDirtyFlags.color;
      if (geometryVersion != nextDirtyState.geometryVersion) changes |= RenderDirtyFlags.geometry;
      if (textureVersion != nextDirtyState.textureVersion) changes |= RenderDirtyFlags.texture;
      if (blendVersion != nextDirtyState.blendVersion) changes |= RenderDirtyFlags.blend;
      if (maskVersion != nextDirtyState.maskVersion) changes |= RenderDirtyFlags.mask;
      if (filterVersion != nextDirtyState.filterVersion) changes |= RenderDirtyFlags.filter;
    }
    dirtyFlags = changes;
    pipeId = renderable.renderPipeId;
    structureVersion = renderable.renderStructureVersion;
    dataVersion = renderable.renderDataVersion;
    _captureDirtyState(nextDirtyState);
  }

  void _captureDirtyState(RenderDirtyState? state) {
    dirtyState = state;
    transformVersion = state?.transformVersion ?? 0;
    colorVersion = state?.colorVersion ?? 0;
    geometryVersion = state?.geometryVersion ?? 0;
    textureVersion = state?.textureVersion ?? 0;
    blendVersion = state?.blendVersion ?? 0;
    maskVersion = state?.maskVersion ?? 0;
    filterVersion = state?.filterVersion ?? 0;
  }
}

class _WebGpuScenePipe implements RetainedSlotPipe<_WebGpuSceneRenderable> {
  @override
  void addSlot(_WebGpuSceneRenderable slot, InstructionSet instructionSet) => instructionSet.addSlot(slot);

  @override
  void updateSlot(_WebGpuSceneRenderable slot) {}

  @override
  bool validateSlot(_WebGpuSceneRenderable slot) => true;
}

class _WebGpuBatchInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuBatchInstruction>('webgpu.batch');

  final RenderContextWebGPU renderContext;
  final renderables = <_WebGpuBatchRenderable>[];
  final runs = <_WebGpuRun>[];
  final bindGroups = <GPUBindGroup>[];
  Float32List? vertexData;
  Float32List? metadataData;
  Uint32List? indexData;
  GPUBuffer? vertexBuffer;
  GPUBuffer? metadataBuffer;
  GPUBuffer? indexBuffer;
  GPUBindGroup? metadataBindGroup;
  var renderableSize = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var vertexCapacity = 0;
  var metadataCapacity = 0;
  var indexCapacity = 0;
  var structuralDirty = true;
  GPURenderBundle? renderBundle;
  final bundlePipelines = <GPURenderPipeline>[];
  final bundleBindGroups = <GPUBindGroup>[];
  var bundleObservationCount = 0;
  var bundleSampleCount = 0;
  var bundleStencilTest = false;

  _WebGpuBatchInstruction(this.renderContext);

  @override
  InstructionPipeId<_WebGpuBatchInstruction> get instructionPipeId => pipeId;

  void beginUpdate() => renderableSize = 0;

  (_WebGpuBatchRenderable, bool) addRenderable(
    RenderState state,
    RenderTexture texture,
    Int16List indices,
    Float32List vertices,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    final old = renderableSize < renderables.length ? renderables[renderableSize] : null;
    final reusable = old != null && old.matchesStructure(state, texture, indices, vertices);
    final renderable = reusable
        ? old
        : _WebGpuBatchRenderable(state, texture, indices, vertices, red, green, blue, alpha);
    if (reusable) renderable.update(state, indices, vertices, red, green, blue, alpha);
    if (renderableSize == renderables.length) {
      renderables.add(renderable);
    } else {
      renderables[renderableSize] = renderable;
    }
    renderableSize++;
    if (!reusable) structuralDirty = true;
    return (renderable, !reusable);
  }

  bool finishUpdate() {
    if (renderableSize != renderables.length) {
      renderables.length = renderableSize;
      structuralDirty = true;
    }
    if (!structuralDirty) return false;
    _rebuildRuns();
    return true;
  }

  void _rebuildRuns() {
    runs.clear();
    vertexCount = 0;
    indexCount = 0;
    final maxTextures = renderContext.pipelineSystem.maxBatchTextures;
    final opaqueTarget = renderContext._activeRenderTargetIsOpaque;
    final dualSourceBlending = renderContext.dualSourceBlending &&
        (!opaqueTarget || renderables.any((renderable) => _requiresDualSourceBatchBlendMode(renderable.blendMode)));
    for (var renderableIndex = 0; renderableIndex < renderables.length; renderableIndex++) {
      final renderable = renderables[renderableIndex];
      final batchBlendMode = _batchBlendMode(
        renderable.blendMode,
        opaqueTarget: opaqueTarget,
        dualSourceBlending: dualSourceBlending,
        promoteOpaqueNormalAdd: dualSourceBlending,
      );
      var run = runs.isEmpty ? null : runs.last;
      var textureIndex = run?.textureIndex(renderable.texture);
      if (run == null || !identical(run.blendMode, batchBlendMode) || textureIndex == null) {
        run = _WebGpuRun(renderable.texture, batchBlendMode, maxTextures)
          ..firstIndex = indexCount;
        runs.add(run);
        textureIndex = 0;
      }
      renderable.updateTextureIndex(_batchTextureIndex(
        textureIndex,
        renderable.blendMode,
        maxTextures,
        opaqueTarget: opaqueTarget,
        dualSourceBlending: dualSourceBlending,
        promoteOpaqueNormalAdd: dualSourceBlending,
      ));
      renderable.renderableIndex = renderableIndex;
      renderable.vertexFloatOffset = vertexCount * _WebGpuBatchPipe._floatsPerVertex;
      renderable.metadataFloatOffset = renderable.renderableIndex * _WebGpuBatchPipe._floatsPerRenderable;
      renderable.indexOffset = indexCount;
      renderable.baseVertex = vertexCount;
      run
        ..vertexCount += renderable.vertexCount
        ..indexCount += renderable.indices.length;
      vertexCount += renderable.vertexCount;
      indexCount += renderable.indices.length;
      renderable
        ..geometryDirty = true
        ..metadataDirty = true
        ..indexDirty = true;
    }
    bindGroups.length = 0;
    invalidateBundle();
    structuralDirty = false;
  }

  void invalidateBundle() {
    renderBundle = null;
    bundlePipelines.clear();
    bundleBindGroups.clear();
    bundleObservationCount = 0;
  }

  void dispose() {
    vertexBuffer?.destroy();
    metadataBuffer?.destroy();
    indexBuffer?.destroy();
    vertexBuffer = null;
    metadataBuffer = null;
    indexBuffer = null;
    metadataBindGroup = null;
    vertexCapacity = 0;
    metadataCapacity = 0;
    indexCapacity = 0;
    invalidateBundle();
  }
}

class _WebGpuBatchPipe
    implements RetainedSlotPipe<_WebGpuBatchRenderable>, InstructionPipe<_WebGpuBatchInstruction> {
  static const _floatsPerVertex = 5;
  static const _floatsPerRenderable = 12;
  static const _bytesPerVertex = _floatsPerVertex * 4;
  static const _bytesPerRenderable = _floatsPerRenderable * 4;
  static const _bytesPerIndex = 4;

  final RenderContextWebGPU renderContext;
  final List<num>? Function() takeClearColor;

  _WebGpuBatchPipe(this.renderContext, this.takeClearColor);

  @override
  InstructionPipeId<_WebGpuBatchInstruction> get id => _WebGpuBatchInstruction.pipeId;

  @override
  void addSlot(_WebGpuBatchRenderable slot, InstructionSet instructionSet) => instructionSet.addSlot(slot);

  @override
  void updateSlot(_WebGpuBatchRenderable slot) {}

  @override
  bool validateSlot(_WebGpuBatchRenderable slot) => true;

  @override
  void upload(_WebGpuBatchInstruction instruction) {
    final vertexLength = instruction.vertexCount * _floatsPerVertex;
    final metadataLength = instruction.renderables.length * _floatsPerRenderable;
    final indexLength = instruction.indexCount;
    var uploadAllVertices = instruction.vertexData == null;
    var uploadAllMetadata = instruction.metadataData == null;
    var uploadAllIndices = instruction.indexData == null;
    if (instruction.vertexData == null || instruction.vertexData!.length < vertexLength) {
      instruction.vertexData = JSFloat32Array.withLength(math.max(vertexLength, 4)).toDart;
      uploadAllVertices = true;
    }
    if (instruction.metadataData == null || instruction.metadataData!.length < metadataLength) {
      instruction.metadataData =
          JSFloat32Array.withLength(math.max(metadataLength, _floatsPerRenderable)).toDart;
      uploadAllMetadata = true;
    }
    if (instruction.indexData == null || instruction.indexData!.length < indexLength) {
      instruction.indexData = JSUint32Array.withLength(math.max(indexLength, 4)).toDart;
      uploadAllIndices = true;
    }

    final (vertexBufferRebuilt, metadataBufferRebuilt, indexBufferRebuilt) = _ensureGpuBuffers(
      instruction,
      vertexLength * 4,
      metadataLength * 4,
      indexLength * _bytesPerIndex,
    );
    uploadAllVertices = uploadAllVertices || vertexBufferRebuilt;
    uploadAllMetadata = uploadAllMetadata || metadataBufferRebuilt;
    uploadAllIndices = uploadAllIndices || indexBufferRebuilt;

    final stopwatch = Stopwatch()..start();
    var uploaded = false;
    for (final renderable in instruction.renderables) {
      renderable.updateTextureScale(
        renderContext.textureSystem._textureCoordinateScaleX(renderable.texture),
        renderContext.textureSystem._textureCoordinateScaleY(renderable.texture),
      );
    }
    if (uploadAllVertices && vertexLength > 0) {
      _bakeVertices(instruction);
      renderContext.device.queue.writeBuffer(
        instruction.vertexBuffer!,
        0,
        instruction.vertexData!.toJS,
        0,
        vertexLength,
      );
      _recordUpload(vertexLength * 4);
      uploaded = true;
    } else {
      uploaded = _uploadDirtyVertexRanges(instruction) || uploaded;
    }
    if (uploadAllMetadata && metadataLength > 0) {
      _bakeMetadata(instruction);
      renderContext.device.queue.writeBuffer(
        instruction.metadataBuffer!,
        0,
        instruction.metadataData!.toJS,
        0,
        metadataLength,
      );
      _recordUpload(metadataLength * 4);
      uploaded = true;
    } else {
      uploaded = _uploadDirtyMetadataRanges(instruction) || uploaded;
    }
    if (uploadAllIndices && indexLength > 0) {
      _bakeIndices(instruction);
      renderContext.device.queue.writeBuffer(
        instruction.indexBuffer!,
        0,
        instruction.indexData!.toJS,
        0,
        indexLength,
      );
      _recordUpload(indexLength * _bytesPerIndex);
      uploaded = true;
    } else {
      uploaded = _uploadDirtyIndexRanges(instruction) || uploaded;
    }
    if (uploaded) {
      renderContext.renderStatistics.webgpuBufferUploadMicroseconds += stopwatch.elapsedMicroseconds;
    }

    for (var i = 0; i < instruction.runs.length; i++) {
      final bindGroup = renderContext.textureSystem.getBatchBindGroup(instruction.runs[i].textures);
      if (i == instruction.bindGroups.length) {
        instruction.bindGroups.add(bindGroup);
        instruction.invalidateBundle();
      } else if (!identical(instruction.bindGroups[i], bindGroup)) {
        instruction.bindGroups[i] = bindGroup;
        instruction.invalidateBundle();
      }
    }
  }

  void _bakeVertices(_WebGpuBatchInstruction instruction) {
    final target = instruction.vertexData!;
    for (final renderable in instruction.renderables) {
      _bakeRenderableVertices(renderable, target);
    }
  }

  void _bakeRenderableVertices(_WebGpuBatchRenderable renderable, Float32List target) {
    final source = renderable.vertices;
    var writeIndex = renderable.vertexFloatOffset;
    for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex += 4) {
      target[writeIndex++] = source[sourceIndex + 0];
      target[writeIndex++] = source[sourceIndex + 1];
      target[writeIndex++] = source[sourceIndex + 2] * renderable.textureScaleX;
      target[writeIndex++] = source[sourceIndex + 3] * renderable.textureScaleY;
      target[writeIndex++] = renderable.renderableIndex.toDouble();
    }
    renderable.geometryDirty = false;
  }

  void _bakeMetadata(_WebGpuBatchInstruction instruction) {
    final target = instruction.metadataData!;
    for (final renderable in instruction.renderables) {
      _bakeRenderableMetadata(renderable, target);
    }
  }

  void _bakeRenderableMetadata(_WebGpuBatchRenderable renderable, Float32List target) {
    var writeIndex = renderable.metadataFloatOffset;
    target[writeIndex++] = renderable.matrixA;
    target[writeIndex++] = renderable.matrixB;
    target[writeIndex++] = renderable.matrixC;
    target[writeIndex++] = renderable.matrixD;
    target[writeIndex++] = renderable.matrixTx;
    target[writeIndex++] = renderable.matrixTy;
    target[writeIndex++] = renderable.red;
    target[writeIndex++] = renderable.green;
    target[writeIndex++] = renderable.blue;
    target[writeIndex++] = renderable.alpha;
    target[writeIndex++] = renderable.textureIndex.toDouble();
    target[writeIndex] = 0;
    renderable.metadataDirty = false;
  }

  void _bakeIndices(_WebGpuBatchInstruction instruction) {
    final target = instruction.indexData!;
    for (final renderable in instruction.renderables) {
      _bakeRenderableIndices(renderable, target);
    }
  }

  void _bakeRenderableIndices(_WebGpuBatchRenderable renderable, Uint32List target) {
    var writeIndex = renderable.indexOffset;
    for (final index in renderable.indices) {
      target[writeIndex++] = renderable.baseVertex + index;
    }
    renderable.indexDirty = false;
  }

  bool _uploadDirtyVertexRanges(_WebGpuBatchInstruction instruction) {
    var uploaded = false;
    var index = 0;
    while (index < instruction.renderables.length) {
      while (index < instruction.renderables.length && !instruction.renderables[index].geometryDirty) {
        index++;
      }
      if (index == instruction.renderables.length) break;
      final first = instruction.renderables[index];
      final start = first.vertexFloatOffset;
      var end = start;
      while (index < instruction.renderables.length && instruction.renderables[index].geometryDirty) {
        final renderable = instruction.renderables[index++];
        _bakeRenderableVertices(renderable, instruction.vertexData!);
        end = renderable.vertexFloatOffset + renderable.vertexCount * _floatsPerVertex;
      }
      renderContext.device.queue.writeBuffer(
        instruction.vertexBuffer!,
        start * 4,
        instruction.vertexData!.toJS,
        start,
        end - start,
      );
      _recordUpload((end - start) * 4);
      uploaded = true;
    }
    return uploaded;
  }

  bool _uploadDirtyMetadataRanges(_WebGpuBatchInstruction instruction) {
    var uploaded = false;
    var index = 0;
    while (index < instruction.renderables.length) {
      while (index < instruction.renderables.length && !instruction.renderables[index].metadataDirty) {
        index++;
      }
      if (index == instruction.renderables.length) break;
      final first = instruction.renderables[index];
      final start = first.metadataFloatOffset;
      var end = start;
      while (index < instruction.renderables.length && instruction.renderables[index].metadataDirty) {
        final renderable = instruction.renderables[index++];
        _bakeRenderableMetadata(renderable, instruction.metadataData!);
        end = renderable.metadataFloatOffset + _floatsPerRenderable;
      }
      renderContext.device.queue.writeBuffer(
        instruction.metadataBuffer!,
        start * 4,
        instruction.metadataData!.toJS,
        start,
        end - start,
      );
      _recordUpload((end - start) * 4);
      uploaded = true;
    }
    return uploaded;
  }

  bool _uploadDirtyIndexRanges(_WebGpuBatchInstruction instruction) {
    var uploaded = false;
    var index = 0;
    while (index < instruction.renderables.length) {
      while (index < instruction.renderables.length && !instruction.renderables[index].indexDirty) {
        index++;
      }
      if (index == instruction.renderables.length) break;
      final first = instruction.renderables[index];
      final start = first.indexOffset;
      var end = start;
      while (index < instruction.renderables.length && instruction.renderables[index].indexDirty) {
        final renderable = instruction.renderables[index++];
        _bakeRenderableIndices(renderable, instruction.indexData!);
        end = renderable.indexOffset + renderable.indices.length;
      }
      renderContext.device.queue.writeBuffer(
        instruction.indexBuffer!,
        start * _bytesPerIndex,
        instruction.indexData!.toJS,
        start,
        end - start,
      );
      _recordUpload((end - start) * _bytesPerIndex);
      uploaded = true;
    }
    return uploaded;
  }

  (bool, bool, bool) _ensureGpuBuffers(
    _WebGpuBatchInstruction instruction,
    int vertexBytes,
    int metadataBytes,
    int indexBytes,
  ) {
    var vertexBufferRebuilt = false;
    var metadataBufferRebuilt = false;
    var indexBufferRebuilt = false;
    if (instruction.vertexBuffer == null || instruction.vertexCapacity < vertexBytes) {
      instruction.vertexBuffer?.destroy();
      instruction.invalidateBundle();
      instruction.vertexCapacity = math.max(vertexBytes * 2, _bytesPerVertex * 4);
      instruction.vertexBuffer = renderContext.device.createBuffer(GPUBufferDescriptor(
        size: instruction.vertexCapacity,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
      ));
      vertexBufferRebuilt = true;
    }
    if (instruction.metadataBuffer == null || instruction.metadataCapacity < metadataBytes) {
      instruction.metadataBuffer?.destroy();
      instruction.invalidateBundle();
      instruction.metadataCapacity = math.max(metadataBytes * 2, _bytesPerRenderable);
      instruction.metadataBuffer = renderContext.device.createBuffer(GPUBufferDescriptor(
        size: instruction.metadataCapacity,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.STORAGE,
      ));
      instruction.metadataBindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
        layout: renderContext.pipelineSystem.retainedMetadataBindGroupLayout,
        entries: [
          GPUBindGroupEntry(binding: 0, resource: GPUBufferBinding(buffer: instruction.metadataBuffer!)),
        ].toJS,
      ));
      renderContext.renderStatistics.webgpuBindGroupCreateCount++;
      metadataBufferRebuilt = true;
    }
    if (instruction.indexBuffer == null || instruction.indexCapacity < indexBytes) {
      instruction.indexBuffer?.destroy();
      instruction.invalidateBundle();
      instruction.indexCapacity = math.max(indexBytes * 2, _bytesPerIndex * 12);
      instruction.indexBuffer = renderContext.device.createBuffer(GPUBufferDescriptor(
        size: instruction.indexCapacity,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.INDEX,
      ));
      indexBufferRebuilt = true;
    }
    return (vertexBufferRebuilt, metadataBufferRebuilt, indexBufferRebuilt);
  }

  void _recordUpload(int bytes) {
    final statistics = renderContext.renderStatistics;
    statistics.webgpuInstructionUploadCount++;
    statistics.webgpuInstructionUploadBytes += bytes;
  }

  @override
  void execute(_WebGpuBatchInstruction instruction) => executeWithClear(instruction, takeClearColor());

  @override
  void dispose(_WebGpuBatchInstruction instruction) => instruction.dispose();

  void executeWithClear(_WebGpuBatchInstruction instruction, List<num>? clearColor) {
    if (instruction.vertexCount == 0) {
      if (clearColor != null) renderContext._batchSystem.flush(clearColor);
      return;
    }

    renderContext.pipelineSystem.uploadProjectionMatrix(renderContext.activeProjectionMatrix);
    final encodeStopwatch = Stopwatch()..start();
    final pass = renderContext.commandSystem.beginColorPass(clearColor);
    final stencilValue = renderContext._maskSystem.activeStencilValue;
    if (stencilValue > 0) pass.setStencilReference(stencilValue);
    pass
      ..setVertexBuffer(0, instruction.vertexBuffer, 0, instruction.vertexCount * _bytesPerVertex)
      ..setIndexBuffer(instruction.indexBuffer!, 'uint32', 0, instruction.indexCount * _bytesPerIndex)
      ..setBindGroup(1, renderContext.pipelineSystem.projectionBindGroup)
      ..setBindGroup(2, instruction.metadataBindGroup);

    final bundle = _getRenderBundle(instruction, stencilValue > 0);
    if (bundle != null) {
      pass.executeBundles([bundle].toJS);
    } else {
      GPURenderPipeline? activePipeline;
      for (var i = 0; i < instruction.runs.length; i++) {
        final run = instruction.runs[i];
        final pipeline = renderContext.pipelineSystem.getRetainedPipeline(
          run.blendMode,
          stencilTest: stencilValue > 0,
        );
        if (!identical(pipeline, activePipeline)) {
          pass.setPipeline(pipeline);
          activePipeline = pipeline;
        }
        pass
          ..setBindGroup(0, instruction.bindGroups[i])
          ..drawIndexed(run.indexCount, 1, run.firstIndex, 0, 0);
      }
    }
    pass.end();

    final statistics = renderContext.renderStatistics;
    statistics.webgpuBatchFlushCount++;
    statistics.webgpuBatchRunCount += instruction.runs.length;
    statistics.webgpuPassEncodeMicroseconds += encodeStopwatch.elapsedMicroseconds;
    for (var i = 1; i < instruction.runs.length; i++) {
      if (identical(instruction.runs[i - 1].blendMode, instruction.runs[i].blendMode)) {
        statistics.webgpuBatchTextureBreakCount++;
      } else {
        statistics.webgpuBatchBlendBreakCount++;
      }
    }
    for (final run in instruction.runs) {
      statistics.drawCount++;
      statistics.vertexCount += run.vertexCount;
      statistics.indexCount += run.indexCount;
    }
    renderContext.commandSystem.submit();
  }

  GPURenderBundle? _getRenderBundle(_WebGpuBatchInstruction instruction, bool stencilTest) {
    if (!renderContext.renderBundles || _hasDynamicTexture(instruction)) return null;

    final sampleCount = renderContext.sampleCount;
    var matches = instruction.bundleSampleCount == sampleCount &&
        instruction.bundleStencilTest == stencilTest &&
        instruction.bundlePipelines.length == instruction.runs.length &&
        instruction.bundleBindGroups.length == instruction.runs.length;
    for (var i = 0; matches && i < instruction.runs.length; i++) {
      final pipeline = renderContext.pipelineSystem.getRetainedPipeline(
        instruction.runs[i].blendMode,
        stencilTest: stencilTest,
      );
      matches = identical(instruction.bundlePipelines[i], pipeline) &&
          identical(instruction.bundleBindGroups[i], instruction.bindGroups[i]);
    }
    if (!matches) {
      instruction.invalidateBundle();
      instruction.bundleSampleCount = sampleCount;
      instruction.bundleStencilTest = stencilTest;
      for (var i = 0; i < instruction.runs.length; i++) {
        instruction.bundlePipelines.add(
          renderContext.pipelineSystem.getRetainedPipeline(
            instruction.runs[i].blendMode,
            stencilTest: stencilTest,
          ),
        );
        instruction.bundleBindGroups.add(instruction.bindGroups[i]);
      }
    }

    final cached = instruction.renderBundle;
    if (cached != null) {
      renderContext.renderStatistics.webgpuRenderBundleCacheHitCount++;
      return cached;
    }
    instruction.bundleObservationCount++;
    if (instruction.bundleObservationCount < 2) return null;

    final encoder = renderContext.device.createRenderBundleEncoder(GPURenderBundleEncoderDescriptor(
      colorFormats: [renderContext.preferredTextureFormat.toJS].toJS,
      depthStencilFormat: 'depth24plus-stencil8',
      sampleCount: sampleCount,
    ));
    encoder
      ..setVertexBuffer(0, instruction.vertexBuffer, 0, instruction.vertexCount * _bytesPerVertex)
      ..setIndexBuffer(instruction.indexBuffer!, 'uint32', 0, instruction.indexCount * _bytesPerIndex)
      ..setBindGroup(1, renderContext.pipelineSystem.projectionBindGroup)
      ..setBindGroup(2, instruction.metadataBindGroup);

    GPURenderPipeline? activePipeline;
    for (var i = 0; i < instruction.runs.length; i++) {
      final run = instruction.runs[i];
      final pipeline = renderContext.pipelineSystem.getRetainedPipeline(run.blendMode, stencilTest: stencilTest);
      if (!identical(pipeline, activePipeline)) {
        encoder.setPipeline(pipeline);
        activePipeline = pipeline;
      }
      encoder
        ..setBindGroup(0, instruction.bindGroups[i])
        ..drawIndexed(run.indexCount, 1, run.firstIndex, 0, 0);
    }
    instruction.renderBundle = encoder.finish(GPURenderBundleDescriptor(label: 'StageXL retained batch'));
    renderContext.renderStatistics.webgpuRenderBundleBuildCount++;
    return instruction.renderBundle;
  }

  bool _hasDynamicTexture(_WebGpuBatchInstruction instruction) {
    for (final run in instruction.runs) {
      for (final texture in run.textures) {
        if (texture.source.isA<HTMLVideoElement>()) return true;
      }
    }
    return false;
  }
}

class _WebGpuDrawInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuDrawInstruction>('webgpu.draw');

  final RenderDrawOperation operation;
  final RenderState state;

  _WebGpuDrawInstruction(RenderContextWebGPU renderContext, this.operation) : state = RenderState(renderContext);

  @override
  InstructionPipeId<_WebGpuDrawInstruction> get instructionPipeId => pipeId;
}

class _WebGpuDrawPipe implements InstructionPipe<_WebGpuDrawInstruction> {
  final RenderContextWebGPU renderContext;
  final void Function() ensureClear;

  _WebGpuDrawPipe(this.renderContext, this.ensureClear);

  @override
  InstructionPipeId<_WebGpuDrawInstruction> get id => _WebGpuDrawInstruction.pipeId;

  @override
  void upload(_WebGpuDrawInstruction instruction) {}

  @override
  void execute(_WebGpuDrawInstruction instruction) {
    ensureClear();
    instruction.operation.executeDraw(instruction.state);
    renderContext.flush();
  }

  @override
  void dispose(_WebGpuDrawInstruction instruction) {}
}

class _WebGpuMaskInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuMaskInstruction>('webgpu.mask');

  final RenderMask mask;
  final bool begin;
  final RenderState state;
  final capturedVertices = <double>[];
  Rectangle<num>? capturedScissor;

  _WebGpuMaskInstruction(RenderContextWebGPU renderContext, this.mask, this.begin)
      : state = RenderState(renderContext);

  @override
  InstructionPipeId<_WebGpuMaskInstruction> get instructionPipeId => pipeId;

  void captureMask() {
    if (mask is ScissorRenderMask) {
      capturedScissor = (mask as ScissorRenderMask).getScissorRectangle(state);
      capturedVertices.clear();
    } else {
      capturedScissor = null;
      capturedVertices
        ..clear()
        ..addAll((state.renderContext as RenderContextWebGPU)._maskSystem.captureMask(state, mask));
    }
  }
}

class _WebGpuMaskPipe implements InstructionPipe<_WebGpuMaskInstruction> {
  final RenderContextWebGPU renderContext;
  final void Function() ensureClear;

  _WebGpuMaskPipe(this.renderContext, this.ensureClear);

  @override
  InstructionPipeId<_WebGpuMaskInstruction> get id => _WebGpuMaskInstruction.pipeId;

  @override
  void upload(_WebGpuMaskInstruction instruction) {}

  @override
  void execute(_WebGpuMaskInstruction instruction) {
    ensureClear();
    if (instruction.begin) {
      renderContext._maskSystem.beginMask(
        instruction.state,
        instruction.mask,
        useCapturedData: true,
        capturedScissor: instruction.capturedScissor,
        capturedVertices: instruction.capturedVertices,
      );
    } else {
      renderContext._maskSystem.endMask(instruction.state, instruction.mask);
    }
  }

  @override
  void dispose(_WebGpuMaskInstruction instruction) {}
}

class _WebGpuFilterInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuFilterInstruction>('webgpu.filter');

  final RenderContextWebGPU renderContext;
  final RenderState state;
  RenderTextureQuad? quad;
  RenderObject? renderObject;
  final filters = <RenderFilter>[];

  _WebGpuFilterInstruction.quad(
    this.renderContext,
    this.quad,
    List<RenderFilter> filters,
  ) : state = RenderState(renderContext) {
    this.filters.addAll(filters);
  }

  _WebGpuFilterInstruction.object(
    this.renderContext,
    this.renderObject,
    List<RenderFilter> filters,
  ) : state = RenderState(renderContext) {
    this.filters.addAll(filters);
  }

  @override
  InstructionPipeId<_WebGpuFilterInstruction> get instructionPipeId => pipeId;

  bool matchesQuad(RenderTextureQuad nextQuad, List<RenderFilter> nextFilters) =>
      renderObject == null &&
      identical(quad?.renderTexture, nextQuad.renderTexture) &&
      _sameFilters(nextFilters);

  bool matchesObject(RenderObject nextObject, List<RenderFilter> nextFilters) =>
      identical(renderObject, nextObject) && _sameFilters(nextFilters);

  bool _sameFilters(List<RenderFilter> other) {
    if (filters.length != other.length) return false;
    for (var i = 0; i < filters.length; i++) {
      if (!identical(filters[i], other[i])) return false;
    }
    return true;
  }

  void updateQuad(RenderState sourceState, RenderTextureQuad sourceQuad, List<RenderFilter> sourceFilters) {
    state
      ..copyFrom(sourceState)
      ..currentTime = sourceState.currentTime
      ..deltaTime = sourceState.deltaTime;
    quad = sourceQuad;
    filters
      ..clear()
      ..addAll(sourceFilters);
  }

  void updateObject(RenderState sourceState, RenderObject sourceObject, List<RenderFilter> sourceFilters) {
    state
      ..copyFrom(sourceState)
      ..currentTime = sourceState.currentTime
      ..deltaTime = sourceState.deltaTime;
    renderObject = sourceObject;
    filters
      ..clear()
      ..addAll(sourceFilters);
  }
}

class _WebGpuFilterPipe implements InstructionPipe<_WebGpuFilterInstruction> {
  final RenderContextWebGPU renderContext;
  final void Function() ensureClear;

  _WebGpuFilterPipe(this.renderContext, this.ensureClear);

  @override
  InstructionPipeId<_WebGpuFilterInstruction> get id => _WebGpuFilterInstruction.pipeId;

  @override
  void upload(_WebGpuFilterInstruction instruction) {}

  @override
  void execute(_WebGpuFilterInstruction instruction) {
    ensureClear();
    final quad = instruction.quad;
    if (quad != null) {
      renderContext.filterSystem.renderTextureQuadFiltered(instruction.state, quad, instruction.filters);
    } else {
      renderContext.filterSystem.renderObjectFiltered(instruction.state, instruction.renderObject!);
    }
  }

  @override
  void dispose(_WebGpuFilterInstruction instruction) {}
}

class _WebGpuProjectionInstruction implements RenderInstruction {
  static const pipeId = InstructionPipeId<_WebGpuProjectionInstruction>('webgpu.projection');

  final RenderContextWebGPU renderContext;
  final matrix = Matrix3D.fromIdentity();

  _WebGpuProjectionInstruction(this.renderContext);

  @override
  InstructionPipeId<_WebGpuProjectionInstruction> get instructionPipeId => pipeId;
}

class _WebGpuProjectionPipe implements InstructionPipe<_WebGpuProjectionInstruction> {
  final RenderContextWebGPU renderContext;
  final void Function() ensureClear;

  _WebGpuProjectionPipe(this.renderContext, this.ensureClear);

  @override
  InstructionPipeId<_WebGpuProjectionInstruction> get id => _WebGpuProjectionInstruction.pipeId;

  @override
  void upload(_WebGpuProjectionInstruction instruction) {}

  @override
  void execute(_WebGpuProjectionInstruction instruction) {
    ensureClear();
    renderContext.activateProjectionMatrix(instruction.matrix);
  }

  @override
  void dispose(_WebGpuProjectionInstruction instruction) {}
}
