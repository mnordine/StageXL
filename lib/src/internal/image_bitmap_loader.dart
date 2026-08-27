library;

import 'dart:async';
import 'dart:js_interop';
import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

import 'image_loader.dart';
import 'package:http/http.dart' as http;

@JS('globalThis')
external JSObject get _globalScope;

extension type _ImageBitmapGlobal(JSObject _) implements JSObject {
  external JSPromise<ImageBitmap> createImageBitmap(JSObject image);
}

class ImageBitmapLoader implements BaseImageLoader<ImageBitmap> {
  final String _url;
  final _completer = Completer<ImageBitmap>();
  Completer<void>? _cancelCompleter;
  var _cancelled = false;

  ImageBitmapLoader(this._url) {
    _load(_url);
  }

  Future<void> _load(String url) async {
    final cancelCompleter = _cancelCompleter = Completer<void>();
    final client = http.Client();

    try {
      final request = http.AbortableRequest('GET', .parse(url), abortTrigger: cancelCompleter.future);
      final response = await client.send(request);
      final bodyBytes = await response.stream.toBytes();
      if (_cancelled) throw LoadError('image bitmap load cancelled');

      if (response.statusCode != 200) {
        throw LoadError('failed to load image bitmap $url');
      }

      final imageBitmap = await _ImageBitmapGlobal(_globalScope).createImageBitmap(Blob([bodyBytes.toJS].toJS)).toDart;
      _completer.complete(imageBitmap);
    } catch (e, stackTrace) {
      if (!_completer.isCompleted) _completer.completeError(e, stackTrace);
    } finally {
      client.close();
      _cancelCompleter = null;
    }
  }

  @override
  Future<ImageBitmap> get done => _completer.future;

  @override
  void cancel() {
    _cancelled = true;
    if (_cancelCompleter case final completer? when !completer.isCompleted) completer.complete();
  }
}
