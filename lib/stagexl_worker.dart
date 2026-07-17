/// Browser Web Worker support for StageXL.
///
/// Import this library from both the main host entry point and the worker
/// entry point. The normal `package:stagexl/stagexl.dart` API remains the
/// entry point for main-thread-only applications.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart' as web;

@JS('self')
external web.DedicatedWorkerGlobalScope get _workerScope;

extension type _StageXLWorkerMessage(JSObject _) implements JSObject {
  external String get kind;
  external web.OffscreenCanvas get canvas;
  external int get left;
  external int get top;
  external int get width;
  external int get height;
  external double get devicePixelRatio;
  external String get source;
  external String get eventType;
  external double get clientX;
  external double get clientY;
  external int get button;
  external double get deltaX;
  external double get deltaY;
  external int get identifier;
  external int get keyCode;
  external int get charCode;
  external int get keyLocation;
  external bool get altKey;
  external bool get ctrlKey;
  external bool get shiftKey;
  external bool get audioEnabled;
  external String get error;
  external String get stackTrace;
  external JSAny? get audioTypes;
  external JSAny? get data;
}

class StageWorkerException implements Exception {
  final String message;
  final String? workerStackTrace;

  const StageWorkerException(this.message, [this.workerStackTrace]);

  @override
  String toString() => workerStackTrace == null
      ? 'StageWorkerException: $message'
      : 'StageWorkerException: $message\n$workerStackTrace';
}

/// Main-thread behavior for a StageXL worker canvas.
class StageWorkerClientOptions {
  final InputEventMode inputEventMode;
  final bool preventDefaultOnMouse;
  final bool preventDefaultOnTouch;
  final bool preventDefaultOnWheel;
  final bool preventDefaultOnKeyboard;
  final bool emulateMouseFromTouch;
  final bool enableAudio;
  final web.WorkerOptions? workerOptions;
  final Object? initialData;

  const StageWorkerClientOptions({
    this.inputEventMode = .MouseOnly,
    this.preventDefaultOnMouse = true,
    this.preventDefaultOnTouch = true,
    this.preventDefaultOnWheel = false,
    this.preventDefaultOnKeyboard = false,
    this.emulateMouseFromTouch = false,
    this.enableAudio = true,
    this.workerOptions,
    this.initialData,
  });
}

/// Owns the DOM-only half of a StageXL worker application.
///
/// The client transfers [canvas] to a dedicated worker, observes its CSS
/// viewport, and forwards input. It does not mirror or serialize the StageXL
/// display list.
class StageWorkerClient {
  final web.HTMLCanvasElement canvas;
  final web.Worker worker;
  final StageWorkerClientOptions options;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _messageController = StreamController<JSAny?>.broadcast(sync: true);
  final _errorController = StreamController<Object>.broadcast(sync: true);
  final _readyCompleter = Completer<void>();
  late final web.ResizeObserver _resizeObserver;
  late final JSFunction _scrollListener;
  late final _StageWorkerAudioHost? _audioHost;
  var _disposed = false;

