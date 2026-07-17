library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' hide Int32List;
import 'dart:typed_data';

@JS('globalThis')
external JSObject get _globalScope;

extension type _EnvironmentGlobal(JSObject _) implements JSObject {
  external double get devicePixelRatio;
  external _EnvironmentNavigator get navigator;
  external _EnvironmentScreen get screen;
}

extension type _EnvironmentNavigator(JSObject _) implements JSObject {
  external String get userAgent;
}

extension type _EnvironmentScreen(JSObject _) implements JSObject {
  external int get width;
  external int get height;
}

final _environmentGlobal = _EnvironmentGlobal(_globalScope);

final bool autoHiDPI = _checkAutoHiDPI();
final num devicePixelRatio = _checkDevicePixelRatio();
final Future<bool> isWebpSupported = _checkWebpSupport();
final Future<bool> isAvifSupported = _checkAvifSupport();
final bool isMobileDevice = _checkMobileDevice();
final bool isLittleEndianSystem = _checkLittleEndianSystem();
final bool isTouchEventSupported = _checkTouchEventSupport();
bool get isImageBitmapSupported => _globalScope.has('createImageBitmap');
bool get hasDocument => _globalScope.has('document');

//-------------------------------------------------------------------------------------

num _checkDevicePixelRatio() =>
    _globalScope.has('devicePixelRatio') ? _environmentGlobal.devicePixelRatio : 1.0;

//-------------------------------------------------------------------------------------

bool _checkMobileDevice() {
  final ua = _environmentGlobal.navigator.userAgent.toLowerCase();
  final identifiers = [
    'iphone',
    'ipad',
    'ipod',
    'android',
    'webos',
    'windows phone'
  ];
  return identifiers.any(ua.contains);
}

//-------------------------------------------------------------------------------------

bool _checkLittleEndianSystem() {
  final wordList = Int32List(1);
  final byteList = wordList.buffer.asUint8List();
  wordList[0] = 0x11223344;
  return byteList[0] == 0x44;
}

//-------------------------------------------------------------------------------------

bool _checkAutoHiDPI() {
  var autoHiDPI = devicePixelRatio > 1.0;
  if (!_globalScope.has('screen')) return autoHiDPI;
  final screen = _environmentGlobal.screen;

  // only recent devices (> iPhone4) and hi-dpi desktops

  if (isMobileDevice) {
    autoHiDPI = autoHiDPI && (screen.width > 480 || screen.height > 480);
  }

  return autoHiDPI;
}

//-------------------------------------------------------------------------------------

@JS('ImageDecoder')
extension type _ImageDecoder._(JSObject _) implements JSObject {
  @JS('isTypeSupported')
  external static JSPromise<JSBoolean> _isTypeSupported(String type);

  static Future<bool> isTypeSupported(String type) async {
    final result = await _isTypeSupported(type).toDart;
    return result.toDart;
  }
}

bool get _hasImageDecoder => _globalScope.has('ImageDecoder');

Future<bool> _checkWebpSupport() async {
  try {
    if (_hasImageDecoder) return await _ImageDecoder.isTypeSupported('image/webp');
  } catch (_) {}

  if (!_globalScope.has('document')) return false;
  final completer = Completer<bool>();
  final img = HTMLImageElement();

  img.onLoad
      .listen((e) => completer.complete(img.width == 2 && img.height == 2));
  img.onError.listen((e) => completer.complete(false));

  img.src = 'data:image/webp;base64,UklGRjoAAABXRUJQVlA4IC4AAACyAg'
      'CdASoCAAIALmk0mk0iIiIiIgBoSygABc6WWgAA/veff/0PP8bA//LwYAAA';

  return completer.future;
}

//-------------------------------------------------------------------------------------

Future<bool> _checkAvifSupport() async {
  try {
    if (_hasImageDecoder) return await _ImageDecoder.isTypeSupported('image/avif');
  } catch (_) {}

  if (!_globalScope.has('document')) return false;
  final completer = Completer<bool>();
  final img = HTMLImageElement();

  img.onLoad
      .listen((_) => completer.complete(img.width == 2 && img.height == 2));
  img.onError.listen((_) => completer.complete(false));

  img.src = 'data:image/avif;base64,AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAADybWV0YQAAAAAAAAAoaGRscgAAAAAAAAAAc'
    'GljdAAAAAAAAAAAAAAAAGxpYmF2aWYAAAAADnBpdG0AAAAAAAEAAAAeaWxvYwAAAABEAAABAAEAAAABAAABGgAAAB0AAAAoaWluZgAAAAAAAQAAA'
    'BppbmZlAgAAAAABAABhdjAxQ29sb3IAAAAAamlwcnAAAABLaXBjbwAAABRpc3BlAAAAAAAAAAIAAAACAAAAEHBpeGkAAAAAAwgICAAAAAxhdjFDg'
    'Q0MAAAAABNjb2xybmNseAACAAIAAYAAAAAXaXBtYQAAAAAAAAABAAEEAQKDBAAAACVtZGF0EgAKCBgANogQEAwgMg8f8D///8WfhwB8+ErK42A=';

  return completer.future;
}

//-------------------------------------------------------------------------------------

// NOTE(CEksal): This is basically `TouchEvent.supported` from `dart:html`
bool _checkTouchEventSupport() {
    try {
      final _ = TouchEvent('touches');
      return true;
    } catch (_) {
      return false;
    }
}
