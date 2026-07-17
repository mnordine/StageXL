part of '../../media.dart';

class WorkerSoundChannel extends SoundChannel {
  final WorkerSound _workerSound;
  final num _startTime;
  final num _duration;
  final bool _loop;
  final _stopwatch = Stopwatch()..start();
  late final int _channelId;
  late final StreamSubscription<int> _completeSubscription;
  late SoundTransform _soundTransform;
  num _position = 0;
  var _paused = false;
  var _stopped = false;

  WorkerSoundChannel(
    this._workerSound,
    this._startTime,
    this._duration,
    this._loop, [
    SoundTransform? soundTransform,
  ]) {
    final adapter = SoundMixer._workerAdapter!;
    _soundTransform = soundTransform ?? SoundTransform();
    _channelId = adapter.play(
      _workerSound._soundId,
      startTime: _startTime,
      duration: _duration,
      loop: _loop,
      soundTransform: _soundTransform,
    );
    _completeSubscription = adapter.onChannelComplete
        .where((channelId) => channelId == _channelId)
        .listen((_) => _complete());
  }

  @override
  bool get loop => _loop;

  @override
  bool get stopped => _stopped;

  @override
  Sound get sound => _workerSound;

  @override
  num get position {
    if (_paused || _stopped) return _position;
    final position = _position + _stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    if (_loop && _duration > 0) return position % _duration;
    return position.clamp(0, _duration);
  }

  @override
  set position(num value) {
    if (_stopped) return;
    _position = _loop && _duration > 0 ? value % _duration : value.clamp(0, _duration);
    _stopwatch
      ..reset()
      ..start();
    SoundMixer._workerAdapter!.setChannelPosition(_channelId, _position);
  }

  @override
  bool get paused => _paused;

  @override
  set paused(bool value) {
    if (_stopped || _paused == value) return;
    if (value) {
      _position = position;
      _stopwatch.stop();
    } else {
      _stopwatch
        ..reset()
        ..start();
    }
    _paused = value;
    SoundMixer._workerAdapter!.setChannelPaused(_channelId, value);
  }

  @override
  SoundTransform get soundTransform => _soundTransform;

  @override
  set soundTransform(SoundTransform value) {
    _soundTransform = value;
    if (!_stopped) SoundMixer._workerAdapter!.setChannelSoundTransform(_channelId, value);
  }

  @override
  void stop() {
    if (_stopped) return;
    _position = position;
    SoundMixer._workerAdapter!.stopChannel(_channelId);
    _complete();
  }

  void _complete() {
    if (_stopped) return;
    _stopped = true;
    _paused = true;
    _stopwatch.stop();
    unawaited(_completeSubscription.cancel());
    dispatchEvent(Event(Event.COMPLETE));
  }
}
