# Debug drawing

This example supports WebGPU (default) and WebGL 2 (`?webgl`). Compile it with
explicit debug support, serve the repository, and open `example/debug_draw.html`:

```sh
dart compile js -O2 -Dstagexl-debug-draw=true example/debug_draw.dart -o example/debug_draw.dart.js
```

Without the define, the optimizing compiler removes debug renderer hooks,
shaders, buffers, and pipeline creation. Normal rendering follows `diagnostics`.
No repository-wide debug define is enabled in `build.yaml`.

With the define enabled, `debugDraw.wireframes` and `debugDraw.masks` toggle the
implemented overlays at runtime. Wireframe resources are allocated on first use.
Bounds, pivots, and batch annotations remain unimplemented; bounds and pivot
markers can use ordinary `Shape`/`Graphics` objects in a separate overlay.

## Geometry and retained rendering

Both backends reuse the normal vertex buffer. Each triangle `(a,b,c)` becomes
six edge indices `(a,b,b,c,c,a)`; shared edges remain visible.

| Backend | Extra geometry upload | Retained geometry |
| --- | --- | --- |
| WebGL | 12 bytes per triangle, 16-bit indices | Reuses uploaded vertices; uploads edges per draw group |
| WebGPU | 24 bytes per triangle, 32-bit indices | Caches edges with each instruction; uploads again only when indices change |

WebGPU wireframes also reuse retained transform and clipping metadata. Changing
an object's transform does not rebuild its edges. Debug color uses a separate
16-byte uniform, updated only when the color changes. A wireframe draw follows
each normal draw group, using the same render target, projection, and clipping.
Later content may cover earlier wireframes; filters also affect overlays drawn
into their intermediate targets.

WebGPU render bundles are bypassed while wireframes are enabled so each normal
draw can be followed by its wireframe. Existing cached bundles remain available
and resume when wireframes are disabled. Debug buffers are released with their
owning instruction/context, including `Stage.releaseRenderPlan()`.

## Masks

`debugDraw.maskDrawOrder` selects `.front` or `.back`. Filled mask overlays use
the active scissor/stencil region. While mask overlays are enabled, rectangular
masks use the native mask path so their begin/end boundaries can be displayed;
wireframes alone retain shader-based scissor batching.

WebGPU supports nested stencil overlays in both orders and multisampled canvas
targets. WebGL filled mask overlays require VAOs. For nested WebGL stencil masks,
use `.back`: the existing front overlay follows the restored parent stencil
region, which can extend beyond the parent's original shape. Normal stencil
rendering is unchanged by this port.

## Regression checks

The tests require actual WebGL/WebGPU support and fail if WebGPU falls back to
another backend. Use GPU-enabled Chrome; the test runner's default headless mode
may disable the GPU. For example, save this configuration to a file:

```yaml
override_platforms:
  chrome:
    settings:
      headless: false
```

Then run with debugging both compiled out and compiled in:

```sh
dart test --configuration=<file> -p chrome test/engine/debug_draw_test.dart test/engine/debug_draw_webgpu_test.dart
dart test --configuration=<file> -p chrome test/engine/debug_draw_test.dart test/engine/debug_draw_webgpu_test.dart --dart2js-args=-Dstagexl-debug-draw=true
```

Checks cover GPU pixel readback, upload sizes, runtime toggles, multiple blend
groups, retained shader clipping, mutable meshes, cached bundles, nested masks,
filter targets, MSAA, WebGL context restoration, and debug-buffer disposal.
Transfer sizes are measured; frame-time improvements are not claimed.

The port also fixes existing WebGL 1 shader constants to emit floating-point
literals, avoiding GLSL float/int multiplication compilation errors on this branch.
