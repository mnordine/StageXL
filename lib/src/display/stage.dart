part of '../display.dart';

/// The StageRenderMode defines how often the Stage is rendered by
/// the [RenderLoop] where the Stage is attached to.

enum StageRenderMode {
  /// Render the stage automatically on each frame.
  AUTO,

  /// Render the stage automatically after a stage invalidation.
  AUTO_INVALID,

  /// Render the stage once then change to ´STOP´.
  ONCE,

  /// Do not render the stage.
  STOP
}

/// The StageScaleMode defines how the Stage is scaled inside of the Canvas.

enum StageScaleMode { EXACT_FIT, NO_BORDER, NO_SCALE, SHOW_ALL }

/// The StageAlign defines how the content of the Stage is aligned inside
/// of the Canvas. The setting controls where the origin (point 0,0) of the
/// Stage will be placed on the Canvas.

enum StageAlign {
  TOP_LEFT,
  TOP,
  TOP_RIGHT,
  LEFT,
  NONE,
  RIGHT,
  BOTTOM_LEFT,
  BOTTOM,
  BOTTOM_RIGHT
}

/// The Stage is the drawing area where all display objects are rendered to.
/// Place a Canvas element to your HTML and use the Stage to wrap all the
/// rendering functions to this Canvas element.
///
/// Example HTML:
///
///     <canvas id="stage"></canvas>
///
/// Example Dart:
///
///     var canvas = querySelector('#stage');
///     var stage = Stage(canvas, width: 800, height: 600);

class Stage extends DisplayObjectContainer {
  static var defaultOptions = StageOptions();

  late StageHost _host;
  late final RenderContext _renderContext;
  RenderLoop? _renderLoop;
  StageConsole? _console;
  StreamSubscription<RenderContextEvent>? _contextLostSubscription;
  StreamSubscription<RenderContextEvent>? _contextRestoredSubscription;
  StreamSubscription<String>? _cursorSubscription;
  var _disposed = false;

  var _sourceWidth = 0;
  var _sourceHeight = 0;
  var _stageWidth = 0;
  var _stageHeight = 0;
  num _pixelRatio = 1.0;
  var _invalid = false;

  double _avgFrameTime = 0;
  double _avgDrawCalls = 0;
  double _avgVertexCount = 0;
  double _avgIdexCount = 0;

  final _contentRectangle = Rectangle<num>(0.0, 0.0, 0.0, 0.0);
  final _clientTransformation = Matrix.fromIdentity();
  final _stageTransformation = Matrix.fromIdentity();
  final _consoleTransformation = Matrix.fromIdentity();
  final _renderEvent = RenderEvent();

  late RenderState _renderState;
  InputEventMode _inputEventMode = .MouseOnly;
  var _renderContextLost = false;
  var _renderAfterContextRestore = false;

  /// Gets and sets the render mode of this Stage. You can choose between
  /// three different modes defined in [StageRenderMode].
  StageRenderMode renderMode = .AUTO;

  StageScaleMode _stageScaleMode = .SHOW_ALL;
  StageAlign _stageAlign = .NONE;

  String _mouseCursor = MouseCursor.DEFAULT;
  var _mousePosition = Point<num>(0.0, 0.0);
  InteractiveObject? _mouseTarget;

  final _drags = <_Drag>[];
  final Map<int, _TouchPoint> _touchPoints = {};
  final List<_MouseButton> _mouseButtons = _MouseButton.createDefaults();

  //----------------------------------------------------------------------------

  /// A dedicated [Juggler] for this Stage. This Juggler is driven by the
  /// [RenderLoop] where this Stage is added to. If this Stage is not added
  /// to a RenderLoop, the [Juggler] will not advance in time.

  final juggler = Juggler();

  /// The interactive object with keyboard focus or null if focus is not set.

  InteractiveObject? focus;

  /// Gets and sets the background color of this Stage.

  int backgroundColor = Color.White;

  /// Prevents the browser's default behavior for touch events.

  var preventDefaultOnTouch = true;

  /// Prevents the browser's default behavior for mouse events.

  var preventDefaultOnMouse = true;

  /// Prevents the browser's default behavior for wheel events.

  var preventDefaultOnWheel = false;

  /// Prevents the browser's default behavior for keyboard events.

  var preventDefaultOnKeyboard = false;

  //----------------------------------------------------------------------------

  static const resizeEvent = EventStreamProvider<Event>(Event.RESIZE);

  static const mouseLeaveEvent = EventStreamProvider<Event>(Event.MOUSE_LEAVE);

  EventStream<Event> get onResize => Stage.resizeEvent.forTarget(this);

  EventStream<Event> get onMouseLeave => Stage.mouseLeaveEvent.forTarget(this);

  //----------------------------------------------------------------------------

