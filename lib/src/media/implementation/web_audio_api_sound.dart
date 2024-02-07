part of stagexl.media;

class WebAudioApiSound extends Sound {
  final AudioBuffer _audioBuffer;

  static final _loaders = <String, Future<void>>{};

  WebAudioApiSound._(this._audioBuffer);

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url,
      [SoundLoadOptions? soundLoadOptions]) async {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    final audioUrls = options.getOptimalAudioUrls(url);
    final aggregateError = AggregateError('Error loading sound.');

    for (var audioUrl in audioUrls) {
      try {
        final sound = await _tryAudioUrl(url, audioUrl);
        return sound;
      } catch (e) {
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
    final completer = Completer<Sound>();

    _loaders[key] = http.get(Uri.parse(audioUrl)).then((response) async {
      if (response.statusCode == 200) {

        if (!_loaders.containsKey(key)) {
          completer.completeError('sound already cancelled');
        }

        try {
          final buffer = response.bodyBytes.buffer;
          final audioContext = WebAudioApiMixer.audioContext;
          final audioBuffer = await audioContext.decodeAudioData(buffer.toJS).toDart;
          final sound = WebAudioApiSound._(audioBuffer);

          if (!_loaders.containsKey(key)) {
            completer.completeError('sound already cancelled');
          }

          unawaited(_loaders.remove(key));
          completer.complete(sound);

        } catch (e) {
          if (!completer.isCompleted) completer.completeError('caught error loading $audioUrl');
        }
      }
    });

    return completer.future;
  }

  static void cancel(String key) {
    if (!_loaders.containsKey(key)) return;

    _loaders.remove(key);
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

  //---------------------------------------------------------------------------

  @override
  SoundEngine get engine => SoundEngine.WebAudioApi;

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
