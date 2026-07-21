part of '../engine.dart';

extension type const RenderDirtyFlags(int bits) {
  static const none = RenderDirtyFlags(0);
  static const structure = RenderDirtyFlags(1 << 0);
  static const transform = RenderDirtyFlags(1 << 1);
  static const color = RenderDirtyFlags(1 << 2);
  static const geometry = RenderDirtyFlags(1 << 3);
  static const texture = RenderDirtyFlags(1 << 4);
  static const blend = RenderDirtyFlags(1 << 5);
  static const mask = RenderDirtyFlags(1 << 6);
  static const filter = RenderDirtyFlags(1 << 7);
  static const allData = RenderDirtyFlags(0xFE);
  static const all = RenderDirtyFlags(0xFF);

  bool contains(RenderDirtyFlags flags) => bits & flags.bits != 0;

  RenderDirtyFlags operator |(RenderDirtyFlags other) => RenderDirtyFlags(bits | other.bits);
}

/// Per-category versions that can be observed independently by multiple renderers.
final class RenderDirtyState {
  var structureVersion = 0;
  var transformVersion = 0;
  var colorVersion = 0;
  var geometryVersion = 0;
  var textureVersion = 0;
  var blendVersion = 0;
  var maskVersion = 0;
  var filterVersion = 0;

  void mark(RenderDirtyFlags flags) {
    if (flags.contains(.structure)) structureVersion++;
    if (flags.contains(.transform)) transformVersion++;
    if (flags.contains(.color)) colorVersion++;
    if (flags.contains(.geometry)) geometryVersion++;
    if (flags.contains(.texture)) textureVersion++;
    if (flags.contains(.blend)) blendVersion++;
    if (flags.contains(.mask)) maskVersion++;
    if (flags.contains(.filter)) filterVersion++;
  }
}

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

  /// Category versions used by retained renderers. Null means only the coarse versions are available.
  RenderDirtyState? get renderDirtyState => null;

  /// Adds this object's backend-neutral operations to the current render plan.
  void collectRenderables(RenderBuildContext context);
  void renderFiltered(RenderState renderState);
}

/// Compatibility contract for built-ins that still need direct [RenderState] access.
///
/// New renderables should implement [RenderObject.collectRenderables] or register a
/// [RenderPipe] instead.
abstract interface class LegacyRenderObject {
  void renderLegacy(RenderState renderState);
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

  @override
  RenderDirtyState? get renderDirtyState => null;

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
  void collectRenderables(RenderBuildContext context) => context.addTextureQuad(renderTextureQuad);

  @override
  void renderFiltered(RenderState renderState) {
    renderState.renderTextureQuad(renderTextureQuad);
  }
}
