library;

import 'dart:async';
import 'dart:js_interop';
import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

import '../internal/image_loader.dart';
import 'package:http/http.dart' as http;

class ImageBitmapLoader implements BaseImageLoader<ImageBitmap> {
  final String _url;
  final _completer = Completer<ImageBitmap>();
  bool _cancelled = false;

  ImageBitmapLoader(this._url) {
    _load(_url);
  }

  void _load(String url) {
    http.get(Uri.parse(url)).then((response) {
      if (_cancelled) {
        _completer.completeError(LoadError('image bitmap load cancelled'));
        return;
      } 
      if (response.statusCode == 200) {
        try {
          final imageBitmap = window.createImageBitmap(Blob([response.bodyBytes.toJS].toJS)).toDart;
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
