part of '../../engine.dart';

class WebGpuInstructionSystem {
  final RenderContextWebGPU renderContext;
  final _renderGroups = Expando<InstructionSet>('StageXL WebGPU render groups');
  late InstructionSet instructionSet;
  late final _scenePipe = _WebGpuScenePipe();
  late final _batchPipe = _WebGpuBatchPipe(renderContext);
  late final _maskPipe = _WebGpuMaskPipe(renderContext);
  late final _filterPipe = _WebGpuFilterPipe(renderContext);
  late final _projectionPipe = _WebGpuProjectionPipe(renderContext);
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

  WebGpuInstructionSystem(this.renderContext);

  bool get isCollecting => _isCollecting;

  void collect(RenderState renderState, RenderObject renderObject) {
    instructionSet = _renderGroups[renderObject] ??= InstructionSet();
    _beginCollect();
    renderState.renderObject(renderObject);
    _endCollect();

    final statistics = renderContext.renderStatistics;
    statistics.webgpuRenderableCount += instructionSet.renderableSize;
    if (_structureChanged) {
      instructionSet.buildCount++;
      statistics.webgpuInstructionBuildCount++;
    } else {
      instructionSet.reuseCount++;
      statistics.webgpuInstructionReuseCount++;
    }

  }

  void execute() {
    _batchPipe.upload(instructionSet);
    _maskPipe.upload(instructionSet);
    _filterPipe.upload(instructionSet);
    _projectionPipe.upload(instructionSet);
    _pendingClearColor = renderContext.consumeClearColor();

    for (var i = 0; i < instructionSet.instructionSize; i++) {
      final instruction = instructionSet.instructions[i]!;
      switch (instruction) {
        case _WebGpuBatchInstruction():
          _batchPipe.executeWithClear(instruction, _takeClearColor());
        case _WebGpuMaskInstruction():
          _ensureClear();
          _maskPipe.execute(instruction);
        case _WebGpuFilterInstruction():
          _ensureClear();
          _filterPipe.execute(instruction);
        case _WebGpuProjectionInstruction():
          _ensureClear();
          _projectionPipe.execute(instruction);
      }
    }
    _ensureClear();
  }

  void _beginCollect() {
    _oldInstructionSize = instructionSet.instructionSize;
    _oldRenderableSize = instructionSet.renderableSize;
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
      _disposeInstruction(instructionSet.instructions[i]);
      instructionSet.instructions[i] = null;
    }
    instructionSet.instructionSize = _instructionCursor;
    instructionSet.renderableSize = _renderableCursor;
  }

  void beginRenderable(RenderObject renderable) {
    if (!_isCollecting) return;
    final reusable = _renderableCursor < _oldRenderableSize &&
        identical(instructionSet.renderables[_renderableCursor], renderable) &&
        _scenePipe.validateRenderable(renderable);
    if (reusable) {
      _scenePipe.updateRenderable(renderable);
      _renderableCursor++;
    } else {
      _addRenderable(renderable, _scenePipe);
    }
  }

  void endRenderable(RenderObject renderable) {}

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
        identical(instructionSet.renderables[_renderableCursor], renderable) &&
        _batchPipe.validateRenderable(renderable);
    if (reusable) {
      _batchPipe.updateRenderable(renderable);
      _renderableCursor++;
    } else {
      _addRenderable(renderable, _batchPipe);
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
      renderObject.render(state);
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
      _instructionCursor < _oldInstructionSize ? instructionSet.instructions[_instructionCursor] : null;

  void _replaceInstruction(RenderInstruction instruction) {
    if (_instructionCursor == instructionSet.instructions.length) {
      instructionSet.instructions.add(instruction);
    } else {
      _disposeInstruction(instructionSet.instructions[_instructionCursor]);
      instructionSet.instructions[_instructionCursor] = instruction;
    }
    _structureChanged = true;
  }

  void _disposeInstruction(RenderInstruction? instruction) {
    if (instruction is _WebGpuBatchInstruction) instruction.dispose();
  }

  void _addRenderable<TRenderable>(TRenderable renderable, RenderPipe<TRenderable> pipe) {
    instructionSet.renderableSize = _renderableCursor;
    pipe.addRenderable(renderable, instructionSet);
    _renderableCursor = instructionSet.renderableSize;
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
    renderContext.batchSystem.flush(color);
  }
}

