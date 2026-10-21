part of '../../media.dart';

class AudioElementSound extends Sound {
  final HTMLAudioElement _audioElement;
  final AudioLoader _loader;
  static final _loaders = <Future<Sound>, AudioLoader>{};
  final Map<HTMLAudioElement, AudioElementSoundChannel?> _soundChannels = {};
  final _pendingElements = <HTMLAudioElement, ({
    Completer<HTMLAudioElement> completer,
    StreamSubscription<html.Event> subscription,
  })>{};
  var _disposed = false;

  AudioElementSound._(HTMLAudioElement audioElement, this._loader)
      : _audioElement = audioElement {
    _audioElement.onEnded.listen(_onAudioEnded);
    _soundChannels[audioElement] = null;
  }

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url,
      [SoundLoadOptions? soundLoadOptions, AssetManifest? manifest]) {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    final audioUrls = options.getOptimalAudioUrls(url, manifest);
    final loader = AudioLoader(audioUrls, false, options.corsEnabled);
    late final Future<Sound> future;
    Future<Sound> complete() async {
      try {
        final element = await loader.done;
        if (loader.cancelled) throw _SoundLoadCancelled(url);
        return AudioElementSound._(element, loader);
      } catch (e) {
        if (loader.cancelled) rethrow;
        if (options.ignoreErrors) return MockSound.load(url, options);
        rethrow;
      } finally {
        _loaders.remove(future);
      }
    }
    future = complete();
    _loaders[future] = loader;
    return future;
  }

  static void cancel(Future<Sound> future) => _loaders.remove(future)?.cancel();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final channel in _soundChannels.values.toList()) {
      channel?.stop();
    }
    for (final element in _soundChannels.keys) {
      element.pause();
      element.removeAttribute('src');
      element.load();
      element.remove();
    }
    _soundChannels.clear();
    for (final entry in _pendingElements.entries) {
      entry.value.subscription.cancel();
      entry.value.completer.complete(entry.key);
    }
    _pendingElements.clear();
    _loader.cancel();
  }

  static Future<Sound> loadDataUrl(String dataUrl,
      [SoundLoadOptions? soundLoadOptions]) async {
    try {
      final audioUrls = <String>[dataUrl];
      final audioLoader = AudioLoader(audioUrls, false, false);
      final audioElement = await audioLoader.done;
      return AudioElementSound._(audioElement, audioLoader);
    } catch (e) {
      final options = soundLoadOptions ?? Sound.defaultLoadOptions;
      if (options.ignoreErrors) {
        return MockSound.loadDataUrl(dataUrl, options);
      } else {
        rethrow;
      }
    }
  }

  //---------------------------------------------------------------------------

  @override
  SoundEngine get engine => .AudioElement;

  @override
  num get length => _audioElement.duration;

  @override
  SoundChannel play([bool loop = false, SoundTransform? soundTransform]) {
    if (_disposed) throw StateError('Cannot play a disposed sound.');
    const startTime = 0.0;
    var duration = _audioElement.duration;
    if (duration.isInfinite) duration = 3600.0;
    return AudioElementSoundChannel(
        this, startTime, duration, loop, soundTransform);
  }

  @override
  SoundChannel playSegment(num startTime, num duration,
          [bool loop = false, SoundTransform? soundTransform]) {
    if (_disposed) throw StateError('Cannot play a disposed sound.');
    return AudioElementSoundChannel(this, startTime, duration, loop, soundTransform);
  }

  //---------------------------------------------------------------------------

  Future<HTMLAudioElement> _requestAudioElement(
      AudioElementSoundChannel soundChannel) async {
    for (final audioElement in _soundChannels.keys) {
      if (_soundChannels[audioElement] == null) {
        _soundChannels[audioElement] = soundChannel;
        return audioElement;
      }
    }

    final audioElement = _audioElement.cloneNode(true) as HTMLAudioElement;
    _soundChannels[audioElement] = soundChannel;
    audioElement.onEnded.listen(_onAudioEnded);
    if (audioElement.readyState != 0) return audioElement;

    final completer = Completer<HTMLAudioElement>();
    late final StreamSubscription<html.Event> subscription;
    subscription = audioElement.onCanPlay.listen((_) {
      subscription.cancel();
      _pendingElements.remove(audioElement);
      completer.complete(audioElement);
    });
    _pendingElements[audioElement] = (completer: completer, subscription: subscription);
    return completer.future;
  }

  void _releaseAudioElement(HTMLAudioElement audioElement) {
    if (!_disposed) _soundChannels[audioElement] = null;
  }

  void _onAudioEnded(html.Event event) {
    final audioElement = event.target;
    if (!audioElement.isA<HTMLAudioElement>()) return;

    _soundChannels[audioElement]?._onAudioEnded();
  }
}
