library stagexl.internal.image_bitmap_loader;

import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import 'package:stagexl/src/internal/image_loader.dart';

import 'environment.dart' as env;
import '../resources.dart' show getUrlHash;

class ImageBitmapLoader extends BaseImageLoader<ImageBitmap> {
  String _url;
  final _completer = Completer<ImageBitmap>();
  HttpRequest _request;

  ImageBitmapLoader(String url, bool webpAvailable) : super(url) {
    if (webpAvailable) {
      env.isWebpSupported.then(_onWebpSupported);
    } else {
      _load(url);
    }
  }

  void _load(String url) {
    final request = _request = HttpRequest();
    request
      ..onReadyStateChange.listen((_) async {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {
          try {
            final blob = request.response as Blob;
            final promise = callMethod(window, 'createImageBitmap', [blob]);
            final imageBitmap = await promiseToFuture<ImageBitmap>(promise);
            _completer.complete(imageBitmap);
          } catch (e) {
            _completer.completeError(e);
          }
        }
      })
      ..onError.listen((e) {
        _completer.completeError(e);
      })
      ..open('GET', url, async: true)
      ..responseType = 'blob'
      ..send();
  }

  @override
  Future<ImageBitmap> get done => _completer.future;

  @override
  void cancel() => _request?.abort();

  void _onWebpSupported(bool webpSupported) {
    var match = RegExp(r'(png|jpg|jpeg)$').firstMatch(_url);
    if (webpSupported && match != null) {
      _url = getUrlHash(_url, webp: true);
    }

    _load(_url);
  }
}
