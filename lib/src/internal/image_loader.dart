library stagexl.internal.image_loader;

import 'dart:async';
import 'dart:html';

import 'environment.dart' as env;
import '../errors.dart';
import '../resources.dart' show getUrlHash;

class ImageLoader {
  final ImageElement image = ImageElement();
  final Completer<ImageElement> _completer = Completer<ImageElement>();

  final String _url;
  final String _originalUrl;
  StreamSubscription _onLoadSubscription;
  StreamSubscription _onErrorSubscription;

  ImageLoader(String url, bool webpAvailable, bool corsEnabled, {String originalUrl})
      : _url = url, _originalUrl = originalUrl {
    _onLoadSubscription = image.onLoad.listen(_onImageLoad);
    _onErrorSubscription = image.onError.listen(_onImageError);

    if (corsEnabled) {
      image.crossOrigin = 'anonymous';
    }

    if (webpAvailable) {
      env.isWebpSupported.then(_onWebpSupported);
    } else {
      image.src = _url;
    }
  }

  void cancel() => image?.src = '';

  //---------------------------------------------------------------------------

  Future<ImageElement> get done => _completer.future;

  //---------------------------------------------------------------------------

  void _onWebpSupported(bool webpSupported) {
    final url = _originalUrl ?? _url;
    var match = RegExp(r'(png|jpg|jpeg)$').firstMatch(url);
    if (webpSupported && match != null) {
      image.src = getUrlHash(url.substring(0, match.start) + 'webp');
    } else {
      image.src = url;
    }
  }

  void _onImageLoad(Event event) {
    _onLoadSubscription.cancel();
    _onErrorSubscription.cancel();
    _completer.complete(image);
  }

  void _onImageError(Event event) {
    _onLoadSubscription.cancel();
    _onErrorSubscription.cancel();
    _completer.completeError(LoadError('Failed to load ${image.src}.'));
  }
}
