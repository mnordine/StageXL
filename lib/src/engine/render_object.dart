part of '../engine.dart';

/// The abstract [RenderObject] class defines the scene data consumed by a
/// registered [RenderPipe]. All display objects implement this interface.

abstract class RenderObject {
  static const defaultRenderPipeId = RenderPipeId<RenderObject>('stagexl.display-object');

  Matrix get transformationMatrix;
  BlendMode? get blendMode;
  num get alpha;

  List<RenderFilter> get filters;
  RenderTextureQuad? get cache;
  RenderMask? get mask;

  Rectangle<num> get bounds;

  RenderPipeId get renderPipeId => defaultRenderPipeId;

  /// Changes when this object emits a different instruction topology.
  int get renderStructureVersion => 0;

  /// Changes when this object's retained data needs to be refreshed.
  int get renderDataVersion => 0;

  /// Internal rendering hook used by StageXL's built-in render pipe.
  void renderLegacy(RenderState renderState);
  void renderFiltered(RenderState renderState);
}

/// The abstract [RenderObject3D] class adds a 3D projection matrix to
/// the [RenderObject] class. Only display objects with 3D capabilities
/// will implement this class.

abstract class RenderObject3D extends RenderObject {
  Matrix3D get transformationMatrix3D;
  Matrix3D get projectionMatrix3D;
}

/// This class is as a wrapper for a [RenderTextureQuad] to be used with
/// the [RenderContext.renderObjectFiltered] method. It is necessary as a
/// fallback if the [RenderTextureQuad] can't be rendered in the fast path.

class _RenderTextureQuadObject implements RenderObject {
  final RenderTextureQuad renderTextureQuad;

  @override
  final List<RenderFilter> filters;

  @override
  final transformationMatrix = Matrix.fromIdentity();

  @override
  final BlendMode blendMode = .NORMAL;

  @override
  final RenderTextureQuad? cache;

  @override
  final RenderMask? mask;

  @override
  final num alpha = 1.0;

  @override
  RenderPipeId get renderPipeId => RenderObject.defaultRenderPipeId;

  @override
  int get renderStructureVersion => 0;

  @override
  int get renderDataVersion => 0;

  _RenderTextureQuadObject(this.renderTextureQuad, this.filters)
      : mask = null,
        cache = null;

  @override
  Rectangle<num> get bounds {
    final w = renderTextureQuad.targetWidth;
    final h = renderTextureQuad.targetHeight;
    return Rectangle<num>(0.0, 0.0, w, h);
  }

  @override
  void renderLegacy(RenderState renderState) {
    renderState.renderTextureQuad(renderTextureQuad);
  }

  @override
  void renderFiltered(RenderState renderState) {
    renderState.renderTextureQuad(renderTextureQuad);
  }
}
