library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import '../errors.dart';

class AudioLoader {
  static final supportedTypes = _getSupportedTypes();

  final audio = HTMLAudioElement();
  final aggregateError = AggregateError('Error loading sound.');
  final _completer = Completer<HTMLAudioElement>();

  late StreamSubscription<Event> _onCanPlaySubscription;
  late StreamSubscription<Event> _onErrorSubscription;
  final _urls = <String>[];
  var _loadData = false;

  AudioLoader(List<String> urls, bool loadData, bool corsEnabled) {
    // we have to add the AudioElement to the document,
    // otherwise some browser won't start loading :(

    document.body!.appendChild(audio);

    if (corsEnabled) audio.crossOrigin = 'anonymous';

    _urls.addAll(urls);
    _loadData = loadData;
    _onCanPlaySubscription = audio.onCanPlay.listen(_onAudioCanPlay);
    _onErrorSubscription = audio.onError.listen(_onAudioError);
    _loadNextUrl();
  }

  Future<HTMLAudioElement> get done => _completer.future;

  //---------------------------------------------------------------------------

  void _onAudioCanPlay(Event event) {
    _onCanPlaySubscription.cancel();
    _onErrorSubscription.cancel();
    _completer.complete(audio);
  }

  void _onAudioError(Event event) {
    final ae = event.target as HTMLAudioElement;
    final loadError = LoadError('Failed to load ${ae.src}.', ae.error);
    aggregateError.errors.add(loadError);
    _loadNextUrl();
  }

  void _loadNextUrl() {
    if (_urls.isEmpty) {
      _loadFailed();
    } else if (_loadData) {
      _loadAudioData(_urls.removeAt(0));
    } else {
      _loadAudioSource(_urls.removeAt(0));
    }
  }

  void _loadFailed() {
    _onCanPlaySubscription.cancel();
    _onErrorSubscription.cancel();
    if (aggregateError.errors.isEmpty) {
      final loadError = LoadError('No configured audio type is supported.');
      aggregateError.errors.add(loadError);
    }
    _completer.completeError(aggregateError);
  }

  Future<void> _loadAudioData(String url) async {
    try {
      final response = await window.fetch(url.toJS).toDart;

      if (!response.ok) {
        throw LoadError('Failed to load $url. (${response.status} ${response.statusText})');
      }

      final buffer = (await response.arrayBuffer().toDart).toDart;
      final bytes = Uint8List.view(buffer);
      final dataUrl = Uri.dataFromBytes(bytes);

      _loadAudioSource(dataUrl.toString());
    } catch (error) {
      final loadError = error is LoadError
          ? error
          : LoadError('Failed to load $url.', error);
      aggregateError.errors.add(loadError);
      _loadNextUrl();
    }
  }

  void _loadAudioSource(String url) {
    audio.preload = 'auto';
    audio.src = url;
    audio.load();
  }

  //-------------------------------------------------------------------------------------------------

  static List<String> _getSupportedTypes() {
    final audio = HTMLAudioElement();
    final valid = ['maybe', 'probably'];

    final supportedTypes = [
      if (valid.contains(audio.canPlayType('audio/ogg; codecs=opus'))) 'opus',
      if (valid.contains(audio.canPlayType('audio/mpeg'))) 'mp3',
      if (valid.contains(audio.canPlayType('audio/mp4'))) 'mp4',
      if (valid.contains(audio.canPlayType('audio/ogg'))) 'ogg',
      if (valid.contains(audio.canPlayType('audio/ac3'))) 'ac3',
      if (valid.contains(audio.canPlayType('audio/wav'))) 'wav',
    ];

    print('StageXL audio types   : $supportedTypes');

    return supportedTypes.toList(growable: false);
  }
}