  StageWorkerClient(
    this.canvas,
    String workerUrl, {
    this.options = const StageWorkerClientOptions(),
  }) : worker = options.workerOptions == null
           ? web.Worker(workerUrl.toJS)
           : web.Worker(workerUrl.toJS, options.workerOptions!) {
    _audioHost = options.enableAudio ? _StageWorkerAudioHost(worker) : null;
    worker.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data != null && data.isA<JSObject>()) {
        final object = data as JSObject;
        if (object.has('kind')) {
          final message = _StageXLWorkerMessage(object);
          if (message.kind == 'stagexl:audio') {
            _audioHost?._handleMessage(message.data.dartify());
            return;
          }
          if (message.kind == 'stagexl:cursor') canvas.style.cursor = message.eventType;
          if (message.kind == 'stagexl:focus') canvas.focus();
          if (message.kind == 'stagexl:ready' && !_readyCompleter.isCompleted) {
            _readyCompleter.complete();
          }
          if (message.kind == 'stagexl:error') {
            final error = StageWorkerException(message.error, message.stackTrace);
            _errorController.add(error);
            if (!_readyCompleter.isCompleted) _readyCompleter.completeError(error);
          }
        }
      }
      _messageController.add(data);
    }).toJS;
    worker.onerror = _handleWorkerError.toJS;
    worker.onmessageerror = _handleWorkerError.toJS;

    final offscreenCanvas = canvas.transferControlToOffscreen();
    _postInit(offscreenCanvas);
    _attachEvents();

    _resizeObserver = web.ResizeObserver(((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver _) {
      _postViewport();
    }).toJS)..observe(canvas);
    _scrollListener = ((web.Event _) => _postViewport()).toJS;
    web.window.addEventListener('scroll', _scrollListener);
  }

  /// Messages posted by the worker application, including StageXL lifecycle
  /// messages. This can also carry application-defined structured-clone data.
  Stream<JSAny?> get onMessage => _messageController.stream;

  Stream<Object> get onError => _errorController.stream;

  /// Completes after the worker callback has created the application runtime.
  Future<void> get ready => _readyCompleter.future;

  /// Posts application-defined structured-clone data to the worker.
  void postMessage(Object? message) => worker.postMessage(message.jsify());

  void _handleWorkerError(web.Event event) {
    final error = event.isA<web.ErrorEvent>()
        ? StageWorkerException((event as web.ErrorEvent).message)
        : const StageWorkerException('Worker message could not be deserialized.');
    _errorController.add(error);
    if (!_readyCompleter.isCompleted) _readyCompleter.completeError(error);
  }

  void _postInit(web.OffscreenCanvas offscreenCanvas) {
    final viewport = _viewportMessage('stagexl:init');
    viewport['canvas'] = offscreenCanvas;
    viewport['data'] = options.initialData;
    viewport['audioEnabled'] = options.enableAudio;
    viewport['audioTypes'] = options.enableAudio ? Sound.supportedTypes : const <String>[];
    worker.postMessage(viewport.jsify(), [offscreenCanvas].toJS);
  }

  Map<String, Object?> _viewportMessage(String kind) {
    final rectangle = canvas.getBoundingClientRect();
    return {
      'kind': kind,
      'left': canvas.clientLeft + rectangle.left.round(),
      'top': canvas.clientTop + rectangle.top.round(),
      'width': canvas.clientWidth,
      'height': canvas.clientHeight,
      'devicePixelRatio': web.window.devicePixelRatio,
    };
  }

  void _postViewport() {
    if (!_disposed) worker.postMessage(_viewportMessage('stagexl:viewport').jsify());
  }

  void _attachEvents() {
    if (canvas.tabIndex <= 0) canvas.tabIndex = 1;
    if (canvas.style.outline == '') canvas.style.outline = 'none';

    final mouseEnabled = options.inputEventMode == .MouseOnly || options.inputEventMode == .MouseAndTouch;
    if (mouseEnabled) {
      _listen(canvas.onMouseDown, _postMouseEvent);
      _listen(canvas.onMouseUp, _postMouseEvent);
      _listen(canvas.onMouseMove, _postMouseEvent);
      _listen(canvas.onMouseOut, _postMouseEvent);
      _listen(canvas.onContextMenu, _postMouseEvent);
      _listen(canvas.onMouseWheel, _postWheelEvent);
    }

    final touchEnabled = options.inputEventMode == .TouchOnly || options.inputEventMode == .MouseAndTouch;
    if (touchEnabled) {
      _listen(canvas.onTouchStart, _postTouchEvent);
      _listen(canvas.onTouchEnd, _postTouchEvent);
      _listen(canvas.onTouchMove, _postTouchEvent);
      _listen(canvas.onTouchCancel, _postTouchEvent);
    }

    _listen(canvas.onKeyDown, _postKeyboardEvent);
    _listen(canvas.onKeyUp, _postKeyboardEvent);
    _listen(canvas.onKeyPress, _postKeyboardEvent);
  }

  void _postMouseEvent(web.MouseEvent event) {
    if (options.preventDefaultOnMouse) event.preventDefault();
    if (event.type == 'mousedown') {
      canvas.focus();
      if (options.enableAudio) SoundMixer.unlockMobileAudio();
    }
    worker.postMessage({
      'kind': 'stagexl:input',
      'source': 'mouse',
      'eventType': event.type,
      'clientX': event.clientX,
      'clientY': event.clientY,
      'button': event.button,
      'deltaX': 0,
      'deltaY': 0,
      'altKey': event.altKey,
      'ctrlKey': event.ctrlKey,
      'shiftKey': event.shiftKey,
    }.jsify());
  }

  void _postWheelEvent(web.WheelEvent event) {
    if (options.preventDefaultOnWheel) event.preventDefault();
    worker.postMessage({
      'kind': 'stagexl:input',
      'source': 'mouse',
      'eventType': 'wheel',
      'clientX': event.clientX,
      'clientY': event.clientY,
      'button': 0,
      'deltaX': event.deltaX,
      'deltaY': event.deltaY,
      'altKey': event.altKey,
      'ctrlKey': event.ctrlKey,
      'shiftKey': event.shiftKey,
    }.jsify());
  }

  void _postTouchEvent(web.TouchEvent event) {
    if (options.preventDefaultOnTouch) event.preventDefault();
    if (event.type == 'touchstart' && options.enableAudio) SoundMixer.unlockMobileAudio();
    final touches = event.changedTouches;
    for (var i = 0; i < touches.length; i++) {
      final touch = touches.item(i);
      if (touch == null) continue;
      if (options.emulateMouseFromTouch) {
        worker.postMessage({
          'kind': 'stagexl:input',
          'source': 'mouse',
          'eventType': switch (event.type) {
            'touchstart' => 'mousedown',
            'touchend' || 'touchcancel' => 'mouseup',
            _ => 'mousemove',
          },
          'clientX': touch.clientX,
          'clientY': touch.clientY,
          'button': 0,
          'deltaX': 0,
          'deltaY': 0,
          'altKey': event.altKey,
          'ctrlKey': event.ctrlKey,
          'shiftKey': event.shiftKey,
        }.jsify());
        continue;
      }
      worker.postMessage({
        'kind': 'stagexl:input',
        'source': 'touch',
        'eventType': event.type,
        'identifier': touch.identifier,
        'clientX': touch.clientX,
        'clientY': touch.clientY,
        'altKey': event.altKey,
        'ctrlKey': event.ctrlKey,
        'shiftKey': event.shiftKey,
      }.jsify());
    }
  }

  void _postKeyboardEvent(web.KeyboardEvent event) {
    if (options.preventDefaultOnKeyboard) event.preventDefault();
    if (event.type == 'keydown' && options.enableAudio) SoundMixer.unlockMobileAudio();
    final keyLocation = switch (event.location) {
      web.KeyLocation.LEFT => stagexlKeyLocationLeft,
      web.KeyLocation.RIGHT => stagexlKeyLocationRight,
      web.KeyLocation.NUMPAD => stagexlKeyLocationNumPad,
      web.KeyLocation.JOYSTICK || web.KeyLocation.MOBILE => stagexlKeyLocationDPad,
      _ => stagexlKeyLocationStandard,
    };
    worker.postMessage({
      'kind': 'stagexl:input',
      'source': 'keyboard',
      'eventType': event.type,
      'keyCode': event.keyCode,
      'charCode': event.charCode,
      'keyLocation': keyLocation,
      'altKey': event.altKey,
      'ctrlKey': event.ctrlKey,
      'shiftKey': event.shiftKey,
    }.jsify());
  }

  void _listen<T extends Object?>(Stream<T> stream, void Function(T) onData) {
    _subscriptions.add(stream.listen(onData));
  }

  /// Stops event forwarding and terminates the dedicated worker.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resizeObserver.disconnect();
    web.window.removeEventListener('scroll', _scrollListener);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _audioHost?.dispose();
    worker.terminate();
    unawaited(_messageController.close());
    unawaited(_errorController.close());
  }
}

