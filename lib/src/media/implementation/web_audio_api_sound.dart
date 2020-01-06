part of stagexl.media;

class WebAudioApiSound extends Sound {

  AudioBuffer _audioBuffer;

  static final _loaders = <String, HttpRequest>{};

  WebAudioApiSound._(AudioBuffer audioBuffer) : _audioBuffer = audioBuffer;

  //---------------------------------------------------------------------------

  static Future<Sound> load(String url, [SoundLoadOptions soundLoadOptions]) {

    var options = soundLoadOptions ?? Sound.defaultLoadOptions;
    var audioUrls = options.getOptimalAudioUrls(url);
    var audioContext = WebAudioApiMixer.audioContext;
    var aggregateError = new AggregateError("Error loading sound.");

    for(var audioUrl in audioUrls) {
      try {

        final completer = new Completer<Sound>();

        var request = _loaders[url] = new HttpRequest();
        request
          ..onReadyStateChange.listen((_) {
            if (request.readyState == HttpRequest.DONE && request.status == 200) {

              if (!_loaders.containsKey(url)) {
                throw 'sound already cancelled';
              }

              var buffer = request.response as ByteBuffer;
              audioContext.decodeAudioData(buffer).then((audioBuffer) {
                if (!_loaders.containsKey(url)) {
                  throw 'sound already cancelled';
                }

                _loaders.remove(url);

                final sound = new WebAudioApiSound._(audioBuffer);
                completer.complete(sound);
              });
            }
          })
          ..open('GET', url, async: true)
          ..responseType = 'arraybuffer'
          ..send();

        return completer.future;
      } catch (e) {
        var loadError = new LoadError("Failed to load $audioUrl", e);
        aggregateError.errors.add(loadError);
      }
    }

    if (options.ignoreErrors) {
      return MockSound.load(url, options);
    } else {
      throw aggregateError;
    }
  }

  static void cancel(String url) {
    if (!_loaders.containsKey(url)) return;

    _loaders[url]?.abort();
    _loaders.remove(url);
  }

  //---------------------------------------------------------------------------

  static Future<Sound> loadDataUrl(
      String dataUrl, [SoundLoadOptions soundLoadOptions]) async {

    var options = soundLoadOptions ?? Sound.defaultLoadOptions;
    var audioContext = WebAudioApiMixer.audioContext;
    var start = dataUrl.indexOf(',') + 1;
    Uint8List bytes = BASE64.decoder.convert(dataUrl, start);

    try {
      var audioData = bytes.buffer;
      var audioBuffer = await audioContext.decodeAudioData(audioData);
      return new WebAudioApiSound._(audioBuffer);
    } catch (e) {
      if (options.ignoreErrors) {
        return MockSound.loadDataUrl(dataUrl, options);
      } else {
        throw new LoadError("Failed to load sound.", e);
      }
    }
  }

  //---------------------------------------------------------------------------

  @override
  SoundEngine get engine => SoundEngine.WebAudioApi;

  @override
  num get length => _audioBuffer.duration;

  @override
  SoundChannel play([
    bool loop = false, SoundTransform soundTransform]) {

    return new WebAudioApiSoundChannel(
        this, 0, this.length, loop, soundTransform);
  }

  @override
  SoundChannel playSegment(num startTime, num duration, [
    bool loop = false, SoundTransform soundTransform]) {

    return new WebAudioApiSoundChannel(
        this, startTime, duration, loop, soundTransform);
  }

}