  Stage(HTMLCanvasElement canvas,
      {int? width, int? height, StageOptions? options, bool console = false}) {
    options ??= Stage.defaultOptions;
    if (options.renderEngine == .WebGPU) {
      throw StateError(
          'RenderEngine.WebGPU requires async initialization. Use Stage.create(...) instead of Stage(...).');
    }

    final host = BrowserStageHost(canvas);
    final renderContext = _createRenderContext(host.renderSurface, options);
    _initialize(host, renderContext, width: width, height: height, options: options, console: console);
  }

  Stage._withRenderContext(StageHost host, RenderContext renderContext,
      {required StageOptions options, int? width, int? height, bool console = false}) {
    _initialize(host, renderContext, width: width, height: height, options: options, console: console);
  }

  /// Creates a [Stage] asynchronously.
  ///
  /// This factory is required for [RenderEngine.WebGPU] because WebGPU adapter
  /// and device creation is asynchronous. Existing WebGL and Canvas2D callers
  /// can keep using the synchronous [Stage] constructor.
  static Future<Stage> create(HTMLCanvasElement canvas,
      {int? width, int? height, StageOptions? options, bool console = false}) async {
    options ??= Stage.defaultOptions;
    final host = BrowserStageHost(canvas);
    final renderContext = await _createRenderContextAsync(host.renderSurface, options);
    return Stage._withRenderContext(
      host,
      renderContext,
      width: width,
      height: height,
      options: options,
      console: console,
    );
  }

  /// Creates a Stage for a platform host such as an OffscreenCanvas worker.
  ///
  /// Applications running on the main thread should keep using [Stage.create].
  static Future<Stage> createWithHost(StageHost host,
      {int? width, int? height, StageOptions? options, bool console = false}) async {
    options ??= Stage.defaultOptions;
    final renderContext = await _createRenderContextAsync(host.renderSurface, options);
    return Stage._withRenderContext(
      host,
      renderContext,
      width: width,
      height: height,
      options: options,
      console: console,
    );
  }

