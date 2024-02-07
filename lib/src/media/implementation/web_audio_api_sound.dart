part of stagexl.media;

class WebAudioApiSound extends Sound {
  final AudioBuffer _audioBuffer;

  static final _loaders = <String, XMLHttpRequest>{};

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

  static Future<Sound> _tryAudioUrl(String url, String audioUrl) {

    final completer = Completer<Sound>();

    final request = _loaders[url] = XMLHttpRequest();
    request
      ..onReadyStateChange.listen((_) async {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {

          if (!_loaders.containsKey(url)) {
            completer.completeError('sound already cancelled');
          }

          try {
            final buffer = request.response as ByteBuffer;
            final audioContext = WebAudioApiMixer.audioContext;
            final audioBuffer = await audioContext.decodeAudioData(buffer.toJS).toDart;
            final sound = WebAudioApiSound._(audioBuffer);

            if (!_loaders.containsKey(url)) {
              completer.completeError('sound already cancelled');
            }

            _loaders.remove(url);
            completer.complete(sound);

          } catch (e) {
            if (!completer.isCompleted) completer.completeError('caught error loading $audioUrl');
          }
        }
      })
      ..open('GET', audioUrl, true)
      ..responseType = 'arraybuffer'
      ..send();

    return completer.future;
  }

  static void cancel(String url) {
    if (!_loaders.containsKey(url)) return;

    _loaders[url]?.abort();
    _loaders.remove(url);
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
