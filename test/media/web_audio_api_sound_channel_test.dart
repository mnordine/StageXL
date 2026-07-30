@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

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
