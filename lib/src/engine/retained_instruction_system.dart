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
  final _shaderMaskStack = <({RenderMask mask, Rectangle<num>? previousScissor, bool batched})>[];
  var _instructionSet = InstructionSet();
  var _cursor = 0;
  var _oldInstructionCount = 0;
  var _structureChanged = true;
  var _isCollecting = false;
  Rectangle<num>? _activeShaderScissor;

  _RetainedInstructionSystem(this.renderContext) {
    _instructionPipes.register(_commandPipe);
  }

  bool get isCollecting => _isCollecting;

  void collect(RenderState renderState, RenderObject renderObject) {
    _instructionSet = _instructionSets[renderObject] ??= InstructionSet();
    _shaderMaskStack.clear();
    _activeShaderScissor = null;
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
    _commandPipe.beginUpload();
    for (var i = 0; i < _instructionSet.instructionCount; i++) {
      _instructionPipes.upload(_instructionSet.instructionAt(i));
    }
    _commandPipe.endUpload();
    for (var i = 0; i < _instructionSet.instructionCount; i++) {
      _instructionPipes.execute(_instructionSet.instructionAt(i));
    }
    renderContext.flush();
  }

  void release(RenderObject renderObject) {
    if (_isCollecting) throw StateError('Cannot release a retained render plan during collection.');
    final instructionSet = _instructionSets[renderObject];
    if (instructionSet == null) return;
    for (var i = 0; i < instructionSet.instructionCount; i++) {
      final instruction = instructionSet._instructions[i];
      if (instruction != null) _instructionPipes.dispose(instruction);
      instructionSet._instructions[i] = null;
    }
    for (var i = 0; i < instructionSet.slotCount; i++) {
      instructionSet._slots[i] = null;
    }
    instructionSet
      .._instructionCount = 0
      .._slotCount = 0;
    _instructionSets[renderObject] = null;
    if (identical(_instructionSet, instructionSet)) _instructionSet = InstructionSet();
  }

  void dispose() => _commandPipe.disposeResources();

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
    _updateWebGlShaderScissor(command);
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
    _updateWebGlShaderScissor(command);
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
    _updateWebGlShaderScissor(command);
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
    _updateWebGlShaderScissor(command);
    _cursor++;
  }

  void recordTriangleMesh(RenderState state, Int16List indices, Float32List vertices, int color) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedTriangleMeshCommand && old.matches(indices, vertices);
    final command = reusable ? old : _RetainedTriangleMeshCommand(renderContext, indices, vertices);
    if (!reusable) _replace(command);
    command.update(state, indices, vertices, color);
    _updateWebGlShaderScissor(command);
    _cursor++;
  }

  void recordDrawOperation(RenderState state, RenderDrawOperation operation) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedDrawCommand && identical(old.operation, operation);
    final command = reusable ? old : _RetainedDrawCommand(renderContext, operation);
    if (!reusable) _replace(command);
    command.updateState(state);
    _cursor++;
  }

  void recordCanvasText(RenderState state, RenderText text) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedCanvasTextCommand && identical(old.text, text);
    final command = reusable ? old : _RetainedCanvasTextCommand(renderContext, text);
    if (!reusable) _replace(command);
    command.updateState(state);
    _cursor++;
  }

  void recordMask(RenderState state, RenderMask mask, {required bool begin}) {
    if (_supportsShaderScissor) {
      if (begin) {
        final previousScissor = _activeShaderScissor;
        final scissor = mask is ShaderScissorRenderMask ? mask.getScissorRectangle(state) : null;
        final batched = scissor != null;
        _shaderMaskStack.add((mask: mask, previousScissor: previousScissor, batched: batched));
        if (batched) {
          _activeShaderScissor = previousScissor == null ? scissor : previousScissor.intersection(scissor);
          return;
        }
      } else {
        final entry = _shaderMaskStack.removeLast();
        if (!identical(entry.mask, mask)) throw StateError('Retained mask collection order is invalid.');
        if (entry.batched) {
          _activeShaderScissor = entry.previousScissor;
          return;
        }
      }
    }

    final old = _instructionAtCursor;
    final reusable = old is _RetainedMaskCommand && old.begin == begin && identical(old.mask, mask);
    final command = reusable ? old : _RetainedMaskCommand(renderContext, mask, begin);
    if (!reusable) _replace(command);
    command.updateState(state);
    _cursor++;
  }

  bool get _supportsShaderScissor => renderContext is RenderContextWebGL;

  void _updateWebGlShaderScissor(_RetainedWebGLBatchCommand command) =>
      command.webGlShaderScissor = _activeShaderScissor;

  void recordCanvasShadow(
    RenderState? state,
    int color,
    double blur,
    double offsetX,
    double offsetY, {
    required bool begin,
  }) {
    final old = _instructionAtCursor;
    final reusable = old is _RetainedCanvasShadowCommand && old.begin == begin;
    final command = reusable ? old : _RetainedCanvasShadowCommand(renderContext, begin);
    if (!reusable) _replace(command);
    if (state != null) command.update(state, color, blur, offsetX, offsetY);
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
  late final _RetainedWebGLUpload? _webGlUpload = switch (renderContext) {
    final RenderContextWebGL context => _RetainedWebGLUpload(context),
    _ => null,
  };

  _RetainedCommandPipe(this.renderContext);

  @override
  InstructionPipeId<_RetainedCommand> get id => _RetainedCommand.pipeId;

  void beginUpload() => _webGlUpload?.begin();

  @override
  void upload(_RetainedCommand instruction) => _webGlUpload?.add(instruction);

  void endUpload() => _webGlUpload?.end();

  @override
  void execute(_RetainedCommand instruction) => instruction.execute(renderContext);

  @override
  void dispose(_RetainedCommand instruction) {
    if (instruction is _RetainedWebGLBatchCommand && instruction.webGlBatchSlice != null) {
      _webGlUpload?.invalidate();
    }
  }

  void disposeResources() => _webGlUpload?.dispose();
}

