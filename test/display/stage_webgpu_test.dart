@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  test('sync Stage constructor rejects WebGPU because device creation is async', () {
    final options = StageOptions()..renderEngine = .WebGPU;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;

    expect(
      () => Stage(canvas, options: options),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Stage.create'),
      )),
    );
  });

  test('StageOptions clone preserves WebGPU render engine', () {
    final options = StageOptions()..renderEngine = .WebGPU;

    expect(options.clone().renderEngine, RenderEngine.WebGPU);
  });
}
