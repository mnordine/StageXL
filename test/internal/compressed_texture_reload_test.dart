@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:stagexl/src/internal/texture_source_loader.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late JSFunction fetch;
  var requests = 0;

  setUp(() {
    fetch = globalContext.getProperty<JSFunction>('fetch'.toJS);
    requests = 0;
    _setFetch((_, _) async {
      requests++;
      return web.Response(_bytes().toJS);
    });
  });
  tearDown(() => globalContext.setProperty('fetch'.toJS, fetch));

  test('fetch uses default HTTP caching and returns the native ArrayBuffer without copying', () async {
    final native = JSArrayBuffer(8);
    String? cacheMode;
    _setFetch((_, init) async {
      cacheMode = web.Request('/direct.pvr'.toJS, init!).cache;
      return (JSObject()
        ..setProperty('ok'.toJS, true.toJS)
        ..setProperty('arrayBuffer'.toJS, (() => Future.value(native).toJS).toJS)) as web.Response;
    });
    final buffer = await TextureSourceLoader.loadBuffer('/direct.pvr', signal: web.AbortController().signal);
    expect(cacheMode, 'default');
    expect(buffer.toJS, same(native));
  });

  test('an aborted load does not start a request', () async {
    final controller = web.AbortController()..abort();
    await expectLater(TextureSourceLoader.loadBuffer('/aborted.pvr', signal: controller.signal),
        throwsA(isA<LoadError>()));
    expect(requests, 0);
  });

  test('cancellation settles while fetch remains pending', () async {
    final pending = Completer<web.Response>();
    _setFetch((_, _) => pending.future);
    final controller = web.AbortController();
    final failed = expectLater(TextureSourceLoader.loadBuffer('/pending.pvr', signal: controller.signal),
        throwsA(isA<LoadError>()));
    controller.abort();
    await failed;
    pending.complete(web.Response(_bytes().toJS));
  });

  test('textures without a source URL keep their buffer for restoration', () async {
    final (stage, context) = _stage();
    final compressed = PvrTexture(_bytes().buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed);
    addTearDown(texture.dispose);
    stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(texture.quad)));
    stage.materialize(0, 0);
    expect(compressed.hasBackingBuffer, isTrue);
    await _restore(context);
    stage.materialize(1, 0);
    expect(compressed.hasBackingBuffer, isTrue);
    expect(requests, 0);
    expect(_pixel(context), [255, 0, 0, 255]);
  });

  test('successful uploads release the backing buffer and refetches render the same pixels', () async {
    final (stage, context) = _stage();
    final buffer = await TextureSourceLoader.loadBuffer('/restore.pvr', signal: web.AbortController().signal);
    final compressed = PvrTexture(buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/restore.pvr');
    addTearDown(texture.dispose);
    stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(texture.quad)));
    stage.materialize(0, 0);
    expect(compressed.hasBackingBuffer, isFalse);
    expect(_pixel(context), [255, 0, 0, 255]);
    await _restore(context);
    expect(compressed.hasBackingBuffer, isFalse);
    expect(requests, 2, reason: 'restoration must refetch through the normal HTTP cache');
    stage.materialize(1, 0);
    expect(_pixel(context), [255, 0, 0, 255]);
  });

  test('disposal deletes an uploaded texture and excludes it from restoration', () async {
    final (_, context) = _stage();
    final compressed = PvrTexture(_bytes().buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/disposed-before-restore.pvr');
    addTearDown(texture.dispose);
    texture.activate(context, web.WebGLRenderingContext.TEXTURE0);
    final handle = texture.texture!;
    expect(context.rawContext.isTexture(handle), isTrue);
    expect(compressed.hasBackingBuffer, isFalse);
    texture.dispose();
    expect(context.rawContext.isTexture(handle), isFalse);
    expect(texture.texture, isNull);
    await _restore(context);
    expect(context.contextValid, isTrue);
    expect(requests, 0);
  });

  test('moving a released texture to another stage waits for reload and renders correctly', () async {
    final (firstStage, _) = _stage();
    final (secondStage, secondContext) = _stage();
    final buffer = await TextureSourceLoader.loadBuffer('/moved.pvr', signal: web.AbortController().signal);
    final compressed = PvrTexture(buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/moved.pvr');
    addTearDown(texture.dispose);
    final bitmap = Bitmap(BitmapData.fromRenderTextureQuad(texture.quad));
    firstStage.addChild(bitmap);
    firstStage.materialize(0, 0);
    final restored = secondContext.onContextRestored.first;
    secondStage.addChild(bitmap);
    secondStage.materialize(1, 0);
    expect(secondContext.contextValid, isFalse);
    await restored.timeout(const Duration(seconds: 5));
    secondStage.materialize(2, 0);
    expect(compressed.hasBackingBuffer, isFalse);
    expect(_pixel(secondContext), [255, 0, 0, 255]);
    expect(requests, 2);
  });

  for (final replacementUrl in [null, '/replacement.pvr']) {
    test('rewrapping a released texture preserves its original URL with replacement $replacementUrl', () async {
      final (stage, context) = _stage();
      final compressed = PvrTexture(_bytes().buffer);
      final original = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/original.pvr');
      original.activate(context, web.WebGLRenderingContext.TEXTURE0);
      expect(compressed.hasBackingBuffer, isFalse);
      original.dispose();

      final urls = <String>[];
      _setFetch((url, _) async {
        urls.add(url);
        return web.Response(_bytes().toJS);
      });
      final replacement = RenderTexture.fromCompressedTexture(compressed, sourceUrl: replacementUrl);
      addTearDown(replacement.dispose);
      stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(replacement.quad)));
      final restored = context.onContextRestored.first;
      stage.materialize(0, 0);
      await restored.timeout(const Duration(seconds: 5));
      stage.materialize(1, 0);
      expect(urls, ['/original.pvr']);
      expect(_pixel(context), [255, 0, 0, 255]);
      expect(compressed.hasBackingBuffer, isFalse);
    });
  }

  test('missing backing data and restoration URL report a descriptive load error', () async {
    final (_, context) = _stage();
    final texture = RenderTexture.fromCompressedTexture(_MissingSourceTexture());
    addTearDown(texture.dispose);
    final failed = context.onContextRestoreError.first;
    expect(() => texture.activate(context, web.WebGLRenderingContext.TEXTURE0),
        throwsA(isA<RenderTexturePendingException>()));
    final error = await failed.timeout(const Duration(seconds: 5));
    expect(error.error, isA<LoadError>().having((error) => error.message, 'message',
        'Cannot restore compressed texture without a backing buffer or source URL.'));
    expect(context.contextValid, isFalse);
    expect(requests, 0);
  });

  test('a second context loss cancels the old restore and allows a fresh restore', () async {
    final (stage, context) = _stage();
    final buffer = await TextureSourceLoader.loadBuffer('/repeated.pvr', signal: web.AbortController().signal);
    final compressed = PvrTexture(buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/repeated.pvr');
    addTearDown(texture.dispose);
    stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(texture.quad)));
    stage.materialize(0, 0);
    final pending = Completer<web.Response>();
    final reading = Completer<void>();
    _setFetch((_, _) {
      requests++;
      reading.complete();
      return pending.future;
    });
    var extension = context.rawContext.getExtension('WEBGL_lose_context')! as web.WEBGL_lose_context;
    var lost = context.onContextLost.first;
    extension.loseContext();
    await lost;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    extension.restoreContext();
    await reading.future;
    extension = context.rawContext.getExtension('WEBGL_lose_context')! as web.WEBGL_lose_context;
    lost = context.onContextLost.first;
    extension.loseContext();
    await lost;
    pending.complete(web.Response(_bytes().toJS));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(context.contextValid, isFalse);
    _setFetch((_, _) async {
      requests++;
      return web.Response(_bytes().toJS);
    });
    final restored = context.onContextRestored.first;
    extension.restoreContext();
    await restored.timeout(const Duration(seconds: 5));
    stage.materialize(1, 0);
    expect(compressed.hasBackingBuffer, isFalse);
    expect(_pixel(context), [255, 0, 0, 255]);
    expect(requests, 3);
  });

  test('disposal during restoration settles without uploading the late texture', () async {
    final (_, context) = _stage();
    final buffer = await TextureSourceLoader.loadBuffer('/disposed.pvr', signal: web.AbortController().signal);
    final compressed = PvrTexture(buffer);
    final texture = RenderTexture.fromCompressedTexture(compressed, sourceUrl: '/disposed.pvr');
    texture.activate(context, web.WebGLRenderingContext.TEXTURE0);
    final pending = Completer<web.Response>();
    final reading = Completer<void>();
    _setFetch((_, _) {
      requests++;
      reading.complete();
      return pending.future;
    });
    final restored = _restore(context);
    await reading.future;
    texture.dispose();
    await restored;
    expect(texture.texture, isNull);
    expect(compressed.hasBackingBuffer, isFalse);
    pending.complete(web.Response(_bytes().toJS));
  });

  test('restoration reads at most two texture bodies concurrently', () async {
    final (_, context) = _stage();
    final textures = <RenderTexture>[];
    for (var i = 0; i < 5; i++) {
      final url = '/parallel-$i.pvr';
      final buffer = await TextureSourceLoader.loadBuffer(url, signal: web.AbortController().signal);
      final texture = RenderTexture.fromCompressedTexture(PvrTexture(buffer), sourceUrl: url);
      textures.add(texture);
      texture.activate(context, web.WebGLRenderingContext.TEXTURE0);
    }
    addTearDown(() => textures.forEach((texture) => texture.dispose()));
    var active = 0;
    var peak = 0;
    _setFetch((_, _) {
      Future<web.Response> read() async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return web.Response(_bytes().toJS);
      }
      return read();
    });
    await _restore(context);
    expect(peak, 2);
  });

  test('restoration failures are surfaced and keep rendering paused', () async {
    final (_, context) = _stage();
    final buffer = await TextureSourceLoader.loadBuffer('/offline.pvr', signal: web.AbortController().signal);
    final texture = RenderTexture.fromCompressedTexture(PvrTexture(buffer), sourceUrl: '/offline.pvr');
    addTearDown(texture.dispose);
    texture.activate(context, web.WebGLRenderingContext.TEXTURE0);
    _setFetch((_, _) => Future.error(StateError('offline')));
    final failed = context.onContextRestoreError.first;
    final extension = context.rawContext.getExtension('WEBGL_lose_context')! as web.WEBGL_lose_context;
    final lost = context.onContextLost.first;
    extension.loseContext();
    await lost;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    extension.restoreContext();
    expect(await failed.timeout(const Duration(seconds: 5)), isA<LoadError>());
    expect(context.contextValid, isFalse);
  });
}

