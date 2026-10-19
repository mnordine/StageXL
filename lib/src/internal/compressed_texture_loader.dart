library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import '../errors.dart';

@JS('WeakRef')
external JSFunction? get _weakRef;

class CompressedTextureLoader {
  static bool get supportsBufferRelease => _weakRef != null;

  static Future<ByteBuffer> load(String url, {required AbortSignal signal}) async {
    _checkActive(signal);
    final response = await _wait(window.fetch(url.toJS, RequestInit(signal: signal)).toDart, signal);
    _checkActive(signal);
    if (!response.ok) throw LoadError('Failed to fetch $url: ${response.status} ${response.statusText}');
    final buffer = await _wait(response.arrayBuffer().toDart, signal);
    _checkActive(signal);
    return buffer.toDart;
  }

  static Future<T> _wait<T>(Future<T> future, AbortSignal signal) async {
    _checkActive(signal);
    final cancelled = Completer<T>();
    final subscription = const EventStreamProvider<Event>('abort').forTarget(signal)
        .listen((_) => cancelled.completeError(LoadError('Texture load cancelled.')));
    try {
      return await Future.any([future, cancelled.future]);
    } finally {
      await subscription.cancel();
    }
  }

  static void _checkActive(AbortSignal signal) {
    if (signal.aborted) throw LoadError('Texture load cancelled.');
  }
}