class _WebGpuBatchRenderable {
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
  var textureIndex = 0;
  var vertexDirty = true;
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
      vertexDirty = true;
    }

    for (var i = 0; i < sourceVertices.length; i++) {
      final value = sourceVertices[i];
      if (vertices[i] == value) continue;
      vertices[i] = value;
      vertexDirty = true;
    }
    for (var i = 0; i < sourceIndices.length; i++) {
      final value = sourceIndices[i];
      if (indices[i] == value) continue;
      indices[i] = value;
      indexDirty = true;
    }
  }

  int get vertexCount => vertices.length >> 2;
}

class _WebGpuScenePipe implements RenderPipe<RenderObject> {
  @override
  void addRenderable(RenderObject renderable, InstructionSet instructionSet) =>
      instructionSet.addRenderable(renderable);

  @override
  void updateRenderable(RenderObject renderable) {}

  @override
  bool validateRenderable(RenderObject renderable) => true;
}

class _WebGpuBatchInstruction implements RenderInstruction {
  final RenderContextWebGPU renderContext;
  final renderables = <_WebGpuBatchRenderable>[];
  final runs = <_WebGpuRun>[];
  final bindGroups = <GPUBindGroup>[];
  Float32List? vertexData;
  Uint32List? indexData;
  GPUBuffer? vertexBuffer;
  GPUBuffer? indexBuffer;
  var renderableSize = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var vertexCapacity = 0;
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
  String get renderPipeId => 'batch';

  @override
  bool get canBundle => true;

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
    for (final renderable in renderables) {
      var run = runs.isEmpty ? null : runs.last;
      var textureIndex = run?.textureIndex(renderable.texture);
      if (run == null || !identical(run.blendMode, renderable.blendMode) || textureIndex == null) {
        run = _WebGpuRun(renderable.texture, renderable.blendMode, maxTextures)
          ..firstIndex = indexCount;
        runs.add(run);
        textureIndex = 0;
      }
      renderable.textureIndex = textureIndex;
      run
        ..vertexCount += renderable.vertexCount
        ..indexCount += renderable.indices.length;
      vertexCount += renderable.vertexCount;
      indexCount += renderable.indices.length;
      renderable
        ..vertexDirty = true
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
    indexBuffer?.destroy();
    vertexBuffer = null;
    indexBuffer = null;
    vertexCapacity = 0;
    indexCapacity = 0;
    invalidateBundle();
  }
}

