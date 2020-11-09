library stagexl.internal.image_loader;

import 'dart:async';
import 'dart:html';

import 'environment.dart' as env;
import '../errors.dart';
import '../resources.dart' show getUrlHash;

abstract class BaseImageLoader<T> {
  final String _url;

  BaseImageLoader(this._url);

  void cancel();

  Future<T> get done;
}

class ImageLoader extends BaseImageLoader<ImageElement> {
  final ImageElement image = ImageElement();
  final _completer = Completer<ImageElement>();
  StreamSubscription _onLoadSubscription;
  StreamSubscription _onErrorSubscription;

  ImageLoader(String url, bool webpAvailable, bool corsEnabled) : super(url) {
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

  @override
  Future<ImageElement> get done => _completer.future;

  @override
  void cancel() => image?.src = '';

  void _onWebpSupported(bool webpSupported) {
    var match = RegExp(r'(png|jpg|jpeg)$').firstMatch(_url);
    if (webpSupported && match != null) {
      image.src = getUrlHash(_url, webp: true);
    } else {
      image.src = _url;
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