class _StageWorkerAudioHost {
  final web.Worker _worker;
  final _sounds = <int, Sound>{};
  final _channels = <int, SoundChannel>{};
  var _nextSoundId = 1;

  _StageWorkerAudioHost(this._worker);

  void _handleMessage(Object? rawData) {
    if (rawData is! Map<Object?, Object?>) return;
    final data = rawData;
    switch (data['command']) {
      case 'load':
        unawaited(_load(data));
      case 'loadDataUrl':
        unawaited(_loadDataUrl(data));
      case 'play':
        _play(data);
      case 'position':
        _channels[data['channelId']]?.position = data['position']! as num;
      case 'paused':
        _channels[data['channelId']]?.paused = data['paused']! as bool;
      case 'channelTransform':
        _channels[data['channelId']]?.soundTransform = _soundTransform(data);
      case 'stop':
        _channels[data['channelId']]?.stop();
      case 'mixerTransform':
        SoundMixer.soundTransform = _soundTransform(data);
      case 'unlock':
        SoundMixer.unlockMobileAudio();
    }
  }

  Future<void> _load(Map<Object?, Object?> data) async {
    final requestId = data['requestId']! as int;
    try {
      final urls = (data['urls']! as List).cast<String>();
      final options = SoundLoadOptions()
        ..opus = true
        ..alternativeUrls = urls.skip(1).toList(growable: false)
        ..ignoreErrors = data['ignoreErrors']! as bool
        ..corsEnabled = data['corsEnabled']! as bool;
      final sound = await Sound.load(urls.firstOrNull ?? '', options);
      _completeLoad(requestId, sound);
    } catch (error) {
      _post({'command': 'loadError', 'requestId': requestId, 'error': '$error'});
    }
  }

