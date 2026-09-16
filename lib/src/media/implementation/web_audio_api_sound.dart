part of '../../media.dart';

class _LoadTask {
  _LoadTask(this.controller, this.completer);

  final AbortController controller;
  final Completer<Sound> completer;
}

class _SoundLoadCancelled extends LoadError {
  _SoundLoadCancelled(String url) : super('Sound load cancelled: $url');
}

class WebAudioApiSound extends Sound {
  final AudioBuffer _audioBuffer;
  late final _loopAudioBuffers = <num, AudioBuffer>{};

  static final _needsLoopGuard = needsWebAudioLoopGuard(window.navigator.userAgent);
  static final _loaders = <String, _LoadTask>{};

  WebAudioApiSound._(this._audioBuffer);

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url,
      [SoundLoadOptions? soundLoadOptions, AssetManifest? manifest]) async {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    final audioUrls = options.getOptimalAudioUrls(url, manifest);
    final aggregateError = AggregateError('Error loading sound.');

    for (final audioUrl in audioUrls) {
      try {
        final sound = await _tryAudioUrl(url, audioUrl);
        return sound;
      } catch (e) {
        if (e is _SoundLoadCancelled) rethrow;
        final loadError = LoadError('Failed to load $audioUrl', e);
        aggregateError.errors.add(loadError);
      }
    }

    if (options.ignoreErrors) {
      return MockSound.load(url, options);
    } else {
      throw aggregateError;
    }
  }

  static Future<Sound> _tryAudioUrl(String key, String audioUrl) {
    cancel(key);
    final completer = Completer<Sound>();
    final controller = AbortController();
    final task = _LoadTask(controller, completer);
    _loaders[key] = task;

    Future<void> load() async {
      try {
        final response = await window.fetch(audioUrl.toJS, RequestInit(signal: controller.signal)).toDart;

        if (!identical(_loaders[key], task)) {
          // Load cancelled or superseded.
          return;
        }

        if (!response.ok) {
          throw LoadError('Failed to load $audioUrl. (${response.status} ${response.statusText})');
        }

        final audioData = await response.arrayBuffer().toDart;

        if (!identical(_loaders[key], task)) {
          return;
        }

        final audioContext = WebAudioApiMixer.audioContext;
        final audioBuffer = await audioContext.decodeAudioData(audioData).toDart;

        if (!identical(_loaders[key], task)) return;
        final currentTask = _loaders.remove(key);
        if (currentTask == null || currentTask.completer.isCompleted) {
          return;
        }

        currentTask.completer.complete(WebAudioApiSound._(audioBuffer));
      } catch (error, stackTrace) {
        if (!identical(_loaders[key], task)) return;
        final currentTask = _loaders.remove(key);
        if (currentTask == null || currentTask.completer.isCompleted) {
          return;
        }

        final loadError = error is LoadError
            ? error
            : LoadError('Failed to load $audioUrl.', error);
        currentTask.completer.completeError(loadError, stackTrace);
      }
    }

    load();

    return completer.future;
  }

  static void cancel(String key) {
    final task = _loaders.remove(key);
    if (task == null) {
      return;
    }

    task.controller.abort();
    if (!task.completer.isCompleted) {
      task.completer.completeError(_SoundLoadCancelled(key));
    }
  }

  //---------------------------------------------------------------------------

  static Future<Sound> loadDataUrl(String dataUrl,
      [SoundLoadOptions? soundLoadOptions]) async {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    final audioContext = WebAudioApiMixer.audioContext;
    final start = dataUrl.indexOf(',') + 1;
    final bytes = base64.decoder.convert(dataUrl, start);

    try {
      final audioData = bytes.buffer;
      final audioBuffer = await audioContext.decodeAudioData(audioData.toJS).toDart;
      return WebAudioApiSound._(audioBuffer);
    } catch (e) {
      if (options.ignoreErrors) {
        return MockSound.loadDataUrl(dataUrl, options);
      } else {
        throw LoadError('Failed to load sound.', e);
      }
    }
  }

  // Chromium 152 can repeat its last render quantum when a loop reaches the
  // end of the backing buffer. Keep a guard frame outside the original loop
  // points so playback wraps without changing the sound's duration or samples.
  // Repeat the first sample in the guard for interpolation at fractional ends.
  AudioBuffer _getLoopAudioBuffer(num startTime, num duration) {
    if (!_needsLoopGuard || startTime + duration < length) return _audioBuffer;
    return _loopAudioBuffers.putIfAbsent(startTime, () => _createLoopAudioBuffer(startTime));
  }

  AudioBuffer _createLoopAudioBuffer(num startTime) {
    final source = _audioBuffer;
    final buffer = WebAudioApiMixer.audioContext.createBuffer(
        source.numberOfChannels, source.length + 1, source.sampleRate);
    final startFrame = (startTime * source.sampleRate).clamp(0, source.length - 1);
    final first = startFrame.floor();
    final fraction = startFrame - first;
    for (var channel = 0; channel < source.numberOfChannels; channel++) {
      final samples = source.getChannelData(channel);
      final values = samples.toDart;
      buffer.copyToChannel(samples, channel);
      buffer.getChannelData(channel).toDart[source.length] =
          values[first] * (1 - fraction) + values[(first + 1) % source.length] * fraction;
    }
    return buffer;
  }

  //---------------------------------------------------------------------------

  @override
  SoundEngine get engine => .WebAudioApi;

  @override
  num get length => _audioBuffer.duration;

  @override
  SoundChannel play([bool loop = false, SoundTransform? soundTransform]) =>
      WebAudioApiSoundChannel(this, 0, length, loop, soundTransform);

  @override
  SoundChannel playSegment(num startTime, num duration,
          [bool loop = false, SoundTransform? soundTransform]) =>
      WebAudioApiSoundChannel(this, startTime, duration, loop, soundTransform);
}
