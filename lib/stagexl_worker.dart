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
  external String get error;
  external String get stackTrace;
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
  final web.WorkerOptions? workerOptions;
  final Object? initialData;

  const StageWorkerClientOptions({
    this.inputEventMode = .MouseOnly,
    this.preventDefaultOnMouse = true,
    this.preventDefaultOnTouch = true,
    this.preventDefaultOnWheel = false,
    this.preventDefaultOnKeyboard = false,
    this.emulateMouseFromTouch = false,
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
  var _disposed = false;

  StageWorkerClient(
    this.canvas,
    String workerUrl, {
    this.options = const StageWorkerClientOptions(),
  }) : worker = options.workerOptions == null
           ? web.Worker(workerUrl.toJS)
           : web.Worker(workerUrl.toJS, options.workerOptions!) {
    worker.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data != null && data.isA<JSObject>()) {
        final object = data as JSObject;
        if (object.has('kind')) {
          final message = _StageXLWorkerMessage(object);
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
    if (event.type == 'mousedown') canvas.focus();
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
    worker.terminate();
    unawaited(_messageController.close());
    unawaited(_errorController.close());
  }
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

  StageWorkerHost._(
    this.canvas, {
    required this.devicePixelRatio,
    required this._viewport,
    required this.initialData,
  });

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
