part of '../media.dart';

abstract class SoundAnalyzer {
  int get fftSize;
  set fftSize(int value);

  int get frequencyBinCount;
  num get sampleRate;

  double get minDecibels;
  set minDecibels(num value);

  double get maxDecibels;
  set maxDecibels(num value);

  double get smoothingTimeConstant;
  set smoothingTimeConstant(num value);

  void getByteFrequencyData(Uint8List data);

  double getFrequencyRangeLevel(num minHz, num maxHz) {
    if (frequencyBinCount <= 0 || fftSize <= 0 || sampleRate <= 0) return 0;

    final data = JSUint8Array.withLength(frequencyBinCount).toDart;
    getByteFrequencyData(data);

    final hzPerBin = sampleRate / fftSize;
    final startBin = (minHz / hzPerBin).floor().clamp(0, data.length - 1);
    final endBin = (maxHz / hzPerBin).ceil().clamp(startBin + 1, data.length);
    var total = 0;

    for (var i = startBin; i < endBin; i++) {
      total += data[i];
    }

    return total / ((endBin - startBin) * 255);
  }
}

class WebAudioApiSoundAnalyzer extends SoundAnalyzer {
  final AnalyserNode _analyserNode;

  WebAudioApiSoundAnalyzer(this._analyserNode);

  @override
  int get fftSize => _analyserNode.fftSize;

  @override
  set fftSize(int value) {
    _analyserNode.fftSize = value;
  }

  @override
  int get frequencyBinCount => _analyserNode.frequencyBinCount;

  @override
  num get sampleRate => WebAudioApiMixer.audioContext.sampleRate;

  @override
  double get minDecibels => _analyserNode.minDecibels;

  @override
  set minDecibels(num value) {
    _analyserNode.minDecibels = value;
  }

  @override
  double get maxDecibels => _analyserNode.maxDecibels;

  @override
  set maxDecibels(num value) {
    _analyserNode.maxDecibels = value;
  }

  @override
  double get smoothingTimeConstant => _analyserNode.smoothingTimeConstant;

  @override
  set smoothingTimeConstant(num value) {
    _analyserNode.smoothingTimeConstant = value;
  }

  @override
  void getByteFrequencyData(Uint8List data) {
    _analyserNode.getByteFrequencyData(data.toJS);
  }
}
