library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import '../errors.dart';

class VideoLoader {
  static final List<String> supportedTypes = _getSupportedTypes();

  final video = HTMLVideoElement();
  final aggregateError = AggregateError('Error loading video.');
  final _completer = Completer<HTMLVideoElement>();

  late StreamSubscription<Event> _onCanPlaySubscription;
  late StreamSubscription<Event> _onErrorSubscription;
  final _urls = <String>[];
  var _loadData = false;
  String? _activeObjectUrl;
  final _abortController = AbortController();
  var _cancelled = false;
  var _references = 1;

  VideoLoader(List<String> urls, bool loadData, bool corsEnabled) {
    if (corsEnabled) video.crossOrigin = 'anonymous';

    _onCanPlaySubscription = video.onCanPlay.listen(_onVideoCanPlay);
    _onErrorSubscription = video.onError.listen(_onVideoError);

    _urls.addAll(urls);
    _loadData = loadData;
    _loadNextUrl();
  }

  Future<HTMLVideoElement> get done => _completer.future;

  bool get cancelled => _cancelled;

  void retain() => _references++;

  void release() {
    if (--_references == 0) cancel();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abortController.abort();
    _onCanPlaySubscription.cancel();
    _onErrorSubscription.cancel();
    video.pause();
    video.removeAttribute('src');
    video.load();
    _revokeActiveObjectUrl();
    if (!_completer.isCompleted) _completer.completeError(LoadError('Video load cancelled.'));
  }

  //---------------------------------------------------------------------------

  void _onVideoCanPlay(Event event) {
    _onCanPlaySubscription.cancel();
    _onErrorSubscription.cancel();
    _completer.complete(video);
  }

  void _onVideoError(Event event) {
    final ve = event.target as HTMLVideoElement;
    final loadError = LoadError('Failed to load ${ve.src}.', ve.error);
    aggregateError.errors.add(loadError);
    _loadNextUrl();
  }

  void _loadNextUrl() {
    if (_cancelled) return;
    _revokeActiveObjectUrl();
    if (_urls.isEmpty) {
      _loadFailed();
    } else if (_loadData) {
      _loadVideoData(_urls.removeAt(0));
    } else {
      _loadVideoSource(_urls.removeAt(0));
    }
  }

  void _loadFailed() {
    _onCanPlaySubscription.cancel();
    _onErrorSubscription.cancel();
    _revokeActiveObjectUrl();
    if (aggregateError.errors.isEmpty) {
      final loadError = LoadError('No configured video type is supported.');
      aggregateError.errors.add(loadError);
    }
    _completer.completeError(aggregateError);
  }

  Future<void> _loadVideoData(String url) async {
    try {
      final response = await window.fetch(url.toJS, RequestInit(signal: _abortController.signal)).toDart;
      if (_cancelled) return;

      if (!response.ok) {
        throw LoadError('Failed to load $url. (${response.status} ${response.statusText})');
      }

      final blob = await response.blob().toDart;
      if (_cancelled) return;
      final objectUrl = URL.createObjectURL(blob);
      _setVideoSource(objectUrl);
    } catch (error) {
      if (_cancelled) return;
      final loadError = error is LoadError
          ? error
          : LoadError('Failed to load $url.', error);
      aggregateError.errors.add(loadError);
      _loadNextUrl();
    }
  }

  void _loadVideoSource(String url) {
    _revokeActiveObjectUrl();
    video.preload = 'auto';
    video.src = url;
    video.load();
  }

  void _setVideoSource(String objectUrl) {
    _revokeActiveObjectUrl();
    _activeObjectUrl = objectUrl;
    video.preload = 'auto';
    video.src = objectUrl;
    video.load();
  }

  void _revokeActiveObjectUrl() {
    final url = _activeObjectUrl;
    if (url != null) {
      URL.revokeObjectURL(url);
      _activeObjectUrl = null;
    }
  }

  //---------------------------------------------------------------------------

  static List<String> _getSupportedTypes() {
    final supportedTypes = <String>[];
    final video = HTMLVideoElement();
    final valid = ['maybe', 'probably'];

    if (valid.contains(video.canPlayType('video/webm'))) {
      supportedTypes.add('webm');
    }
    if (valid.contains(video.canPlayType('video/mp4'))) {
      supportedTypes.add('mp4');
    }
    if (valid.contains(video.canPlayType('video/ogg'))) {
      supportedTypes.add('ogg');
    }

    print('StageXL video types   : $supportedTypes');
    return supportedTypes.toList(growable: false);
  }
}