  Future<void> _loadDataUrl(Map<Object?, Object?> data) async {
    final requestId = data['requestId']! as int;
    try {
      final options = SoundLoadOptions()..ignoreErrors = data['ignoreErrors']! as bool;
      final sound = await Sound.loadDataUrl(data['dataUrl']! as String, options);
      _completeLoad(requestId, sound);
    } catch (error) {
      _post({'command': 'loadError', 'requestId': requestId, 'error': '$error'});
    }
  }

  void _completeLoad(int requestId, Sound sound) {
    final soundId = _nextSoundId++;
    _sounds[soundId] = sound;
    _post({
      'command': 'loaded',
      'requestId': requestId,
      'soundId': soundId,
      'length': sound.length,
    });
  }

  void _play(Map<Object?, Object?> data) {
    final channelId = data['channelId']! as int;
    final sound = _sounds[data['soundId']];
    if (sound == null) {
      _post({'command': 'complete', 'channelId': channelId});
      return;
    }

    final channel = sound.playSegment(
      data['startTime']! as num,
      data['duration']! as num,
      data['loop']! as bool,
      _soundTransform(data),
    );
    _channels[channelId] = channel;
    channel.onComplete.first.then((_) {
      if (_channels.remove(channelId) != null) {
        _post({'command': 'complete', 'channelId': channelId});
      }
    });
  }

  SoundTransform _soundTransform(Map<Object?, Object?> data) =>
      SoundTransform(data['volume']! as num, data['pan']! as num);

  void _post(Map<String, Object?> data) =>
      _worker.postMessage({'kind': 'stagexl:audio', 'data': data}.jsify());

  void dispose() {
    for (final channel in _channels.values.toList(growable: false)) {
      channel.stop();
    }
    _channels.clear();
    _sounds.clear();
  }
}

class _StageWorkerAudioAdapter implements SoundWorkerAdapter {
  @override
  final List<String> supportedTypes;
  final _completeController = StreamController<int>.broadcast(sync: true);
  final _loadCompleters = <int, Completer<SoundWorkerLoadResult>>{};
  var _nextRequestId = 1;
  var _nextChannelId = 1;

  _StageWorkerAudioAdapter(List<String> supportedTypes)
      : supportedTypes = supportedTypes.toList(growable: false);

  @override
  Stream<int> get onChannelComplete => _completeController.stream;

  @override
  Future<SoundWorkerLoadResult> load(
    List<String> urls, {
    required bool ignoreErrors,
    required bool corsEnabled,
  }) => _request({
    'command': 'load',
    'urls': urls,
    'ignoreErrors': ignoreErrors,
    'corsEnabled': corsEnabled,
  });

  @override
  Future<SoundWorkerLoadResult> loadDataUrl(
    String dataUrl, {
    required bool ignoreErrors,
  }) => _request({
    'command': 'loadDataUrl',
    'dataUrl': dataUrl,
    'ignoreErrors': ignoreErrors,
  });