final class _RetainedWebGLUpload {
  static const _floatsPerVertex = 9;
  static const _clippedFloatsPerVertex = 13;
  static const _bytesPerVertex = _floatsPerVertex * 4;
  static const _bytesPerIndex = 2;
  static const _maxSliceVertices = 65535;

  final RenderContextWebGL renderContext;
  final _sequence = <_RetainedWebGLBatchCommand>[];
  final _slices = <_RetainedWebGLBatchSlice>[];
  var _vertexData = Float32List(_floatsPerVertex * 4);
  var _indexData = Uint16List(12);
  WebGLBuffer? _vertexBuffer;
  WebGLBuffer? _indexBuffer;
  var _contextIdentifier = -1;
  var _vertexCapacity = 0;
  var _indexCapacity = 0;
  var _vertexLength = 0;
  var _indexLength = 0;
  var _previousVertexLength = 0;
  var _previousIndexLength = 0;
  var _dirtyVertexStart = -1;
  var _dirtyVertexEnd = 0;
  var _dirtyIndexStart = -1;
  var _dirtyIndexEnd = 0;
  var _sliceCount = 0;

  _RetainedWebGLUpload(this.renderContext);

  void begin() {
    _previousVertexLength = _vertexLength;
    _previousIndexLength = _indexLength;
    _vertexLength = 0;
    _indexLength = 0;
    _dirtyVertexStart = -1;
    _dirtyVertexEnd = 0;
    _dirtyIndexStart = -1;
    _dirtyIndexEnd = 0;
    _sliceCount = 0;
    _sequence.clear();
  }

  void add(_RetainedCommand command) {
    if (command is _RetainedWebGLBatchCommand) {
      _sequence.add(command);
    } else {
      _flushSequence();
    }
  }

  void end() {
    _flushSequence();
    for (var i = _sliceCount; i < _slices.length; i++) {
      _slices[i].clearAssignments();
    }
    _uploadBuffers();
    _prepareTextures();
  }

