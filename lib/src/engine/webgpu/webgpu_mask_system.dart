part of '../../engine.dart';

class WebGpuMaskSystem {
  static const _floatsPerStencilVertex = 4;
  static const _bytesPerStencilVertex = _floatsPerStencilVertex * 4;

  final RenderContextWebGPU renderContext;
  final _scissorStack = <Rectangle<num>>[];
  final _maskStates = <_WebGpuMaskState>[];
  final _maskVertices = <double>[];
  Rectangle<num>? _activeScissor;
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  var _vertexCapacity = 0;
  var _indexCapacity = 0;
  var _renderingStencilMask = false;

  WebGpuMaskSystem(this.renderContext) {
    _vertexBuffer = _createVertexBuffer(_bytesPerStencilVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
  }

  bool get isRenderingStencilMask => _renderingStencilMask;

  int get activeStencilValue {
    for (var i = _maskStates.length - 1; i >= 0; i--) {
      final state = _maskStates[i];
      if (state.stencilValue > 0) return state.stencilValue;
    }
    return 0;
  }

  void resetFrame() {
    _scissorStack.clear();
    _maskStates.clear();
    _activeScissor = null;
    _renderingStencilMask = false;
  }

  _WebGpuMaskSnapshot _detach() {
    final snapshot = _WebGpuMaskSnapshot(
      List<Rectangle<num>>.of(_scissorStack),
      List<_WebGpuMaskState>.of(_maskStates),
      _activeScissor,
      _renderingStencilMask,
    );
    resetFrame();
    return snapshot;
  }

  void _restore(_WebGpuMaskSnapshot snapshot) {
    _scissorStack
      ..clear()
      ..addAll(snapshot.scissorStack);
    _maskStates
      ..clear()
      ..addAll(snapshot.maskStates);
    _activeScissor = snapshot.activeScissor;
    _renderingStencilMask = snapshot.renderingStencilMask;
  }

  void beginMask(RenderState renderState, RenderMask mask) {
    if (mask is ScissorRenderMask) {
      final rectangle = mask.getScissorRectangle(renderState);
      if (rectangle == null) return;
      _activeScissor = _activeScissor == null ? rectangle : _activeScissor!.intersection(rectangle);
      _scissorStack.add(_activeScissor!);
      _maskStates.add(_WebGpuMaskState(0));
      return;
    }

    _maskVertices.clear();
    _renderingStencilMask = true;
    try {
      mask.renderMask(renderState);
    } finally {
      _renderingStencilMask = false;
    }

    if (_maskVertices.isEmpty) return;

    final stencilValue = activeStencilValue + 1;
    final stencilVertices = _bakeStencilVertices(_maskVertices);
    _renderStencilMask(stencilValue, stencilVertices);
    _maskStates.add(_WebGpuMaskState(stencilValue, stencilVertices));
  }

  void endMask(RenderState renderState, RenderMask mask) {
    if (_maskStates.isEmpty) return;
    final state = _maskStates.removeLast();
    if (state.stencilValue > 0) {
      _restoreStencil(activeStencilValue);
      return;
    }

    if (_scissorStack.isNotEmpty) _scissorStack.removeLast();
    _activeScissor = _scissorStack.isEmpty ? null : _scissorStack.last;
  }

  void renderTriangleMesh(RenderState renderState, Int16List ixList, Float32List vxList) {
    final matrix = renderState.globalMatrix;
    for (var i = 0; i < ixList.length; i++) {
      final sourceIndex = ixList[i] << 1;
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      _maskVertices
        ..add(matrix.tx + matrix.a * x + matrix.c * y)
        ..add(matrix.ty + matrix.b * x + matrix.d * y);
    }
  }

  void applyScissor(GPURenderPassEncoder pass) {
    final scissor = _activeScissor;
    if (scissor == null) return;

    var left = scissor.left.floor();
    var top = scissor.top.floor();
    var width = scissor.width.ceil();
    var height = scissor.height.ceil();

    if (left < 0) {
      width += left;
      left = 0;
    }
    if (top < 0) {
      height += top;
      top = 0;
    }

    width = math.min(width, renderContext.viewportWidth - left);
    height = math.min(height, renderContext.viewportHeight - top);
    if (width <= 0 || height <= 0) return;
    pass.setScissorRect(left, top, width, height);
  }

  Float32List _bakeStencilVertices(List<double> maskVertices) {
    final vertexCount = maskVertices.length ~/ 2;
    final vertices = Float32List(vertexCount * _floatsPerStencilVertex);
    final projectionMatrix = renderContext.activeProjectionMatrix;

    var writeIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 2) {
      final x = maskVertices[sourceIndex + 0];
      final y = maskVertices[sourceIndex + 1];
      final clipX = projectionMatrix.m00 * x + projectionMatrix.m10 * y + projectionMatrix.m30;
      final clipY = projectionMatrix.m01 * x + projectionMatrix.m11 * y + projectionMatrix.m31;
      final clipZ = projectionMatrix.m02 * x + projectionMatrix.m12 * y + projectionMatrix.m32;
      final clipW = projectionMatrix.m03 * x + projectionMatrix.m13 * y + projectionMatrix.m33;
      vertices[writeIndex++] = clipX;
      vertices[writeIndex++] = clipY;
      vertices[writeIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[writeIndex++] = clipW;
    }

    return vertices;
  }

  void _renderStencilMask(int stencilValue, Float32List vertices) {
    final vertexCount = vertices.length ~/ _floatsPerStencilVertex;
    if (vertexCount > 0xFFFF) {
      throw StateError('WebGPU stencil mask exceeds 16-bit index capacity.');
    }

    final indices = Uint16List(vertexCount.isOdd ? vertexCount + 1 : vertexCount);
    for (var i = 0; i < vertexCount; i++) {
      indices[i] = i;
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS);

    final pass = renderContext.commandSystem.beginColorPass(null);
    pass
      ..setStencilReference(stencilValue)
      ..setPipeline(renderContext.pipelineSystem.getStencilWritePipeline())
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes)
      ..drawIndexed(vertexCount, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();
  }

  void _restoreStencil(int stencilValue) {
    final pass = renderContext.commandSystem.beginStencilClearPass();
    pass.end();
    renderContext.commandSystem.submit();

    if (stencilValue == 0) return;

    for (final state in _maskStates) {
      final vertices = state.stencilVertices;
      if (vertices == null) continue;
      _renderStencilMask(state.stencilValue, vertices);
    }
  }

  GPUBuffer _createVertexBuffer(int size) {
    _vertexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
    ));
  }

  GPUBuffer _createIndexBuffer(int size) {
    _indexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.INDEX,
    ));
  }

  void _ensureVertexCapacity(int size) {
    if (size <= _vertexCapacity) return;
    _vertexBuffer.destroy();
    _vertexBuffer = _createVertexBuffer(size * 2);
  }

  void _ensureIndexCapacity(int size) {
    if (size <= _indexCapacity) return;
    _indexBuffer.destroy();
    _indexBuffer = _createIndexBuffer(size * 2);
  }
}

class _WebGpuMaskState {
  final int stencilValue;
  final Float32List? stencilVertices;

  _WebGpuMaskState(this.stencilValue, [this.stencilVertices]);
}

class _WebGpuMaskSnapshot {
  final List<Rectangle<num>> scissorStack;
  final List<_WebGpuMaskState> maskStates;
  final Rectangle<num>? activeScissor;
  final bool renderingStencilMask;

  _WebGpuMaskSnapshot(this.scissorStack, this.maskStates, this.activeScissor, this.renderingStencilMask);
}
