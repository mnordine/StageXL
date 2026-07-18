part of '../media.dart';

class SoundWorkerLoadResult {
  final int soundId;
  final num length;

  const SoundWorkerLoadResult(this.soundId, this.length);
}

class SoundWorkerAnalysisResult {
  final int channelId;
  final num sampleRate;
  final Uint8List? byteFrequencyData;
  final double? frequencyRangeLevel;

  const SoundWorkerAnalysisResult(
    this.channelId,
    this.sampleRate, {
    this.byteFrequencyData,
    this.frequencyRangeLevel,
  });
}

/// Transport implemented by a worker host when audio playback must stay on
/// the browser main thread.
abstract interface class SoundWorkerAdapter {
  List<String> get supportedTypes;

  Stream<int> get onChannelComplete;

  Stream<SoundWorkerAnalysisResult> get onAnalysis;

  Future<SoundWorkerLoadResult> load(
    List<String> urls, {
    required bool ignoreErrors,
    required bool corsEnabled,
  });

  Future<SoundWorkerLoadResult> loadDataUrl(
    String dataUrl, {
    required bool ignoreErrors,
  });

  int play(
    int soundId, {
    required num startTime,
    required num duration,
    required bool loop,
    required SoundTransform soundTransform,
  });

  void setChannelPosition(int channelId, num position);

  void setChannelPaused(int channelId, bool paused);

  void setChannelSoundTransform(int channelId, SoundTransform soundTransform);

  void configureAnalyzer(
    int channelId, {
    required int fftSize,
    required num minDecibels,
    required num maxDecibels,
    required num smoothingTimeConstant,
  });

  void requestByteFrequencyData(int channelId);

  void requestFrequencyRangeLevel(int channelId, num minHz, num maxHz);

  void stopChannel(int channelId);

  void setSoundTransform(SoundTransform soundTransform);

  void unlock();
}
