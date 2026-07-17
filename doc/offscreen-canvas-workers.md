# OffscreenCanvas and Web Workers

StageXL can run a complete Stage runtime in a dedicated browser worker. In this mode the `Stage`, display list,
jugglers and enter-frame updates, hit testing, StageXL event dispatch, texture/filter/mask work, batching, and the
WebGL or WebGPU renderer remain in the worker. The main thread owns only the DOM canvas, CSS layout, focus, cursor,
and DOM input capture.

The worker protocol transfers the `OffscreenCanvas` once. It does not serialize the display list or send rendering
commands on each frame.

## Main host entry point

```dart
import 'package:stagexl/stagexl.dart';
import 'package:stagexl/stagexl_worker.dart';
import 'package:web/web.dart';

late final StageWorkerClient workerClient;

void main() {
  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  workerClient = StageWorkerClient(
    canvas,
    'game_worker.dart.js',
    options: const StageWorkerClientOptions(
      inputEventMode: InputEventMode.MouseAndTouch,
    ),
  );
}
```

Keep the `StageWorkerClient` alive for as long as the application is running. Call `dispose()` to remove listeners
and terminate the worker. The client options control main-thread `preventDefault` behavior because a worker cannot
synchronously change the already-dispatched DOM event.

## Worker entry point

```dart
import 'package:stagexl/stagexl.dart';
import 'package:stagexl/stagexl_worker.dart';

void main() {
  runStageXLWorker((host) async {
    final options = StageOptions()
      ..renderEngine = RenderEngine.WebGL2
      ..inputEventMode = InputEventMode.MouseAndTouch;
    final stage = await host.createStage(
      width: 800,
      height: 600,
      options: options,
    );
    final renderLoop = RenderLoop()..addStage(stage);

    // Construct and own the complete scene in this worker.
    stage.addChild(Sprite());
    renderLoop.targetFramesPerSecond = 0;
  });
}
```

`RenderLoop` uses `requestAnimationFrame` from the current global scope, so the same loop runs on a window or a
dedicated worker. Bitmap loading uses worker-compatible `fetch`/`createImageBitmap`, and runtime-created bitmap and
text surfaces use `OffscreenCanvas` when no document exists.

## Compile both entry points

Compile the main host and worker as independent Dart web programs. The worker URL passed to `StageWorkerClient` must
resolve to the second output:

```sh
mkdir -p build/web
dart compile js web/main.dart -o build/web/main.dart.js
dart compile js web/game_worker.dart -o build/web/game_worker.dart.js
```

Projects using `build_runner` can instead include both entry points as build filters:

```sh
dart run build_runner build \
  --build-filter=web/main.dart.js \
  --build-filter=web/game_worker.dart.js
```

The repository example is split into `example/offscreen_canvas_main.dart` and
`example/offscreen_canvas_worker.dart`, served by `example/offscreen_canvas.html`.

For development, both files are registered as web entry points in the repository `build.yaml`. Start a fresh webdev
process after adding or changing entry points:

```sh
webdev serve example:8090
```

Then open <http://localhost:8090/offscreen_canvas.html>. Restart `webdev serve` after changing `build.yaml`; a running
process does not reliably discover newly registered entry points. The repository uses dart2js for webdev development
builds because dartdevc's multi-file RequireJS bootstrap does not reliably initialize inside a dedicated worker. The
first build is therefore slower, but the host and worker outputs are both standalone scripts.

## Platform boundaries

DOM display objects, HTML media-element fallbacks, synchronous canvas data URLs, and other APIs that inherently
require `document` remain main-thread-only. Prefer `BitmapData.load`, `ImageBitmap`, WebGL/WebGPU textures, and
StageXL scene objects in worker applications. WebGPU in workers also depends on browser support for `navigator.gpu`;
StageXL keeps its existing WebGPU-to-WebGL fallback behavior.

The normal `Stage(HTMLCanvasElement)` and `Stage.create(HTMLCanvasElement)` APIs continue to use the built-in
`BrowserStageHost` and require no application changes.
