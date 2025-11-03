library;

import 'dart:async';
import 'dart:js_interop';
import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

import 'image_loader.dart';

class ImageBitmapLoader implements BaseImageLoader<ImageBitmap> {
  final String _url;
  final _completer = Completer<ImageBitmap>();
  final _abortController = AbortController();
  var _cancelled = false;

  ImageBitmapLoader(this._url) {
    _load(_url);
  }

  Future<void> _load(String url) async {
    try {
      final response = await window.fetch(url.toJS, RequestInit(signal: _abortController.signal)).toDart;
      if (_cancelled) {
        _completeCancelled();
        return;
      }

      if (!response.ok) {
        _completeError(LoadError('image bitmap load failed: ${response.status} ${response.statusText}'));
        return;
      }

      final blob = await response.blob().toDart;

      if (_cancelled) {
        _completeCancelled();
        return;
      }

      final imageBitmap = await window.createImageBitmap(blob).toDart;

      if (_cancelled) {
        _completeCancelled();
        return;
      }

      _completeSuccess(imageBitmap);
    } catch (e, stack) {
      if (_cancelled) {
        _completeCancelled(stack);
        return;
      }

      _completeError(e, stack);
    }
  }

  @override
  Future<ImageBitmap> get done => _completer.future;

  @override
  void cancel() {
    if (_cancelled) {
      return;
    }

    _cancelled = true;
    _abortController.abort();
  }

  void _completeSuccess(ImageBitmap bitmap) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.complete(bitmap);
  }

  void _completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.completeError(error, stackTrace);
  }

  void _completeCancelled([StackTrace? stackTrace]) {
    _completeError(LoadError('image bitmap load cancelled'), stackTrace);
  }
}
