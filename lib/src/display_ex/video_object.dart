part of '../display_ex.dart';

/// The VideoObject class is a display object to show and control videos.
///
/// To show the video just add the VideoObject to the display list. Use
/// the [play] abd [pause] method to control the video.
///
///     var resourceManager = new ResourceManager();
///     resourceManager.addVideo("vid1", "video.webm");
///     resourceManager.load().then((_) {
///       var video = resourceManager.getVideo("vid1");
///       var videoObject = new VideoObject(video);
///       stage.addChild(videoObject);
///       videoObject.play();
///     });
///

class VideoObject extends InteractiveObject {
  static const EventStreamProvider<Event> endedEvent =
      EventStreamProvider<Event>('videoEnded');
  static const EventStreamProvider<Event> pauseEvent =
      EventStreamProvider<Event>('videoPause');
  static const EventStreamProvider<Event> errorEvent =
      EventStreamProvider<Event>('videoError');
  static const EventStreamProvider<Event> playEvent =
      EventStreamProvider<Event>('videoPlay');

  EventStream<Event> get onEnded => VideoObject.endedEvent.forTarget(this);
  EventStream<Event> get onPause => VideoObject.pauseEvent.forTarget(this);
  EventStream<Event> get onError => VideoObject.errorEvent.forTarget(this);
  EventStream<Event> get onPlay => VideoObject.playEvent.forTarget(this);

  final Video _video;
  final RenderTexture _renderTexture;
  late final RenderTextureQuad _renderTextureQuad;

  VideoObject(this._video, [bool autoplay = false])
      : _renderTexture = RenderTexture.fromVideoElement(_video.videoElement) {
    _renderTextureQuad = _renderTexture.quad;

    final videoElement = _video.videoElement;
    videoElement.onEnded.listen((e) => dispatchEvent(Event('videoEnded')));
    videoElement.onPause.listen((e) => dispatchEvent(Event('videoPause')));
    videoElement.onError.listen((e) => dispatchEvent(Event('videoError')));
    videoElement.onPlay.listen((e) => dispatchEvent(Event('videoPlay')));
    videoElement.autoplay = autoplay;

    if (autoplay) play();
  }

  //----------------------------------------------------------------------------

  Video get video => _video;
  RenderTexture get renderTexture => _renderTexture;
  RenderTextureQuad get renderTextureQuad => _renderTextureQuad;

  //----------------------------------------------------------------------------

  @override
  Rectangle<num> get bounds {
    final width = _renderTextureQuad.targetWidth;
    final height = _renderTextureQuad.targetHeight;
    return Rectangle<num>(0.0, 0.0, width, height);
  }

  @override
  void render(RenderState renderState) {
    renderState.renderTextureQuad(_renderTextureQuad);
  }

  @override
  void renderFiltered(RenderState renderState) {
    renderState.renderTextureQuadFiltered(_renderTextureQuad, filters);
  }

  //----------------------------------------------------------------------------

  void play() {
    video.play();
  }

  void pause() {
    video.pause();
  }

  bool get muted => video.muted;

  set muted(bool value) {
    video.muted = value;
  }

  bool get loop => video.loop;

  set loop(bool value) {
    video.loop = value;
  }

  num get volume => video.volume;

  set volume(num value) {
    video.volume = value;
  }

  bool get isPlaying => video.isPlaying;

  bool get playsInline => video.playsInline;

  set playsInline(bool value) {
    video.playsInline = value;
  }

  bool get controls => video.controls;

  set controls(bool value) {
    video.controls = value;
  }
}
