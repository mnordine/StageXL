part of '../engine.dart';

/// Optional lifecycle samples. Values describe the JS heap and owned texture sources, not total process RAM.
class MemoryDiagnostics {
  static void Function(Map<String, Object?> sample)? onSample;

  static void sample(String phase, {Map<String, Object?> details = const {}}) {
    final listener = onSample;
    if (listener == null) return;
    final memory = _PerformanceMemory(window.performance).memory;
    listener({
      'phase': phase,
      'timeMs': window.performance.now(),
      'jsHeapUsedBytes': memory?.usedJSHeapSize,
      'jsHeapTotalBytes': memory?.totalJSHeapSize,
      ...details,
    });
  }
}

extension type _PerformanceMemory(JSObject _) implements JSObject {
  external _JSHeapMemory? get memory;
}

extension type _JSHeapMemory(JSObject _) implements JSObject {
  external int get usedJSHeapSize;
  external int get totalJSHeapSize;
}
