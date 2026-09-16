@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart' as web;
import 'package:test/test.dart';

void main() {
  for (final sampleRate in [44100, 48000]) {
    test('loops a $sampleRate Hz WAV without buzzing', () async {
      final sound = await _loadWaveform(sampleRate);
      final source = _captureSource(() {
        final channel = sound.play(true);
        addTearDown(channel.stop);
      });

      expect(source.loopEnd, sound.length);
      await _expectLoopOutput(source);
    });
  }

  test('loops a sound sprite segment ending at the original buffer boundary', () async {
    final sound = await _loadWaveform(48000);
    final start = 137 / WebAudioApiMixer.audioContext.sampleRate;
    final source = _captureSource(() {
      final channel = sound.playSegment(start, sound.length - start, true);
      addTearDown(channel.stop);
    });

    expect(source.loopStart, start);
    expect(source.loopEnd, sound.length);
    await _expectLoopOutput(source);
  });

  test('loops an interior sound sprite segment without changing its samples', () async {
    final sound = await _loadWaveform(44100);
    final rate = WebAudioApiMixer.audioContext.sampleRate;
    final source = _captureSource(() {
      final channel = sound.playSegment(137 / rate, 511 / rate, true);
      addTearDown(channel.stop);
    });

    await _expectLoopOutput(source);
  });

  test('resumes a looping sound at its position and reuses its buffer', () async {
    final sound = await _loadWaveform(44100);
    late SoundChannel channel;
    final initial = _captureSource(() => channel = sound.play(true));
    addTearDown(channel.stop);
    channel.pause();
    final offset = 173 / WebAudioApiMixer.audioContext.sampleRate;
    channel.position = offset;
    final resumed = _captureSource(channel.resume);

    expect(resumed.buffer, same(initial.buffer));
    expect(resumed.loopEnd, sound.length);
    await _expectLoopOutput(resumed, offset: offset);
  });

  test('keeps one-shot playback and sound length unchanged after looping', () async {
    final sound = await _loadWaveform(44100);
    final loop = _captureSource(() {
      final channel = sound.play(true);
      addTearDown(channel.stop);
    });
    final once = _captureSource(() {
      final channel = sound.play();
      addTearDown(channel.stop);
    });

    expect(once.loop, isFalse);
    expect(sound.length, once.buffer!.duration);
    expect(loop.buffer, isNot(same(once.buffer)));
    expect(loop.buffer!.length, once.buffer!.length + 1);
    for (var channel = 0; channel < once.buffer!.numberOfChannels; channel++) {
      expect(loop.buffer!.getChannelData(channel).toDart.take(once.buffer!.length),
          orderedEquals(once.buffer!.getChannelData(channel).toDart));
    }
  });

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
}

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

Future<Sound> _loadWaveform(int sampleRate) => Sound.loadDataUrl(
    _createWaveformWavDataUrl(sampleRate),
    SoundLoadOptions()
      ..engine = .WebAudioApi
      ..ignoreErrors = false);

web.AudioBufferSourceNode _captureSource(void Function() play) {
  final context = WebAudioApiMixer.audioContext;
  final key = 'createBufferSource'.toJS;
  final original = context.getProperty<JSFunction>(key);
  late web.AudioBufferSourceNode source;
  context.setProperty(key,
      (() => source = original.callAsFunction(context)! as web.AudioBufferSourceNode).toJS);
  try {
    play();
    return source;
  } finally {
    context.setProperty(key, original);
  }
}

Future<void> _expectLoopOutput(web.AudioBufferSourceNode source, {double offset = 0}) async {
  final buffer = source.buffer!;
  final rate = buffer.sampleRate;

  final first = (source.loopStart * rate).round();
  final end = (source.loopEnd * rate).round();
  final frames = end - first;
  final offsetFrames = (offset * rate).round();
  final context = web.OfflineAudioContext(web.OfflineAudioContextOptions(
      numberOfChannels: buffer.numberOfChannels, length: frames * 4, sampleRate: rate));

  final loop = context.createBufferSource()
    ..buffer = buffer
    ..loop = true
    ..loopStart = source.loopStart
    ..loopEnd = source.loopEnd;

  loop.connect(context.destination);
  loop.start(0, source.loopStart + offset);
  final rendered = await context.startRendering().toDart;

  for (var channel = 0; channel < buffer.numberOfChannels; channel++) {
    final original = buffer.getChannelData(channel).toDart;
    final output = rendered.getChannelData(channel).toDart;
    var maxError = 0.0;
    for (var i = 0; i < output.length; i++) {
      final expected = original[first + (offsetFrames + i) % frames];
      final error = (output[i] - expected).abs();
      if (error > maxError) maxError = error;
    }
    expect(maxError, lessThan(0.00001), reason: 'channel $channel must repeat the full segment');
  }
}

String _createWaveformWavDataUrl(int sampleRate) {
  // Match the tally asset's decoded lengths, including the floating-point
  // loop-end boundary that triggers Chromium 152's repeated render quantum.
  final frames = sampleRate == 44100 ? 104736 : 113999;
  const channels = 2;
  final dataLength = frames * channels * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);

  void writeString(int offset, String value) => bytes.setRange(offset, offset + value.length, value.codeUnits);

  writeString(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, .little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');

  data
    ..setUint32(16, 16, .little)
    ..setUint16(20, 1, .little)
    ..setUint16(22, channels, .little)
    ..setUint32(24, sampleRate, .little)
    ..setUint32(28, sampleRate * channels * 2, .little)
    ..setUint16(32, channels * 2, .little)
    ..setUint16(34, 16, .little);

  writeString(36, 'data');
  data.setUint32(40, dataLength, .little);
  for (var i = 0; i < frames; i++) {
    for (var channel = 0; channel < channels; channel++) {
      data.setInt16(44 + (i * channels + channel) * 2, ((i * 17 + channel * 13) % 101 - 50) * 500, .little);
    }
  }
  return 'data:audio/wav;base64,${base64Encode(bytes)}';
}
