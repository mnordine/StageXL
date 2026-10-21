@TestOn('browser && dart2js')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';

import 'compressed_texture_reload_test.dart' as compressed;
import 'image_texture_reload_test.dart' as image;

void main() {
  test('native WeakRef is unavailable', () {
    expect(globalContext.getProperty<JSAny?>('WeakRef'.toJS), isNull);
  });

  group('compressed textures without native WeakRef', compressed.main);
  group('image textures without native WeakRef', image.main);
}
