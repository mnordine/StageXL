part of '../../media.dart';

class _LoadTask {
  _LoadTask(this.url, this.controller, this.completer);

  final String url;

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
  static final _loaders = <String, Set<_LoadTask>>{};
  static final _pendingLoads = <Future<Sound>, _LoadTask>{};

  WebAudioApiSound._(this._audioBuffer);

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url,
      [SoundLoadOptions? soundLoadOptions, AssetManifest? manifest]) {
    final task = _LoadTask(url, AbortController(), Completer<Sound>());
    final future = task.completer.future;
    _loaders.putIfAbsent(url, () => <_LoadTask>{}).add(task);
    _pendingLoads[future] = task;
    unawaited(_load(task, soundLoadOptions ?? Sound.defaultLoadOptions, manifest));
    return future;
  }

  static Future<void> _load(_LoadTask task, SoundLoadOptions options, AssetManifest? manifest) async {
    final aggregateError = AggregateError('Error loading sound.');
    try {
      for (final audioUrl in options.getOptimalAudioUrls(task.url, manifest)) {
        try {
          final sound = await _tryAudioUrl(task, audioUrl);
          if (!task.completer.isCompleted) task.completer.complete(sound);
          return;
        } catch (error) {
          if (task.completer.isCompleted) return;
          aggregateError.errors.add(LoadError('Failed to load $audioUrl', error));
        }
      }
      if (options.ignoreErrors) {
        final sound = await MockSound.load(task.url, options);
        if (!task.completer.isCompleted) task.completer.complete(sound);
      } else {
        task.completer.completeError(aggregateError);
      }
    } catch (error, stackTrace) {
      if (!task.completer.isCompleted) task.completer.completeError(error, stackTrace);
    } finally {
      _removeTask(task);
    }
  }

  static Future<Sound> _tryAudioUrl(_LoadTask task, String audioUrl) async {
    final response = await window.fetch(audioUrl.toJS, RequestInit(signal: task.controller.signal)).toDart;
    if (task.controller.signal.aborted) throw _SoundLoadCancelled(task.url);
    if (!response.ok) {
      throw LoadError('Failed to load $audioUrl. (${response.status} ${response.statusText})');
    }
    final audioData = await response.arrayBuffer().toDart;
    if (task.controller.signal.aborted) throw _SoundLoadCancelled(task.url);
    final audioBuffer = await WebAudioApiMixer.audioContext.decodeAudioData(audioData).toDart;
    if (task.controller.signal.aborted) throw _SoundLoadCancelled(task.url);
    return WebAudioApiSound._(audioBuffer);
  }

  static void cancel(String key) {
    for (final task in _loaders[key]?.toList() ?? <_LoadTask>[]) {
      _cancelTask(task);
    }
  }

  static void cancelLoad(Future<Sound> future) {
    final task = _pendingLoads[future];
    if (task != null) _cancelTask(task);
  }

  static void _cancelTask(_LoadTask task) {
    _removeTask(task);
    task.controller.abort();
    if (!task.completer.isCompleted) task.completer.completeError(_SoundLoadCancelled(task.url));
  }

  static void _removeTask(_LoadTask task) {
    _pendingLoads.remove(task.completer.future);
    final tasks = _loaders[task.url];
    tasks?.remove(task);
    if (tasks != null && tasks.isEmpty) _loaders.remove(task.url);
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
