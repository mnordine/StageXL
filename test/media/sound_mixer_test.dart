@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

@JS('Object.getOwnPropertyDescriptor')
external JSObject? _getOwnPropertyDescriptor(JSObject object, JSString property);

@JS('Object.defineProperty')
external JSObject _defineProperty(JSObject object, JSString property, JSObject descriptor);

@JS('Reflect.deleteProperty')
external bool _deleteProperty(JSObject object, JSString property);

void main() {
  late bool sourceStarted;
  late int resumeCalls;
  late Future<void> Function() resume;

  setUp(() {
    final engine = SoundMixer.engine;
    SoundMixer.engine = .WebAudioApi;
    addTearDown(() => SoundMixer.engine = engine);
    sourceStarted = false;
    resumeCalls = 0;
    resume = Future<void>.value;

    final context = WebAudioApiMixer.audioContext;
    final source = context.createBufferSource();
    // Native interop methods do not support tear-offs.
    // ignore: unnecessary_lambdas
    addTearDown(() => source.disconnect());
    _overrideProperty(context, 'createBufferSource', (() => source).toJS);
    _overrideProperty(source, 'start', ((JSNumber _) {
      sourceStarted = true;
    }).toJS);
    _overrideProperty(context, 'resume', (() {
      resumeCalls++;
      return resume().toJS;
    }).toJS);
  });

  test('starts the silent source before awaiting context resume', () async {
    final resumed = Completer<void>();
    addTearDown(() {
      if (!resumed.isCompleted) resumed.complete();
    });
    resume = () => resumed.future;

    var unlocked = false;
    final unlock = SoundMixer.unlockMobileAudioAsync().then((_) => unlocked = true);
    expect(resumeCalls, 1);
    expect(sourceStarted, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(unlocked, isFalse);

    resumed.complete();
    await unlock;
    expect(unlocked, isTrue);
  });

  test('async unlock propagates resume errors', () async {
    resume = () => Future<void>.error(StateError('Resume was blocked'));

    await expectLater(SoundMixer.unlockMobileAudioAsync(), throwsA(anything));
    expect(resumeCalls, 1);
  });

  test('legacy unlock suppresses async resume errors', () async {
    resume = () => Future<void>.error(StateError('Resume was blocked'));

    SoundMixer.unlockMobileAudio();
    await Future<void>.delayed(Duration.zero);
    expect(resumeCalls, 1);
    expect(sourceStarted, isTrue);
  });

  for (final engine in <SoundEngine>[.AudioElement, .Mockup]) {
    test('does not unlock Web Audio when using ${engine.name}', () async {
      SoundMixer.engine = engine;

      await SoundMixer.unlockMobileAudioAsync();
      SoundMixer.unlockMobileAudio();
      await Future<void>.delayed(Duration.zero);
      expect(resumeCalls, 0);
      expect(sourceStarted, isFalse);
    });
  }
}

void _overrideProperty(JSObject object, String property, JSAny value) {
  final key = property.toJS;
  final original = _getOwnPropertyDescriptor(object, key);
  addTearDown(() {
    if (original == null) {
      _deleteProperty(object, key);
    } else {
      _defineProperty(object, key, original);
    }
  });
  _defineProperty(object, key, JSObject()
    ..setProperty('configurable'.toJS, true.toJS)
    ..setProperty('value'.toJS, value));
}
