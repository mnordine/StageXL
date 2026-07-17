part of '../display.dart';

/// The canvas viewport StageXL uses for sizing and input-coordinate mapping.
///
/// Browser hosts obtain this from the canvas DOM element. Worker hosts receive
/// it from the main thread because an [OffscreenCanvas] has no layout box.
class StageViewport {
  final int left;
  final int top;
  final int width;
  final int height;

  const StageViewport({
    required this.width,
    required this.height,
    this.left = 0,
    this.top = 0,
  });
}

/// Platform-neutral input consumed by a [Stage].
sealed class StageInputEvent {
  final String type;
  final bool altKey;
  final bool ctrlKey;
  final bool shiftKey;

  const StageInputEvent(
    this.type, {
    this.altKey = false,
    this.ctrlKey = false,
    this.shiftKey = false,
  });
}

/// Mouse or wheel input in viewport coordinates.
class StageMouseInput extends StageInputEvent {
  final num clientX;
  final num clientY;
  final int button;
  final num deltaX;
  final num deltaY;

  const StageMouseInput(
    super.type, {
    required this.clientX,
    required this.clientY,
    this.button = 0,
    this.deltaX = 0,
    this.deltaY = 0,
    super.altKey,
    super.ctrlKey,
    super.shiftKey,
  });
}

/// One changed touch point in viewport coordinates.
class StageTouchInput extends StageInputEvent {
  final int identifier;
  final num clientX;
  final num clientY;

  const StageTouchInput(
    super.type, {
    required this.identifier,
    required this.clientX,
    required this.clientY,
    super.altKey,
    super.ctrlKey,
    super.shiftKey,
  });
}

/// Keyboard input forwarded by a Stage host.
class StageKeyboardInput extends StageInputEvent {
  final int keyCode;
  final int charCode;
  final KeyLocation keyLocation;

  const StageKeyboardInput(
    super.type, {
    required this.keyCode,
    this.charCode = 0,
    this.keyLocation = .STANDARD,
    super.altKey,
    super.ctrlKey,
    super.shiftKey,
  });
}

/// Isolates StageXL's scene runtime from the environment that owns its canvas.
///
/// Custom hosts can supply a DOM canvas, an `OffscreenCanvas`, or another
/// canvas-compatible rendering surface. The standard [Stage] constructor uses
/// [BrowserStageHost]; worker entry points use `StageWorkerHost` from
/// `package:stagexl/stagexl_worker.dart`.
abstract interface class StageHost {
  RenderSurface get renderSurface;

  num get devicePixelRatio;

  StageViewport get viewport;

  void attach(Stage stage);

  void focus();

  void setCursor(String cursor);

  void setViewportSize(int width, int height);
}

/// The normal browser main-thread host used by [Stage].
class BrowserStageHost implements StageHost {
  final HTMLCanvasElement canvas;

  BrowserStageHost(this.canvas);

  @override
  RenderSurface get renderSurface => renderSurfaceFrom(canvas);

  @override
  num get devicePixelRatio => env.devicePixelRatio;

  @override
  StageViewport get viewport {
    final rectangle = canvas.getBoundingClientRect();
    return StageViewport(
      left: canvas.clientLeft + rectangle.left.round(),
      top: canvas.clientTop + rectangle.top.round(),
      width: canvas.clientWidth,
      height: canvas.clientHeight,
    );
  }

