@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('WebGPU fallback causes reset with counters', () {
    final statistics = RenderStatistics()
      ..drawCount = 3
      ..frameTimeMicroseconds = 1200
      ..renderObjectMicroseconds = 700
      ..renderFlushMicroseconds = 300
      ..webgpuBufferUploadMicroseconds = 40
      ..webgpuPassEncodeMicroseconds = 50
      ..webgpuSubmitMicroseconds = 60
      ..addWebGpuFallbackCause('compressed texture')
      ..addWebGpuFallbackCause('unsupported filter');

    expect(statistics.webgpuFallbackCount, 2);
    expect(statistics.webgpuFallbackCauses, ['compressed texture', 'unsupported filter']);

    statistics.reset();

    expect(statistics.drawCount, 0);
    expect(statistics.frameTimeMicroseconds, 0);
    expect(statistics.renderObjectMicroseconds, 0);
    expect(statistics.renderFlushMicroseconds, 0);
    expect(statistics.webgpuBufferUploadMicroseconds, 0);
    expect(statistics.webgpuPassEncodeMicroseconds, 0);
    expect(statistics.webgpuSubmitMicroseconds, 0);
    expect(statistics.webgpuFallbackCount, 0);
    expect(statistics.webgpuFallbackCauses, isEmpty);
  });
}
