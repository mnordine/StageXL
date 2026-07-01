part of '../../engine.dart';

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
  final _runs = <_WebGpuRun>[];
  final _combined = Matrix3D.fromIdentity();
  late Float32List _vertices;
  late Uint16List _indices;
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  var _vertexCapacity = 0;
  var _indexCapacity = 0;
  var _vertexPosition = 0;
  var _indexPosition = 0;
  var _vertexCount = 0;

  WebGpuBatchSystem(this.renderContext) {
    _vertices = Float32List(_floatsPerVertex * 4);
    _indices = Uint16List(12);
    _vertexBuffer = _createVertexBuffer(_bytesPerVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
  }

  bool get isEmpty => _vertexCount == 0;

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
    _prepareForDraw(renderTexture, renderState.globalBlendMode, 4, 6);
    _bakeVertices(renderState, renderTexture, vxList, 4);
    final baseVertex = _vertexCount - 4;
    _indices[_indexPosition++] = baseVertex + 0;
    _indices[_indexPosition++] = baseVertex + 1;
    _indices[_indexPosition++] = baseVertex + 2;
    _indices[_indexPosition++] = baseVertex + 0;
    _indices[_indexPosition++] = baseVertex + 2;
    _indices[_indexPosition++] = baseVertex + 3;
    _runs.last.indexCount += 6;
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

    _prepareForDraw(renderTexture, renderState.globalBlendMode, vertexCount, ixList.length);
    _bakeVertices(renderState, renderTexture, vxList, vertexCount, r, g, b, a);
    final baseVertex = _vertexCount - vertexCount;
    for (var i = 0; i < ixList.length; i++) {
      _indices[_indexPosition++] = baseVertex + ixList[i];
    }
    _runs.last.indexCount += ixList.length;
  }

  void _prepareForDraw(RenderTexture texture, BlendMode blendMode, int vertexCount, int indexCount) {
    if (vertexCount > 0xFFFF) {
      throw StateError('WebGPU draw exceeds 16-bit index capacity.');
    }

    if (_vertexCount > 0 && _vertexCount + vertexCount > 0xFFFF) {
      flush(renderContext.consumeClearColor());
    }

    _ensureCpuVertexCapacity(_vertexPosition + vertexCount * _floatsPerVertex);
    _ensureCpuIndexCapacity(_indexPosition + indexCount + 1);

    final run = _runs.isEmpty ? null : _runs.last;
    if (run == null || !identical(run.texture, texture) || !identical(run.blendMode, blendMode)) {
      _runs.add(_WebGpuRun(texture, blendMode)
        ..firstIndex = _indexPosition);
    }
    _runs.last.vertexCount += vertexCount;
    _vertexCount += vertexCount;
  }

  void _bakeVertices(
    RenderState renderState,
    RenderTexture renderTexture,
    Float32List vxList,
    int vertexCount, [
    num r = 1,
    num g = 1,
    num b = 1,
    num a = 1,
  ]) {
    final combined = _combined
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);
    final alpha = renderState.globalAlpha * a;
    final red = r * alpha;
    final green = g * alpha;
    final blue = b * alpha;
    final textureSystem = renderContext.textureSystem;
    final textureScaleX = textureSystem._textureCoordinateScaleX(renderTexture);
    final textureScaleY = textureSystem._textureCoordinateScaleY(renderTexture);

    var writeIndex = _vertexPosition;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;

      _vertices[writeIndex++] = clipX;
      _vertices[writeIndex++] = clipY;
      _vertices[writeIndex++] = clipZ * 0.5 + clipW * 0.5;
      _vertices[writeIndex++] = clipW;
      _vertices[writeIndex++] = red;
      _vertices[writeIndex++] = green;
      _vertices[writeIndex++] = blue;
      _vertices[writeIndex++] = alpha;
      _vertices[writeIndex++] = vxList[sourceIndex + 2] * textureScaleX;
      _vertices[writeIndex++] = vxList[sourceIndex + 3] * textureScaleY;
    }
    _vertexPosition = writeIndex;
  }

  void flush(List<num>? clearColor) {
    if (_vertexCount == 0 && clearColor == null) return;

    if (_vertexCount == 0) {
      final pass = renderContext.commandSystem.beginColorPass(clearColor);
      pass.end();
      renderContext.commandSystem.submit();
      return;
    }

    final vertexBytes = _vertexPosition * 4;
    final indexBytes = (_indexPosition.isOdd ? _indexPosition + 1 : _indexPosition) * 2;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, _vertices.buffer.toJS, 0, vertexBytes)
      ..writeBuffer(_indexBuffer, 0, _indices.buffer.toJS, 0, indexBytes);

    final pass = renderContext.commandSystem.beginColorPass(clearColor);
    pass
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);

    GPURenderPipeline? activePipeline;
    final stencilValue = renderContext.maskSystem.activeStencilValue;
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    for (final run in _runs) {
      final pipeline = renderContext.pipelineSystem.getPipeline(run.blendMode, stencilTest: stencilValue > 0);
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
    _runs.clear();
    _vertexPosition = 0;
    _indexPosition = 0;
    _vertexCount = 0;
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

  void _ensureCpuVertexCapacity(int size) {
    if (size <= _vertices.length) return;
    var capacity = _vertices.length * 2;
    while (capacity < size) {
      capacity *= 2;
    }
    _vertices = Float32List(capacity);
  }

  void _ensureCpuIndexCapacity(int size) {
    if (size <= _indices.length) return;
    var capacity = _indices.length * 2;
    while (capacity < size) {
      capacity *= 2;
    }
    _indices = Uint16List(capacity);
  }
}