  void _flushSequence() {
    if (_sequence.isEmpty) return;
    var start = 0;
    while (start < _sequence.length) {
      final shaderScissor = _sequence[start].webGlShaderScissor != null;
      var end = start;
      var vertexCount = 0;
      while (end < _sequence.length) {
        if ((_sequence[end].webGlShaderScissor != null) != shaderScissor) break;
        final nextVertexCount = _sequence[end].webGlVertices.length ~/ _sequence[end].webGlVertexStride;
        if (nextVertexCount > _maxSliceVertices) {
          if (end == start) end++;
          break;
        }
        if (vertexCount + nextVertexCount > _maxSliceVertices) break;
        vertexCount += nextVertexCount;
        end++;
      }

      if (end == start + 1 &&
          _sequence[start].webGlVertices.length ~/ _sequence[start].webGlVertexStride > _maxSliceVertices) {
        _sequence[start]
          ..webGlBatchSlice = null
          ..isWebGlBatchLeader = false;
      } else {
        _buildSlice(start, end, shaderScissor: shaderScissor);
      }
      start = end;
    }
    _sequence.clear();
  }

  void _buildSlice(int start, int end, {required bool shaderScissor}) {
    final slice = _sliceAt(_sliceCount++)
      ..reset(_vertexLength, _indexLength, shaderScissor: shaderScissor);
    var sliceVertexCount = 0;
    final opaqueTarget = renderContext._activeRenderTargetIsOpaque;
    final dualSourceBlending = renderContext.dualSourceBlending &&
        (!opaqueTarget ||
            _sequence
                .getRange(start, end)
                .any((command) => _requiresDualSourceBatchBlendMode(command.state.globalBlendMode)));

    for (var commandIndex = start; commandIndex < end; commandIndex++) {
      final command = _sequence[commandIndex];
      final texture = command.webGlTexture;
      final blendMode = command.state.globalBlendMode;
      final batchBlendMode = _batchBlendMode(
        blendMode,
        opaqueTarget: opaqueTarget,
        dualSourceBlending: dualSourceBlending,
        promoteOpaqueNormalAdd: dualSourceBlending,
      );
      var run = slice.lastRun;
      var textureIndex = run?.textureIndex(texture);
      if (run == null || !_sameBlendMode(run.blendMode, batchBlendMode) || textureIndex == null) {
        run = slice.addRun(batchBlendMode, _indexLength, texture);
        textureIndex = 0;
      }

      final vertices = command.webGlVertices;
      final indices = command.webGlIndices;
      final commandVertexCount = vertices.length ~/ command.webGlVertexStride;
      _ensureCpuCapacity(
        _vertexLength + commandVertexCount * slice.vertexFloatStride,
        _indexLength + indices.length,
      );
      _bakeVertices(
        command,
        vertices,
        _batchTextureIndex(
          textureIndex,
          blendMode,
          RenderProgramBatchWebGL._maxTextures,
          opaqueTarget: opaqueTarget,
          dualSourceBlending: dualSourceBlending,
          promoteOpaqueNormalAdd: dualSourceBlending,
        ),
      );
      _bakeIndices(indices, sliceVertexCount);
      run
        ..vertexCount += commandVertexCount
        ..indexCount += indices.length;
      sliceVertexCount += commandVertexCount;
      slice.addCommand(command);
    }

    slice.finish(sliceVertexCount, _indexLength - slice.indexOffset);
  }

  _RetainedWebGLBatchSlice _sliceAt(int index) {
    if (index == _slices.length) _slices.add(_RetainedWebGLBatchSlice(this));
    return _slices[index];
  }

  bool _sameBlendMode(BlendMode first, BlendMode second) =>
      first.srcFactor == second.srcFactor && first.dstFactor == second.dstFactor;

