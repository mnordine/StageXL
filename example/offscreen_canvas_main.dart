import 'dart:js_interop';

import 'package:stagexl/stagexl_worker.dart';
import 'package:web/web.dart';

late final StageWorkerClient workerClient;

void main() {
  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  workerClient = StageWorkerClient(
    canvas,
    'offscreen_canvas_worker.dart.js',
    options: const StageWorkerClientOptions(
      inputEventMode: .MouseAndTouch,
      initialData: {'source': 'example-host'},
    ),
  );
  workerClient.onError.listen(print);
  workerClient.ready.then((_) {
    print('StageXL worker ready');
    workerClient.postMessage({'kind': 'example:host-message'});
  });
  workerClient.onMessage.listen((message) {
    final data = message.dartify();
    if (data is Map<Object?, Object?> && data['kind'] == 'example:input') {
      canvas.setAttribute('data-worker-input', 'true');
    }
    if (data is Map<Object?, Object?> && data['kind'] == 'example:host-message') {
      canvas.setAttribute('data-worker-message', 'true');
    }
  });
}
