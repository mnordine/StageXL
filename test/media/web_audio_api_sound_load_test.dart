@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('Error')
external JSObject _error(String message);

@JS('Promise.reject')
external JSPromise<JSAny?> _reject(JSAny error);

@JS('window.fetch')
external JSFunction get _fetch;

@JS('window.fetch')
external set _fetch(JSFunction value);

void main() {
  late JSFunction fetch;
  late SoundLoadOptions options;

  setUp(() {
    fetch = _fetch;
    options = SoundLoadOptions()
      ..engine = .WebAudioApi
      ..alternativeUrls = []
      ..ignoreErrors = false;
  });

  tearDown(() => _fetch = fetch);

  test('loads and decodes a successful response', () async {
    _fetch = ((JSAny url, [JSAny? init]) => Future.value(web.Response(_silentWav().toJS)).toJS).toJS;

    final sound = await Sound.load('success.wav', options);

    expect(sound.engine, SoundEngine.WebAudioApi);
    expect(sound.length, closeTo(128 / 48000, 0.0001));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('reports rejected requests through the sound future', () async {
    _fetch = ((JSAny url, [JSAny? init]) =>
        _reject(_error('network failed'))).toJS;

    await expectLater(Sound.load('failed-request.wav', options),
        throwsA(isA<AggregateError>().having((error) => '$error', 'message', contains('network failed'))));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('reports non-200 responses through the sound future', () async {
    _fetch = ((JSAny url, [JSAny? init]) =>
        Future.value(web.Response(null, web.ResponseInit(status: 503))).toJS).toJS;

    await expectLater(Sound.load('failed-status.wav', options),
        throwsA(isA<AggregateError>().having((error) => '$error', 'message', contains('503'))));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('reports response buffer allocation failures through the sound future', () async {
    final response = web.Response(null, web.ResponseInit(status: 200));
    response.setProperty('arrayBuffer'.toJS, (() =>
        _reject(_error('Array buffer allocation failed'))).toJS);
    _fetch = ((JSAny url, [JSAny? init]) => Future.value(response).toJS).toJS;

    await expectLater(Sound.load('failed-buffer.wav', options),
        throwsA(isA<AggregateError>().having(
            (error) => '$error', 'message', contains('Array buffer allocation failed'))));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('reports decoding failures through the sound future', () async {
    _fetch = ((JSAny url, [JSAny? init]) =>
        Future.value(web.Response(Uint8List.fromList([1, 2, 3]).toJS)).toJS).toJS;

    await expectLater(Sound.load('failed-decode.wav', options), throwsA(isA<AggregateError>()));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('tries an alternative format after an HTTP failure', () async {
    final requested = <String>[];
    options.alternativeUrls = ['fallback.wav'];
    _fetch = ((JSAny url, [JSAny? init]) {
      requested.add((url as JSString).toDart);
      return Future.value(requested.length == 1
          ? web.Response(null, web.ResponseInit(status: 503))
          : web.Response(_silentWav().toJS)).toJS;
    }).toJS;

    final sound = await Sound.load('failed-primary.mp3', options);

    expect(requested, ['failed-primary.mp3', 'fallback.wav']);
    expect(sound.engine, SoundEngine.WebAudioApi);
  }, timeout: const Timeout(Duration(seconds: 3)));

  test('uses the silent fallback when request errors are ignored', () async {
    options.ignoreErrors = true;
    _fetch = ((JSAny url, [JSAny? init]) =>
        _reject(_error('network failed'))).toJS;

    final sound = await Sound.load('ignored-error.wav', options);

    expect(sound.engine, SoundEngine.Mockup);
  }, timeout: const Timeout(Duration(seconds: 3)));
}

Uint8List _silentWav() {
  final bytes = Uint8List(44 + 128);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setAll(8, 'WAVE'.codeUnits);
  bytes.setAll(12, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 48000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 1, Endian.little);
  data.setUint16(34, 8, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  data.setUint32(40, 128, Endian.little);
  bytes.fillRange(44, bytes.length, 128);
  return bytes;
}