  void _bakeVertices(_RetainedWebGLBatchCommand command, Float32List source, int textureIndex) {
    final matrix = command.state.globalMatrix;
    final alpha = command.webGlAlpha * command.state.globalAlpha;
    final colorMultiplier = (command.webGlPremultiplyColor ? alpha : 1).toDouble();
    final red = command.webGlRed * colorMultiplier;
    final green = command.webGlGreen * colorMultiplier;
    final blue = command.webGlBlue * colorMultiplier;
    final stride = command.webGlVertexStride;
    final mapping = command.webGlMappingMatrix;
    for (var sourceIndex = 0; sourceIndex + 1 < source.length; sourceIndex += stride) {
      final x = source[sourceIndex + 0];
      final y = source[sourceIndex + 1];
      _writeVertex(matrix.tx + matrix.a * x + matrix.c * y);
      _writeVertex(matrix.ty + matrix.b * x + matrix.d * y);
      _writeVertex(stride == 4
          ? source[sourceIndex + 2]
          : mapping == null
              ? 0
              : mapping.tx + mapping.a * x + mapping.c * y);
      _writeVertex(stride == 4
          ? source[sourceIndex + 3]
          : mapping == null
              ? 0
              : mapping.ty + mapping.b * x + mapping.d * y);
      _writeVertex(red);
      _writeVertex(green);
      _writeVertex(blue);
      _writeVertex(alpha);
      _writeVertex(textureIndex.toDouble());
      final scissor = command.webGlShaderScissor;
      if (scissor != null) {
        _writeVertex(scissor.left.toDouble());
        if (renderContext._activeRenderFrameBuffer == null) {
          _writeVertex(renderContext._canvasElement.height - scissor.bottom.toDouble());
        } else {
          _writeVertex(scissor.top.toDouble());
        }
        _writeVertex(scissor.right.toDouble());
        if (renderContext._activeRenderFrameBuffer == null) {
          _writeVertex(renderContext._canvasElement.height - scissor.top.toDouble());
        } else {
          _writeVertex(scissor.bottom.toDouble());
        }
      }
    }
  }

  void _bakeIndices(Int16List source, int baseVertex) {
    for (final index in source) {
      _writeIndex(baseVertex + index);
    }
  }

  void _writeVertex(double value) {
    final index = _vertexLength++;
    final previous = _vertexData[index];
    _vertexData[index] = value;
    if (index >= _previousVertexLength || previous != _vertexData[index]) {
      _dirtyVertexStart = _dirtyVertexStart == -1 ? index : math.min(_dirtyVertexStart, index);
      _dirtyVertexEnd = index + 1;
    }
  }

  void _writeIndex(int value) {
    final index = _indexLength++;
    if (index >= _previousIndexLength || _indexData[index] != value) {
      _indexData[index] = value;
      _dirtyIndexStart = _dirtyIndexStart == -1 ? index : math.min(_dirtyIndexStart, index);
      _dirtyIndexEnd = index + 1;
    }
  }

  void _ensureCpuCapacity(int vertexLength, int indexLength) {
    if (vertexLength > _vertexData.length) {
      var capacity = _vertexData.length * 2;
      while (capacity < vertexLength) {
        capacity *= 2;
      }
      _vertexData = Float32List(capacity)..setRange(0, _vertexLength, _vertexData);
    }
    if (indexLength > _indexData.length) {
      var capacity = _indexData.length * 2;
      while (capacity < indexLength) {
        capacity *= 2;
      }
      _indexData = Uint16List(capacity)..setRange(0, _indexLength, _indexData);
    }
  }

