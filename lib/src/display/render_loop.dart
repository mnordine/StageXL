part of '../display.dart';

class RenderLoop extends RenderLoopBase {
  final _juggler = Juggler();
  final _stages = <Stage>[];
  final _enterFrameEvent = EnterFrameEvent(0);
  final _exitFrameEvent = ExitFrameEvent();

  num _currentTime = 0.0;
  num _pendingTime = 0.0;
  var _targetFramesPerSecond = 0;
  final _animationFrameController = StreamController<double>.broadcast(sync: true);

  RenderLoop() {
    start();
  }

  Juggler get juggler => _juggler;

  /// Raw requestAnimationFrame intervals, before optional frame-rate limiting.
  Stream<double> get onAnimationFrame => _animationFrameController.stream;

  int get targetFramesPerSecond => _targetFramesPerSecond;

  set targetFramesPerSecond(int value) {
    if (value != 0 && value != 30 && value != 60) {
      throw ArgumentError.value(value, 'value', 'must be 0 (native rAF), 30, or 60');
    }
    _targetFramesPerSecond = value;
    _pendingTime = 0;
  }

  void addStage(Stage stage) {
    stage._renderLoop?.removeStage(stage);
    stage._renderLoop = this;
    _stages.add(stage);
  }

  void removeStage(Stage stage) {
    if (_stages.remove(stage)) {
      stage._renderLoop = null;
    }
  }

  @override
  void advanceTime(num deltaTime) {
    _animationFrameController.add(deltaTime.toDouble());
    if (_targetFramesPerSecond == 0) {
      _advanceStages(deltaTime);
      return;
    }
    _pendingTime += deltaTime;
    final minimumInterval = 1 / _targetFramesPerSecond;
    if (_pendingTime + .001 < minimumInterval) return;
    deltaTime = _pendingTime;
    _pendingTime = 0;
    _advanceStages(deltaTime);
  }

  void _advanceStages(num deltaTime) {
    _currentTime += deltaTime;
    _enterFrameEvent.passedTime = deltaTime;
    _enterFrameEvent.dispatch();
    _juggler.advanceTime(deltaTime);
    _stages.forEach((s) => s.juggler.advanceTime(deltaTime));
    _stages.forEach((s) => s.materialize(_currentTime, deltaTime));
    _exitFrameEvent.dispatch();
  }
}
