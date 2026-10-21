part of '../media.dart';

abstract class SoundChannel extends EventDispatcher {
  EventStream<Event> get onComplete => on<Event>(Event.COMPLETE);

  //---------------------------------------------------------------------------

  bool get loop;
  bool get stopped;
  Sound get sound;

  num get position;
  set position(num value);

  bool get paused;
  set paused(bool value);

  SoundTransform get soundTransform;
  set soundTransform(SoundTransform value);

  /// The analyzer previously created by [createSoundAnalyzer], or `null`.
  SoundAnalyzer? get soundAnalyzer => null;

  /// Creates an analyzer for this channel, reusing it on subsequent calls.
  ///
  /// Returns `null` if analysis is unsupported or the channel has stopped.
  /// Creating the analyzer may throw if the browser cannot allocate its buffers.
  SoundAnalyzer? createSoundAnalyzer() => null;

  //---------------------------------------------------------------------------

  void stop();

  void pause() {
    paused = true;
  }

  void resume() {
    paused = false;
  }
}