  void _uploadBuffers() {
    if (_vertexLength == 0 || _indexLength == 0) return;
    final buffersRebuilt = _ensureGpuBuffers();
    final gl = renderContext.rawContext;
    gl.bindBuffer(WebGL.ARRAY_BUFFER, _vertexBuffer);
    if (buffersRebuilt.$1) {
      gl.bufferData(WebGL.ARRAY_BUFFER, _vertexCapacity.toJS, WebGL.DYNAMIC_DRAW);
      _dirtyVertexStart = 0;
      _dirtyVertexEnd = _vertexLength;
    }
    if (_dirtyVertexStart != -1) {
      final data = Float32List.view(
        _vertexData.buffer,
        _dirtyVertexStart * 4,
        _dirtyVertexEnd - _dirtyVertexStart,
      );
      gl.bufferSubData(WebGL.ARRAY_BUFFER, _dirtyVertexStart * 4, data.toJS);
      renderContext.renderStatistics.retainedInstructionUploadCount++;
    }

    gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, _indexBuffer);
    if (buffersRebuilt.$2) {
      gl.bufferData(WebGL.ELEMENT_ARRAY_BUFFER, _indexCapacity.toJS, WebGL.DYNAMIC_DRAW);
      _dirtyIndexStart = 0;
      _dirtyIndexEnd = _indexLength;
    }
    if (_dirtyIndexStart != -1) {
      final data = Uint16List.view(
        _indexData.buffer,
        _dirtyIndexStart * 2,
        _dirtyIndexEnd - _dirtyIndexStart,
      );
      gl.bufferSubData(WebGL.ELEMENT_ARRAY_BUFFER, _dirtyIndexStart * 2, data.toJS);
      renderContext.renderStatistics.retainedInstructionUploadCount++;
    }
  }

  (bool, bool) _ensureGpuBuffers() {
    if (_contextIdentifier != renderContext.contextIdentifier) {
      _contextIdentifier = renderContext.contextIdentifier;
      _vertexBuffer = null;
      _indexBuffer = null;
      _vertexCapacity = 0;
      _indexCapacity = 0;
    }

    final gl = renderContext.rawContext;
    var vertexRebuilt = false;
    var indexRebuilt = false;
    final vertexBytes = _vertexLength * 4;
    final indexBytes = _indexLength * 2;
    if (_vertexBuffer == null || vertexBytes > _vertexCapacity) {
      gl.deleteBuffer(_vertexBuffer);
      _vertexCapacity = math.max(vertexBytes * 2, _bytesPerVertex * 4);
      _vertexBuffer = gl.createBuffer();
      if (_vertexBuffer == null) {
        throw StateError(gl.isContextLost() ? 'ContextLost' : 'Failed to create WebGL buffer.');
      }
      vertexRebuilt = true;
    }
    if (_indexBuffer == null || indexBytes > _indexCapacity) {
      gl.deleteBuffer(_indexBuffer);
      _indexCapacity = math.max(indexBytes * 2, _bytesPerIndex * 12);
      _indexBuffer = gl.createBuffer();
      if (_indexBuffer == null) throw StateError(gl.isContextLost() ? 'ContextLost' : 'Failed to create WebGL buffer.');
      indexRebuilt = true;
    }
    return (vertexRebuilt, indexRebuilt);
  }

  void _prepareTextures() {
    for (var sliceIndex = 0; sliceIndex < _sliceCount; sliceIndex++) {
      final slice = _slices[sliceIndex];
      for (var runIndex = 0; runIndex < slice.runCount; runIndex++) {
        final run = slice.runs[runIndex];
        for (var i = 0; i < run.textures.length; i++) {
          renderContext.activateRenderTextureAt(run.textures[i], i, flush: false);
        }
      }
    }
  }

  void execute(_RetainedWebGLBatchSlice slice) {
    final vertexBuffer = _vertexBuffer;
    final indexBuffer = _indexBuffer;
    if (vertexBuffer == null || indexBuffer == null || slice.indexCount == 0) return;
    renderContext.activateRenderProgram(renderContext.renderProgramBatch);
    renderContext.renderProgramBatch._executeRetainedBatch(
      renderContext,
      vertexBuffer,
      indexBuffer,
      slice,
    );
  }

  void invalidate() {
    for (final slice in _slices) {
      slice.clearAssignments();
    }
    _sliceCount = 0;
    _sequence.clear();
  }

  void dispose() {
    invalidate();
    final gl = renderContext.rawContext;
    gl
      ..deleteBuffer(_vertexBuffer)
      ..deleteBuffer(_indexBuffer);
    _vertexBuffer = null;
    _indexBuffer = null;
    _vertexCapacity = 0;
    _indexCapacity = 0;
  }
}

