part of '../engine.dart';

class RenderContextWebGPU extends RenderContext {
  final RenderSurface _canvasElement;
  final WebGpuDeviceSystem deviceSystem;
  final bool renderBundles;
  late final WebGpuCommandSystem commandSystem;
  late final WebGpuTextureSystem textureSystem;
  late final WebGpuPipelineSystem pipelineSystem;
  late final _WebGpuBatchSystem _batchSystem;
  late final _WebGpuInstructionSystem _instructionSystem;
  late final _WebGpuMaskSystem _maskSystem;
  late final WebGpuFilterSystem filterSystem;
  final _projectionMatrix = Matrix3D.fromIdentity();
  final _solidFillIndexList = Int16List.fromList([0, 1, 2]);
  final _solidFillVertexList = Float32List(6);
  RenderTexture? _solidFillTexture;
  RenderTexture? _activeRenderTexture;
  List<num>? _clearColor;
  GPUDeviceLostInfo? _deviceLostInfo;

  RenderContextWebGPU._(this._canvasElement, this.deviceSystem, {required this.renderBundles}) {
    commandSystem = WebGpuCommandSystem(this);
    textureSystem = WebGpuTextureSystem(this);
    pipelineSystem = WebGpuPipelineSystem(this);
    _batchSystem = _WebGpuBatchSystem(this);
    _instructionSystem = _WebGpuInstructionSystem(this);
    _maskSystem = _WebGpuMaskSystem(this);
    filterSystem = WebGpuFilterSystem(this);
    _updateStageProjection();
    unawaited(device.lost.toDart.then(_onDeviceLost));
    _contextRestoredEvent.add(const RenderContextEvent());
  }

  static Future<RenderContextWebGPU?> create(
    RenderSurface canvas, {
    required PowerPreference powerPreference,
    bool alpha = false,
    bool antialias = false,
    bool renderBundles = false,
  }) async {
    final deviceSystem = await WebGpuDeviceSystem.create(
      canvas,
      alpha: alpha,
      antialias: antialias,
      powerPreference: powerPreference,
    );
    if (deviceSystem == null) return null;
    return RenderContextWebGPU._(canvas, deviceSystem, renderBundles: renderBundles);
  }

