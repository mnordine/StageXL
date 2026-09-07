/// Debug drawing configuration for StageXL.
///
/// Set the `stagexl-debug-draw` environment variable to `true` to include
/// renderer support. When it is `false`, the optimizing compiler removes debug
/// renderer hooks, shaders, and buffers. The configuration API remains available
/// to applications. Wireframe GPU resources are created on first use.
///
/// Example (compile with debug draw enabled):
/// ```
/// dart compile js -Dstagexl-debug-draw=true main.dart
/// ```
library;

/// Compile-time flag that controls whether debug-draw support is included.
///
/// Set via `--define stagexl-debug-draw=true` at compile time.
const stagexlDebugDraw = bool.fromEnvironment('stagexl-debug-draw');

/// Controls whether mask debug overlays are rendered in front of or behind
/// the masked content.
enum MaskDrawOrder { front, back }

/// Runtime debug-draw options.
///
/// Each boolean flag controls a specific debug overlay. When any flag is
/// `true`, the renderer will execute the corresponding overlay pass after
/// each normal batch draw. All flags default to `false`.
///
/// The [wireframeColor] and [maskColor] properties use standard ARGB integers
/// (e.g. `0xFFFF0000` for red).
class DebugDraw {
  /// Draw wireframe outlines for every rendered triangle batch.
  ///
  /// Reuses the normal vertex buffer and uploads only edge indices.
  /// Each triangle `(a, b, c)` is drawn as three separate line segments
  /// `(a, b)`, `(b, c)`, `(c, a)`. Shared edges are NOT deduplicated, so
  /// you see the real tessellation including sprite diagonals.
  var wireframes = false;

  /// Draw bounding-box rectangles around display objects.
  ///
  /// Not yet implemented; reserved for future use.
  var bounds = false;

  /// Draw pivot markers at display object pivot points.
  ///
  /// Not yet implemented; reserved for future use.
  var pivots = false;

  /// Draw mask/stencil regions.
  var masks = false;

  /// Draw per-batch batch boundaries.
  ///
  /// Not yet implemented; reserved for future use.
  var batches = false;

  /// The color used for wireframe overlays.
  ///
  /// Standard ARGB format, e.g. `0xFF00FF00` for green.
  var wireframeColor = 0xFF00FF00;

  /// The color used for mask overlays.
  ///
  /// Standard ARGB format, e.g. `0xFFFF00FF` for magenta.
  var maskColor = 0xFFFF00FF;

  /// The draw order used for mask overlays.
  var maskDrawOrder = MaskDrawOrder.front;

  /// Whether any debug overlay is currently enabled.
  bool get enabled => wireframes || bounds || pivots || masks || batches;
}

/// The global debug-draw configuration.
///
/// This instance is only referenced at runtime when [stagexlDebugDraw] is
/// `true`. In production builds (flag = `false`) this object is never
/// accessed and the entire debug-draw code path is tree-shakeable.
final debugDraw = DebugDraw();
