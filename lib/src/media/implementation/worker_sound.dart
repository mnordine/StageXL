part of '../../media.dart';

class WorkerSound extends Sound {
  final int _soundId;
  @override
  final num length;

  WorkerSound._(this._soundId, this.length);

  static Future<Sound> load(
    String url,
    SoundLoadOptions options,
    AssetManifest? manifest,
  ) async {
    final urls = _getAudioUrls(url, options, manifest);
    final result = await SoundMixer._workerAdapter!.load(
      urls,
      ignoreErrors: options.ignoreErrors,
      corsEnabled: options.corsEnabled,
    );
    return WorkerSound._(result.soundId, result.length);
  }

  static Future<Sound> loadDataUrl(String dataUrl, SoundLoadOptions options) async {
    final result = await SoundMixer._workerAdapter!.loadDataUrl(
      dataUrl,
      ignoreErrors: options.ignoreErrors,
    );
    return WorkerSound._(result.soundId, result.length);
  }

  static List<String> _getAudioUrls(
    String primaryUrl,
    SoundLoadOptions options,
    AssetManifest? manifest,
  ) {
    final enabledTypes = {
      if (options.mp3) 'mp3',
      if (options.mp4) 'mp4',
      if (options.ogg) 'ogg',
      if (options.opus) 'opus',
      if (options.ac3) 'ac3',
      if (options.wav) 'wav',
    };
    final extension = RegExp(r'([A-Za-z0-9]+)$');
    final primaryType = extension.firstMatch(primaryUrl)?.group(1)?.toLowerCase();
    if (primaryType == null) return const [];

    final urls = <String>[
      if (enabledTypes.contains(primaryType)) primaryUrl,
      if (options.alternativeUrls case final alternatives?)
        ...alternatives.where((url) {
          final type = extension.firstMatch(url)?.group(1)?.toLowerCase();
          return type != null && enabledTypes.contains(type);
        })
      else
        for (final type in enabledTypes)
          if (type != primaryType) primaryUrl.replaceAll(extension, type),
    ];

    return urls.map((url) => manifest?.mapUrl(url) ?? url).toSet().toList(growable: false);
  }

  @override
  SoundEngine get engine => .Worker;

  @override
  SoundChannel play([bool loop = false, SoundTransform? soundTransform]) =>
      _trackChannel(WorkerSoundChannel(this, 0, length, loop, soundTransform));

  @override
  SoundChannel playSegment(
    num startTime,
    num duration, [
    bool loop = false,
    SoundTransform? soundTransform,
  ]) => _trackChannel(WorkerSoundChannel(this, startTime, duration, loop, soundTransform));
}
