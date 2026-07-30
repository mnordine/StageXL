part of '../engine.dart';

/// The implementation kind of the render context.

enum RenderEngine { WebGL2, WebGL, WebGPU, Canvas2D }

/// The base class for all events fired by a render context.

class RenderContextEvent {
  final String? reason;
  final String? message;

  const RenderContextEvent({this.reason, this.message});
}

/// The interface for all implementations of a render context.

abstract class RenderContext {
  final renderStatistics = RenderStatistics();
  final renderPipes = RenderPipeRegistry();
  var _disposed = false;
  var _diagnosticsRegistered = false;

  void _registerDiagnostics() {
    if (_diagnosticsRegistered) return;
    _diagnosticsRegistered = true;
    ResourceDiagnostics.register(.renderContext);
  }

  final _contextLostEvent = StreamController<RenderContextEvent>.broadcast();
  final _contextRestoredEvent =
      StreamController<RenderContextEvent>.broadcast();

  Stream<RenderContextEvent> get onContextLost => _contextLostEvent.stream;
  Stream<RenderContextEvent> get onContextRestored =>
      _contextRestoredEvent.stream;

  bool get isDisposed => _disposed;

  RenderEngine get renderEngine;

  _RetainedInstructionSystem? get _retainedInstructionSystem => null;

  int? get maxTextureSize;
  Object? getParameter(int parameter);

  Matrix3D? get activeProjectionMatrix => null;

  void activateProjectionMatrix(Matrix3D matrix) {}

  /// Invalidates backend state cached by this renderer.
  ///
  /// Call this before rendering after another engine has used the same
  /// graphics context. Renderers that do not cache shared state treat this
  /// the same as [reset].
  void resetState() => reset();

  void reset();
  void clear(int color);
  void flush();

