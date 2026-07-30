import 'dart:collection';

/// Resource categories tracked by [ResourceDiagnostics].
enum StageXLResourceType {
  resourceManagerEntry,
  bitmapData,
  textureAtlas,
  video,
  sound,
  soundSprite,
  renderContext,
  renderTexture,
  webglTexture,
  renderBuffer,
  webglBuffer,
  webglFramebuffer,
  webglRenderbuffer,
  webglProgram,
  webglVertexArray,
  soundChannel,
  webAudioGraph,
}

/// An immutable point-in-time view of live StageXL resources.
final class ResourceSnapshot {
  final Map<StageXLResourceType, int> counts;

  ResourceSnapshot(Map<StageXLResourceType, int> counts)
      : counts = UnmodifiableMapView(Map.of(counts));

  int operator [](StageXLResourceType type) => counts[type] ?? 0;

  /// Returns the count change from [baseline] to this snapshot.
  Map<StageXLResourceType, int> difference(ResourceSnapshot baseline) =>
      UnmodifiableMapView({
        for (final type in StageXLResourceType.values)
          if (this[type] != baseline[type]) type: this[type] - baseline[type],
      });

  /// Returns resource categories whose live count increased since [baseline].
  Map<StageXLResourceType, int> growthSince(ResourceSnapshot baseline) =>
      UnmodifiableMapView({
        for (final MapEntry(key: type, value: difference) in difference(baseline).entries)
          if (difference > 0) type: difference,
      });

  Map<String, int> toJson() => {
        for (final type in StageXLResourceType.values) type.name: this[type],
      };
}

/// Tracks explicitly owned StageXL resources without retaining the resources.
///
/// Compare snapshots before loading content and after disposing it. A positive
/// [ResourceSnapshot.growthSince] result identifies resources whose cleanup
/// path did not return to the baseline.
final class ResourceDiagnostics {
  static final _counts = {
    for (final type in StageXLResourceType.values) type: 0,
  };

  static ResourceSnapshot snapshot() => ResourceSnapshot(_counts);

  /// For StageXL internals. Applications should use [snapshot].
  static void register(StageXLResourceType type) {
    _counts[type] = _counts[type]! + 1;
  }

  /// For StageXL internals. Applications should use [snapshot].
  static void unregister(StageXLResourceType type) {
    final count = _counts[type]!;
    if (count == 0) {
      throw StateError('No live ${type.name} resource to unregister.');
    }
    _counts[type] = count - 1;
  }
}
