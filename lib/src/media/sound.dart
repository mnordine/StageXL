part of '../media.dart';

abstract class Sound {
  Sound() {
    SoundMixer._initEngine();
  }

  /// Get a list of the audio types supported by the browser.

  static List<String> get supportedTypes =>
      AudioLoader.supportedTypes.toList(growable: false);

  /// The default loading options for the [Sound.load] method.

  static var defaultLoadOptions = SoundLoadOptions();

  /// Loads a sound from a file url.
  ///
  /// The file extension in the url will be replaced according to the browser's
  /// capability to playback certain kinds of audio types. For example if the
  /// url ends with the 'mp3' extension and the browser does not support mp3
  /// playback, the file extension will be replaced with 'ogg' or 'ac3'. You
  /// can customize this behavior by changing the [soundLoadOptions].
  ///
  ///     var sound = await Sound.load("assets/audio/hello.mp3");
  ///     sound.play();

  static Future<Sound> load(String url, [SoundLoadOptions? soundLoadOptions, AssetManifest? manifest]) {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    return switch (options.engine ?? SoundMixer.engine) {
      .WebAudioApi => WebAudioApiSound.load(url, options, manifest),
      .AudioElement => AudioElementSound.load(url, options, manifest),
      _ => MockSound.load(url, options),
    };
  }

  /// Loads a sound from a data url.
  ///
  /// Please be aware that browsers do support different kinds of audio types.
  /// You can get a list of supported types here: [Sound.supportedTypes]
  ///
  ///     var sound = await Sound.loadDataUrl("data:audio/mpeg;base64,<data>");
  ///     sound.play();

  static Future<Sound> loadDataUrl(String dataUrl,
      [SoundLoadOptions? soundLoadOptions]) {
    final options = soundLoadOptions ?? Sound.defaultLoadOptions;
    return switch (options.engine ?? SoundMixer.engine) {
      .WebAudioApi => WebAudioApiSound.loadDataUrl(dataUrl, options),
      .AudioElement => AudioElementSound.loadDataUrl(dataUrl, options),
      _ => MockSound.loadDataUrl(dataUrl, options),
    };
  }

  //---------------------------------------------------------------------------

  SoundEngine get engine;

  num get length;

  SoundChannel play([bool loop = false, SoundTransform? soundTransform]);

  SoundChannel playSegment(num startTime, num duration,
      [bool loop = false, SoundTransform? soundTransform]);
}
