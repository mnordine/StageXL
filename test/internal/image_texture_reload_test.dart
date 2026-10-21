@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stagexl/stagexl.dart';
import 'package:stagexl/src/internal/image_loader.dart';
import 'package:stagexl/src/internal/texture_source_loader.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late JSFunction originalFetch;
  late JSFunction originalDecode;
  late Uint8List png;
  final requests = <String>[];
  final decoded = <web.ImageBitmap>[];

  setUp(() {
    originalFetch = globalContext.getProperty<JSFunction>('fetch'.toJS);
    originalDecode = globalContext.getProperty<JSFunction>('createImageBitmap'.toJS);
    requests.clear();
    decoded.clear();
    png = _imageBytes('image/png');
    Future<web.ImageBitmap> decode(web.Blob blob) async {
      final image = originalDecode.callAsFunction(null, blob) as JSPromise<web.ImageBitmap>;
      final bitmap = await image.toDart;
      decoded.add(bitmap);
      return bitmap;
    }
    globalContext.setProperty('createImageBitmap'.toJS, ((web.Blob blob) => decode(blob).toJS).toJS);
    _setFetch((url, _) async {
      requests.add(url);
      return web.Response(png.toJS);
    });
  });

  tearDown(() {
    globalContext.setProperty('fetch'.toJS, originalFetch);
    globalContext.setProperty('createImageBitmap'.toJS, originalDecode);
  });

  test('image release and CPU readability are opt in and clone preserves both options', () {
    final options = BitmapDataLoadOptions();
    expect(options.releaseImageSources, isFalse);
    expect(options.readable, isFalse);
    options..releaseImageSources = true..readable = true;
    expect(options.clone().releaseImageSources, isTrue);
    expect(options.clone().readable, isTrue);
  });

  for (final type in ['png', 'jpeg', 'webp']) {
    test('$type images close after upload and reload on context restoration', () async {
      final bytes = _imageBytes('image/$type');
      _setFetch((url, init) async {
        requests.add(url);
        expect(web.Request(url.toJS, init!).cache, 'default');
        return web.Response(bytes.toJS);
      });
      final bitmap = await _loadBitmap('/image.$type', _options());
      addTearDown(bitmap.renderTexture.dispose);
      final (stage, context) = _stage();
      stage.addChild(Bitmap(bitmap));
      stage.materialize(0, 0);
      expect(decoded.single.width, 0, reason: 'ImageBitmap.close must release the decoded pixels');
      final before = _pixels(context);
      expect(before.any((value) => value != 0), isTrue);
      await _restore(context);
      stage.materialize(1, 0);
      expect(_pixels(context), before);
      expect(requests, ['/image.$type', '/image.$type']);
      expect(decoded.last.width, 0);
    });
  }

  test('released images reject CPU access by default without affecting rendering', () async {
    final bitmap = await _loadBitmap('/no-readback.png', _options());
    addTearDown(bitmap.renderTexture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    final before = _pixels(context);
    expect(bitmap.clone, throwsStateError);
    expect(() => bitmap.getPixel32(0, 0), throwsStateError);
    stage.materialize(1, 0);
    expect(_pixels(context), before);
  });

  test('CPU-readable images retain their original pixels after upload and restore without fetching', () async {
    final bitmap = await _loadBitmap('/readback.png', _options()..readable = true);
    addTearDown(bitmap.renderTexture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    final before = _pixels(context);
    expect(decoded.single.width, 4, reason: 'CPU-readable images keep the original decoded source');
    final clone = bitmap.clone();
    addTearDown(clone.renderTexture.dispose);
    expect(clone.getPixel32(0, 0), 0xFFFF0000);
    expect(clone.getPixel32(0, 3), 0xFF0000FF);
    expect(clone.getPixel32(3, 0), 0x8000FF00);
    stage.materialize(1, 0);
    expect(_pixels(context), before);
    bitmap.setPixel32(0, 0, 0xFFFFFFFF);
    await _restore(context);
    stage.materialize(2, 0);
    expect(bitmap.getPixel32(0, 0), 0xFFFFFFFF);
    expect(requests, ['/readback.png'], reason: 'CPU-readable textures restore from their retained source');
  });

  test('Canvas2D use before upload retains the decoded source for later pixel access', () async {
    final bitmap = await _loadBitmap('/cpu.png', _options());
    addTearDown(bitmap.renderTexture.dispose);
    final copy = bitmap.clone();
    addTearDown(copy.renderTexture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    expect(decoded.single.width, 4);
    expect(bitmap.getPixel32(0, 0), 0xFFFF0000);
    await _restore(context);
    stage.materialize(1, 0);
    expect(requests, ['/cpu.png']);
    expect(copy.getPixel32(0, 3), 0xFF0000FF);
  });

  test('the retention option preserves original images after upload', () async {
    final bitmap = await _loadBitmap('/retained.png', _options()..releaseImageSources = false);
    addTearDown(bitmap.renderTexture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    expect(decoded.single.width, 4);
    await _restore(context);
    stage.materialize(1, 0);
    expect(requests, ['/retained.png']);
  });

  test('atlas restoration uses the manifest-resolved image URL', () async {
    const source = '{"frames":{"whole.png":{"frame":{"x":0,"y":0,"w":4,"h":4},'
        '"rotated":false,"trimmed":false,"spriteSourceSize":{"x":0,"y":0,"w":4,"h":4},'
        '"sourceSize":{"w":4,"h":4}}},"meta":{"image":"image.png"}}';
    _setFetch((url, _) async {
      requests.add(url);
      return url.endsWith('.json') ? web.Response(source.toJS) : web.Response(png.toJS);
    });
    final atlas = await _withHttpClient(() => TextureAtlas.load('/atlas.json', null, _options(),
        AssetManifest({'image.png': 'image-hashed.png'})).atlasFuture);
    final bitmap = atlas.getBitmapData('whole');
    addTearDown(bitmap.renderTexture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    expect(decoded.single.width, 0);
    await _restore(context);
    stage.materialize(1, 0);
    expect(requests, ['/atlas.json', '/image-hashed.png', '/image-hashed.png']);
  });

  test('moving released images between stages reloads before rendering', () async {
    final bitmap = await _loadBitmap('/moved.png', _options());
    addTearDown(bitmap.renderTexture.dispose);
    final (first, _) = _stage();
    final (second, context) = _stage();
    final display = Bitmap(bitmap);
    first.addChild(display);
    first.materialize(0, 0);
    final restored = context.onContextRestored.first;
    second.addChild(display);
    second.materialize(1, 0);
    await restored.timeout(const Duration(seconds: 5));
    second.materialize(2, 0);
    expect(requests, ['/moved.png', '/moved.png']);
    expect(decoded.last.width, 0);
    expect(_pixels(context).any((value) => value != 0), isTrue);
  });

  test('disposing an image during restoration cancels its pending fetch', () async {
    final bitmap = await _loadBitmap('/disposed.png', _options());
    final (stage, context) = _stage();
    stage.addChild(Bitmap(bitmap));
    stage.materialize(0, 0);
    final pending = Completer<web.Response>();
    final started = Completer<void>();
    web.AbortSignal? signal;
    _setFetch((_, init) {
      signal = init!.signal;
      started.complete();
      return pending.future;
    });
    final restored = _restore(context);
    await started.future;
    bitmap.renderTexture.dispose();
    await restored;
    expect(signal!.aborted, isTrue);
    expect(bitmap.renderTexture.texture, isNull);
    pending.complete(web.Response(png.toJS));
  });

  test('an image decoded after restoration is cancelled releases its pixels', () async {
    final created = await (originalDecode.callAsFunction(null, web.Blob([png.toJS].toJS))
        as JSPromise<web.ImageBitmap>).toDart;
    final decoding = Completer<void>();
    final result = Completer<web.ImageBitmap>();
    globalContext.setProperty('createImageBitmap'.toJS, ((web.Blob _) {
      decoding.complete();
      return result.future.toJS;
    }).toJS);
    final controller = web.AbortController();
    final loading = TextureSourceLoader.loadImageBitmap('/late-image.png', signal: controller.signal);
    final failed = expectLater(loading, throwsA(isA<LoadError>()));
    await decoding.future;
    controller.abort();
    await failed;
    result.complete(created);
    await Future<void>.delayed(Duration.zero);
    expect(created.width, 0);
  });

  test('HTML image fallback releases its source and restores without ImageBitmap', () async {
    final url = 'data:image/png;base64,${base64Encode(png)}';
    final image = await ImageLoader(url, false).done;
    final texture = RenderTexture.fromImageElement(image, sourceUrl: url);
    addTearDown(texture.dispose);
    final (stage, context) = _stage();
    stage.addChild(Bitmap(BitmapData.fromRenderTextureQuad(texture.quad)));
    stage.materialize(0, 0);
    expect(image.hasAttribute('src'), isFalse);
    final before = _pixels(context);
    await _restore(context);
    stage.materialize(1, 0);
    expect(_pixels(context), before);
    expect(decoded, isEmpty);
  });
}

BitmapDataLoadOptions _options() => BitmapDataLoadOptions()
  ..webp = false..avif = false..releaseImageSources = true;

Uint8List _imageBytes(String type) {
  final canvas = web.HTMLCanvasElement()..width = 4..height = 4;
  final context = canvas.context2D;
  context..fillStyle = 'red'.toJS..fillRect(0, 0, 2, 2);
  context..fillStyle = 'rgba(0,255,0,0.5)'.toJS..fillRect(2, 0, 2, 2);
  context..fillStyle = 'blue'.toJS..fillRect(0, 2, 2, 2);
  return base64Decode(canvas.toDataURL(type, 1.toJS).split(',').last);
}

(Stage, RenderContextWebGL) _stage() {
  final canvas = web.HTMLCanvasElement()..width = 4..height = 4;
  web.document.body!.appendChild(canvas);
  final stage = Stage(canvas, width: 4, height: 4, options: StageOptions()
    ..renderEngine = .WebGL2..maxPixelRatio = 1);
  addTearDown(() {
    final context = stage.renderContext as RenderContextWebGL;
    final extension = context.rawContext.getExtension('WEBGL_lose_context') as web.WEBGL_lose_context?;
    extension?.loseContext();
    canvas.remove();
  });
  return (stage, stage.renderContext as RenderContextWebGL);
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

List<int> _pixels(RenderContextWebGL context) {
  final pixels = Uint8List(4 * 4 * 4);
  context.rawContext.readPixels(0, 0, 4, 4, web.WebGLRenderingContext.RGBA,
      web.WebGLRenderingContext.UNSIGNED_BYTE, pixels.toJS);
  expect(context.rawContext.getError(), web.WebGLRenderingContext.NO_ERROR);
  return pixels;
}

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);

Future<BitmapData> _loadBitmap(String url, BitmapDataLoadOptions options) =>
    _withHttpClient(() => BitmapData.load(url, options));

Future<T> _withHttpClient<T>(Future<T> Function() load) => http.runWithClient(load, () => MockClient((request) async {
  final response = await web.window.fetch(request.url.toString().toJS, web.RequestInit()).toDart;
  final body = await response.arrayBuffer().toDart;
  return http.Response.bytes(body.toDart.asUint8List(), response.status);
}));