  Future<SoundWorkerLoadResult> _request(Map<String, Object?> data) {
    final requestId = _nextRequestId++;
    final completer = Completer<SoundWorkerLoadResult>();
    _loadCompleters[requestId] = completer;
    _post({...data, 'requestId': requestId});
    return completer.future;
  }

  @override
  int play(
    int soundId, {
    required num startTime,
    required num duration,
    required bool loop,
    required SoundTransform soundTransform,
  }) {
    final channelId = _nextChannelId++;
    _post({
      'command': 'play',
      'soundId': soundId,
      'channelId': channelId,
      'startTime': startTime,
      'duration': duration,
      'loop': loop,
      ..._transformData(soundTransform),
    });
    return channelId;
  }

  @override
  void setChannelPosition(int channelId, num position) =>
      _post({'command': 'position', 'channelId': channelId, 'position': position});

  @override
  void setChannelPaused(int channelId, bool paused) =>
      _post({'command': 'paused', 'channelId': channelId, 'paused': paused});

  @override
  void setChannelSoundTransform(int channelId, SoundTransform soundTransform) => _post({
    'command': 'channelTransform',
    'channelId': channelId,
    ..._transformData(soundTransform),
  });

  @override
  void stopChannel(int channelId) => _post({'command': 'stop', 'channelId': channelId});

  @override
  void setSoundTransform(SoundTransform soundTransform) => _post({
    'command': 'mixerTransform',
    ..._transformData(soundTransform),
  });

  @override
  void unlock() => _post({'command': 'unlock'});

  void _handleMessage(Object? rawData) {
    if (rawData is! Map<Object?, Object?>) return;
    final data = rawData;
    switch (data['command']) {
      case 'loaded':
        final requestId = data['requestId']! as int;
        _loadCompleters.remove(requestId)?.complete(
          SoundWorkerLoadResult(data['soundId']! as int, data['length']! as num),
        );
      case 'loadError':
        final requestId = data['requestId']! as int;
        _loadCompleters.remove(requestId)?.completeError(
          StateError(data['error']! as String),
        );
      case 'complete':
        _completeController.add(data['channelId']! as int);
    }
  }

  Map<String, Object?> _transformData(SoundTransform transform) => {
    'volume': transform.volume,
    'pan': transform.pan,
  };

  void _post(Map<String, Object?> data) =>
      _workerScope.postMessage({'kind': 'stagexl:audio', 'data': data}.jsify());
}

const stagexlKeyLocationStandard = 0;
const stagexlKeyLocationLeft = 1;
const stagexlKeyLocationRight = 2;
const stagexlKeyLocationNumPad = 3;
const stagexlKeyLocationDPad = 4;

/// Worker-side Stage host backed by a transferred [OffscreenCanvas].
class StageWorkerHost implements StageHost {
  final web.OffscreenCanvas canvas;
  final Object? initialData;
  @override
  final num devicePixelRatio;
  StageViewport _viewport;
  Stage? _stage;
  final _messageController = StreamController<Object?>.broadcast(sync: true);
  _StageWorkerAudioAdapter? _audioAdapter;

  StageWorkerHost._(
    this.canvas, {
    required this.devicePixelRatio,
    required this._viewport,
    required this.initialData,
    required bool audioEnabled,
    required List<String> audioTypes,
  }) {
    if (audioEnabled) {
      _audioAdapter = _StageWorkerAudioAdapter(audioTypes);
      SoundMixer.useWorkerAdapter(_audioAdapter!);
    }
  }

  @override
  RenderSurface get renderSurface => renderSurfaceFrom(canvas);

  @override
  StageViewport get viewport => _viewport;

  @override
  void attach(Stage stage) => _stage = stage;

  @override
  void focus() => _postProtocol({'kind': 'stagexl:focus'});

  @override
  void setCursor(String cursor) => _postProtocol({'kind': 'stagexl:cursor', 'eventType': cursor});

  @override
  void setViewportSize(int width, int height) {}