final class _RetainedWebGLBatchSlice {
  final _RetainedWebGLUpload upload;
  final commands = <_RetainedWebGLBatchCommand>[];
  final runs = <_RetainedWebGLRun>[];
  var vertexFloatOffset = 0;
  var indexOffset = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var runCount = 0;
  var shaderScissor = false;

  _RetainedWebGLBatchSlice(this.upload);

  _RetainedWebGLRun? get lastRun => runCount == 0 ? null : runs[runCount - 1];

  int get vertexFloatStride => shaderScissor
      ? _RetainedWebGLUpload._clippedFloatsPerVertex
      : _RetainedWebGLUpload._floatsPerVertex;

  void reset(int vertexFloatOffset, int indexOffset, {required bool shaderScissor}) {
    clearAssignments();
    this.vertexFloatOffset = vertexFloatOffset;
    this.indexOffset = indexOffset;
    this.shaderScissor = shaderScissor;
    vertexCount = 0;
    indexCount = 0;
    runCount = 0;
  }

  _RetainedWebGLRun addRun(BlendMode blendMode, int indexOffset, RenderTexture texture) {
    final run = runCount == runs.length
        ? _RetainedWebGLRun(blendMode, indexOffset, texture)
        : runs[runCount]..reset(blendMode, indexOffset, texture);
    if (runCount == runs.length) runs.add(run);
    runCount++;
    return run;
  }

  void addCommand(_RetainedWebGLBatchCommand command) {
    commands.add(command);
    command
      ..webGlBatchSlice = this
      ..isWebGlBatchLeader = commands.length == 1;
  }

  void finish(int vertexCount, int indexCount) {
    this.vertexCount = vertexCount;
    this.indexCount = indexCount;
  }

  void clearAssignments() {
    for (final command in commands) {
      if (identical(command.webGlBatchSlice, this)) {
        command
          ..webGlBatchSlice = null
          ..isWebGlBatchLeader = false;
      }
    }
    commands.clear();
  }

  void execute(RenderContextWebGL renderContext) => upload.execute(this);
}

final class _RetainedWebGLRun {
  late BlendMode blendMode;
  var indexOffset = 0;
  final textures = <RenderTexture>[];
  var vertexCount = 0;
  var indexCount = 0;

  _RetainedWebGLRun(BlendMode blendMode, int indexOffset, RenderTexture texture) {
    reset(blendMode, indexOffset, texture);
  }

  void reset(BlendMode blendMode, int indexOffset, RenderTexture texture) {
    this.blendMode = blendMode;
    this.indexOffset = indexOffset;
    textures
      ..clear()
      ..add(texture);
    vertexCount = 0;
    indexCount = 0;
  }

  int? textureIndex(RenderTexture texture) {
    for (var i = 0; i < textures.length; i++) {
      if (identical(textures[i], texture)) return i;
    }
    if (textures.length == RenderProgramBatchWebGL._maxTextures) return null;
    textures.add(texture);
    return textures.length - 1;
  }
}

abstract base class _RetainedWebGLBatchCommand extends _RetainedCommand {
  _RetainedWebGLBatchSlice? webGlBatchSlice;
  Rectangle<num>? webGlShaderScissor;
  var isWebGlBatchLeader = false;

  _RetainedWebGLBatchCommand(super.renderContext);

  RenderTexture get webGlTexture;
  Int16List get webGlIndices;
  Float32List get webGlVertices;
  int get webGlVertexStride => 4;
  Matrix? get webGlMappingMatrix => null;
  bool get webGlPremultiplyColor => true;
  num get webGlRed;
  num get webGlGreen;
  num get webGlBlue;
  num get webGlAlpha;

  void executeRetainedOr(RenderContext renderContext, void Function() fallback) {
    final slice = webGlBatchSlice;
    if (renderContext is RenderContextWebGL && slice != null) {
      if (isWebGlBatchLeader) slice.execute(renderContext);
      return;
    }
    fallback();
  }
}

