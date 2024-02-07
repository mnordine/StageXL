library stagexl.internal.image_bitmap_loader;

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';

import '../internal/image_loader.dart';
import '../resources.dart' show getUrlHash;
import 'environment.dart' as env;

class ImageBitmapLoader implements BaseImageLoader<ImageBitmap> {
  String _url;
  final _completer = Completer<ImageBitmap>();
  XMLHttpRequest? _request;

  ImageBitmapLoader(this._url, bool webpAvailable) {
    if (webpAvailable) {
      env.isWebpSupported.then(_onWebpSupported);
    } else {
      _load(_url);
    }
  }

  void _load(String url) {
    final request = _request = XMLHttpRequest();
    request
      ..onReadyStateChange.listen((_) async {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {
          try {
            final blob = request.response as Blob;

            final imageBitmap = window.createImageBitmap(blob).toDart;
            _completer.complete(imageBitmap);
          } catch (e) {
            _completer.completeError(e);
          }
        }
      })
      ..onError.listen(_completer.completeError)
      ..open('GET', url, true)
      ..responseType = 'blob'
      ..send();
  }

  @override
  Future<ImageBitmap> get done => _completer.future;

  @override
  void cancel() => _request?.abort();

  void _onWebpSupported(bool webpSupported) {
    final match = RegExp(r'(png|jpg|jpeg)$').firstMatch(_url);
    if (webpSupported && match != null) {
      final url = getUrlHash(_url, webp: true);
      if (url == null) return;

      _url = url;
      _load(_url);
    }
  }
}
