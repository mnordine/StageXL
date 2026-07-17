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
  var _cancelled = false;

  ImageBitmapLoader(this._url) {
    _load(_url);
  }

  void _load(String url) {
    http.get(.parse(url)).then((response) {
      if (_cancelled) {
        _completer.completeError(LoadError('image bitmap load cancelled'));
        return;
      } 
      if (response.statusCode == 200) {
        try {
          final blob = Blob([response.bodyBytes.toJS].toJS);
          final imageBitmap = _ImageBitmapGlobal(_globalScope).createImageBitmap(blob).toDart;
          _completer.complete(imageBitmap);
        } catch (e) {
          _completer.completeError(e);
        }
      }
    });
  }

  @override
  Future<ImageBitmap> get done => _completer.future;

  @override
  void cancel() => _cancelled = true;
}
