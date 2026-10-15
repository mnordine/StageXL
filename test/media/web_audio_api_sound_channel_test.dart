@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

@JS('AudioContext.prototype.createAnalyser')
external JSFunction get _createAnalyser;

@JS('AudioContext.prototype.createAnalyser')
external set _createAnalyser(JSFunction value);

void main() {
  test('stopping a looping Web Audio channel completes once', () async {
    final options = SoundLoadOptions()
      ..engine = .WebAudioApi
      ..ignoreErrors = false;
    final sound = await Sound.loadDataUrl(_createSilentWavDataUrl(), options);
    final channel = sound.play(true);
    final complete = channel.onComplete.first;

    channel.stop();
    await complete;
    channel.stop();

    expect(channel.stopped, isTrue);
    expect(channel.paused, isTrue);
  });

  test('ordinary playback does not allocate an analyzer', () async {
    final sound = await _loadWebAudioSound();
    final createAnalyser = _createAnalyser;
    addTearDown(() => _createAnalyser = createAnalyser);
    _createAnalyser = _failAnalyzerAllocation.toJS;

    final channel = sound.play(true);
    addTearDown(channel.stop);

    expect(channel.soundAnalyzer, isNull);
    channel.pause();
    channel.resume();
    expect(channel.stopped, isFalse);
    expect(channel.paused, isFalse);
  });

  test('explicit analysis is reused across pause and resume', () async {
    final sound = await _loadWebAudioSound();
    final channel = sound.play(true);
    addTearDown(channel.stop);
    final analyzer = channel.createSoundAnalyzer();

    expect(analyzer, isNotNull);
    expect(channel.soundAnalyzer, same(analyzer));
    expect(channel.createSoundAnalyzer(), same(analyzer));
    channel.pause();
    channel.resume();
    expect(channel.soundAnalyzer, same(analyzer));
    expect(analyzer!.frequencyBinCount, greaterThan(0));
  });

  test('analysis can be created while paused and is released on stop', () async {
    final sound = await _loadWebAudioSound();
    final channel = sound.play(true);
    addTearDown(channel.stop);
    channel.pause();

    expect(channel.createSoundAnalyzer(), isNotNull);
    channel.resume();
    expect(channel.paused, isFalse);
    channel.stop();
    expect(channel.soundAnalyzer, isNull);
    expect(channel.createSoundAnalyzer(), isNull);
  });

  test('failed analyzer allocation leaves playback usable', () async {
    final sound = await _loadWebAudioSound();
    final channel = sound.play(true);
    addTearDown(channel.stop);
    final createAnalyser = _createAnalyser;
    addTearDown(() => _createAnalyser = createAnalyser);
    _createAnalyser = _failAnalyzerAllocation.toJS;

    expect(channel.createSoundAnalyzer, throwsStateError);
    expect(channel.soundAnalyzer, isNull);
    expect(channel.stopped, isFalse);
    expect(channel.paused, isFalse);
    channel.pause();
    channel.resume();

    _createAnalyser = createAnalyser;
    expect(channel.createSoundAnalyzer(), isNotNull);
  });

  test('unsupported engines do not create an analyzer', () async {
    final sound = await Sound.load('unused.mp3', SoundLoadOptions()..engine = .Mockup);
    final channel = sound.play(true);
    addTearDown(channel.stop);

    expect(channel.createSoundAnalyzer(), isNull);
    expect(channel.soundAnalyzer, isNull);
  });
}

JSObject _failAnalyzerAllocation() => throw StateError('Analyzer allocation failed');

Future<Sound> _loadWebAudioSound() => Sound.loadDataUrl(
    _createSilentWavDataUrl(),
    SoundLoadOptions()
      ..engine = .WebAudioApi
      ..ignoreErrors = false);

String _createSilentWavDataUrl() {
  const sampleRate = 8000;
  const sampleCount = 800;
  final bytes = Uint8List(44 + sampleCount);
  final data = ByteData.sublistView(bytes);

  void writeString(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + sampleCount, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate, Endian.little);
  data.setUint16(32, 1, Endian.little);
  data.setUint16(34, 8, Endian.little);
  writeString(36, 'data');
  data.setUint32(40, sampleCount, Endian.little);
  bytes.fillRange(44, bytes.length, 128);

  return 'data:audio/wav;base64,${base64Encode(bytes)}';
}
