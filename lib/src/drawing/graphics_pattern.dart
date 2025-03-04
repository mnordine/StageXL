// ignore_for_file: non_constant_identifier_names
part of '../drawing.dart';

class GraphicsPatternType {
  final String value;
  final RenderTextureWrapping wrappingX;
  final RenderTextureWrapping wrappingY;

  const GraphicsPatternType(this.value, this.wrappingX, this.wrappingY);

  static final GraphicsPatternType Repeat = GraphicsPatternType(
      'repeat', RenderTextureWrapping.REPEAT, RenderTextureWrapping.REPEAT);

  static final GraphicsPatternType RepeatX = GraphicsPatternType(
      'repeat-x', RenderTextureWrapping.REPEAT, RenderTextureWrapping.CLAMP);

  static final GraphicsPatternType RepeatY = GraphicsPatternType(
      'repeat-y', RenderTextureWrapping.CLAMP, RenderTextureWrapping.REPEAT);

  static final GraphicsPatternType NoRepeat = GraphicsPatternType(
      'no-repeat', RenderTextureWrapping.CLAMP, RenderTextureWrapping.CLAMP);
}

//------------------------------------------------------------------------------

class _CanvasPatternKey {
  final RenderTextureQuad renderTextureQuad;
  final GraphicsPatternType type;

  _CanvasPatternKey(this.renderTextureQuad, this.type);

  @override
  int get hashCode =>
      JenkinsHash.hash2(renderTextureQuad.hashCode, type.hashCode);

  @override
  bool operator ==(Object other) =>
      other is _CanvasPatternKey &&
      renderTextureQuad == other.renderTextureQuad &&
      type == other.type;
}

//------------------------------------------------------------------------------

class GraphicsPattern {
  static final SharedCache<_CanvasPatternKey, CanvasPattern?>
      _canvasPatternCache = SharedCache<_CanvasPatternKey, CanvasPattern?>();

  static final SharedCache<RenderTextureQuad?, RenderTexture?>
      _patternTextureCache = SharedCache<RenderTextureQuad?, RenderTexture?>()
        ..onObjectReleased.listen((e) => e.object!.dispose());

  /// cached by the canvas2D renderer
  CanvasPattern? _canvasPattern;

  /// cached by both the canvas2D and the webgl renderer
  RenderTexture? _patternTexture;

  RenderTextureQuad _renderTextureQuad;
  GraphicsPatternType _type;
  Matrix? matrix;

  GraphicsPattern(RenderTextureQuad renderTextureQuad, GraphicsPatternType type,
      [this.matrix])
      : _renderTextureQuad = renderTextureQuad,
        _type = type;

  GraphicsPattern.repeat(RenderTextureQuad renderTextureQuad, [Matrix? matrix])
      : this(renderTextureQuad, GraphicsPatternType.Repeat, matrix);

  GraphicsPattern.repeatX(RenderTextureQuad renderTextureQuad, [Matrix? matrix])
      : this(renderTextureQuad, GraphicsPatternType.RepeatX, matrix);

  GraphicsPattern.repeatY(RenderTextureQuad renderTextureQuad, [Matrix? matrix])
      : this(renderTextureQuad, GraphicsPatternType.RepeatY, matrix);

  GraphicsPattern.noRepeat(RenderTextureQuad renderTextureQuad,
      [Matrix? matrix])
      : this(renderTextureQuad, GraphicsPatternType.NoRepeat, matrix);

  //----------------------------------------------------------------------------

  GraphicsPatternType get type => _type;

  set type(GraphicsPatternType value) {
    disposeCachedRenderObjects(false);
    _type = value;
  }

  RenderTextureQuad get renderTextureQuad {
    disposeCachedRenderObjects(true);
    return _renderTextureQuad;
  }

  set renderTextureQuad(RenderTextureQuad texture) {
    disposeCachedRenderObjects(true);
    _renderTextureQuad = texture;
  }

  //----------------------------------------------------------------------------

  void disposeCachedRenderObjects(bool patternTextureChanged) {
    final cacheKey = _CanvasPatternKey(_renderTextureQuad, _type);
    _canvasPatternCache.releaseObject(cacheKey);
    _canvasPattern = null;
    if (patternTextureChanged && _patternTexture != null) {
      if (_patternTexture != _renderTextureQuad.renderTexture) {
        _patternTextureCache.releaseObject(_renderTextureQuad);
      }
      _patternTexture = null;
    }
  }

  CanvasPattern getCanvasPattern(CanvasRenderingContext2D context) {
    // try to get the canvasPattern from the cache
    if (_canvasPattern == null) {
      final cacheKey = _CanvasPatternKey(_renderTextureQuad, _type);
      _canvasPattern = _canvasPatternCache.getObject(cacheKey);
    }

    // create a canvasPattern and add it to the cache
    if (_canvasPattern == null) {
      final cacheKey = _CanvasPatternKey(_renderTextureQuad, _type);
      _canvasPattern =
          context.createPattern(patternTexture.source!, _type.value);
      _canvasPatternCache.addObject(cacheKey, _canvasPattern);
    }

    return _canvasPattern!;
  }

  RenderTexture get patternTexture {
    // try to get the patternTexture from the texture cache
    _patternTexture ??= _patternTextureCache.getObject(_renderTextureQuad);

    // try to use the original texture as patternTexture
    if (_patternTexture == null && _renderTextureQuad.isEquivalentToSource) {
      _patternTexture = _renderTextureQuad.renderTexture;
    }

    // clone the original texture to get the patternTexture
    if (_patternTexture == null) {
      final pixelRatio = _renderTextureQuad.pixelRatio;
      final textureWidth = _renderTextureQuad.offsetRectangle.width;
      final textureHeight = _renderTextureQuad.offsetRectangle.height;
      final renderTexture = RenderTexture(textureWidth, textureHeight, 0);
      final renderTextureQuad = renderTexture.quad.withPixelRatio(pixelRatio);
      final renderContext = RenderContextCanvas(renderTexture.canvas);
      final renderState =
          RenderState(renderContext, renderTextureQuad.drawMatrix);
      renderState.renderTextureQuad(_renderTextureQuad);
      _patternTexture = renderTexture;
      _patternTextureCache.addObject(_renderTextureQuad, _patternTexture);
    }

    return _patternTexture!;
  }
}