(Stage, RenderContextWebGL) _stage() {
  final canvas = web.HTMLCanvasElement()..width = 4..height = 4;
  web.document.body!.appendChild(canvas);
  final stage = Stage(canvas, width: 4, height: 4, options: StageOptions()
    ..renderEngine = .WebGL2
    ..maxPixelRatio = 1);
  final context = stage.renderContext as RenderContextWebGL;
  expect(CompressedTexture.supportsDxt, isTrue);
  addTearDown(() {
    final extension = context.rawContext.getExtension('WEBGL_lose_context') as web.WEBGL_lose_context?;
    extension?.loseContext();
    canvas.remove();
  });
  return (stage, context);
}

Future<void> _restore(RenderContextWebGL context) async {
  final extension = context.rawContext.getExtension('WEBGL_lose_context')! as web.WEBGL_lose_context;
  final lost = context.onContextLost.first;
  extension.loseContext();
  await lost.timeout(const Duration(seconds: 5));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final restored = context.onContextRestored.first;
  extension.restoreContext();
  await restored.timeout(const Duration(seconds: 5));
}

List<int> _pixel(RenderContextWebGL context) {
  final pixels = Uint8List(4);
  context.rawContext.readPixels(0, 0, 1, 1, web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE, pixels.toJS);
  expect(context.rawContext.getError(), web.WebGLRenderingContext.NO_ERROR);
  return pixels;
}

Uint8List _bytes() {
  final bytes = Uint8List(60);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, 0x03525650, Endian.little);
  header.setUint32(8, 7, Endian.little);
  for (final offset in [24, 28]) {
    header.setUint32(offset, 4, Endian.little);
  }
  for (final offset in [32, 36, 40, 44]) {
    header.setUint32(offset, 1, Endian.little);
  }
  header.setUint16(52, 0xF800, Endian.little);
  return bytes;
}

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);

class _MissingSourceTexture extends CompressedTexture {
  _MissingSourceTexture() : super(null) {
    width = 4;
    height = 4;
  }

  @override
  int get format => 0x83F1;

  @override
  ByteData get textureData => throw StateError('Missing backing data must not be uploaded.');
}
