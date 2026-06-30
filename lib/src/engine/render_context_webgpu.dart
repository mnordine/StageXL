part of '../engine.dart';

class RenderContextWebGPU extends RenderContext {
  final HTMLCanvasElement _canvasElement;
  final WebGpuDeviceSystem deviceSystem;
  late final WebGpuCommandSystem commandSystem;
  late final WebGpuTextureSystem textureSystem;
  late final WebGpuPipelineSystem pipelineSystem;
  late final WebGpuBatchSystem batchSystem;
  late final WebGpuMaskSystem maskSystem;
  late final WebGpuFilterSystem filterSystem;
  final _projectionMatrix = Matrix3D.fromIdentity();
  final _solidFillIndexList = Int16List.fromList([0, 1, 2]);
  final _solidFillVertexList = Float32List(6);
  RenderTexture? _solidFillTexture;
  RenderTexture? _activeRenderTexture;
  List<num>? _clearColor;

  RenderContextWebGPU._(this._canvasElement, this.deviceSystem) {
    commandSystem = WebGpuCommandSystem(this);
    textureSystem = WebGpuTextureSystem(this);
    pipelineSystem = WebGpuPipelineSystem(this);
    batchSystem = WebGpuBatchSystem(this);
    maskSystem = WebGpuMaskSystem(this);
    filterSystem = WebGpuFilterSystem(this);
    _updateStageProjection();
    _contextRestoredEvent.add(RenderContextEvent());
  }

  static Future<RenderContextWebGPU?> create(
    HTMLCanvasElement canvas, {
    required PowerPreference powerPreference,
    bool alpha = false,
    bool antialias = false,
  }) async {
    final deviceSystem = await WebGpuDeviceSystem.create(
      canvas,
      alpha: alpha,
      antialias: antialias,
      powerPreference: powerPreference,
    );
    if (deviceSystem == null) return null;
    return RenderContextWebGPU._(canvas, deviceSystem);
  }

  GPUDevice get device => deviceSystem.device;
  GPUCanvasContext get canvasContext => deviceSystem.canvasContext;
  GPUTextureFormat get preferredTextureFormat => deviceSystem.preferredTextureFormat;
  int get viewportWidth => _activeRenderTexture?.width ?? _canvasElement.width;
  int get viewportHeight => _activeRenderTexture?.height ?? _canvasElement.height;
  RenderTexture? get activeRenderTexture => _activeRenderTexture;
  Matrix3D get activeProjectionMatrix => _projectionMatrix;

  @override
  RenderEngine get renderEngine => .WebGPU;

  @override
  int? get maxTextureSize => deviceSystem.maxTextureSize;

  @override
  Object? getParameter(int parameter) => null;

  @override
  void reset() {
    _updateStageProjection();
  }

  @override
  void clear(int color) {
    commandSystem.beginFrame();
    maskSystem.resetFrame();
    _setClearColor(color);
  }

  void clearActiveRenderTexture(int color) {
    _setClearColor(color);
  }

  void _setClearColor(int color) {
    const inv255 = 1 / 255;
    _clearColor = [
      colorGetR(color) * inv255,
      colorGetG(color) * inv255,
      colorGetB(color) * inv255,
      colorGetA(color) * inv255,
    ];
  }

  @override
  void flush() {
    batchSystem.flush(_clearColor);
    _clearColor = null;
  }

  void activateProjectionMatrix(Matrix3D matrix) {
    flush();
    _projectionMatrix.copyFrom(matrix);
  }

  void activateRenderTexture(RenderTexture? renderTexture) {
    if (identical(renderTexture, _activeRenderTexture)) return;
    flush();
    _activeRenderTexture = renderTexture;
  }

  void _updateStageProjection() {
    final width = viewportWidth.toDouble();
    final height = viewportHeight.toDouble();
    if (width <= 0 || height <= 0) return;
    _projectionMatrix.setIdentity();
    _projectionMatrix.scale(2 / width, -2 / height, 1);
    _projectionMatrix.translate(-1, 1, 0);
  }

  RenderTexture _getSolidFillTexture() {
    var texture = _solidFillTexture;
    if (texture != null) return texture;
    texture = RenderTexture(1, 1, 0xFFFFFFFF)..filtering = RenderTextureFiltering.NEAREST;
    return _solidFillTexture = texture;
  }

  @override
  void beginRenderMask(RenderState renderState, RenderMask mask) {
    flush();
    maskSystem.beginMask(renderState, mask);
  }

  @override
  void endRenderMask(RenderState renderState, RenderMask mask) {
    flush();
    maskSystem.endMask(renderState, mask);
  }

  @override
  void renderTextureQuad(RenderState renderState, RenderTextureQuad renderTextureQuad) {
    batchSystem.renderTextureQuad(renderState, renderTextureQuad);
  }

  @override
  void renderTextureMesh(
      RenderState renderState, RenderTexture renderTexture, Int16List ixList, Float32List vxList) {
    if (maskSystem.isRenderingStencilMask) {
      maskSystem.renderTriangleMesh(renderState, ixList, vxList);
      return;
    }

    batchSystem.renderTextureMesh(renderState, renderTexture, ixList, vxList);
  }

  @override
  void renderTextureMapping(
    RenderState renderState,
    RenderTexture renderTexture,
    Matrix mappingMatrix,
    Int16List ixList,
    Float32List vxList,
  ) {
    final vertexCount = vxList.length >> 1;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final mapped = Float32List(vertexCount * 4);
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 2) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final targetIndex = i * 4;
      mapped[targetIndex + 0] = x;
      mapped[targetIndex + 1] = y;
      mapped[targetIndex + 2] = mappingMatrix.tx + mappingMatrix.a * x + mappingMatrix.c * y;
      mapped[targetIndex + 3] = mappingMatrix.ty + mappingMatrix.b * x + mappingMatrix.d * y;
    }

    batchSystem.renderTextureMesh(renderState, renderTexture, ixList, mapped);
  }

  @override
  void renderTriangle(RenderState renderState, num x1, num y1, num x2, num y2, num x3, num y3, int color) {
    final vertices = _solidFillVertexList;
    vertices[0] = x1.toDouble();
    vertices[1] = y1.toDouble();
    vertices[2] = x2.toDouble();
    vertices[3] = y2.toDouble();
    vertices[4] = x3.toDouble();
    vertices[5] = y3.toDouble();
    renderTriangleMesh(renderState, _solidFillIndexList, vertices, color);
  }

  @override
  void renderTriangleMesh(RenderState renderState, Int16List ixList, Float32List vxList, int color) {
    if (maskSystem.isRenderingStencilMask) {
      maskSystem.renderTriangleMesh(renderState, ixList, vxList);
      return;
    }

    final vertexCount = vxList.length >> 1;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final mapped = Float32List(vertexCount * 4);
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 2) {
      final targetIndex = i * 4;
      mapped[targetIndex + 0] = vxList[sourceIndex + 0];
      mapped[targetIndex + 1] = vxList[sourceIndex + 1];
      mapped[targetIndex + 2] = 0;
      mapped[targetIndex + 3] = 0;
    }

    const inv255 = 1 / 255;
    batchSystem.renderTextureMesh(
      renderState,
      _getSolidFillTexture(),
      ixList,
      mapped,
      colorGetR(color) * inv255,
      colorGetG(color) * inv255,
      colorGetB(color) * inv255,
      colorGetA(color) * inv255,
    );
  }

  @override
  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    filterSystem.renderTextureQuadFiltered(renderState, renderTextureQuad, renderFilters);
  }

  @override
  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    filterSystem.renderObjectFiltered(renderState, renderObject);
  }
}
