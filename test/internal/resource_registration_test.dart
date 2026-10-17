@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late JSFunction fetch;
  late void Function(String)? onConflict;
  late List<String> conflicts;

  setUp(() {
    fetch = globalContext.getProperty<JSFunction>('fetch'.toJS);
    onConflict = ResourceManager.onResourceConflict;
    conflicts = [];
    ResourceManager.onResourceConflict = conflicts.add;
  });
  tearDown(() {
    globalContext.setProperty('fetch'.toJS, fetch);
    ResourceManager.onResourceConflict = onConflict;
  });

  for (final kind in ['bitmap', 'atlas', 'sound', 'sound sprite', 'video', 'manifest']) {
    test('$kind compares equivalent options and reports conflicting definitions without downloading', () async {
      final response = Completer<web.Response>();
      final urls = <String>[];
      _setFetch((url, _) {
        urls.add(url);
        return response.future;
      });
      final manager = ResourceManager();
      void add(String path, {bool changed = false}) {
        switch (kind) {
          case 'bitmap':
            manager.addBitmapData('same', '$path.png', BitmapDataLoadOptions()..corsEnabled = changed);
          case 'atlas':
            manager.addTextureAtlas('same', '$path.json', .jsonArray,
                BitmapDataLoadOptions()..pixelRatios = changed ? [1] : [1, 2]);
          case 'sound':
            manager.addSound('same', '$path.wav', SoundLoadOptions()
              ..engine = .WebAudioApi
              ..alternativeUrls = []
              ..ignoreErrors = changed);
          case 'sound sprite':
            manager.addSoundSprite('same', '$path.json', SoundLoadOptions()..corsEnabled = changed);
          case 'video':
            manager.addVideo('same', '$path.webm', VideoLoadOptions()
              ..loadData = true
              ..alternativeUrls = []
              ..corsEnabled = changed);
          case 'manifest':
            manager.assetManifests.add('same', '$path.json', changed ? '/other/' : '/');
        }
      }
      add('/first');
      final resource = manager.resources.single;
      add('/first');
      expect(conflicts, isEmpty);
      add('/first', changed: true);
      expect(conflicts, hasLength(1));
      add('/second');
      expect(conflicts, hasLength(2));
      expect(conflicts.last, contains('/second'));
      add('/first');
      expect(conflicts, hasLength(2), reason: 'ignored conflicts cannot replace the first definition');
      expect(manager.resources.single, same(resource));
      await _drain();
      expect(urls, hasLength(1));
      manager.dispose();
      response.completeError(StateError('Finish pending registration verification.'));
      await resource.complete;
      await _drain();
    });
  }

  test('default bitmap options and an equal explicit options object are identical', () async {
    final response = Completer<web.Response>();
    _setFetch((_, _) => response.future);
    final original = BitmapData.defaultLoadOptions;
    final options = BitmapDataLoadOptions();
    BitmapData.defaultLoadOptions = options;
    addTearDown(() => BitmapData.defaultLoadOptions = original);
    final manager = ResourceManager()..addBitmapData('same', '/same.png');
    final resource = manager.resources.single;
    manager.addBitmapData('same', '/same.png', options.clone());
    expect(conflicts, isEmpty);
    options.pixelRatios.add(3);
    manager.addBitmapData('same', '/same.png', options);
    expect(conflicts, hasLength(1), reason: 'the first options must be captured by value');
    await _drain();
    response.completeError(StateError('Finish pending registration verification.'));
    await resource.complete;
    manager.dispose();
  });

  test('atlas formats are part of the definition', () async {
    final response = Completer<web.Response>();
    _setFetch((_, _) => response.future);
    final manager = ResourceManager()..addTextureAtlas('same', '/same.json');
    final resource = manager.resources.single;
    manager.addTextureAtlas('same', '/same.json', .jsonArray);
    manager.addTextureAtlas('same', '/same.json', .json);
    expect(conflicts, isEmpty);
    manager.addTextureAtlas('same', '/same.json', .starlingXml);
    expect(conflicts, hasLength(1));
    manager.dispose();
    response.complete(web.Response());
    await resource.complete;
  });

  test('inline text and custom futures retain the first definition until explicitly removed', () async {
    final manager = ResourceManager();
    final first = Future.value(1);
    manager.texts.add('same', 'first');
    manager.customObjects.add('same', first);
    await manager.load();
    manager.texts.add('same', 'first');
    manager.customObjects.add('same', first);
    expect(conflicts, isEmpty);
    manager.texts.add('same', 'second');
    manager.customObjects.add('same', Future.value(2));
    expect(conflicts, hasLength(2));
    expect(manager.texts.get('same'), 'first');
    expect(manager.customObjects.get('same'), 1);
    manager.texts.remove('same');
    manager.texts.add('same', 'replacement');
    await manager.load();
    expect(manager.texts.get('same'), 'replacement');
    expect(conflicts, hasLength(2));
    manager.dispose();
  });

  test('text-file URLs are part of the definition', () async {
    var requests = 0;
    _setFetch((_, _) async {
      requests++;
      return web.Response('first'.toJS);
    });
    final manager = ResourceManager()..addTextFile('same', '/first.txt');
    await manager.load();
    manager.addTextFile('same', '/first.txt');
    expect(conflicts, isEmpty);
    manager.addTextFile('same', '/second.txt');
    expect(conflicts, hasLength(1));
    expect(requests, 1);
    expect(manager.getTextFile('same'), 'first');
    manager.dispose();
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);
