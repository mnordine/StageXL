part of '../engine.dart';

class _ContextState {
  double alpha = 1;
  double colorScaleR = 1;
  double colorScaleG = 1;
  double colorScaleB = 1;
  double colorScaleA = 1;
  BlendMode blendMode = .NORMAL;

  final matrix = Matrix.fromIdentity();
  final matrix3D = Matrix3D.fromIdentity();
  final _ContextState? previousContextState;

  _ContextState(this.previousContextState);

  _ContextState? _nextContextState;
  _ContextState get nextContextState =>
      _nextContextState ??= _ContextState(this);
}

/// The [RenderState] class is used to render objects to a give render surface
/// defined by the renderContext parameter.
///
/// This class is internal to display-list traversal. Custom display objects
/// use [RenderPipe] and [RenderBuildContext].
///
/// The [renderObject] method keeps track of the state for hierarchical objects
/// from the display list and therefore can be called recursively.
/// The [renderQuad] method renders simple [RenderTextureQuad] objects. This is
/// also the method that is used by the display list to draw BitmapData objects.

class RenderState {
  num currentTime = 0.0;
  num deltaTime = 0.0;

  final RenderContext _renderContext;
  final _ContextState _firstContextState;
  final _identityMatrix = Matrix.fromIdentity();
  late final buildContext = RenderBuildContext._(this);

  _ContextState? _currentContextState;

