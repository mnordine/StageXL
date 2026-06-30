@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('DisplacementMapFilter apply uses scaleY for vertical displacement', () {
    final bitmapData = BitmapData(1, 3, Color.Transparent)
      ..setPixel32(0, 0, Color.Red)
      ..setPixel32(0, 1, Color.Green)
      ..setPixel32(0, 2, Color.Blue);
    final displacementMap = BitmapData(1, 3, 0xFF7FFF7F);

    DisplacementMapFilter(displacementMap, null, 0, 2).apply(bitmapData);

    expect(bitmapData.getPixel32(0, 0), Color.Green);
    expect(bitmapData.getPixel32(0, 1), Color.Blue);
    expect(bitmapData.getPixel32(0, 2), 0);
  });
}
