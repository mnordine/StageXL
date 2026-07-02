part of '../../engine.dart';

class _WebGpuRun {
  final BlendMode blendMode;
  final textures = <RenderTexture>[];
  var firstIndex = 0;
  var indexCount = 0;
  var vertexCount = 0;

  _WebGpuRun(RenderTexture texture, this.blendMode) {
    textures.add(texture);
  }

  int? textureIndex(RenderTexture texture) {
    for (var i = 0; i < textures.length; i++) {
      if (identical(textures[i], texture)) return i;
    }
    if (textures.length >= WebGpuPipelineSystem.maxBatchTextures) return null;
    textures.add(texture);
    return textures.length - 1;
  }
}

class WebGpuBatchSystem {
  static const _floatsPerVertex = 9;
  static const _bytesPerVertex = _floatsPerVertex * 4;

  final RenderContextWebGPU renderContext;
  final _runs = <_WebGpuRun>[];
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
    final textureIndex = _prepareForDraw(renderTexture, renderState.globalBlendMode, 4, 6);
    _bakeQuadVertices(renderState, renderTexture, renderTextureQuad.vxListQuad, textureIndex);
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

    final textureIndex = _prepareForDraw(renderTexture, renderState.globalBlendMode, vertexCount, ixList.length);
    _bakeVertices(renderState, renderTexture, vxList, vertexCount, textureIndex, r, g, b, a);
    final baseVertex = _vertexCount - vertexCount;
    for (var i = 0; i < ixList.length; i++) {
      _indices[_indexPosition++] = baseVertex + ixList[i];
    }
    _runs.last.indexCount += ixList.length;
  }

  int _prepareForDraw(RenderTexture texture, BlendMode blendMode, int vertexCount, int indexCount) {
    if (vertexCount > 0xFFFF) {
      throw StateError('WebGPU draw exceeds 16-bit index capacity.');
    }

    if (_vertexCount > 0 && _vertexCount + vertexCount > 0xFFFF) {
      flush(renderContext.consumeClearColor());
    }

    _ensureCpuVertexCapacity(_vertexPosition + vertexCount * _floatsPerVertex);
    _ensureCpuIndexCapacity(_indexPosition + indexCount + 1);

    var run = _runs.isEmpty ? null : _runs.last;
    var textureIndex = run == null || !identical(run.blendMode, blendMode) ? null : run.textureIndex(texture);
    if (textureIndex == null) {
      run = _WebGpuRun(texture, blendMode)
        ..firstIndex = _indexPosition;
      _runs.add(run);
      textureIndex = 0;
    }
    run!.vertexCount += vertexCount;
    _vertexCount += vertexCount;
    return textureIndex;
  }

  void _bakeVertices(
    RenderState renderState,
    RenderTexture renderTexture,
    Float32List vxList,
    int vertexCount,
    int textureIndex, [
    num r = 1,
    num g = 1,
    num b = 1,
    num a = 1,
  ]) {
    final matrix = renderState.globalMatrix;
    final ma = matrix.a;
    final mb = matrix.b;
    final mc = matrix.c;
    final md = matrix.d;
    final mx = matrix.tx;
    final my = matrix.ty;
    final alpha = renderState.globalAlpha * a;
    final red = r * alpha;
    final green = g * alpha;
    final blue = b * alpha;
    final textureSystem = renderContext.textureSystem;
    final textureScaleX = textureSystem._textureCoordinateScaleX(renderTexture);
    final textureScaleY = textureSystem._textureCoordinateScaleY(renderTexture);
    final textureIndexValue = textureIndex.toDouble();

    var writeIndex = _vertexPosition;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      _vertices[writeIndex++] = mx + ma * x + mc * y;
      _vertices[writeIndex++] = my + mb * x + md * y;
      _vertices[writeIndex++] = red;
      _vertices[writeIndex++] = green;
      _vertices[writeIndex++] = blue;
      _vertices[writeIndex++] = alpha;
      _vertices[writeIndex++] = vxList[sourceIndex + 2] * textureScaleX;
      _vertices[writeIndex++] = vxList[sourceIndex + 3] * textureScaleY;
      _vertices[writeIndex++] = textureIndexValue;
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
    final uploadStopwatch = Stopwatch()..start();
    renderContext.pipelineSystem.uploadProjectionMatrix(renderContext.activeProjectionMatrix);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, _vertices.buffer.toJS, 0, vertexBytes)
      ..writeBuffer(_indexBuffer, 0, _indices.buffer.toJS, 0, indexBytes);
    renderContext.renderStatistics.webgpuBufferUploadMicroseconds += uploadStopwatch.elapsedMicroseconds;

    final encodeStopwatch = Stopwatch()..start();
    final pass = renderContext.commandSystem.beginColorPass(clearColor);
    pass
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes)
      ..setBindGroup(1, renderContext.pipelineSystem.projectionBindGroup);

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
        ..setBindGroup(0, renderContext.textureSystem.getBatchBindGroup(run.textures))
        ..drawIndexed(run.indexCount, 1, run.firstIndex, 0, 0);
      final statistics = renderContext.renderStatistics;
      statistics.drawCount++;
      statistics.vertexCount += run.vertexCount;
      statistics.indexCount += run.indexCount;
    }

    pass.end();
    renderContext.renderStatistics.webgpuPassEncodeMicroseconds += encodeStopwatch.elapsedMicroseconds;
    renderContext.commandSystem.submit();
    _runs.clear();
    _vertexPosition = 0;
    _indexPosition = 0;
    _vertexCount = 0;
  }

  void _bakeQuadVertices(
    RenderState renderState,
    RenderTexture renderTexture,
    Float32List vxList,
    int textureIndex,
  ) {
    final matrix = renderState.globalMatrix;
    final x1 = vxList[0];
    final y1 = vxList[1];
    final x2 = vxList[8];
    final y2 = vxList[9];
    final ma1 = x1 * matrix.a + matrix.tx;
    final ma2 = x2 * matrix.a + matrix.tx;
    final mb1 = x1 * matrix.b + matrix.ty;
    final mb2 = x2 * matrix.b + matrix.ty;
    final mc1 = y1 * matrix.c;
    final mc2 = y2 * matrix.c;
    final md1 = y1 * matrix.d;
    final md2 = y2 * matrix.d;
    final alpha = renderState.globalAlpha;
    final textureSystem = renderContext.textureSystem;
    final textureScaleX = textureSystem._textureCoordinateScaleX(renderTexture);
    final textureScaleY = textureSystem._textureCoordinateScaleY(renderTexture);
    final textureIndexValue = textureIndex.toDouble();
    final vertices = _vertices;

    var writeIndex = _vertexPosition;
    vertices[writeIndex++] = ma1 + mc1;
    vertices[writeIndex++] = mb1 + md1;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = vxList[2] * textureScaleX;
    vertices[writeIndex++] = vxList[3] * textureScaleY;
    vertices[writeIndex++] = textureIndexValue;

    vertices[writeIndex++] = ma2 + mc1;
    vertices[writeIndex++] = mb2 + md1;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = vxList[6] * textureScaleX;
    vertices[writeIndex++] = vxList[7] * textureScaleY;
    vertices[writeIndex++] = textureIndexValue;

    vertices[writeIndex++] = ma2 + mc2;
    vertices[writeIndex++] = mb2 + md2;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = vxList[10] * textureScaleX;
    vertices[writeIndex++] = vxList[11] * textureScaleY;
    vertices[writeIndex++] = textureIndexValue;

    vertices[writeIndex++] = ma1 + mc2;
    vertices[writeIndex++] = mb1 + md2;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = alpha;
    vertices[writeIndex++] = vxList[14] * textureScaleX;
    vertices[writeIndex++] = vxList[15] * textureScaleY;
    vertices[writeIndex++] = textureIndexValue;
    _vertexPosition = writeIndex;
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