  GPUDevice get device => deviceSystem.device;
  GPUDeviceLostInfo? get deviceLostInfo => _deviceLostInfo;
  GPUCanvasContext get canvasContext => deviceSystem.canvasContext;
  GPUTextureFormat get preferredTextureFormat => deviceSystem.preferredTextureFormat;
  int get viewportWidth => _activeRenderTexture?.width ?? _canvasElement.width;
  int get viewportHeight => _activeRenderTexture?.height ?? _canvasElement.height;
  RenderTexture? get activeRenderTexture => _activeRenderTexture;
  @override
  Matrix3D get activeProjectionMatrix => _projectionMatrix;
  int get sampleCount => _activeRenderTexture == null && deviceSystem.antialias ? 4 : 1;

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
    _maskSystem.resetFrame();
    _setClearColor(color);
  }

  void clearActiveRenderTexture(int color) {
    _setClearColor(color);
  }

  List<num>? consumeClearColor() {
    final clearColor = _clearColor;
    _clearColor = null;
    return clearColor;
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
    if (_instructionSystem.isCollecting) {
      _instructionSystem.flushBatch();
      return;
    }
    _batchSystem.flush(_clearColor);
    _clearColor = null;
  }

  @override
  void activateProjectionMatrix(Matrix3D matrix) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordProjection(matrix);
      _projectionMatrix.copyFrom(matrix);
      return;
    }
    if (!_batchSystem.isEmpty) flush();
    _projectionMatrix.copyFrom(matrix);
  }

  @override
  void buildRenderFrame(RenderState renderState, RenderObject renderObject) =>
      _instructionSystem.collect(renderState, renderObject);

  @override
  void executeRenderFrame(RenderState renderState) => _instructionSystem.execute();

  @override
  void releaseRenderPlan(RenderObject renderObject) => _instructionSystem.release(renderObject);

  @override
  void beginRenderObject(RenderState renderState, RenderObject renderObject) =>
      _instructionSystem.beginRenderable(renderState, renderObject);

  @override
  void endRenderObject(RenderObject renderObject) => _instructionSystem.endRenderable(renderObject);

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
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordMask(renderState, mask, begin: true);
      return;
    }
    flush();
    _maskSystem.beginMask(renderState, mask);
  }

  @override
  void endRenderMask(RenderState renderState, RenderMask mask) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordMask(renderState, mask, begin: false);
      return;
    }
    flush();
    _maskSystem.endMask(renderState, mask);
  }

  @override
  void renderTextureQuad(RenderState renderState, RenderTextureQuad renderTextureQuad) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTextureQuad(renderState, renderTextureQuad);
      return;
    }
    _batchSystem.renderTextureQuad(renderState, renderTextureQuad);
  }

  @override
  void renderTextureQuadTinted(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTextureQuad(renderState, renderTextureQuad, red, green, blue, alpha);
      return;
    }
    _batchSystem.renderTextureQuad(renderState, renderTextureQuad, red, green, blue, alpha);
  }

  @override
  void renderTextureMesh(
      RenderState renderState, RenderTexture renderTexture, Int16List ixList, Float32List vxList) {
    if (_maskSystem.isRenderingStencilMask) {
      _maskSystem.renderTriangleMesh(renderState, ixList, vxList);
      return;
    }
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTextureMesh(renderState, renderTexture, ixList, vxList);
      return;
    }

    _batchSystem.renderTextureMesh(renderState, renderTexture, ixList, vxList);
  }

  @override
  void renderTextureMeshTinted(
    RenderState renderState,
    RenderTexture renderTexture,
    Int16List ixList,
    Float32List vxList,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    if (_maskSystem.isRenderingStencilMask) {
      _maskSystem.renderTriangleMesh(renderState, ixList, vxList);
      return;
    }
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTextureMesh(renderState, renderTexture, ixList, vxList, red, green, blue, alpha);
      return;
    }
    _batchSystem.renderTextureMesh(renderState, renderTexture, ixList, vxList, red, green, blue, alpha);
  }

  @override
  void renderTextureMapping(
    RenderState renderState,
    RenderTexture renderTexture,
    Matrix mappingMatrix,
    Int16List ixList,
    Float32List vxList,
  ) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTextureMapping(renderState, renderTexture, mappingMatrix, ixList, vxList);
      return;
    }
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

    _batchSystem.renderTextureMesh(renderState, renderTexture, ixList, mapped);
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
    if (_maskSystem.isRenderingStencilMask) {
      _maskSystem.renderTriangleMesh(renderState, _solidFillIndexList, vertices);
      return;
    }
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTriangle(renderState, x1, y1, x2, y2, x3, y3, color);
      return;
    }
    renderTriangleMesh(renderState, _solidFillIndexList, vertices, color);
  }

  @override
  void renderTriangleMesh(RenderState renderState, Int16List ixList, Float32List vxList, int color) {
    if (_maskSystem.isRenderingStencilMask) {
      _maskSystem.renderTriangleMesh(renderState, ixList, vxList);
      return;
    }
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordTriangleMesh(renderState, ixList, vxList, color);
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
    _batchSystem.renderTextureMesh(
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
  void _renderDrawOperation(RenderState renderState, RenderDrawOperation operation) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordDrawOperation(renderState, operation);
      return;
    }
    operation.executeDraw(renderState);
  }

  @override
  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordFilteredQuad(renderState, renderTextureQuad, renderFilters);
      return;
    }
    filterSystem.renderTextureQuadFiltered(renderState, renderTextureQuad, renderFilters);
  }

  @override
  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    if (_instructionSystem.isCollecting) {
      _instructionSystem.recordFilteredObject(renderState, renderObject);
      return;
    }
    filterSystem.renderObjectFiltered(renderState, renderObject);
  }

  void _onDeviceLost(GPUDeviceLostInfo info) {
    if (isDisposed) return;
    _deviceLostInfo = info;
    _clearColor = null;
    _contextLostEvent.add(RenderContextEvent(reason: info.reason, message: info.message));
  }

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    _instructionSystem.dispose();
    _batchSystem.dispose();
    _maskSystem.dispose();
    filterSystem.dispose();
    commandSystem.dispose();
    textureSystem.dispose();
    pipelineSystem.dispose();
    _solidFillTexture?.dispose();
    _solidFillTexture = null;
    _activeRenderTexture = null;
    _clearColor = null;
    deviceSystem.dispose();
  }
}
