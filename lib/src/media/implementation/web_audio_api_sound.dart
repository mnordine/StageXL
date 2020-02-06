part of stagexl.media;

class WebAudioApiSound extends Sound {
  final AudioBuffer _audioBuffer;

  static final _loaders = <String, HttpRequest>{};

  WebAudioApiSound._(AudioBuffer audioBuffer) : _audioBuffer = audioBuffer;

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url,
      [SoundLoadOptions soundLoadOptions]) async {
    var options = soundLoadOptions ?? Sound.defaultLoadOptions;
    var audioUrls = options.getOptimalAudioUrls(url);
    var aggregateError = AggregateError('Error loading sound.');

    for (var audioUrl in audioUrls) {
      try {
        final sound = await _tryAudioUrl(url, audioUrl);
        return sound;
      } catch (e) {
        var loadError = LoadError('Failed to load $audioUrl', e);
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

    final completer = Completer();

    var request = _loaders[url] = HttpRequest();
    request
      ..onReadyStateChange.listen((_) async {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {

          if (!_loaders.containsKey(url)) {
            throw 'sound already cancelled';
          }

          try {
            var buffer = request.response as ByteBuffer;
            var audioContext = WebAudioApiMixer.audioContext;
            var audioBuffer = await audioContext.decodeAudioData(buffer);
            final sound = WebAudioApiSound._(audioBuffer);
            if (!_loaders.containsKey(url)) {
              throw 'sound already cancelled';
            }

            _loaders.remove(url);
            completer.complete(sound);

          } catch (e){
            completer.completeError('caught error loading $audioUrl');
          }
        }
      })
      ..open('GET', audioUrl, async: true)
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
      [SoundLoadOptions soundLoadOptions]) async {
    var options = soundLoadOptions ?? Sound.defaultLoadOptions;
    var audioContext = WebAudioApiMixer.audioContext;
    var start = dataUrl.indexOf(',') + 1;
    var bytes = base64.decoder.convert(dataUrl, start);

    try {
      var audioData = bytes.buffer;
      var audioBuffer = await audioContext.decodeAudioData(audioData);
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
  SoundChannel play([bool loop = false, SoundTransform soundTransform]) {
    return WebAudioApiSoundChannel(this, 0, length, loop, soundTransform);
  }

  @override
  SoundChannel playSegment(num startTime, num duration,
      [bool loop = false, SoundTransform soundTransform]) {
    return WebAudioApiSoundChannel(
        this, startTime, duration, loop, soundTransform);
  }
}
