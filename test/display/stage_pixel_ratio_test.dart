@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  test('changing pixel ratio resizes the backing buffer without changing CSS dimensions', () {
    final canvas = HTMLCanvasElement()
      ..style.width = '320px'
      ..style.height = '180px';
    document.body!.append(canvas);
    addTearDown(() => canvas.remove());

    final stage = Stage(
      canvas,
      width: 320,
      height: 180,
      options: StageOptions()..maxPixelRatio = 2,
    );
    stage.pixelRatio = 1.25;

    expect(canvas.clientWidth, 320);
    expect(canvas.clientHeight, 180);
    expect(canvas.width, 400);
    expect(canvas.height, 225);
  });
}