  void buildRenderFrame(RenderState renderState, RenderObject renderObject) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem == null) {
      renderState.renderObject(renderObject);
    } else {
      instructionSystem.collect(renderState, renderObject);
    }
  }

  void executeRenderFrame(RenderState renderState) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem == null) {
      renderState.flush();
    } else {
      instructionSystem.execute();
    }
  }

  /// Releases the retained instruction plan owned by [renderObject].
  ///
  /// Call this outside frame collection and execution when an independent
  /// render root will no longer be rendered. A later build recreates the plan.
  void releaseRenderPlan(RenderObject renderObject) => _retainedInstructionSystem?.release(renderObject);

  /// Releases backend resources owned by this context.
  ///
  /// A disposed context cannot render again. Scene objects and externally
  /// owned textures are not disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_diagnosticsRegistered) ResourceDiagnostics.unregister(.renderContext);
    unawaited(_contextLostEvent.close());
    unawaited(_contextRestoredEvent.close());
  }

  void beginRenderObject(RenderState renderState, RenderObject renderObject) {}

  void endRenderObject(RenderObject renderObject) {}

  void beginCanvasShadow(RenderState renderState, int color, num blur, num offsetX, num offsetY) {}

  void endCanvasShadow() {}

  void _beginCanvasShadow(RenderState renderState, int color, num blur, num offsetX, num offsetY) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordCanvasShadow(
        renderState,
        color,
        blur.toDouble(),
        offsetX.toDouble(),
        offsetY.toDouble(),
        begin: true,
      );
    } else {
      beginCanvasShadow(renderState, color, blur, offsetX, offsetY);
    }
  }

  void _endCanvasShadow() {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordCanvasShadow(null, 0, 0, 0, 0, begin: false);
    } else {
      endCanvasShadow();
    }
  }

  void _beginRenderMask(RenderState renderState, RenderMask mask) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordMask(renderState, mask, begin: true);
    } else {
      beginRenderMask(renderState, mask);
    }
  }

  void _endRenderMask(RenderState renderState, RenderMask mask) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordMask(renderState, mask, begin: false);
    } else {
      endRenderMask(renderState, mask);
    }
  }

  void beginRenderMask(RenderState renderState, RenderMask mask);
  void endRenderMask(RenderState renderState, RenderMask mask);

  //---------------------------------------------------------------------------

  void renderTextureQuad(
      RenderState renderState, RenderTextureQuad renderTextureQuad);

  void renderTextureQuadTinted(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    num red,
    num green,
    num blue,
    num alpha,
  );

  void renderTextureMesh(RenderState renderState, RenderTexture renderTexture,
      Int16List ixList, Float32List vxList);

  void renderTextureMeshTinted(
    RenderState renderState,
    RenderTexture renderTexture,
    Int16List ixList,
    Float32List vxList,
    num red,
    num green,
    num blue,
    num alpha,
  );

  void renderTextureMapping(
      RenderState renderState,
      RenderTexture renderTexture,
      Matrix mappingMatrix,
      Int16List ixList,
      Float32List vxList);

  void renderTriangle(RenderState renderState, num x1, num y1, num x2, num y2,
      num x3, num y3, int color);

  void renderTriangleMesh(
      RenderState renderState, Int16List ixList, Float32List vxList, int color);

  void renderTextureQuadFiltered(RenderState renderState,
      RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters);

  void renderObjectFiltered(RenderState renderState, RenderObject renderObject);

  void _renderTextureQuad(RenderState renderState, RenderTextureQuad quad) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTextureQuad(renderState, quad);
    } else {
      renderTextureQuad(renderState, quad);
    }
  }

  void _renderTextureQuadTinted(
    RenderState renderState,
    RenderTextureQuad quad,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTextureQuad(renderState, quad, red, green, blue, alpha);
    } else {
      renderTextureQuadTinted(renderState, quad, red, green, blue, alpha);
    }
  }

  void _renderTextureMesh(
    RenderState renderState,
    RenderTexture texture,
    Int16List indices,
    Float32List vertices,
  ) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTextureMesh(renderState, texture, indices, vertices);
    } else {
      renderTextureMesh(renderState, texture, indices, vertices);
    }
  }

  void _renderTextureMeshTinted(
    RenderState renderState,
    RenderTexture texture,
    Int16List indices,
    Float32List vertices,
    num red,
    num green,
    num blue,
    num alpha,
  ) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTextureMesh(renderState, texture, indices, vertices, red, green, blue, alpha);
    } else {
      renderTextureMeshTinted(renderState, texture, indices, vertices, red, green, blue, alpha);
    }
  }

  void _renderTextureMapping(
    RenderState renderState,
    RenderTexture texture,
    Matrix mappingMatrix,
    Int16List indices,
    Float32List vertices,
  ) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTextureMapping(renderState, texture, mappingMatrix, indices, vertices);
    } else {
      renderTextureMapping(renderState, texture, mappingMatrix, indices, vertices);
    }
  }

  void _renderTriangle(
    RenderState renderState,
    num x1,
    num y1,
    num x2,
    num y2,
    num x3,
    num y3,
    int color,
  ) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTriangle(renderState, x1, y1, x2, y2, x3, y3, color);
    } else {
      renderTriangle(renderState, x1, y1, x2, y2, x3, y3, color);
    }
  }

  void _renderTriangleMesh(RenderState renderState, Int16List indices, Float32List vertices, int color) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordTriangleMesh(renderState, indices, vertices, color);
    } else {
      renderTriangleMesh(renderState, indices, vertices, color);
    }
  }

  void _renderVectorGraphics(RenderState renderState, RenderVectorGraphics graphics) {
    graphics.collectVectorGraphics(renderState.buildContext);
  }

  void _renderDrawOperation(RenderState renderState, RenderDrawOperation operation) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordDrawOperation(renderState, operation);
    } else {
      operation.executeDraw(renderState);
    }
  }

  void _renderText(RenderState renderState, RenderText text) {
    final quad = text.prepareTextTexture(renderState.globalMatrix);
    _renderTextureQuad(renderState, quad);
  }

  void _renderTextureQuadFiltered(RenderState renderState, RenderTextureQuad quad, List<RenderFilter> filters) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordFilteredQuad(renderState, quad, filters);
    } else {
      renderTextureQuadFiltered(renderState, quad, filters);
    }
  }

  void _renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    final instructionSystem = _retainedInstructionSystem;
    if (instructionSystem?.isCollecting ?? false) {
      instructionSystem!.recordFilteredObject(renderState, renderObject);
    } else {
      renderObjectFiltered(renderState, renderObject);
    }
  }
}
