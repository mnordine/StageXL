part of '../../engine.dart';

class _WebGpuQueuedDraw {
  final Float32List vertices;
  final Uint16List indices;
  final int vertexCount;
  final RenderTexture texture;
  final BlendMode blendMode;

  _WebGpuQueuedDraw(this.vertices, this.indices, this.vertexCount, this.texture, this.blendMode);
}

class _WebGpuRun {
  final RenderTexture texture;
  final BlendMode blendMode;
  var firstIndex = 0;
  var indexCount = 0;
  var vertexCount = 0;

  _WebGpuRun(this.texture, this.blendMode);
}

class WebGpuBatchSystem {
  static const _floatsPerVertex = 10;
  static const _bytesPerVertex = _floatsPerVertex * 4;

  final RenderContextWebGPU renderContext;
  final _queue = <_WebGpuQueuedDraw>[];
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  var _vertexCapacity = 0;
  var _indexCapacity = 0;

  WebGpuBatchSystem(this.renderContext) {
    _vertexBuffer = _createVertexBuffer(_bytesPerVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
  }

  bool get isEmpty => _queue.isEmpty;

  void renderTextureQuad(RenderState renderState, RenderTextureQuad renderTextureQuad) {
    if (renderTextureQuad.hasCustomVertices) {
      renderTextureMesh(
        renderState,
        renderTextureQuad.renderTexture,
        renderTextureQuad.ixList,
        renderTextureQuad.vxList,
      );
      return;
    }

    final renderTexture = renderTextureQuad.renderTexture;
    final vxList = renderTextureQuad.vxList;
    final baked = Float32List(4 * _floatsPerVertex);
    _bakeVertices(renderState, vxList, 4, baked);
    _queue.add(_WebGpuQueuedDraw(
      baked,
      Uint16List.fromList([0, 1, 2, 0, 2, 3]),
      4,
      renderTexture,
      renderState.globalBlendMode,
    ));
  }

  void renderTextureMesh(
    RenderState renderState,
    RenderTexture renderTexture,
    Int16List ixList,
    Float32List vxList, [
    num r = 1,
    num g = 1,
    num b = 1,
    num a = 1,
  ]) {
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final baked = Float32List(vertexCount * _floatsPerVertex);
    _bakeVertices(renderState, vxList, vertexCount, baked, r, g, b, a);
    _queue.add(_WebGpuQueuedDraw(
      baked,
      Uint16List.fromList(ixList),
      vertexCount,
      renderTexture,
      renderState.globalBlendMode,
    ));
  }

  void _bakeVertices(
    RenderState renderState,
    Float32List vxList,
    int vertexCount,
    Float32List target, [
    num r = 1,
    num g = 1,
    num b = 1,
    num a = 1,
  ]) {
    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);
    final alpha = renderState.globalAlpha * a;
    final red = r * alpha;
    final green = g * alpha;
    final blue = b * alpha;

    var writeIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;

      target[writeIndex++] = clipX;
      target[writeIndex++] = clipY;
      target[writeIndex++] = clipZ * 0.5 + clipW * 0.5;
      target[writeIndex++] = clipW;
      target[writeIndex++] = red;
      target[writeIndex++] = green;
      target[writeIndex++] = blue;
      target[writeIndex++] = alpha;
      target[writeIndex++] = vxList[sourceIndex + 2];
      target[writeIndex++] = vxList[sourceIndex + 3];
    }
  }

  void flush(List<num>? clearColor) {
    if (_queue.isEmpty && clearColor == null) return;

    if (_queue.isEmpty) {
      final pass = renderContext.commandSystem.beginColorPass(clearColor);
      pass.end();
      renderContext.commandSystem.submit();
      return;
    }

    final runs = <_WebGpuRun>[];
    RenderTexture? currentTexture;
    BlendMode? currentBlendMode;
    _WebGpuRun? currentRun;
    var totalVertices = 0;
    var totalIndices = 0;

    for (final draw in _queue) {
      if (!identical(draw.texture, currentTexture) || !identical(draw.blendMode, currentBlendMode)) {
        currentTexture = draw.texture;
        currentBlendMode = draw.blendMode;
        currentRun = _WebGpuRun(draw.texture, draw.blendMode);
        runs.add(currentRun);
      }
      currentRun!
        ..indexCount += draw.indices.length
        ..vertexCount += draw.vertexCount;
      totalVertices += draw.vertexCount;
      totalIndices += draw.indices.length;
    }

    if (totalVertices > 0xFFFF) {
      throw StateError('WebGPU batch exceeds 16-bit index capacity.');
    }

    final vertices = Float32List(totalVertices * _floatsPerVertex);
    final paddedIndexCount = totalIndices.isOdd ? totalIndices + 1 : totalIndices;
    final indices = Uint16List(paddedIndexCount);
    var vertexOffset = 0;
    var indexOffset = 0;
    var baseVertex = 0;
    var runIndex = 0;
    RenderTexture? lastTexture;
    BlendMode? lastBlendMode;

    for (final draw in _queue) {
      if (!identical(draw.texture, lastTexture) || !identical(draw.blendMode, lastBlendMode)) {
        lastTexture = draw.texture;
        lastBlendMode = draw.blendMode;
        runs[runIndex++].firstIndex = indexOffset;
      }

      final vertexFloats = draw.vertexCount * _floatsPerVertex;
      vertices.setRange(vertexOffset, vertexOffset + vertexFloats, draw.vertices);
      vertexOffset += vertexFloats;
      for (var i = 0; i < draw.indices.length; i++) {
        indices[indexOffset + i] = baseVertex + draw.indices[i];
      }
      indexOffset += draw.indices.length;
      baseVertex += draw.vertexCount;
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS);

    final pass = renderContext.commandSystem.beginColorPass(clearColor);
    pass
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);

    GPURenderPipeline? activePipeline;
    for (final run in runs) {
      final pipeline = renderContext.pipelineSystem.getPipeline(run.blendMode);
      if (!identical(pipeline, activePipeline)) {
        pass.setPipeline(pipeline);
        activePipeline = pipeline;
      }
      pass
        ..setBindGroup(0, renderContext.textureSystem.getBindGroup(run.texture))
        ..drawIndexed(run.indexCount, 1, run.firstIndex, 0, 0);
      final statistics = renderContext.renderStatistics;
      statistics.drawCount++;
      statistics.vertexCount += run.vertexCount;
      statistics.indexCount += run.indexCount;
    }

    pass.end();
    renderContext.commandSystem.submit();
    _queue.clear();
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
