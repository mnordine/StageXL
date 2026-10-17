@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:stagexl/stagexl.dart';
import 'package:stagexl/src/internal/audio_loader.dart';
import 'package:stagexl/src/internal/video_loader.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

@JS('HTMLMediaElement.prototype.load')
external JSFunction get _load;
@JS('HTMLMediaElement.prototype.load')
external set _load(JSFunction value);
@JS('URL.createObjectURL')
external JSFunction get _createObjectURL;
@JS('URL.createObjectURL')
external set _createObjectURL(JSFunction value);
@JS('URL.revokeObjectURL')
external JSFunction get _revokeObjectURL;
@JS('URL.revokeObjectURL')
external set _revokeObjectURL(JSFunction value);

void main() {
  late JSFunction fetch;
  late JSFunction load;
  late JSFunction create;
  late JSFunction revoke;
  late List<String> revoked;

  setUp(() {
    fetch = globalContext.getProperty<JSFunction>('fetch'.toJS);
    load = _load;
    create = _createObjectURL;
    revoke = _revokeObjectURL;
    revoked = [];
    _load = ((web.HTMLMediaElement element) {
      if (element.hasAttribute('src')) {
        scheduleMicrotask(() => element.dispatchEvent(web.Event('canplay')));
      }
    }).toJSCaptureThis;
    _revokeObjectURL = ((JSString url) {
      revoked.add(url.toDart);
      revoke.callAsFunction(null, url);
    }).toJS;
  });
  tearDown(() {
    globalContext.setProperty('fetch'.toJS, fetch);
    _load = load;
    _createObjectURL = create;
    _revokeObjectURL = revoke;
  });

  for (final isAudio in [true, false]) {
    final kind = isAudio ? 'audio' : 'video';
    test('$kind downloads pass the native blob directly to createObjectURL', () async {
      final blob = web.Blob();
      web.Blob? source;
      _setFetch((_, _) async => (JSObject()
        ..setProperty('ok'.toJS, true.toJS)
        ..setProperty('blob'.toJS, (() => Future.value(blob).toJS).toJS)) as web.Response);
      _createObjectURL = ((web.Blob value) {
        source = value;
        return create.callAsFunction(null, value)! as JSString;
      }).toJS;
      final loader = isAudio ? AudioLoader(['/media.wav'], true, false) : VideoLoader(['/media.webm'], true, false);
      late web.HTMLMediaElement element;
      late void Function() cancel;
      if (loader is AudioLoader) {
        element = await loader.done;
        cancel = loader.cancel;
      } else {
        final video = loader as VideoLoader;
        element = await video.done;
        cancel = video.cancel;
      }
      final url = element.src;
      expect(source, same(blob));
      expect(url, startsWith('blob:'));
      expect(revoked, isEmpty, reason: 'the source must stay valid for playback and cloning');
      cancel();
      cancel();
      expect(revoked, [url]);
      expect(element.hasAttribute('src'), isFalse);
    });

    test('$kind cancellation aborts its download and does not load a fallback', () async {
      final response = Completer<web.Response>();
      late web.AbortSignal signal;
      var requests = 0;
      _setFetch((_, init) {
        requests++;
        signal = init!.signal!;
        return response.future;
      });
      final loader = isAudio
          ? AudioLoader(['/first.wav', '/fallback.mp3'], true, false)
          : VideoLoader(['/first.webm', '/fallback.mp4'], true, false);
      late Future done;
      late void Function() cancel;
      if (loader is AudioLoader) {
        done = loader.done;
        cancel = loader.cancel;
      } else {
        final video = loader as VideoLoader;
        done = video.done;
        cancel = video.cancel;
      }
      final failed = expectLater(done, throwsA(isA<LoadError>()));
      cancel();
      response.completeError(StateError('Aborted'));
      await failed;
      await Future<void>.delayed(Duration.zero);
      expect(signal.aborted, isTrue);
      expect(requests, 1);
      expect(revoked, isEmpty);
    });
  }

  test('video clones keep their shared blob URL until the last owner is disposed', () async {
    _setFetch((_, _) async => web.Response(web.Blob()));
    final video = await Video.load('/shared.webm', VideoLoadOptions()
      ..loadData = true
      ..alternativeUrls = []);
    final clone = await video.clone();
    final url = video.videoElement.src;
    expect(clone.videoElement.src, url);

    video.dispose();
    video.dispose();
    expect(revoked, isEmpty);
    expect(clone.videoElement.hasAttribute('src'), isTrue);
    final secondClone = await clone.clone();
    clone.dispose();
    expect(revoked, isEmpty);
    secondClone.dispose();
    secondClone.dispose();
    expect(revoked, [url]);
  });

  for (final isAudio in [true, false]) {
    test('${isAudio ? 'audio' : 'video'} completion cannot escape simultaneous disposal', () async {
      late ResourceManager manager;
      _load = ((web.HTMLMediaElement element) {
        if (element.hasAttribute('src')) {
          scheduleMicrotask(() {
            element.dispatchEvent(web.Event('canplay'));
            manager.dispose();
          });
        }
      }).toJSCaptureThis;
      manager = ResourceManager();
      if (isAudio) {
        manager.addSound('sound', '/late.wav', SoundLoadOptions()..engine = .AudioElement);
      } else {
        manager.addVideo('video', '/late.webm');
      }
      final resource = manager.resources.single;
      await manager.load();
      expect(resource.error, isA<LoadError>());
    });
  }

  for (final isAudio in [true, false]) {
    test('${isAudio ? 'audio' : 'video'} cancellation is isolated between managers sharing a URL', () async {
      final elements = <web.HTMLMediaElement>[];
      _load = ((web.HTMLMediaElement element) {
        if (element.hasAttribute('src')) elements.add(element);
      }).toJSCaptureThis;
      final first = ResourceManager();
      final second = ResourceManager();
      for (final manager in [first, second]) {
        if (isAudio) {
          manager.addSound('sound', '/shared.wav', SoundLoadOptions()..engine = .AudioElement);
        } else {
          manager.addVideo('video', '/shared.webm');
        }
      }
      final firstResource = first.resources.single;
      final firstLoaded = first.load();
      final secondLoaded = second.load();
      expect(elements, hasLength(2));
      first.dispose();
      elements.last.dispatchEvent(web.Event('canplay'));
      await firstLoaded;
      await secondLoaded;
      expect(firstResource.error, isA<LoadError>());
      expect(second.finishedResources, hasLength(1));
      second.dispose();
    });
  }

  test('disposing loaded resources releases media sources', () async {
    _setFetch((_, _) async => web.Response(web.Blob()));
    final audioCount = web.document.querySelectorAll('audio').length;
    final manager = ResourceManager()
      ..addVideo('video', '/dispose.webm', VideoLoadOptions()..loadData = true)
      ..addSound('sound', '/dispose.wav', SoundLoadOptions()..engine = .AudioElement);
    await manager.load();
    final url = manager.getVideo('video').videoElement.src;
    expect(web.document.querySelectorAll('audio').length, audioCount + 1);
    manager.dispose();
    expect(revoked, [url]);
    expect(web.document.querySelectorAll('audio').length, audioCount);
  });

  test('disposing resources cancels AudioElement loads instead of returning a mock', () async {
    _load = ((web.HTMLMediaElement _) {}).toJSCaptureThis;
    final manager = ResourceManager()..addSound('/sound', '/pending.wav', SoundLoadOptions()..engine = .AudioElement);
    final resource = manager.resources.single;
    final loaded = manager.load();
    manager.dispose();
    await loaded;
    expect(resource.error, isA<LoadError>());
  });

  test('disposing resources aborts pending video downloads', () async {
    final response = Completer<web.Response>();
    late web.AbortSignal signal;
    _setFetch((_, init) {
      signal = init!.signal!;
      return response.future;
    });
    final manager = ResourceManager()..addVideo('video', '/pending.webm', VideoLoadOptions()..loadData = true);
    final resource = manager.resources.single;
    final loaded = manager.load();
    manager.dispose();
    await loaded;
    expect(resource.error, isA<LoadError>());
    expect(signal.aborted, isTrue);
    response.complete(web.Response(web.Blob()));
    await Future<void>.delayed(Duration.zero);
    expect(revoked, isEmpty);
  });
}

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);
