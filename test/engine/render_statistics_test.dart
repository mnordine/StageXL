@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('WebGPU fallback causes reset with counters', () {
    final statistics = RenderStatistics()
      ..drawCount = 3
      ..addWebGpuFallbackCause('compressed texture')
      ..addWebGpuFallbackCause('unsupported filter');

    expect(statistics.webgpuFallbackCount, 2);
    expect(statistics.webgpuFallbackCauses, ['compressed texture', 'unsupported filter']);

    statistics.reset();

    expect(statistics.drawCount, 0);
    expect(statistics.webgpuFallbackCount, 0);
    expect(statistics.webgpuFallbackCauses, isEmpty);
  });
}