  RenderState(RenderContext renderContext,
      [Matrix? matrix, num? alpha, BlendMode? blendMode])
      : _renderContext = renderContext,
        _firstContextState = _ContextState(null) {
    _currentContextState = _firstContextState;

    if (matrix is Matrix) _firstContextState.matrix.copyFrom(matrix);
    if (alpha is num) _firstContextState.alpha = alpha.toDouble();
    if (blendMode is BlendMode) _firstContextState.blendMode = blendMode;
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  RenderContext get renderContext => _renderContext;

  Matrix get globalMatrix => _currentContextState!.matrix;
  double get globalAlpha => _currentContextState!.alpha;
  double get globalColorScaleR => _currentContextState!.colorScaleR;
  double get globalColorScaleG => _currentContextState!.colorScaleG;
  double get globalColorScaleB => _currentContextState!.colorScaleB;
  double get globalColorScaleA => _currentContextState!.colorScaleA;
  BlendMode get globalBlendMode => _currentContextState!.blendMode;

  //---------------------------------------------------------------------------

  void reset([Matrix? matrix, num? alpha, BlendMode? blendMode]) {
    final currentContextState = _currentContextState = _firstContextState;
    currentContextState.matrix.identity();
    currentContextState.alpha = 1.0;
    currentContextState.colorScaleR = 1.0;
    currentContextState.colorScaleG = 1.0;
    currentContextState.colorScaleB = 1.0;
    currentContextState.colorScaleA = 1.0;
    currentContextState.blendMode = .NORMAL;

    if (matrix is Matrix) _firstContextState.matrix.copyFrom(matrix);
    if (alpha is num) _firstContextState.alpha = alpha.toDouble();
    if (blendMode is BlendMode) _firstContextState.blendMode = blendMode;
  }

  void copyFrom(RenderState renderState) {
    final currentContextState = _currentContextState = _firstContextState;
    currentContextState.matrix.copyFrom(renderState.globalMatrix);
    currentContextState.alpha = renderState.globalAlpha;
    currentContextState.colorScaleR = renderState.globalColorScaleR;
    currentContextState.colorScaleG = renderState.globalColorScaleG;
    currentContextState.colorScaleB = renderState.globalColorScaleB;
    currentContextState.colorScaleA = renderState.globalColorScaleA;
    currentContextState.blendMode = renderState.globalBlendMode;
  }

  //---------------------------------------------------------------------------

  void flush() {
    _renderContext.flush();
  }

  void renderTextureQuad(RenderTextureQuad renderTextureQuad) {
    _renderContext._renderTextureQuad(this, renderTextureQuad);
  }

  void renderTextureQuadTinted(
    RenderTextureQuad renderTextureQuad,
    num red,
    num green,
    num blue,
    num alpha, {
    BlendMode? blendMode,
  }) {
    final pushed = blendMode != null;
    if (pushed) push(_identityMatrix, 1, blendMode);
    _renderContext._renderTextureQuadTinted(this, renderTextureQuad, red, green, blue, alpha);
    if (pushed) pop();
  }

  void renderTextureMapping(RenderTexture renderTexture, Matrix mappingMatrix,
      Int16List ixList, Float32List vxList) {
    _renderContext._renderTextureMapping(
        this, renderTexture, mappingMatrix, ixList, vxList);
  }

  void renderTextureMesh(
      RenderTexture renderTexture, Int16List ixList, Float32List vxList) {
    _renderContext._renderTextureMesh(this, renderTexture, ixList, vxList);
  }

  void renderTextureMeshTinted(
    RenderTexture renderTexture,
    Int16List ixList,
    Float32List vxList,
    num red,
    num green,
    num blue,
    num alpha, {
    BlendMode? blendMode,
  }) {
    final pushed = blendMode != null;
    if (pushed) push(_identityMatrix, 1, blendMode);
    _renderContext._renderTextureMeshTinted(this, renderTexture, ixList, vxList, red, green, blue, alpha);
    if (pushed) pop();
  }

  void renderTriangle(
      num x1, num y1, num x2, num y2, num x3, num y3, int color) {
    _renderContext._renderTriangle(this, x1, y1, x2, y2, x3, y3, color);
  }

  void renderTriangleMesh(Int16List ixList, Float32List vxList, int color) {
    _renderContext._renderTriangleMesh(this, ixList, vxList, color);
  }

  void renderVectorGraphics(RenderVectorGraphics graphics) {
    _renderContext._renderVectorGraphics(this, graphics);
  }

  void renderDrawOperation(RenderDrawOperation operation) {
    _renderContext._renderDrawOperation(this, operation);
  }

  void renderText(RenderText text) {
    _renderContext._renderText(this, text);
  }

  void renderTextureQuadFiltered(
      RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    _renderContext._renderTextureQuadFiltered(
        this, renderTextureQuad, renderFilters);
  }

  void renderObjectFiltered(RenderObject renderObject) {
    _renderContext._renderObjectFiltered(this, renderObject);
  }

  //---------------------------------------------------------------------------

  void renderObject(RenderObject renderObject) {
    final matrix = renderObject.transformationMatrix;
    final blendMode = renderObject.blendMode;
    final alpha = renderObject.alpha;
    final filters = renderObject.filters;
    final cache = renderObject.cache;
    final mask = renderObject.mask;

    final cs1 = _currentContextState!;
    final cs2 = _currentContextState!.nextContextState;
    final maskBefore = mask != null && mask.relativeToParent == true;
    final maskAfter = mask != null && mask.relativeToParent == false;

    //-----------

    if (maskBefore) renderContext._beginRenderMask(this, mask);

    cs2.matrix.copyFromAndConcat(matrix, cs1.matrix);
    cs2.blendMode = (blendMode is BlendMode) ? blendMode : cs1.blendMode;
    cs2.alpha = alpha * cs1.alpha;
    cs2.colorScaleR = cs1.colorScaleR;
    cs2.colorScaleG = cs1.colorScaleG;
    cs2.colorScaleB = cs1.colorScaleB;
    cs2.colorScaleA = cs1.colorScaleA;

    final activeProjectionMatrix = renderContext.activeProjectionMatrix;
    if (renderObject case final RenderObject3D renderObject3D when activeProjectionMatrix != null) {
      cs1.matrix3D.copyFrom(activeProjectionMatrix);
      cs2.matrix3D.copyFrom2DAndConcat(cs2.matrix, cs1.matrix3D);
      cs2.matrix3D.prepend(renderObject3D.projectionMatrix3D);
      cs2.matrix3D.prependInverse2D(cs2.matrix);
      renderContext.activateProjectionMatrix(cs2.matrix3D);
    }

    _currentContextState = cs2;

    //-----------

    _renderContext.beginRenderObject(this, renderObject);

    if (maskAfter) renderContext._beginRenderMask(this, mask);

    if (cache != null) {
      renderTextureQuad(cache);
    } else if (filters.isNotEmpty) {
      renderObject.renderFiltered(this);
    } else {
      _addRenderable(renderObject);
    }

    if (maskAfter) renderContext._endRenderMask(this, mask);

    //-----------

    _renderContext.endRenderObject(renderObject);
    _currentContextState = cs1;

    if (renderObject is RenderObject3D && activeProjectionMatrix != null) {
      renderContext.activateProjectionMatrix(cs1.matrix3D);
    }

    if (maskBefore) renderContext._endRenderMask(this, mask);
  }

  /// Renders [object] at its draw-order proxy while retaining its logical
  /// transformation, alpha, and blend-mode ancestry.
  ///
  /// This is used by render layers. Effects on [ancestors] are intentionally
  /// not replayed because they belong to the ancestor's original render
  /// position.
  void renderObjectWithAncestors(RenderObject object, Iterable<RenderObject> ancestors) {
    final previousContextState = _currentContextState;
    _currentContextState = _firstContextState;
    try {
      for (final ancestor in ancestors) {
        push(ancestor.transformationMatrix, ancestor.alpha, ancestor.blendMode);
      }
      renderObject(object);
    } finally {
      _currentContextState = previousContextState;
    }
  }

  void _addRenderable(RenderObject renderObject) => _renderContext.renderPipes.addRenderable(renderObject, buildContext);

  //---------------------------------------------------------------------------

  void push(Matrix matrix, num alpha, [BlendMode? blendMode]) {
    final cs1 = _currentContextState!;
    final cs2 = _currentContextState!.nextContextState;
    cs2.matrix.copyFromAndConcat(matrix, cs1.matrix);
    cs2.blendMode = blendMode ?? cs1.blendMode;
    cs2.alpha = alpha * cs1.alpha;
    cs2.colorScaleR = cs1.colorScaleR;
    cs2.colorScaleG = cs1.colorScaleG;
    cs2.colorScaleB = cs1.colorScaleB;
    cs2.colorScaleA = cs1.colorScaleA;
    _currentContextState = cs2;
  }

  void pushColorScale(Float32List colorScale) {
    final cs1 = _currentContextState!;
    final cs2 = _currentContextState!.nextContextState;
    cs2.matrix.copyFrom(cs1.matrix);
    cs2.matrix3D.copyFrom(cs1.matrix3D);
    cs2.blendMode = cs1.blendMode;
    cs2.alpha = cs1.alpha;
    cs2.colorScaleR = cs1.colorScaleR * colorScale[0];
    cs2.colorScaleG = cs1.colorScaleG * colorScale[1];
    cs2.colorScaleB = cs1.colorScaleB * colorScale[2];
    cs2.colorScaleA = cs1.colorScaleA * colorScale[3];
    _currentContextState = cs2;
  }

  void pop() {
    _currentContextState = _currentContextState!.previousContextState;
  }
}