  void _initialize(StageHost host, RenderContext renderContext,
      {required StageOptions options, int? width, int? height, bool console = false}) {
    width ??= host.renderSurface.width;
    height ??= host.renderSurface.height;

    backgroundColor = options.backgroundColor;
    preventDefaultOnTouch = options.preventDefaultOnTouch;
    preventDefaultOnMouse = options.preventDefaultOnMouse;
    preventDefaultOnWheel = options.preventDefaultOnWheel;
    preventDefaultOnKeyboard = options.preventDefaultOnKeyboard;

    _host = host;
    _stageAlign = options.stageAlign;
    _stageScaleMode = options.stageScaleMode;
    renderMode = options.stageRenderMode;
    _inputEventMode = options.inputEventMode;

    _sourceWidth = width;
    _sourceHeight = height;
    _pixelRatio = min(options.maxPixelRatio, host.devicePixelRatio);
    _renderContext = renderContext;
    _renderContext.renderPipes.copyFrom(options.renderPipes);
    _renderState = RenderState(_renderContext);

    _contextLostSubscription = _renderContext.onContextLost.listen((_) {
      _renderContextLost = true;
      _renderAfterContextRestore = false;
      _invalid = true;
    });

    _contextRestoredSubscription = _renderContext.onContextRestored.listen((_) {
      _renderContextLost = false;
      _renderAfterContextRestore = true;
      _invalid = true;
    });

    if (console) _console = StageConsole()..visible = false;

    print('StageXL render engine : ${_renderContext.renderEngine.name}');

    host.attach(this);

    _cursorSubscription = Mouse.onCursorChanged.listen((cursorName) => _updateMouseCursor());

    _updateMouseCursor();
    _updateCanvasSize();
    _renderContext.clear(backgroundColor);
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  /// Gets the underlying render engine used to draw the pixels to the screen.
  /// The returned string is defined in [RenderEngine] and is either "WebGL"
  /// or "Canvas2D".

  RenderEngine get renderEngine => _renderContext.renderEngine;

  RenderContext get renderContext => _renderContext;

  bool get isDisposed => _disposed;

  /// Gets the [RenderLoop] where this Stage was added to, or
  /// NULL in case this Stage is not added to a [RenderLoop].

  RenderLoop? get renderLoop => _renderLoop;

  /// Gets the [StageConsole] to show render information about the previous
  /// frame as well as other custom information.

  StageConsole? get console => _console;

  /// Gets the last known mouse position in Stage coordinates.

  @override
  Point<num> get mousePosition => _mousePosition;

  /// Gets the available content area on the stage. The value of this rectangle
  /// changes with the scaleMode and the alignment of the stage, as well as the
  /// size of the underlying Canvas element.

  Rectangle<num> get contentRectangle => _contentRectangle.clone();

  /// Gets the width of the Stage in screen coordinates/pixels.

  int get stageWidth => _stageWidth;

  /// Gets the height of the Stage in screen coordinates/pixels.

  int get stageHeight => _stageHeight;

  /// Gets and sets the width of the Stage in world coordinates.
  /// The initial value of [sourceWidth] is the width of the canvas
  /// element or the width provided in the constructor of the Stage.

  int get sourceWidth => _sourceWidth;

  set sourceWidth(int value) {
    _sourceWidth = value;
    _updateCanvasSize();
  }

  /// Get the max texture size from the current WebGL canvas.
  /// Will return null if called on Canvas2D
  int? get maxTextureSize => _renderContext.maxTextureSize;

  /// Access WebGL parameters, you need to get the int's for access through
  /// dart:web_gl. Will return null if called on Canvas2D
  Object? getParameter(int parameter) => _renderContext.getParameter(parameter);

  /// Gets and sets the height of the Stage in world coordinates.
  /// The initial value of [sourceHeight] is the height of the canvas
  /// element or the height provided in the constructor of the Stage.

  int get sourceHeight => _sourceHeight;

  set sourceHeight(int value) {
    _sourceHeight = value;
    _updateCanvasSize();
  }

  /// Gets and sets the pixel ratio of the Stage.

  num get pixelRatio => _pixelRatio;

  set pixelRatio(num value) {
    if (_pixelRatio == value) return;
    _pixelRatio = value;
    _stageWidth = 0;
    _stageHeight = 0;
    _updateCanvasSize();
  }

  /// Gets and sets the scale mode of this Stage. You can choose between
  /// four different modes defined in [StageScaleMode].

  StageScaleMode get scaleMode => _stageScaleMode;

  set scaleMode(StageScaleMode value) {
    _stageScaleMode = value;
    _updateCanvasSize();
  }

  /// Gets and sets the alignment of this Stage inside of the Canvas element.
  /// You can choose between nine different align modes defined in [StageAlign].

  StageAlign get align => _stageAlign;

  set align(StageAlign value) {
    _stageAlign = value;
    _updateCanvasSize();
  }

  //----------------------------------------------------------------------------

  void _throwStageException() {
    throw UnsupportedError(
        'The Stage class does not implement this property or method.');
  }

  @override
  set x(num value) {
    _throwStageException();
  }

  @override
  set y(num value) {
    _throwStageException();
  }

  @override
  set pivotX(num value) {
    _throwStageException();
  }

  @override
  set pivotY(num value) {
    _throwStageException();
  }

  @override
  set scaleX(num value) {
    _throwStageException();
  }

  @override
  set scaleY(num value) {
    _throwStageException();
  }

  @override
  set skewX(num value) {
    _throwStageException();
  }

  @override
  set skewY(num value) {
    _throwStageException();
  }

  @override
  set rotation(num value) {
    _throwStageException();
  }

  @override
  set alpha(num value) {
    _throwStageException();
  }

  @override
  set width(num value) {
    _throwStageException();
  }

  @override
  set height(num value) {
    _throwStageException();
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  @override
  DisplayObject hitTestInput(num localX, num localY) {
    final target = super.hitTestInput(localX, localY);
    return target ?? this;
  }

  //----------------------------------------------------------------------------

  /// Invalidate the content of the [Stage]. This will render the stage on the
  /// next frame if the [renderMode] is set to [StageRenderMode.AUTO_INVALID].

  void invalidate() {
    _invalid = true;
  }

  /// Releases renderer-owned retained plans for this Stage and its console.
  ///
  /// Scene objects and textures are not disposed. The plans are recreated if
  /// [materialize] is called again.
  void releaseRenderPlan() {
    if (_renderContext.isDisposed) return;
    _renderContext.releaseRenderPlan(this);
    final console = _console;
    if (console != null) _renderContext.releaseRenderPlan(console);
  }

  /// Detaches this Stage and permanently releases its renderer resources.
  ///
  /// Display objects and application-owned textures remain available, but
  /// this Stage cannot render again. Calling this method more than once is safe.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    renderMode = .STOP;
    _renderLoop?.removeStage(this);
    _host.detach(this);
    unawaited(_contextLostSubscription?.cancel());
    unawaited(_contextRestoredSubscription?.cancel());
    unawaited(_cursorSubscription?.cancel());
    _contextLostSubscription = null;
    _contextRestoredSubscription = null;
    _cursorSubscription = null;
    releaseRenderPlan();
    _renderContext.dispose();
  }

  //----------------------------------------------------------------------------

  /// This method is called by the [RenderLoop] where this Stage is added to.
  /// If this Stage is not added to a [RenderLoop] you could call this method
  /// on your own and therefore get full control of the rendering of this Stage.

  void materialize(num currentTime, num deltaTime) {
    if (_disposed) return;
    if (_renderContextLost) return;
    if (renderMode == .STOP) {
      _renderAfterContextRestore = false;
      return;
    }

    final shouldRender = _renderAfterContextRestore ||
        renderMode == .AUTO ||
        renderMode == .AUTO_INVALID && _invalid ||
        renderMode == .ONCE;

    if (shouldRender) {
      final stopwatch = Stopwatch()..start();

      _updateCanvasSize();
      _renderEvent.dispatch();
      _renderContext.reset();
      _renderContext.renderStatistics.reset();
      _renderContext.clear(backgroundColor);
      _renderState.reset(_stageTransformation);
      _renderState.currentTime = currentTime;
      _renderState.deltaTime = deltaTime;
      final renderObjectStart = stopwatch.elapsedMicroseconds;
      _renderContext.buildRenderFrame(_renderState, this);
      final renderObjectEnd = stopwatch.elapsedMicroseconds;
      _renderContext.executeRenderFrame(_renderState);
      final flushEnd = stopwatch.elapsedMicroseconds;
      _renderAfterContextRestore = false;
      _invalid = false;

      final stats = _renderContext.renderStatistics;
      final frameTime = stopwatch.elapsedMilliseconds;
      stats.frameTimeMicroseconds = stopwatch.elapsedMicroseconds;
      stats.renderObjectMicroseconds = renderObjectEnd - renderObjectStart;
      stats.renderFlushMicroseconds = flushEnd - renderObjectEnd;
      _avgDrawCalls = _avgDrawCalls * 0.75 + stats.drawCount * 0.25;
      _avgVertexCount = _avgVertexCount * 0.75 + stats.vertexCount * 0.25;
      _avgIdexCount = _avgIdexCount * 0.75 + stats.indexCount * 0.25;
      _avgFrameTime = _avgFrameTime * 0.95 + frameTime * 0.05;

      if (_console != null) {
        final console = _console!;

        if (console.visible && console.off == false) {
          console.updateRenderStatistics(stats);
          _renderState.reset(_consoleTransformation);
          _renderContext.buildRenderFrame(_renderState, console);
          _renderContext.executeRenderFrame(_renderState);
        }
      }
    }

    if (renderMode == .ONCE) {
      renderMode = .STOP;
    }
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  static Future<RenderContext> _createRenderContextAsync(
      RenderSurface canvas, StageOptions options) async {
    if (options.renderEngine == .WebGPU) {
      if (options.sharedWebGLContext != null) {
        throw ArgumentError.value(
          options.sharedWebGLContext,
          'options.sharedWebGLContext',
          'A WebGL context cannot be used by the WebGPU render engine.',
        );
      }
      final sharedContext = options.sharedWebGPUContext;
      if (sharedContext != null && !options.clearBeforeRender && options.antialias) {
        throw ArgumentError.value(
          options.antialias,
          'options.antialias',
          'WebGPU antialiasing must be disabled when preserving another renderer output.',
        );
      }
      final webgpuContext = sharedContext == null
          ? await RenderContextWebGPU.create(
              canvas,
              alpha: options.transparent,
              antialias: options.antialias,
              powerPreference: options.powerPreference,
              renderBundles: options.renderBundles,
              dualSourceBlending: options.dualSourceBlending,
              hdr: options.hdr,
            )
          : RenderContextWebGPU.shared(
              canvas,
              sharedContext,
              alpha: options.transparent,
              antialias: options.antialias,
              renderBundles: options.renderBundles,
              dualSourceBlending: options.dualSourceBlending,
              hdr: options.hdr,
              clearBeforeRender: options.clearBeforeRender,
            );
      if (webgpuContext != null) return webgpuContext;
    }

    return _createRenderContext(canvas, options.renderEngine == .WebGPU
        ? (options.clone()..renderEngine = .WebGL2)
        : options);
  }

  static RenderContext _createRenderContext(
      RenderSurface canvas, StageOptions options) {
    switch (options.renderEngine) {
      case .WebGL || .WebGL2:
        if (options.sharedWebGPUContext != null) {
          throw ArgumentError.value(
            options.sharedWebGPUContext,
            'options.sharedWebGPUContext',
            'A WebGPU context cannot be used by a WebGL render engine.',
          );
        }
        final RenderContextWebGL context;

        try {
          final sharedContext = options.sharedWebGLContext;
          context = sharedContext == null
              ? RenderContextWebGL(
                  canvas,
                  alpha: options.transparent,
                  antialias: options.antialias,
                  forceWebGL1: options.renderEngine == .WebGL,
                  powerPreference: options.powerPreference,
                  resetScissorTest: options.resetScissorTestOnRenderStart,
                  resetStencilTest: options.resetStencilTestOnRenderStart,
                  resetColor: options.resetColorOnRenderStart,
                  dualSourceBlending: options.dualSourceBlending,
                )
              : RenderContextWebGL.shared(
                  canvas,
                  sharedContext,
                  alpha: options.transparent,
                  antialias: options.antialias,
                  forceWebGL1: options.renderEngine == .WebGL,
                  powerPreference: options.powerPreference,
                  resetScissorTest: options.resetScissorTestOnRenderStart,
                  resetStencilTest: options.resetStencilTestOnRenderStart,
                  resetColor: options.resetColorOnRenderStart,
                  dualSourceBlending: options.dualSourceBlending,
                  clearBeforeRender: options.clearBeforeRender,
                );
        } on StateError catch (e) { // ignore: avoid_catching_errors
          if (e.message == 'Failed to get WebGL context.') {
            return RenderContextCanvas(canvas);
          } 

          rethrow;
        }

        // Override to medium precision if high is not supported
        if (options.shaderPrecision == .high) {
          try {
            final gl = context.rawContext;
            final high = gl.getShaderPrecisionFormat(WebGL.FRAGMENT_SHADER, WebGL.HIGH_FLOAT);
            if (high!.precision <= 0) options.shaderPrecision = .medium;
          } catch (e) {
            options.shaderPrecision = .medium;
          }
        }

        return context;

      case .Canvas2D:
        if (options.sharedWebGLContext != null || options.sharedWebGPUContext != null) {
          throw ArgumentError.value(
            options.sharedWebGLContext ?? options.sharedWebGPUContext,
            'options',
            'Shared GPU contexts cannot be used by the Canvas2D render engine.',
          );
        }
        return RenderContextCanvas(canvas);

      case .WebGPU:
        throw StateError(
            'RenderEngine.WebGPU requires async initialization. Use Stage.create(...) instead of Stage(...).');
    }
  }

  //----------------------------------------------------------------------------

  void _startDrag(Sprite sprite, Point<num> globalPoint, Point<num> anchorPoint,
      Rectangle<num>? bounds, int touchPointID) {
    final drag = _Drag(this, sprite, anchorPoint, bounds, touchPointID);
    drag.update(touchPointID, globalPoint);

    _drags.removeWhere(
        (d) => d.touchPointID == touchPointID || d.sprite == sprite);
    _drags.add(drag);
  }

  void _stopDrag(Sprite sprite) {
    _drags.removeWhere((d) => d.sprite == sprite);
  }

  //----------------------------------------------------------------------------

  void _updateCanvasSize() {
    var clientLeft = 0, clientTop = 0;
    var clientWidth = 0, clientHeight = 0;
    final sourceWidth = _sourceWidth;
    final sourceHeight = _sourceHeight;

    final viewport = _host.viewport;
    clientLeft = viewport.left;
    clientTop = viewport.top;
    clientWidth = viewport.width;
    clientHeight = viewport.height;

    if (clientWidth == 0 || clientHeight == 0) return;

    //----------------------------

    var scaleX = 1.0;
    var scaleY = 1.0;
    var pivotX = 0.0;
    var pivotY = 0.0;
    final ratioWidth = clientWidth / sourceWidth;
    final ratioHeight = clientHeight / sourceHeight;

    switch (_stageScaleMode) {
      case .EXACT_FIT:
        scaleX = ratioWidth;
        scaleY = ratioHeight;
      case .NO_BORDER:
        scaleX = scaleY = (ratioWidth > ratioHeight) ? ratioWidth : ratioHeight;
      case .NO_SCALE:
        scaleX = scaleY = 1.0;
      case .SHOW_ALL:
        scaleX = scaleY = (ratioWidth < ratioHeight) ? ratioWidth : ratioHeight;
    }

    switch (_stageAlign) {
      case .LEFT:
      case .BOTTOM_LEFT:
      case .TOP_LEFT:
        pivotX = 0.0;
      case .TOP:
      case .NONE:
      case .BOTTOM:
        pivotX = (clientWidth - sourceWidth * scaleX) / 2;
      case .TOP_RIGHT:
      case .RIGHT:
      case .BOTTOM_RIGHT:
        pivotX = clientWidth - sourceWidth * scaleX;
    }

    switch (_stageAlign) {
      case .TOP_LEFT:
      case .TOP:
      case .TOP_RIGHT:
        pivotY = 0.0;
      case .LEFT:
      case .NONE:
      case .RIGHT:
        pivotY = (clientHeight - sourceHeight * scaleY) / 2;
      case .BOTTOM_LEFT:
      case .BOTTOM:
      case .BOTTOM_RIGHT:
        pivotY = clientHeight - sourceHeight * scaleY;
    }

    //----------------------------

    _contentRectangle.left = -pivotX / scaleX;
    _contentRectangle.top = -pivotY / scaleY;
    _contentRectangle.width = clientWidth / scaleX;
    _contentRectangle.height = clientHeight / scaleY;

    // stage to canvas coordinate transformation
    _stageTransformation.setTo(scaleX, 0.0, 0.0, scaleY, pivotX, pivotY);
    _stageTransformation.scale(pixelRatio, pixelRatio);

    // client to stage coordinate transformation
    _clientTransformation.setTo(
        1.0, 0.0, 0.0, 1.0, -clientLeft - pivotX, -clientTop - pivotY);
    _clientTransformation.scale(1.0 / scaleX, 1.0 / scaleY);

    _consoleTransformation.identity();
    _consoleTransformation.scale(pixelRatio, pixelRatio);

    //----------------------------

    if (_stageWidth != clientWidth || _stageHeight != clientHeight) {
      _stageWidth = clientWidth;
      _stageHeight = clientHeight;
      _host.renderSurface.width = (clientWidth * pixelRatio).round();
      _host.renderSurface.height = (clientHeight * pixelRatio).round();

      // update hi-dpi canvas style size if client size has changed

      _host.setViewportSize(clientWidth, clientHeight);

      dispatchEvent(Event(Event.RESIZE));
    }
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  void _updateMouseCursor() {
    final mouseTarget = _mouseTarget;
    var mouseCursor = Mouse.cursor;

    if (mouseTarget != null && mouseCursor == MouseCursor.AUTO) {
      final mc = mouseTarget.mouseCursor;
      if (mc != MouseCursor.AUTO) mouseCursor = mc;
    }

    if (mouseCursor == MouseCursor.AUTO) {
      mouseCursor = MouseCursor.DEFAULT;
    }

    if (_mouseCursor != mouseCursor) {
      _mouseCursor = mouseCursor;
      _host.setCursor(Mouse.getCursorStyle(mouseCursor));
    }
  }

  Point<num> transformPoint(math.Point<num> pt, [Point<num>? returnPoint]) =>
      _clientTransformation.transformPoint(pt, returnPoint);

  /// Dispatches input supplied by the active [StageHost].
  ///
  /// Worker hosts call this after deserializing events forwarded by the main
  /// thread. Hit testing and StageXL event propagation still happen locally in
  /// the Stage runtime.
  void dispatchInputEvent(StageInputEvent event) {
    if (_disposed) return;
    switch (event) {
      case StageMouseInput(type: 'wheel'):
        _processMouseWheelInput(event);
      case StageMouseInput():
        _processMouseInput(event);
      case StageTouchInput():
        _processTouchInput(event);
      case StageKeyboardInput():
        _processKeyboardInput(event);
    }
  }

  //----------------------------------------------------------------------------

  void _processMouseInput(StageMouseInput event) {

    final time = DateTime.now().millisecondsSinceEpoch;
    final button = event.button;

    InteractiveObject? target;
    final stagePoint = _clientTransformation.transformPoint(Point(event.clientX, event.clientY));
    final localPoint = Point<num>(0.0, 0.0);

    if (button < 0 || button > 2) return;
    if (event.type == 'mousemove' && _mousePosition == stagePoint) return;

    final mouseButton = _mouseButtons[button];
    _mousePosition = stagePoint;
    _drags.forEach((d) => d.update(0, stagePoint));

    if (event.type != 'mouseout') {
      target = hitTestInput(stagePoint.x, stagePoint.y) as InteractiveObject;
    } else {
      dispatchEvent(Event(Event.MOUSE_LEAVE));
    }

    //-----------------------------------------------------------------
    // MOUSE_OUT, ROLL_OUT, ROLL_OVER, MOUSE_OVER

    if (_mouseTarget != target) {
      final oldTarget = _mouseTarget;
      final newTarget = target;
      final oldTargetList = <DisplayObject>[];
      final newTargetList = <DisplayObject>[];
      var commonCount = 0;

      for (DisplayObject? p = oldTarget; p != null; p = p.parent) {
        oldTargetList.add(p);
      }

      for (DisplayObject? p = newTarget; p != null; p = p.parent) {
        newTargetList.add(p);
      }

      for (;; commonCount++) {
        if (commonCount == oldTargetList.length) break;
        if (commonCount == newTargetList.length) break;
        final ot = oldTargetList[oldTargetList.length - commonCount - 1];
        final nt = newTargetList[newTargetList.length - commonCount - 1];
        if (ot != nt) break;
      }

      if (oldTarget != null) {
        oldTarget.globalToLocal(stagePoint, localPoint);
        oldTarget.dispatchEvent(MouseEvent(
            MouseEvent.MOUSE_OUT,
            true,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            event.altKey,
            event.ctrlKey,
            event.shiftKey,
            0.0,
            0.0,
            mouseButton.buttonDown,
            0));
      }

      for (var i = 0; i < oldTargetList.length - commonCount; i++) {
        final target = oldTargetList[i];
        target.globalToLocal(stagePoint, localPoint);
        target.dispatchEvent(MouseEvent(
            MouseEvent.ROLL_OUT,
            false,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            event.altKey,
            event.ctrlKey,
            event.shiftKey,
            0.0,
            0.0,
            mouseButton.buttonDown,
            0));
      }

      for (var i = newTargetList.length - commonCount - 1; i >= 0; i--) {
        final target = newTargetList[i];
        target.globalToLocal(stagePoint, localPoint);
        target.dispatchEvent(MouseEvent(
            MouseEvent.ROLL_OVER,
            false,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            event.altKey,
            event.ctrlKey,
            event.shiftKey,
            0.0,
            0.0,
            mouseButton.buttonDown,
            0));
      }

      if (newTarget != null) {
        newTarget.globalToLocal(stagePoint, localPoint);
        newTarget.dispatchEvent(MouseEvent(
            MouseEvent.MOUSE_OVER,
            true,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            event.altKey,
            event.ctrlKey,
            event.shiftKey,
            0.0,
            0.0,
            mouseButton.buttonDown,
            0));
      }

      _mouseTarget = newTarget;
    }

    _updateMouseCursor();

    //-----------------------------------------------------------------
    // MOUSE_DOWN, MOUSE_MOVE, MOUSE_UP, CLICK, DOUBLE_CLICK

    String? mouseEventType;
    var isClick = false;
    var isDoubleClick = false;

    if (event.type == 'mousedown') {
      _host.focus();
      mouseEventType = mouseButton.mouseDownEventType;

      if (target != mouseButton.target || time > mouseButton.clickTime + 500) {
        mouseButton.clickCount = 0;
      }

      mouseButton.buttonDown = true;
      mouseButton.target = target;
      mouseButton.clickTime = time;
      mouseButton.clickCount++;
    }

    if (event.type == 'mouseup') {
      mouseEventType = mouseButton.mouseUpEventType;
      mouseButton.buttonDown = false;
      isClick = mouseButton.target == target;
      isDoubleClick = isClick &&
          mouseButton.clickCount.isEven &&
          (time < mouseButton.clickTime + 500);
    }

    if (event.type == 'mousemove') {
      mouseEventType = MouseEvent.MOUSE_MOVE;
    }

    if (event.type == 'contextmenu') {
      mouseEventType = MouseEvent.CONTEXT_MENU;
    }

    //-----------------------------------------------------------------

    if (mouseEventType != null && target != null) {
      target.globalToLocal(stagePoint, localPoint);
      target.dispatchEvent(MouseEvent(
          mouseEventType,
          true,
          localPoint.x,
          localPoint.y,
          stagePoint.x,
          stagePoint.y,
          event.altKey,
          event.ctrlKey,
          event.shiftKey,
          0.0,
          0.0,
          mouseButton.buttonDown,
          mouseButton.clickCount));

      if (isClick) {
        mouseEventType = isDoubleClick && target.doubleClickEnabled
            ? mouseButton.mouseDoubleClickEventType
            : mouseButton.mouseClickEventType;

        target.dispatchEvent(MouseEvent(
            mouseEventType,
            true,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            event.altKey,
            event.ctrlKey,
            event.shiftKey,
            0.0,
            0.0,
            mouseButton.buttonDown,
            0));
      }
    }
  }

  //----------------------------------------------------------------------------

  MouseEvent _processMouseWheelInput(StageMouseInput event) {

    final stagePoint = _clientTransformation.transformPoint(Point(event.clientX, event.clientY));
    final localPoint = Point<num>(0.0, 0.0);

    final target =
        hitTestInput(stagePoint.x, stagePoint.y) as InteractiveObject;
    target.globalToLocal(stagePoint, localPoint);

    final mouseEvent = MouseEvent(
        MouseEvent.MOUSE_WHEEL,
        true,
        localPoint.x,
        localPoint.y,
        stagePoint.x,
        stagePoint.y,
        event.altKey,
        event.ctrlKey,
        event.shiftKey,
        event.deltaX,
        event.deltaY,
        false,
        0);

    target.dispatchEvent(mouseEvent);
    return mouseEvent;
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  void _processTouchInput(StageTouchInput event) {
    final eventType = event.type;
    final altKey = event.altKey;
    final ctrlKey = event.ctrlKey;
    final shiftKey = event.shiftKey;
    final identifier = event.identifier;
    final clientPoint = Point(event.clientX, event.clientY);
    final stagePoint = _clientTransformation.transformPoint(clientPoint);
    final localPoint = Point<num>(0.0, 0.0);
    final target = hitTestInput(stagePoint.x, stagePoint.y) as InteractiveObject;

    final touchPoint = _touchPoints.putIfAbsent(
        identifier, () => _TouchPoint(target, _touchPoints.isEmpty));

    final touchPointID = touchPoint.touchPointID;
    final primaryTouchPoint = touchPoint.primaryTouchPoint;

    _drags.forEach((d) => d.update(touchPointID, stagePoint));

    //---------------------------------------------------------------
    // TOUCH_OUT, TOUCH_ROLL_OUT, TOUCH_ROLL_OVER, TOUCH_OVER

    if (touchPoint.currentTarget != target) {
      final oldTarget = touchPoint.currentTarget;
      final newTarget = target;
      final oldTargetList = <DisplayObject>[];
      final newTargetList = <DisplayObject>[];
      var commonCount = 0;

      for (DisplayObject? p = oldTarget; p != null; p = p.parent) {
        oldTargetList.add(p);
      }

      for (DisplayObject? p = newTarget; p != null; p = p.parent) {
        newTargetList.add(p);
      }

      for (;; commonCount++) {
        if (commonCount == oldTargetList.length) break;
        if (commonCount == newTargetList.length) break;
        final ot = oldTargetList[oldTargetList.length - commonCount - 1];
        final nt = newTargetList[newTargetList.length - commonCount - 1];
        if (ot != nt) break;
      }

      oldTarget.globalToLocal(stagePoint, localPoint);
      oldTarget.dispatchEvent(TouchEvent(
          TouchEvent.TOUCH_OUT,
          true,
          localPoint.x,
          localPoint.y,
          stagePoint.x,
          stagePoint.y,
          altKey,
          ctrlKey,
          shiftKey,
          touchPointID,
          primaryTouchPoint));

      for (var i = 0; i < oldTargetList.length - commonCount; i++) {
        final target = oldTargetList[i];
        target.globalToLocal(stagePoint, localPoint);
        target.dispatchEvent(TouchEvent(
            TouchEvent.TOUCH_ROLL_OUT,
            false,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            altKey,
            ctrlKey,
            shiftKey,
            touchPointID,
            primaryTouchPoint));
      }

      for (var i = newTargetList.length - commonCount - 1; i >= 0; i--) {
        final target = newTargetList[i];
        target.globalToLocal(stagePoint, localPoint);
        target.dispatchEvent(TouchEvent(
            TouchEvent.TOUCH_ROLL_OVER,
            false,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            altKey,
            ctrlKey,
            shiftKey,
            touchPointID,
            primaryTouchPoint));
      }

      newTarget.globalToLocal(stagePoint, localPoint);
      newTarget.dispatchEvent(TouchEvent(
          TouchEvent.TOUCH_OVER,
          true,
          localPoint.x,
          localPoint.y,
          stagePoint.x,
          stagePoint.y,
          altKey,
          ctrlKey,
          shiftKey,
          touchPointID,
          primaryTouchPoint));

      touchPoint.currentTarget = newTarget;
    }

    //---------------------------------------------------------------
    // TOUCH_BEGIN, TOUCH_MOVE, TOUCH_END, TOUCH_CANCEL, TOUCH_TAP

    String? touchEventType;
    var isTap = false;

    if (eventType == 'touchstart') {
      _host.focus();
      _touchPoints[identifier] = touchPoint;
      touchEventType = TouchEvent.TOUCH_BEGIN;
    }

    if (eventType == 'touchend') {
      _touchPoints.remove(identifier);
      touchEventType = TouchEvent.TOUCH_END;
      isTap = touchPoint.target == target;
    }

    if (eventType == 'touchcancel') {
      _touchPoints.remove(identifier);
      touchEventType = TouchEvent.TOUCH_CANCEL;
    }

    if (eventType == 'touchmove') {
      touchEventType = TouchEvent.TOUCH_MOVE;
    }

    if (touchEventType != null) {
      target.globalToLocal(stagePoint, localPoint);
      target.dispatchEvent(TouchEvent(
          touchEventType,
          true,
          localPoint.x,
          localPoint.y,
          stagePoint.x,
          stagePoint.y,
          altKey,
          ctrlKey,
          shiftKey,
          touchPointID,
          primaryTouchPoint));

      if (isTap) {
        target.dispatchEvent(TouchEvent(
            TouchEvent.TOUCH_TAP,
            true,
            localPoint.x,
            localPoint.y,
            stagePoint.x,
            stagePoint.y,
            altKey,
            ctrlKey,
            shiftKey,
            touchPointID,
            primaryTouchPoint));
      }
    }
  }

  //----------------------------------------------------------------------------
  //----------------------------------------------------------------------------

  Event? _processKeyboardInput(StageKeyboardInput event) {
    if (focus == null) return null;

    if (event.type == 'keypress') {
      var charCode = event.charCode;
      final keyCode = event.keyCode;
      if (keyCode == 13) charCode = 13;
      if (charCode == 0) return null;

      final text = String.fromCharCodes([charCode]);
      final textEvent = TextEvent(TextEvent.TEXT_INPUT, true, text);

      focus!.dispatchEvent(textEvent);
      return textEvent;
    } else {
      var keyboardEventType = '';

      if (event.type == 'keyup') {
        keyboardEventType = KeyboardEvent.KEY_UP;
      }
      if (event.type == 'keydown') {
        keyboardEventType = KeyboardEvent.KEY_DOWN;
      }
      final keyboardEvent = KeyboardEvent(
          keyboardEventType,
          true,
          event.keyCode,
          event.keyLocation,
          event.altKey,
          event.ctrlKey,
          event.shiftKey);

      focus!.dispatchEvent(keyboardEvent);
      return keyboardEvent;
    }
  }
}

extension on Event {
  bool get _isInputDefaultPrevented => switch (this) {
    KeyboardEvent() => (this as KeyboardEvent).isDefaultPrevented,
    TextEvent() => (this as TextEvent).isDefaultPrevented,
    _ => false,
  };
}
