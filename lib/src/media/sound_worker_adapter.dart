part of '../media.dart';

class SoundWorkerLoadResult {
  final int soundId;
  final num length;

  const SoundWorkerLoadResult(this.soundId, this.length);
}

/// Transport implemented by a worker host when audio playback must stay on
/// the browser main thread.
abstract interface class SoundWorkerAdapter {
  List<String> get supportedTypes;

  Stream<int> get onChannelComplete;

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

  void stopChannel(int channelId);

  void setSoundTransform(SoundTransform soundTransform);

  void unlock();
}
