library;

import 'dart:async';
import 'package:web/web.dart';

import '../errors.dart';

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

  ImageLoader(this._url, bool corsEnabled) {
    _onLoadSubscription = image.onLoad.listen(_onImageLoad);
    _onErrorSubscription = image.onError.listen(_onImageError);

    if (corsEnabled) {
      image.crossOrigin = 'anonymous';
    }

    image.src = _url;
  }

  @override
  void cancel() => image.src = '';

  //---------------------------------------------------------------------------

  @override
  Future<HTMLImageElement> get done => _completer.future;

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