  /// Creates the Stage whose complete scene runtime will live in this worker.
  Future<Stage> createStage({
    int? width,
    int? height,
    StageOptions? options,
    bool console = false,
  }) => Stage.createWithHost(this, width: width, height: height, options: options, console: console);

  /// Posts application-defined structured-clone data to the main host.
  void postMessage(Object? message) => _workerScope.postMessage(message.jsify());

  /// Application-defined structured-clone messages from the main host.
  Stream<Object?> get onMessage => _messageController.stream;

  void _handleMessage(_StageXLWorkerMessage message) {
    if (message.kind == 'stagexl:audio') {
      _audioAdapter?._handleMessage(message.data.dartify());
      return;
    }
    if (message.kind == 'stagexl:viewport') {
      _viewport = StageViewport(
        left: message.left,
        top: message.top,
        width: message.width,
        height: message.height,
      );
      _stage?.invalidate();
      return;
    }
    if (message.kind != 'stagexl:input') return;

    final modifiers = (
      altKey: message.altKey,
      ctrlKey: message.ctrlKey,
      shiftKey: message.shiftKey,
    );
    final input = switch (message.source) {
      'mouse' => StageMouseInput(
          message.eventType,
          clientX: message.clientX,
          clientY: message.clientY,
          button: message.button,
          deltaX: message.deltaX,
          deltaY: message.deltaY,
          altKey: modifiers.altKey,
          ctrlKey: modifiers.ctrlKey,
          shiftKey: modifiers.shiftKey,
        ),
      'touch' => StageTouchInput(
          message.eventType,
          identifier: message.identifier,
          clientX: message.clientX,
          clientY: message.clientY,
          altKey: modifiers.altKey,
          ctrlKey: modifiers.ctrlKey,
          shiftKey: modifiers.shiftKey,
        ),
      'keyboard' => StageKeyboardInput(
          message.eventType,
          keyCode: message.keyCode,
          charCode: message.charCode,
          keyLocation: switch (message.keyLocation) {
            stagexlKeyLocationLeft => .LEFT,
            stagexlKeyLocationRight => .RIGHT,
            stagexlKeyLocationNumPad => .NUM_PAD,
            stagexlKeyLocationDPad => .D_PAD,
            _ => .STANDARD,
          },
          altKey: modifiers.altKey,
          ctrlKey: modifiers.ctrlKey,
          shiftKey: modifiers.shiftKey,
        ),
      _ => null,
    };
    if (input != null) _stage?.dispatchInputEvent(input);
  }

  void _handleApplicationMessage(JSAny? message) => _messageController.add(message.dartify());

  void _postProtocol(Map<String, Object?> message) => _workerScope.postMessage(message.jsify());
}

/// Installs the StageXL worker protocol and invokes [initialize] after the main
/// thread transfers its canvas.
///
/// Call this once from the worker entry point. Build that entry point alongside
/// the main host entry point with the normal Dart web compiler.
void runStageXLWorker(Future<void> Function(StageWorkerHost host) initialize) {
  StageWorkerHost? host;
  _workerScope.onmessage = ((web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) {
      host?._handleApplicationMessage(data);
      return;
    }
    final object = data as JSObject;
    if (!object.has('kind')) {
      host?._handleApplicationMessage(data);
      return;
    }
    final message = _StageXLWorkerMessage(object);
    if (message.kind == 'stagexl:init') {
      if (host != null) return;
      host = StageWorkerHost._(
        message.canvas,
        devicePixelRatio: message.devicePixelRatio,
        initialData: message.data.dartify(),
        audioEnabled: message.audioEnabled,
        audioTypes: (message.audioTypes.dartify() as List).cast<String>(),
        viewport: StageViewport(
          left: message.left,
          top: message.top,
          width: message.width,
          height: message.height,
        ),
      );
      unawaited(initialize(host!).then((_) {
        _workerScope.postMessage({'kind': 'stagexl:ready'}.jsify());
      }).catchError((Object error, StackTrace stackTrace) {
        _workerScope.postMessage({
          'kind': 'stagexl:error',
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        }.jsify());
      }));
      return;
    }
    if (message.kind.startsWith('stagexl:')) {
      host?._handleMessage(message);
    } else {
      host?._handleApplicationMessage(data);
    }
  }).toJS;
}
