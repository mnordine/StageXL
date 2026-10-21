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
  setUp(() => fetch = globalContext.getProperty<JSFunction>('fetch'.toJS));
  tearDown(() => globalContext.setProperty('fetch'.toJS, fetch));

  for (final isManifest in [false, true]) {
    test('disposing ${isManifest ? 'manifest' : 'text'} resources aborts a pending body', () async {
      final body = Completer<JSString>();
      final reading = Completer<void>();
      late web.AbortSignal signal;
      _setFetch((_, init) async {
        signal = init!.signal!;
        return (JSObject()
          ..setProperty('ok'.toJS, true.toJS)
          ..setProperty('text'.toJS, (() {
            reading.complete();
            return body.future.toJS;
          }).toJS)) as web.Response;
      });
      final manager = ResourceManager();
      if (isManifest) {
        manager.assetManifests.add('resource', '/manifest.json');
      } else {
        manager.addTextFile('resource', '/text.txt');
      }
      final resource = manager.resources.single;
      await reading.future;
      manager.dispose();
      await resource.complete;
      expect(signal.aborted, isTrue);
      expect(resource.error, isA<LoadCancelledError>());
      body.complete('{}'.toJS);
    });
  }

  test('the browser fetches text and manifest data without a fetch stub', () async {
    final manager = ResourceManager()
      ..addTextFile('text', Uri.dataFromString('native browser text').toString());
    addTearDown(manager.dispose);
    manager.assetManifests.add('manifest', Uri.dataFromString('{"asset.png":"hash.png"}',
        mimeType: 'application/json').toString());

    await manager.load();
    expect(manager.getTextFile('text'), 'native browser text');
    expect(manager.assetManifests.get('manifest').mapUrl('/asset.png'), '/hash.png');
  });

  test('text resources and manifests use native text responses', () async {
    final urls = <String>[];
    _setFetch((url, _) async {
      urls.add(url);
      return web.Response((url == '/manifest.json' ? '{"asset.png":"hash.png"}' : 'native text').toJS);
    });
    final manager = ResourceManager()..addTextFile('text', '/text.txt');
    manager.assetManifests.add('manifest', '/manifest.json');
    await manager.load();
    expect(manager.getTextFile('text'), 'native text');
    expect(manager.assetManifests.get('manifest').mapUrl('/asset.png'), '/hash.png');
    expect(urls, ['/text.txt', '/manifest.json']);
  });
}

void _setFetch(Future<web.Response> Function(String, web.RequestInit?) fetch) =>
    globalContext.setProperty('fetch'.toJS, ((JSString url, [JSAny? init]) =>
        fetch(url.toDart, init as web.RequestInit?).toJS).toJS);