final class _RetainedTextureQuadCommand extends _RetainedWebGLBatchCommand {
  late RenderTextureQuad quad;
  var red = 1.0;
  var green = 1.0;
  var blue = 1.0;
  var alpha = 1.0;

  _RetainedTextureQuadCommand(super.renderContext);

  @override
  RenderTexture get webGlTexture => quad.renderTexture;

  @override
  Int16List get webGlIndices => quad.hasCustomVertices ? quad.ixList : quad.ixListQuad;

  @override
  Float32List get webGlVertices => quad.hasCustomVertices ? quad.vxList : quad.vxListQuad;

  @override
  num get webGlRed => red;

  @override
  num get webGlGreen => green;

  @override
  num get webGlBlue => blue;

  @override
  num get webGlAlpha => alpha;

  void update(RenderState source, RenderTextureQuad quad, num red, num green, num blue, num alpha) {
    updateState(source);
    this.quad = quad;
    this.red = red.toDouble();
    this.green = green.toDouble();
    this.blue = blue.toDouble();
    this.alpha = alpha.toDouble();
  }

  @override
  void execute(RenderContext renderContext) => executeRetainedOr(
        renderContext,
        () => renderContext.renderTextureQuadTinted(state, quad, red, green, blue, alpha),
      );
}

final class _RetainedTextureMeshCommand extends _RetainedWebGLBatchCommand {
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

  @override
  RenderTexture get webGlTexture => texture;

  @override
  Int16List get webGlIndices => indices;

  @override
  Float32List get webGlVertices => vertices;

  @override
  num get webGlRed => red;

  @override
  num get webGlGreen => green;

  @override
  num get webGlBlue => blue;

  @override
  num get webGlAlpha => alpha;

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
  void execute(RenderContext renderContext) => executeRetainedOr(
        renderContext,
        () => renderContext.renderTextureMeshTinted(state, texture, indices, vertices, red, green, blue, alpha),
      );
}

final class _RetainedTextureMappingCommand extends _RetainedWebGLBatchCommand {
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

  @override
  RenderTexture get webGlTexture => texture;

  @override
  Int16List get webGlIndices => indices;

  @override
  Float32List get webGlVertices => vertices;

  @override
  int get webGlVertexStride => 2;

  @override
  Matrix get webGlMappingMatrix => mappingMatrix;

  @override
  bool get webGlPremultiplyColor => false;

  @override
  num get webGlRed => 1;

  @override
  num get webGlGreen => 1;

  @override
  num get webGlBlue => 1;

  @override
  num get webGlAlpha => 1;

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
  void execute(RenderContext renderContext) => executeRetainedOr(
        renderContext,
        () => renderContext.renderTextureMapping(state, texture, mappingMatrix, indices, vertices),
      );
}

final class _RetainedTriangleCommand extends _RetainedWebGLBatchCommand {
  final indices = Int16List.fromList([0, 1, 2]);
  final vertices = Float32List(6);
  var x1 = 0.0;
  var y1 = 0.0;
  var x2 = 0.0;
  var y2 = 0.0;
  var x3 = 0.0;
  var y3 = 0.0;
  var color = 0;

  _RetainedTriangleCommand(super.renderContext);

  @override
  RenderTexture get webGlTexture => (state.renderContext as RenderContextWebGL)._getSolidFillTexture();

  @override
  Int16List get webGlIndices => indices;

  @override
  Float32List get webGlVertices => vertices;

  @override
  int get webGlVertexStride => 2;

  @override
  num get webGlRed => colorGetR(color) / 255;

  @override
  num get webGlGreen => colorGetG(color) / 255;

  @override
  num get webGlBlue => colorGetB(color) / 255;