  @override
  void attach(Stage stage) {
    if (canvas.tabIndex <= 0) canvas.tabIndex = 1;
    if (canvas.style.outline == '') canvas.style.outline = 'none';

    canvas.onKeyDown.listen((event) => _onKeyEvent(stage, event));
    canvas.onKeyUp.listen((event) => _onKeyEvent(stage, event));
    canvas.onKeyPress.listen((event) => _onKeyEvent(stage, event));

    final mode = stage._inputEventMode;
    final listenToMouseEvents = mode == .MouseOnly || mode == .MouseAndTouch;
    if (listenToMouseEvents) {
      canvas.onMouseDown.listen((event) => _onMouseEvent(stage, event));
      canvas.onMouseUp.listen((event) => _onMouseEvent(stage, event));
      canvas.onMouseMove.listen((event) => _onMouseEvent(stage, event));
      canvas.onMouseOut.listen((event) => _onMouseEvent(stage, event));
      canvas.onContextMenu.listen((event) => _onMouseEvent(stage, event));
      canvas.onMouseWheel.listen((event) => _onMouseWheelEvent(stage, event));
    }

    final listenToTouchEvents = mode == .TouchOnly || mode == .MouseAndTouch;
    if (listenToTouchEvents && env.isTouchEventSupported) {
      canvas.onTouchStart.listen((event) => _onTouchEvent(stage, event));
      canvas.onTouchEnd.listen((event) => _onTouchEvent(stage, event));
      canvas.onTouchMove.listen((event) => _onTouchEvent(stage, event));
      canvas.onTouchEnter.listen((event) => _onTouchEvent(stage, event));
      canvas.onTouchLeave.listen((event) => _onTouchEvent(stage, event));
      canvas.onTouchCancel.listen((event) => _onTouchEvent(stage, event));
    }
  }

  void _onMouseEvent(Stage stage, html.MouseEvent event) {
    if (stage.preventDefaultOnMouse) event.preventDefault();
    stage._processMouseInput(StageMouseInput(
      event.type,
      clientX: event.clientX,
      clientY: event.clientY,
      button: event.button,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
    ));
  }

  void _onMouseWheelEvent(Stage stage, html.WheelEvent event) {
    if (stage.preventDefaultOnWheel) event.preventDefault();
    final mouseEvent = stage._processMouseWheelInput(StageMouseInput(
      'wheel',
      clientX: event.clientX,
      clientY: event.clientY,
      deltaX: event.deltaX,
      deltaY: event.deltaY,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
    ));
    if (mouseEvent.isImmediatePropagationStopped) event.stopImmediatePropagation();
    if (mouseEvent.isPropagationStopped) event.stopPropagation();
    if (mouseEvent.isDefaultPrevented) event.preventDefault();
  }

  void _onTouchEvent(Stage stage, html.TouchEvent event) {
    if (stage.preventDefaultOnTouch) event.preventDefault();
    final touches = event.changedTouches;
    for (var i = 0; i < touches.length; i++) {
      final touch = touches.item(i);
      if (touch == null) continue;
      stage._processTouchInput(StageTouchInput(
        event.type,
        identifier: touch.identifier,
        clientX: touch.clientX,
        clientY: touch.clientY,
        altKey: event.altKey,
        ctrlKey: event.ctrlKey,
        shiftKey: event.shiftKey,
      ));
    }
  }

  void _onKeyEvent(Stage stage, html.KeyboardEvent event) {
    if (stage.preventDefaultOnKeyboard) event.preventDefault();
    final keyLocation = switch (event.location) {
      html.KeyLocation.LEFT => KeyLocation.LEFT,
      html.KeyLocation.RIGHT => KeyLocation.RIGHT,
      html.KeyLocation.NUMPAD => KeyLocation.NUM_PAD,
      html.KeyLocation.JOYSTICK || html.KeyLocation.MOBILE => KeyLocation.D_PAD,
      _ => KeyLocation.STANDARD,
    };
    final dispatchedEvent = stage._processKeyboardInput(StageKeyboardInput(
      event.type,
      keyCode: event.keyCode,
      charCode: event.charCode,
      keyLocation: keyLocation,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
    ));
    if (dispatchedEvent == null) return;
    if (dispatchedEvent.isImmediatePropagationStopped) event.stopImmediatePropagation();
    if (dispatchedEvent.isPropagationStopped) event.stopPropagation();
    if (dispatchedEvent._isInputDefaultPrevented) event.preventDefault();
  }

  @override
  void focus() => canvas.focus();

  @override
  void setCursor(String cursor) => canvas.style.cursor = cursor;

  @override
  void setViewportSize(int width, int height) {
    if (canvas.clientWidth != width || canvas.clientHeight != height) {
      canvas.style.width = '${width}px';
      canvas.style.height = '${height}px';
    }
  }
}
