library;

import 'dart:async';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' hide Int32List;
import 'dart:typed_data';

final bool autoHiDPI = _checkAutoHiDPI();
final num devicePixelRatio = _checkDevicePixelRatio();
final Future<bool> isWebpSupported = _checkWebpSupport();
final bool isMobileDevice = _checkMobileDevice();
final bool isLittleEndianSystem = _checkLittleEndianSystem();
final bool isTouchEventSupported = _checkTouchEventSupport();
const bool isAssetModules = bool.fromEnvironment('asset_modules');
bool get isImageBitmapSupported => window.has('createImageBitmap');

//-------------------------------------------------------------------------------------

num _checkDevicePixelRatio() => window.devicePixelRatio;

//-------------------------------------------------------------------------------------

bool _checkMobileDevice() {
  final ua = window.navigator.userAgent.toLowerCase();
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
  final screen = window.screen;

  // only recent devices (> iPhone4) and hi-dpi desktops

  if (isMobileDevice) {
    autoHiDPI = autoHiDPI && (screen.width > 480 || screen.height > 480);
  }

  return autoHiDPI;
}

//-------------------------------------------------------------------------------------

Future<bool> _checkWebpSupport() {
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

// NOTE(CEksal): This is basically `TouchEvent.supported` from `dart:html`
bool _checkTouchEventSupport() {
    try {
      final _ = TouchEvent('touches');
      return true;
    } catch (_) {
      return false;
    }
}
