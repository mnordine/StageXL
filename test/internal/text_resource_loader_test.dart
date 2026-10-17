@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late JSFunction fetch;
  setUp(() => fetch = globalContext.getProperty<JSFunction>('fetch'.toJS));
  tearDown(() => globalContext.setProperty('fetch'.toJS, fetch));

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