class _WebGpuBatchPipe
    implements RenderPipe<_WebGpuBatchRenderable>, InstructionPipe<_WebGpuBatchInstruction> {
  static const _floatsPerVertex = 9;
  static const _bytesPerVertex = _floatsPerVertex * 4;
  static const _bytesPerIndex = 4;

  final RenderContextWebGPU renderContext;

  _WebGpuBatchPipe(this.renderContext);

  @override
  void addRenderable(_WebGpuBatchRenderable renderable, InstructionSet instructionSet) =>
      instructionSet.addRenderable(renderable);

  @override
  void updateRenderable(_WebGpuBatchRenderable renderable) {}

  @override
  bool validateRenderable(_WebGpuBatchRenderable renderable) => true;

  @override
  void upload(InstructionSet instructionSet) {
    for (var i = 0; i < instructionSet.instructionSize; i++) {
      final instruction = instructionSet.instructions[i];
      if (instruction is _WebGpuBatchInstruction) _uploadInstruction(instruction);
    }
  }

  void _uploadInstruction(_WebGpuBatchInstruction instruction) {
    var uploadVertices = instruction.vertexData == null;
    var uploadIndices = instruction.indexData == null;
    for (final renderable in instruction.renderables) {
      uploadVertices = uploadVertices || renderable.vertexDirty;
      uploadIndices = uploadIndices || renderable.indexDirty;
    }

    final vertexLength = instruction.vertexCount * _floatsPerVertex;
    final indexLength = instruction.indexCount;
    if (instruction.vertexData == null || instruction.vertexData!.length < vertexLength) {
      instruction.vertexData = JSFloat32Array.withLength(math.max(vertexLength, 4)).toDart;
      uploadVertices = true;
    }
    if (instruction.indexData == null || instruction.indexData!.length < indexLength) {
      instruction.indexData = JSUint32Array.withLength(math.max(indexLength, 4)).toDart;
      uploadIndices = true;
    }

    if (uploadVertices) _bakeVertices(instruction);
    if (uploadIndices) _bakeIndices(instruction);
    _ensureGpuBuffers(instruction, vertexLength * 4, indexLength * _bytesPerIndex);

    final stopwatch = Stopwatch()..start();
    if (uploadVertices && vertexLength > 0) {
      renderContext.device.queue.writeBuffer(
        instruction.vertexBuffer!,
        0,
        instruction.vertexData!.toJS,
        0,
        vertexLength,
      );
      renderContext.renderStatistics.webgpuInstructionUploadCount++;
    }
    if (uploadIndices && indexLength > 0) {
      renderContext.device.queue.writeBuffer(
        instruction.indexBuffer!,
        0,
        instruction.indexData!.toJS,
        0,
        indexLength,
      );
      renderContext.renderStatistics.webgpuInstructionUploadCount++;
    }
    if (uploadVertices || uploadIndices) {
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
    final textureSystem = renderContext.textureSystem;
    var writeIndex = 0;
    for (final renderable in instruction.renderables) {
      final source = renderable.vertices;
      final textureScaleX = textureSystem._textureCoordinateScaleX(renderable.texture);
      final textureScaleY = textureSystem._textureCoordinateScaleY(renderable.texture);
      for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex += 4) {
        final x = source[sourceIndex + 0];
        final y = source[sourceIndex + 1];
        target[writeIndex++] = renderable.matrixTx + renderable.matrixA * x + renderable.matrixC * y;
        target[writeIndex++] = renderable.matrixTy + renderable.matrixB * x + renderable.matrixD * y;
        target[writeIndex++] = renderable.red;
        target[writeIndex++] = renderable.green;
        target[writeIndex++] = renderable.blue;
        target[writeIndex++] = renderable.alpha;
        target[writeIndex++] = source[sourceIndex + 2] * textureScaleX;
        target[writeIndex++] = source[sourceIndex + 3] * textureScaleY;
        target[writeIndex++] = renderable.textureIndex.toDouble();
      }
      renderable.vertexDirty = false;
    }
  }

  void _bakeIndices(_WebGpuBatchInstruction instruction) {
    final target = instruction.indexData!;
    var writeIndex = 0;
    var baseVertex = 0;
    for (final renderable in instruction.renderables) {
      for (final index in renderable.indices) {
        target[writeIndex++] = baseVertex + index;
      }
      baseVertex += renderable.vertexCount;
      renderable.indexDirty = false;
    }
  }

  void _ensureGpuBuffers(_WebGpuBatchInstruction instruction, int vertexBytes, int indexBytes) {
    if (instruction.vertexBuffer == null || instruction.vertexCapacity < vertexBytes) {
      instruction.vertexBuffer?.destroy();
      instruction.invalidateBundle();
      instruction.vertexCapacity = math.max(vertexBytes * 2, _bytesPerVertex * 4);
      instruction.vertexBuffer = renderContext.device.createBuffer(GPUBufferDescriptor(
        size: instruction.vertexCapacity,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
      ));
    }
    if (instruction.indexBuffer == null || instruction.indexCapacity < indexBytes) {
      instruction.indexBuffer?.destroy();
      instruction.invalidateBundle();
      instruction.indexCapacity = math.max(indexBytes * 2, _bytesPerIndex * 12);
      instruction.indexBuffer = renderContext.device.createBuffer(GPUBufferDescriptor(
        size: instruction.indexCapacity,
        usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.INDEX,
      ));
    }
  }

  @override
  void execute(_WebGpuBatchInstruction instruction) => executeWithClear(instruction, null);

  void executeWithClear(_WebGpuBatchInstruction instruction, List<num>? clearColor) {
    if (instruction.vertexCount == 0) {
      if (clearColor != null) renderContext.batchSystem.flush(clearColor);
      return;
    }

    renderContext.pipelineSystem.uploadProjectionMatrix(renderContext.activeProjectionMatrix);
    final encodeStopwatch = Stopwatch()..start();
    final pass = renderContext.commandSystem.beginColorPass(clearColor);
    final stencilValue = renderContext.maskSystem.activeStencilValue;
    if (stencilValue > 0) pass.setStencilReference(stencilValue);
    pass
      ..setVertexBuffer(0, instruction.vertexBuffer, 0, instruction.vertexCount * _bytesPerVertex)
      ..setIndexBuffer(instruction.indexBuffer!, 'uint32', 0, instruction.indexCount * _bytesPerIndex)
      ..setBindGroup(1, renderContext.pipelineSystem.projectionBindGroup);

    final bundle = _getRenderBundle(instruction, stencilValue > 0);
    if (bundle != null) {
      pass.executeBundles([bundle].toJS);
    } else {
      GPURenderPipeline? activePipeline;
      for (var i = 0; i < instruction.runs.length; i++) {
        final run = instruction.runs[i];
        final pipeline = renderContext.pipelineSystem.getPipeline(run.blendMode, stencilTest: stencilValue > 0);
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
      final pipeline = renderContext.pipelineSystem.getPipeline(
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
          renderContext.pipelineSystem.getPipeline(instruction.runs[i].blendMode, stencilTest: stencilTest),
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
      ..setBindGroup(1, renderContext.pipelineSystem.projectionBindGroup);

    GPURenderPipeline? activePipeline;
    for (var i = 0; i < instruction.runs.length; i++) {
      final run = instruction.runs[i];
      final pipeline = renderContext.pipelineSystem.getPipeline(run.blendMode, stencilTest: stencilTest);
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

class _WebGpuMaskInstruction implements RenderInstruction {
  final RenderMask mask;
  final bool begin;
  final RenderState state;
  final capturedVertices = <double>[];
  Rectangle<num>? capturedScissor;

  _WebGpuMaskInstruction(RenderContextWebGPU renderContext, this.mask, this.begin)
      : state = RenderState(renderContext);

  @override
  String get renderPipeId => 'mask';

  @override
  bool get canBundle => false;

  void captureMask() {
    if (mask is ScissorRenderMask) {
      capturedScissor = (mask as ScissorRenderMask).getScissorRectangle(state);
      capturedVertices.clear();
    } else {
      capturedScissor = null;
      capturedVertices
        ..clear()
        ..addAll((state.renderContext as RenderContextWebGPU).maskSystem.captureMask(state, mask));
    }
  }
}

class _WebGpuMaskPipe implements InstructionPipe<_WebGpuMaskInstruction> {
  final RenderContextWebGPU renderContext;

  _WebGpuMaskPipe(this.renderContext);

  @override
  void upload(InstructionSet instructionSet) {}

  @override
  void execute(_WebGpuMaskInstruction instruction) {
    if (instruction.begin) {
      renderContext.maskSystem.beginMask(
        instruction.state,
        instruction.mask,
        useCapturedData: true,
        capturedScissor: instruction.capturedScissor,
        capturedVertices: instruction.capturedVertices,
      );
    } else {
      renderContext.maskSystem.endMask(instruction.state, instruction.mask);
    }
  }
}

class _WebGpuFilterInstruction implements RenderInstruction {
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
  String get renderPipeId => 'filter';

  @override
  bool get canBundle => false;

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

  _WebGpuFilterPipe(this.renderContext);

  @override
  void upload(InstructionSet instructionSet) {}

  @override
  void execute(_WebGpuFilterInstruction instruction) {
    final quad = instruction.quad;
    if (quad != null) {
      renderContext.filterSystem.renderTextureQuadFiltered(instruction.state, quad, instruction.filters);
    } else {
      renderContext.filterSystem.renderObjectFiltered(instruction.state, instruction.renderObject!);
    }
  }
}

class _WebGpuProjectionInstruction implements RenderInstruction {
  final RenderContextWebGPU renderContext;
  final matrix = Matrix3D.fromIdentity();

  _WebGpuProjectionInstruction(this.renderContext);

  @override
  String get renderPipeId => 'projection';

  @override
  bool get canBundle => false;
}

class _WebGpuProjectionPipe implements InstructionPipe<_WebGpuProjectionInstruction> {
  final RenderContextWebGPU renderContext;

  _WebGpuProjectionPipe(this.renderContext);

  @override
  void upload(InstructionSet instructionSet) {}

  @override
  void execute(_WebGpuProjectionInstruction instruction) =>
      renderContext.activateProjectionMatrix(instruction.matrix);
}
