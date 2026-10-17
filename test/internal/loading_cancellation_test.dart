@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:stagexl/src/internal/image_bitmap_loader.dart';
import 'package:stagexl/src/internal/image_loader.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late JSFunction fetch;

  setUp(() => fetch = globalContext.getProperty<JSFunction>('fetch'.toJS));
  tearDown(() => globalContext.setProperty('fetch'.toJS, fetch));

  test('image cancellation aborts fetch and settles without waiting for the body', () async {
    final response = Completer<web.Response>();
    late web.AbortSignal signal;
    _setFetch((_, init) {
      signal = init!.signal!;
      return response.future;
    });
    final loader = ImageBitmapLoader('/cancel.png');
    final done = expectLater(loader.done, throwsA(isA<LoadError>()));

    loader.cancel();
    loader.cancel();
    await done;
    expect(signal.aborted, isTrue);
    response.complete(web.Response());
    await _drain();
  });

  test('cancellation closes a bitmap created after the load was cancelled', () async {
    final createImageBitmap = globalContext.getProperty<JSFunction>('createImageBitmap'.toJS);
    addTearDown(() => globalContext.setProperty('createImageBitmap'.toJS, createImageBitmap));
    final creating = Completer<void>();
    final bitmap = Completer<web.ImageBitmap>();
    globalContext.setProperty('createImageBitmap'.toJS, ((JSAny? _) {
      creating.complete();
      return bitmap.future.toJS;
    }).toJS);
    _setFetch((_, _) async => web.Response(web.Blob()));
    final loader = ImageBitmapLoader('/late.png');
    final done = expectLater(loader.done, throwsA(isA<LoadError>()));
    await creating.future;

    loader.cancel();
    var closed = 0;
    final result = JSObject()..setProperty('close'.toJS, (() => closed++).toJS);
    bitmap.complete(result as web.ImageBitmap);
    await done;
    await _drain();
    expect(closed, 1);
  });

  test('HTML image cancellation settles even when the browser emits no event', () async {
    final loader = ImageLoader('/pending.png', false);
    final done = expectLater(loader.done, throwsA(isA<LoadError>()));
    loader.cancel();
    loader.cancel();
    await done;
  });

  test('disposing an atlas aborts metadata and cannot start a texture request', () async {
    final response = Completer<web.Response>();
    final signals = <web.AbortSignal>[];
    _setFetch((_, init) {
      signals.add(init!.signal!);
      return response.future;
    });
    final manager = ResourceManager()..addTextureAtlas('atlas', '/atlas.json');
    final resource = manager.resources.single;
    final loaded = manager.load();
    manager.dispose();
    response.complete(web.Response('{"frames":[],"meta":{"image":"atlas.png"}}'.toJS));
    await loaded;

    expect(resource.error, isA<LoadError>());
    expect(signals, hasLength(1));
    expect(signals.single.aborted, isTrue);
  });

  test('cancelling during format detection cannot start an image download', () async {
    final imageDecoder = globalContext.getProperty<JSAny?>('ImageDecoder'.toJS);
    addTearDown(() => globalContext.setProperty('ImageDecoder'.toJS, imageDecoder));
    final checking = Completer<void>();
    final supported = Completer<JSBoolean>();
    globalContext.setProperty('ImageDecoder'.toJS, JSObject()
      ..setProperty('isTypeSupported'.toJS, ((JSString _) {
        if (!checking.isCompleted) checking.complete();
        return supported.future.toJS;
      }).toJS));
    var requests = 0;
    _setFetch((_, _) async {
      requests++;
      return web.Response('{"frames":[],"meta":{"image":"atlas.png"}}'.toJS);
    });
    final manager = ResourceManager()
      ..addTextureAtlas('atlas', '/atlas.json', null, BitmapDataLoadOptions()..avif = true);
    final resource = manager.resources.single;
    final loaded = manager.load();
    await checking.future;
    manager.dispose();
    supported.complete(true.toJS);
    await loaded;

    expect(resource.error, isA<LoadError>());
    expect(requests, 1);
  });

  for (final isPvr in [true, false]) {
    test('${isPvr ? 'PVR' : 'KTX'} texture data shares the fetched ArrayBuffer', () {
      final data = JSArrayBuffer(isPvr ? 68 : 84);
      final buffer = data.toDart;
      final header = ByteData.view(buffer);
      if (isPvr) {
        header
          ..setUint32(0, 0x03525650, .little)
          ..setUint32(8, 11, .little)
          ..setUint32(24, 4, .little)
          ..setUint32(28, 4, .little);
      } else {
        Uint8List.view(buffer).setAll(0, KtxFormat.ktx_magic);
        header
          ..setUint32(12, KtxFormat.ktx_end_le, .little)
          ..setUint32(28, 0x83f3, .little)
          ..setUint32(36, 4, .little)
          ..setUint32(40, 4, .little)
          ..setUint32(64, 16, .little);
      }
      final texture = isPvr ? PvrTexture(buffer) : KtxTexture(buffer);
      final bytes = texture.textureData;
      expect(bytes.buffer.toJS, same(data));
      header.setUint32(bytes.offsetInBytes, 123456, .little);
      expect(bytes.getUint32(0, .little), 123456);
    });
  }

  test('disposing an atlas aborts a compressed texture body', () async {
    final textureBody = Completer<JSArrayBuffer>();
    final reading = Completer<void>();
    final signals = <web.AbortSignal>[];
    _setFetch((url, init) async {
      signals.add(init!.signal!);
      if (url.endsWith('.json')) {
        return web.Response('{"frames":[],"meta":{"image":"atlas.pvr"}}'.toJS);
      }
      return _arrayBufferResponse(() {
        reading.complete();
        return textureBody.future;
      });
    });
    final manager = ResourceManager()..addTextureAtlas('atlas', '/atlas.json');
    final resource = manager.resources.single;
    final loaded = manager.load();
    await reading.future;
    manager.dispose();
    textureBody.complete(JSArrayBuffer(0));
    await loaded;

    expect(resource.error, isA<LoadError>());
    expect(signals, hasLength(2));
    expect(signals.last.aborted, isTrue);
  });

  group('Web Audio', () {
    late web.AudioContext context;
    late JSFunction decode;

    setUp(() {
      context = WebAudioApiMixer.audioContext;
      decode = context.getProperty<JSFunction>('decodeAudioData'.toJS);
    });
    tearDown(() => context.setProperty('decodeAudioData'.toJS, decode));

    test('passes the fetched ArrayBuffer directly to the decoder', () async {
      final data = JSArrayBuffer(8);
      JSArrayBuffer? decoded;
      _setFetch((_, _) async => _arrayBufferResponse(() async => data));
      context.setProperty('decodeAudioData'.toJS, ((JSArrayBuffer buffer) {
        decoded = buffer;
        return Future.value(context.createBuffer(1, 32, 8000)).toJS;
      }).toJS);

      final sound = await Sound.load('/direct.wav', _options());
      expect(decoded, same(data));
      expect(sound.engine, SoundEngine.WebAudioApi);
    });

    test('cancelled sounds do not try fallback formats or return a mock sound', () async {
      final response = Completer<web.Response>();
      var requests = 0;
      late web.AbortSignal signal;
      _setFetch((_, init) {
        requests++;
        signal = init!.signal!;
        return response.future;
      });
      final options = _options()
        ..alternativeUrls = ['/fallback.mp3']
        ..ignoreErrors = true;
      final done = Sound.load('/cancel.wav', options);
      final failed = expectLater(done, throwsA(isA<LoadError>()));
      WebAudioApiSound.cancel('/cancel.wav');
      response.completeError(StateError('Aborted'));
      await failed;
      await _drain();

      expect(signal.aborted, isTrue);
      expect(requests, 1);
    });

    for (final failOldDecode in [false, true]) {
      test('a cancelled decode cannot ${failOldDecode ? 'fail' : 'complete'} a replacement load', () async {
        final decodes = <Completer<web.AudioBuffer>>[];
        _setFetch((_, _) async => _arrayBufferResponse(() async => JSArrayBuffer(8)));
        context.setProperty('decodeAudioData'.toJS, ((JSArrayBuffer _) {
          final result = Completer<web.AudioBuffer>();
          decodes.add(result);
          return result.future.toJS;
        }).toJS);
        final first = Sound.load('/replace.wav', _options());
        final cancelled = expectLater(first, throwsA(isA<LoadError>()));
        await _drain();
        expect(decodes, hasLength(1));
        // Starting the replacement must settle the old request too.
        final second = Sound.load('/replace.wav', _options());
        var completed = false;
        unawaited(second.then((_) => completed = true));
        await cancelled;
        await _drain();
        expect(decodes, hasLength(2));

        if (failOldDecode) {
          decodes.first.completeError(StateError('Old decoder failed'));
        } else {
          decodes.first.complete(context.createBuffer(1, 16, 8000));
        }
        await _drain();
        expect(completed, isFalse);
        decodes.last.complete(context.createBuffer(1, 32, 8000));
        expect((await second).length, 32 / 8000);
      });
    }
  });
}

SoundLoadOptions _options() => SoundLoadOptions()
  ..engine = .WebAudioApi
  ..ignoreErrors = false
  ..alternativeUrls = [];

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);

web.Response _arrayBufferResponse(Future<JSArrayBuffer> Function() body) => (JSObject()
  ..setProperty('ok'.toJS, true.toJS)
  ..setProperty('arrayBuffer'.toJS, (() => body().toJS).toJS)) as web.Response;

Future<void> _drain() => Future<void>.delayed(Duration.zero);
