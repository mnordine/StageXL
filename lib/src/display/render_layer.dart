part of '../display.dart';

/// Controls draw order independently from the logical display-list hierarchy.
///
/// Attached objects keep their original [DisplayObject.parent], transforms,
/// interaction order, and event ancestry. They are drawn where this layer
/// appears in the display list.
///
/// Removing an attached object or one of its logical ancestors from its parent
/// automatically detaches it from the layer. Re-adding it does not restore the
/// attachment.
final class RenderLayer extends DisplayObject {
  final _renderLayerChildren = <DisplayObject>[];

  /// Whether attached objects are sorted before every render.
  var sortableChildren = false;

  /// The comparison used by [sortRenderLayerChildren].
  Comparator<DisplayObject> sortFunction;

  RenderLayer({this.sortableChildren = false, Comparator<DisplayObject>? sortFunction}) 
    : sortFunction = sortFunction ?? _compareZIndex;

  /// The objects whose draw order is controlled by this layer.
  List<DisplayObject> get renderLayerChildren => UnmodifiableListView(_renderLayerChildren);

  /// Draws [child] at this layer's position without changing its logical parent.
  ///
  /// If [child] belongs to another layer, it is detached from that layer first.
  T attach<T extends DisplayObject>(T child) {
    if (identical(child, this)) {
      throw ArgumentError('A render layer cannot attach itself.');
    }

    for (RenderLayer? layer = this; layer != null; layer = layer.parentRenderLayer) {
      if (identical(layer, child)) {
        throw ArgumentError('Render layers cannot contain an attachment cycle.');
      }
    }

    if (identical(child._parentRenderLayer, this)) return child;

    child._parentRenderLayer?._detachChild(child);
    _renderLayerChildren.add(child);
    child._parentRenderLayer = this;
    invalidateRenderStructure();
    return child;
  }

  /// Stops drawing [child] at this layer's position.
  T detach<T extends DisplayObject>(T child) {
    _detachChild(child);
    return child;
  }

  /// Detaches every object from this layer.
  void detachAll() {
    if (_renderLayerChildren.isEmpty) return;

    for (final child in _renderLayerChildren) {
      child._parentRenderLayer = null;
    }

    _renderLayerChildren.clear();
    invalidateRenderStructure();
  }

  /// Sorts attached objects with [sortFunction].
  void sortRenderLayerChildren() {
    final indexedChildren = _renderLayerChildren.indexed.toList();
    indexedChildren.sort((a, b) {
      final result = sortFunction(a.$2, b.$2);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });

    for (var i = 0; i < indexedChildren.length; i++) {
      _renderLayerChildren[i] = indexedChildren[i].$2;
    }
  }

  @override
  void renderLegacy(RenderState renderState) {
    if (sortableChildren) sortRenderLayerChildren();
    final layerStage = stage;

    for (final child in _renderLayerChildren) {
      if (!child.visible || child.off || child.stage != layerStage || child.parent == null) {
        continue;
      }

      final ancestors = <DisplayObject>[];
      for (DisplayObject? ancestor = child.parent; ancestor != null; ancestor = ancestor.parent) {
        if (!ancestor.visible || ancestor.off) {
          ancestors.clear();
          break;
        }
        ancestors.add(ancestor);
      }
      if (ancestors.isEmpty) continue;

      renderState.renderObjectWithAncestors(child, ancestors.reversed);
    }
  }

  void _detachChild(DisplayObject child) {
    if (!identical(child._parentRenderLayer, this)) return;

    _renderLayerChildren.remove(child);
    child._parentRenderLayer = null;
    invalidateRenderStructure();
  }

  static int _compareZIndex(DisplayObject a, DisplayObject b) => a.zIndex.compareTo(b.zIndex);
}
