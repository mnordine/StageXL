# Render Layers

Render Layers control when display objects are drawn without changing where those objects live in the display list.
They are useful for health bars, player names, selection outlines, tutorial highlights, and other content that must
render above or below unrelated scene content while continuing to follow a logical parent.

`RenderLayer` works with Canvas2D, WebGL1, WebGL2, and WebGPU.

## Logical hierarchy and draw order

Attaching an object to a layer changes only its draw order:

- `DisplayObject.parent` remains unchanged.
- Transforms, alpha, and blend modes continue to come from the logical parent hierarchy.
- Events and hit testing continue to use the logical hierarchy.
- The layer's position in the display list determines when the attached object is drawn.

For example, this logical hierarchy:

```text
stage
├── world
│   ├── player
│   │   └── healthBar
│   └── foregroundWall
└── hudLayer
```

normally draws `healthBar` before `foregroundWall`. Attaching `healthBar` to `hudLayer` produces this draw order:

```text
world content
foregroundWall
hudLayer
└── healthBar
```

The health bar still follows `player` because its logical parent did not change.

## Basic usage

Add the content and the layer to the normal display list before attaching the content:

```dart
final world = Sprite();
final player = Sprite();
final healthBar = Sprite();
final hudLayer = RenderLayer();

player.addChild(healthBar);
world.addChild(player);
stage
  ..addChild(world)
  ..addChild(hudLayer);

hudLayer.attach(healthBar);

assert(healthBar.parent == player);
assert(healthBar.parentRenderLayer == hudLayer);
```

The attached object and its layer must belong to the same `Stage`. An object with no logical parent is not rendered
through a layer because StageXL needs its logical hierarchy to calculate transforms and inherited render state.

The layer does not provide a new coordinate system. Changing the layer's transform does not move attached objects;
their coordinates continue to come from their logical parents.

## Layer placement

A layer draws at its own position among the children of its logical parent. Move the layer to change its priority:

```dart
stage.addChildAt(hudLayer, 0); // Draw attached objects behind the other Stage children.
stage.addChild(hudLayer);      // Draw attached objects in front of the other Stage children.
```

Multiple layers can provide distinct draw positions:

```dart
final backgroundLayer = RenderLayer();
final highlightLayer = RenderLayer();

stage
  ..addChild(backgroundLayer)
  ..addChild(world)
  ..addChild(highlightLayer);
```

Attaching an object to a second layer automatically detaches it from the first:

```dart
backgroundLayer.attach(target);
highlightLayer.attach(target);

assert(target.parentRenderLayer == highlightLayer);
assert(backgroundLayer.renderLayerChildren.contains(target) == false);
```

`renderLayerChildren` is a read-only view. Use `attach`, `detach`, and `detachAll` instead of modifying it.

## Detaching and lifecycle

Detach an object to restore its normal logical draw order:

```dart
hudLayer.detach(healthBar);

assert(healthBar.parent == player);
assert(healthBar.parentRenderLayer == null);
```

Detach every object from a layer with:

```dart
hudLayer.detachAll();
```

Removing an attached object or any of its logical ancestors from the display list automatically detaches all affected
descendants from their layers:

```dart
world.removeChild(player);

assert(healthBar.parentRenderLayer == null);
assert(hudLayer.renderLayerChildren.contains(healthBar) == false);
```

Adding `player` back does not restore the old layer assignment. Reattach `healthBar` explicitly when that is the
desired behavior. This prevents stale layer assignments from silently returning when scene objects are reused.

## Sorting within a layer

Attached objects keep their attachment order by default. Set `sortableChildren` to sort them by `zIndex` before each
render:

```dart
final nameLayer = RenderLayer(sortableChildren: true);

nameLayer
  ..attach(aliceName)
  ..attach(bobName);

aliceName.zIndex = 10;
bobName.zIndex = 20; // Drawn after aliceName.
```

Objects with equal sort values keep their current relative order. For manual sorting, leave `sortableChildren` false
and call:

```dart
nameLayer.sortRenderLayerChildren();
```

Replace the default `zIndex` comparison with `sortFunction` when another scene property should control the order:

```dart
nameLayer.sortFunction = (a, b) => a.y.compareTo(b.y);
nameLayer.sortRenderLayerChildren();
```

Automatic sorting invokes the comparison every frame. Prefer manual sorting when the order changes infrequently.

## Visibility and inherited state

An attached object is drawn only when all of these conditions are true:

- The object is visible and not off.
- Its logical ancestors are visible and not off.
- It has a logical parent.
- It belongs to the same `Stage` as the layer.
- The layer itself is reached during display-list traversal.

StageXL replays the logical ancestors' transforms, alpha, and blend modes at the layer's draw position. The attached
object's own mask, filters, cache, and descendants render normally.

Effects owned by logical ancestors are not moved to the layer position. In particular, masks, filters, and bitmap
caches on a logical ancestor do not wrap an attached descendant after that descendant is drawn elsewhere. Attach the
container that owns the effect, or put the effect directly on the attached object, when the effect must move with it.

## Interaction order

Render Layers do not change hit testing. Pointer targets are still resolved through the logical child order, even when
a layer makes an object appear visually above another object. If visual order must determine interaction priority,
coordinate that behavior in the application's input handling.

Event capture and bubbling also continue through the logical parent chain.

## Complete example

The repository includes an animated comparison in
[`example/render_layers.dart`](../example/render_layers.dart). It moves status cards behind a foreground object and
lets you toggle their layer assignment while showing the current `parent` and `parentRenderLayer` values.

Run only that entry point to avoid building unrelated examples:

```sh
dart run build_runner serve example:8080 \
  --build-filter=example/render_layers.dart.js
```

Then open <http://localhost:8080/render_layers.html>.

Use the query parameter to select a renderer:

- `?engine=webgl2` for WebGL2, the default.
- `?engine=webgl1` for WebGL1.
- `?engine=webgpu` for WebGPU with StageXL's normal WebGL2 fallback.
- `?engine=canvas` for Canvas2D.