  @override
  num get webGlAlpha => colorGetA(color) / 255;

  void update(RenderState source, num x1, num y1, num x2, num y2, num x3, num y3, int color) {
    updateState(source);
    this.x1 = x1.toDouble();
    this.y1 = y1.toDouble();
    this.x2 = x2.toDouble();
    this.y2 = y2.toDouble();
    this.x3 = x3.toDouble();
    this.y3 = y3.toDouble();
    this.color = color;
    vertices
      ..[0] = this.x1
      ..[1] = this.y1
      ..[2] = this.x2
      ..[3] = this.y2
      ..[4] = this.x3
      ..[5] = this.y3;
  }

  @override
  void execute(RenderContext renderContext) => executeRetainedOr(
        renderContext,
        () => renderContext.renderTriangle(state, x1, y1, x2, y2, x3, y3, color),
      );
}

final class _RetainedTriangleMeshCommand extends _RetainedWebGLBatchCommand {
  final Int16List indices;
  final Float32List vertices;
  var color = 0;

  _RetainedTriangleMeshCommand(super.renderContext, Int16List sourceIndices, Float32List sourceVertices)
      : indices = Int16List(sourceIndices.length),
        vertices = Float32List(sourceVertices.length);

  @override
  RenderTexture get webGlTexture => (state.renderContext as RenderContextWebGL)._getSolidFillTexture();

  @override
  Int16List get webGlIndices => indices;

  @override
  Float32List get webGlVertices => vertices;

  @override
  int get webGlVertexStride => 2;

  @override
  num get webGlRed => colorGetR(color) / 255;

  @override
  num get webGlGreen => colorGetG(color) / 255;

  @override
  num get webGlBlue => colorGetB(color) / 255;

  @override
  num get webGlAlpha => colorGetA(color) / 255;

  bool matches(Int16List indices, Float32List vertices) =>
      this.indices.length == indices.length && this.vertices.length == vertices.length;

  void update(RenderState source, Int16List sourceIndices, Float32List sourceVertices, int color) {
    updateState(source);
    indices.setAll(0, sourceIndices);
    vertices.setAll(0, sourceVertices);
    this.color = color;
  }

  @override
  void execute(RenderContext renderContext) => executeRetainedOr(
        renderContext,
        () => renderContext.renderTriangleMesh(state, indices, vertices, color),
      );
}

final class _RetainedDrawCommand extends _RetainedCommand {
  final RenderDrawOperation operation;

  _RetainedDrawCommand(super.renderContext, this.operation);

  @override
  void execute(RenderContext renderContext) {
    operation.executeDraw(state);
    renderContext.flush();
  }
}

final class _RetainedCanvasTextCommand extends _RetainedCommand {
  final RenderText text;

  _RetainedCanvasTextCommand(super.renderContext, this.text);

  @override
  void execute(RenderContext renderContext) => text.renderCanvasText(state);
}

final class _RetainedMaskCommand extends _RetainedCommand {
  final RenderMask mask;
  final bool begin;

  _RetainedMaskCommand(super.renderContext, this.mask, this.begin);

  @override
  void execute(RenderContext renderContext) =>
      begin ? renderContext.beginRenderMask(state, mask) : renderContext.endRenderMask(state, mask);
}

final class _RetainedCanvasShadowCommand extends _RetainedCommand {
  final bool begin;
  var color = 0;
  var blur = 0.0;
  var offsetX = 0.0;
  var offsetY = 0.0;

  _RetainedCanvasShadowCommand(super.renderContext, this.begin);

  void update(RenderState source, int color, double blur, double offsetX, double offsetY) {
    updateState(source);
    this.color = color;
    this.blur = blur;
    this.offsetX = offsetX;
    this.offsetY = offsetY;
  }

  @override
  void execute(RenderContext renderContext) {
    if (begin) {
      renderContext.beginCanvasShadow(state, color, blur, offsetX, offsetY);
    } else {
      renderContext.endCanvasShadow();
    }
  }
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
