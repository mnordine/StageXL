part of '../media.dart';

/// The Video class is used to load and control videos.
///
/// The video will be rendered to a RenderTexture and therefore can be
/// used like any other static image content. The sample below creates
/// a BitmapData from the video and also a VideoObject display object.
///
///     var resourceManager = ResourceManager();
///     resourceManager.addVideo("vid1", "video.webm");
///     resourceManager.load().then((_) {
///
///       var video = resourceManager.getVideo("vid1");
///       video.play();
///
///       // create a BitmapData used with a Bitmap
///       var bitmapData = BitmapData.fromVideoElement(video.videoElement);
///       var bitmap = Bitmap(bitmapData);
///       stage.addChild(bitmap);
///
///       // create a convenient VideoObject display object
///       var videoObject = VideoObject(video);
///       stage.addChild(videoObject);
///     });
///
/// Please note that a video can be used with more than one display objects.
/// To control the video independantly from each other the [clone] method
/// creates a clone of this instance.
///
///     video.clone().then((newVideo) => {
///       var videoObject = VideoObject(newVideo);
///       stage.addChild(videoObject);
///     });
///
/// If the video codec of the file is not supported by the browser, the
/// runtime will automatically fallback to a different codec. Therefore
/// please provide the same video with different codecs. The supported
/// codecs are webm, mp4 and ogg.

class Video {
  final HTMLVideoElement videoElement;
  bool loop = false;

  final _endedEvent = StreamController<Video>.broadcast();
  final _pauseEvent = StreamController<Video>.broadcast();
  final _errorEvent = StreamController<Video>.broadcast();
  final _playEvent = StreamController<Video>.broadcast();

  Video._(this.videoElement) {
    videoElement.onEnded.listen(_onEnded);
    videoElement.onPause.listen(_onPause);
    videoElement.onError.listen(_onError);
    videoElement.onPlay.listen(_onPlay);
  }

  Stream<Video> get onEnded => _endedEvent.stream;
  Stream<Video> get onPause => _pauseEvent.stream;
  Stream<Video> get onError => _errorEvent.stream;
  Stream<Video> get onPlay => _playEvent.stream;

  //---------------------------------------------------------------------------

  /// The default video load options are used if no custom video load options
  /// are provided for the [load] method. This default video load options
  /// enable all supported video file formats: mp4, webm and ogg.

  static VideoLoadOptions defaultLoadOptions = VideoLoadOptions();

  /// Use this method to load a video from a given [url]. If you don't
  /// provide [videoLoadOptions] the [defaultLoadOptions] will be used.
  ///
  /// Please note that on most mobile devices the load method must be called
  /// from an input event like MouseEvent or TouchEvent. The load method will
  /// never complete if you call it elsewhere in your code. The same is true
  /// for the ResourceManager.addVideo method.

  static Future<Video> load(String url,
      [VideoLoadOptions? videoLoadOptions, AssetManifest? manifest]) async {
    final options = videoLoadOptions ?? Video.defaultLoadOptions;
    final loadData = options.loadData;
    final corsEnabled = options.corsEnabled;
    final videoUrls = options.getOptimalVideoUrls(url, manifest);
    final videoLoader = VideoLoader(videoUrls, loadData, corsEnabled);
    final videoElement = await videoLoader.done;
    return Video._(videoElement);
  }

  /// Clone this video instance and the underlying HTML VideoElement to play
  /// the video independantly from this video.

  Future<Video> clone() {
    final videoElement = this.videoElement.cloneNode(true) as HTMLVideoElement;
    final completer = Completer<Video>();
    late StreamSubscription<html.Event> onCanPlaySubscription;
    late StreamSubscription<html.Event> onErrorSubscription;

    void onCanPlay(html.Event e) {
      final video = Video._(videoElement);
      video.volume = volume;
      video.muted = muted;
      onCanPlaySubscription.cancel();
      onErrorSubscription.cancel();
      completer.complete(video);
    }

    void onError(html.Event e) {
      onCanPlaySubscription.cancel();
      onErrorSubscription.cancel();
      final error = videoElement.error;
      final loadError = LoadError('Failed to clone video.', error);
      completer.completeError(loadError);
    }

    onCanPlaySubscription = videoElement.onCanPlay.listen(onCanPlay);
    onErrorSubscription = videoElement.onError.listen(onError);
    return completer.future;
  }

  /// Play the video.

  void play() {
    if (!isPlaying) {
      videoElement.play();
    }
  }

  /// Pause the video.

  void pause() {
    if (isPlaying) {
      videoElement.pause();
    }
  }

  /// Returns if the video is playing or not.

  bool get isPlaying => !videoElement.paused;

  /// Get or set if the video is muted.

  bool get muted => videoElement.muted;

  set muted(bool muted) {
    videoElement.muted = muted;
  }

  /// Get or set the volume of the video.

  num get volume => videoElement.volume;

  set volume(num volume) {
    videoElement.volume = volume;
  }

  /// Get or set the current time (playback position) of the video.

  num get currentTime => videoElement.currentTime;

  set currentTime(num value) {
    videoElement.currentTime = value;
  }

  bool get playsInline => videoElement.playsInline;

  set playsInline(bool value) {
    videoElement.playsInline = value;
  }

  bool get controls => videoElement.controls;

  set controls(bool value) {
    videoElement.controls = value;
  }

  //---------------------------------------------------------------------------

  void _onEnded(html.Event event) {
    _endedEvent.add(this);

    // we autoloop manualy to avoid a bug in some browser :
    // http://stackoverflow.com/questions/17930964/
    //
    // for some browser the video should even be served with
    // a 206 result (partial content) and not a simple 200
    // http://stackoverflow.com/a/9549404/1537501

    if (loop) {
      videoElement.currentTime = 0.0;
      videoElement.play();
    } else {
      videoElement.currentTime = 0.0;
      videoElement.pause();
    }
  }

  void _onPause(html.Event event) {
    _pauseEvent.add(this);
  }

  void _onError(html.Event event) {
    _errorEvent.add(this);
  }

  void _onPlay(html.Event event) {
    _playEvent.add(this);
  }
}
