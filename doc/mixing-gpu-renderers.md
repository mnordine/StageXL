# Mixing StageXL with Three.js or another GPU renderer

StageXL can render 2D content into a WebGL context created by another engine. This allows one canvas to contain a
Three.js scene and a StageXL UI without copying either renderer's output through a texture.

## WebGL

The renderer that creates the context must enable stencil support if the StageXL scene uses masks:

```javascript
const threeRenderer = new THREE.WebGLRenderer({
  antialias: true,
  stencil: true,
});
```

Pass that renderer's canvas to `Stage` and its context through `StageOptions.sharedWebGLContext`. Disable StageXL's color
clear when it renders over the 3D scene:

```dart
final options = StageOptions()
  ..renderEngine = RenderEngine.WebGL2
  ..sharedWebGLContext = threeRenderer.getContext()
  ..clearBeforeRender = false;

final stage = Stage(
  threeRenderer.domElement,
  width: width,
  height: height,
  options: options,
);
```

Each renderer caches WebGL state. Reset the renderer that is about to draw whenever control of the context changes:

```dart
void render(num time, num deltaTime) {
  threeRenderer.resetState();
  threeRenderer.render(scene, camera);

  // A Stage using sharedWebGLContext restores its state automatically here.
  stage.materialize(time, deltaTime);
}
```

If StageXL is used through lower-level rendering APIs after another renderer, call
`stage.renderContext.resetState()` before issuing StageXL draws.

The application owns the shared context and its canvas dimensions. Keep the Three.js renderer, the canvas, and the
Stage dimensions in sync when resizing. Textures, buffers, shaders, and other resources remain owned by the renderer
that created them; sharing a context does not make Three.js and StageXL texture objects interchangeable.

This follows the same handoff model described by the
[PixiJS mixing guide](https://pixijs.com/8.x/guides/third-party/mixing-three-and-pixi).

## WebGPU

WebGPU renderers share a `GPUDevice` and a configured `GPUCanvasContext`. The application that created them retains
ownership and must also provide the canvas texture format:

```dart
final sharedContext = SharedWebGPUContext(
  device: externalRenderer.device,
  canvasContext: externalRenderer.canvasContext,
  textureFormat: externalRenderer.textureFormat,
);
final options = StageOptions()
  ..renderEngine = RenderEngine.WebGPU
  ..sharedWebGPUContext = sharedContext
  ..clearBeforeRender = false
  ..antialias = false;

final stage = await Stage.create(
  externalRenderer.domElement,
  width: width,
  height: height,
  options: options,
);
```

The external renderer must finish and submit its work before StageXL renders. StageXL then records and submits its own
passes with `loadOp: 'load'`, preserving the existing canvas color attachment. The device queue preserves submission
order.

Keep StageXL antialiasing disabled when preserving an earlier WebGPU renderer's canvas output. StageXL's multisample
target is renderer-owned and cannot load the other renderer's already-resolved canvas content. `Stage.create` rejects
this incompatible combination.

Set `StageOptions.transparent` to match whether the externally configured canvas target should be treated as
transparent for blending.

Disposing the Stage releases only StageXL pipelines, buffers, textures, and attachments. It does not unconfigure the
shared canvas context or destroy the shared device.
