@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('RenderProgramSet requires at least one backend', () {
    expect(RenderProgramSet<Object?>.new, throwsArgumentError);
  });

  test('RenderProgramSet derives supported render engines from its programs', () {
    final programs = RenderProgramSet<void>(
      webGPU: RenderProgramWebGPU.callback((context, parameters) {}),
    );

    expect(programs.supports(.WebGPU), isTrue);
    expect(programs.supports(.WebGL), isFalse);
    expect(programs.supports(.WebGL2), isFalse);
    expect(programs.supports(.Canvas2D), isFalse);
  });

  test('blur-based filters use one pass on WebGPU and WebGL2', () {
    final filters = <RenderFilter>[
      BlurFilter(12, 8, 5),
      GlowFilter(0xFF00FF00, 12, 8, 5),
      DropShadowFilter(8, 0.5, 0xFF000000, 12, 8, 5),
    ];

    for (final filter in filters) {
      expect(filter.renderPassSourcesFor(.WebGPU), [0]);
      expect(filter.renderPassTargetsFor(.WebGPU), [1]);
      expect(filter.renderPassSourcesFor(.WebGL2), [0]);
      expect(filter.renderPassTargetsFor(.WebGL2), [1]);
    }

    expect(filters[0].renderPassSourcesFor(.WebGL), hasLength(10));
    expect(filters[1].renderPassSourcesFor(.WebGL), hasLength(11));
    expect(filters[2].renderPassSourcesFor(.WebGL), hasLength(11));
  });

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
