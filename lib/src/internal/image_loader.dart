library;

import 'dart:async';
import 'package:web/web.dart';

import '../errors.dart';
import 'environment.dart' as env;

abstract class BaseImageLoader<T> {
  void cancel();

  Future<T> get done;
}

class ImageLoader implements BaseImageLoader<HTMLImageElement> {
  final String _url;
  final HTMLImageElement image = HTMLImageElement();
  final _completer = Completer<HTMLImageElement>();
  late final StreamSubscription _onLoadSubscription;
  late final StreamSubscription _onErrorSubscription;

  ImageLoader(this._url, bool webpAvailable, bool corsEnabled) {
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
  void cancel() => image.src = '';

  //---------------------------------------------------------------------------

  @override
  Future<HTMLImageElement> get done => _completer.future;

  void _onWebpSupported(bool webpSupported) {
    final match = RegExp(r'(png|jpg|jpeg)$').firstMatch(_url);
    if (!webpSupported || match == null) {
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
