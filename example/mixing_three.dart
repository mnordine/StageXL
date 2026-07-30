import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';
import 'package:webgpu_interop/generated.dart';

const _stageWidth = 960;
const _stageHeight = 640;

@JS('globalThis')
external JSObject get _globalThis;

extension type _ThreeExampleGlobal(JSObject _) implements JSObject {
  external _ThreeExampleBridge? get stageXLThree;
  external String? get stageXLThreeError;
}

extension type _ThreeExampleBridge(JSObject _) implements JSObject {
  external String get backend;
  external WebGLRenderingContext? get webGLContext;
  external GPUDevice? get webGPUDevice;
  external GPUCanvasContext? get webGPUCanvasContext;
  external GPUTextureFormat? get webGPUTextureFormat;
  external double get rotationX;
  external double get rotationY;
  external void render(double timeMilliseconds);
  external void resize(double width, double height, double pixelRatio);
}

Future<void> main() async {
  final loading = document.querySelector('#loading') as HTMLElement;

  try {
    final bridge = await _waitForThree();
    final canvas = document.querySelector('#stage') as HTMLCanvasElement;
    final backgroundStage = await _createStage(canvas, bridge, clearBeforeRender: true);
    final overlayStage = await _createStage(canvas, bridge, clearBeforeRender: false);
    final background = _buildBackground(backgroundStage, bridge.backend);
    final rotationLabel = _buildOverlay(overlayStage);

    void resize() {
      final pixelRatio = math.min(window.devicePixelRatio, 2).toDouble();
      bridge.resize(canvas.clientWidth.toDouble(), canvas.clientHeight.toDouble(), pixelRatio);
    }

    resize();
    window.addEventListener('resize', ((JSAny? _) => resize()).toJS);
    loading.remove();

    var elapsed = 0.0;
    final renderLoop = RenderLoop();
    renderLoop.onAnimationFrame.listen((deltaTime) {
      elapsed += deltaTime;
      background.rotation = elapsed * 0.08;
      rotationLabel.text =
          'YAW ${(bridge.rotationY * 180 / math.pi).round().toString().padLeft(4)}°  '
          'PITCH ${(bridge.rotationX * 180 / math.pi).round().toString().padLeft(3)}°';

      backgroundStage.materialize(elapsed, deltaTime);
      bridge.render(elapsed * 1000);
      overlayStage.materialize(elapsed, deltaTime);
    });
  } catch (error) {
    loading
      ..className = 'mixing-three-loading is-error'
      ..textContent = 'Unable to start the Three.js example: $error';
  }
}

Future<Stage> _createStage(
  HTMLCanvasElement canvas,
  _ThreeExampleBridge bridge, {
  required bool clearBeforeRender,
}) {
  final options = StageOptions()
    ..clearBeforeRender = clearBeforeRender
    ..backgroundColor = clearBeforeRender ? 0xFF070B18 : Color.Transparent
    ..stageAlign = .NONE
    ..stageScaleMode = .SHOW_ALL
    ..stageRenderMode = .AUTO
    ..maxPixelRatio = 2
    ..preventDefaultOnMouse = false
    ..preventDefaultOnTouch = false;
  if (bridge.backend == 'webgpu') {
    options
      ..renderEngine = .WebGPU
      ..sharedWebGPUContext = SharedWebGPUContext(
        device: bridge.webGPUDevice!,
        canvasContext: bridge.webGPUCanvasContext!,
        textureFormat: bridge.webGPUTextureFormat!,
      );
  } else {
    options
      ..renderEngine = .WebGL2
      ..sharedWebGLContext = bridge.webGLContext;
  }
  return bridge.backend == 'webgpu'
      ? Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options)
      : Future.value(Stage(canvas, width: _stageWidth, height: _stageHeight, options: options));
}

Sprite _buildBackground(Stage stage, String backend) {
  final grid = Shape();
  for (var x = 0; x <= _stageWidth; x += 48) {
    grid.graphics
      ..moveTo(x, 0)
      ..lineTo(x, _stageHeight)
      ..strokeColor(0x102E5A86, 1);
  }
  for (var y = 0; y <= _stageHeight; y += 48) {
    grid.graphics
      ..moveTo(0, y)
      ..lineTo(_stageWidth, y)
      ..strokeColor(0x102E5A86, 1);
  }

  final glow = Shape();
  glow.graphics
    ..circle(_stageWidth / 2, _stageHeight / 2, 250)
    ..fillColor(0x182E9CFF)
    ..circle(_stageWidth / 2, _stageHeight / 2, 185)
    ..fillColor(0x2025D4B8);

  final orbit = Sprite()
    ..x = _stageWidth / 2
    ..y = _stageHeight / 2;
  final rings = Shape();
  rings.graphics
    ..circle(0, 0, 222)
    ..strokeColor(0x5558D6FF, 2)
    ..circle(0, 0, 260)
    ..strokeColor(0x223AB4D8, 1)
    ..moveTo(-280, 0)
    ..lineTo(280, 0)
    ..strokeColor(0x2248B7E8, 1)
    ..moveTo(0, -280)
    ..lineTo(0, 280)
    ..strokeColor(0x2248B7E8, 1);
  orbit.addChild(rings);

  for (var i = 0; i < 18; i++) {
    final angle = i * math.pi * 2 / 18;
    final radius = i.isEven ? 260 : 222;
    final marker = Shape()
      ..x = math.cos(angle) * radius
      ..y = math.sin(angle) * radius;
    marker.graphics
      ..circle(0, 0, i % 3 == 0 ? 3 : 1.5)
      ..fillColor(i % 3 == 0 ? 0xFF70E5FF : 0x7758D6FF);
    orbit.addChild(marker);
  }

  stage
    ..addChild(grid)
    ..addChild(glow)
    ..addChild(orbit);
  _addLabel(stage, 'PASS 01  ·  STAGEXL BACKGROUND', 28, 24, 12, 0xFF5FD9FF, bold: true);
  _addLabel(stage, 'SHARED ${backend.toUpperCase()} CONTEXT', 28, 46, 10, 0xFF61728F);
  _addLabel(stage, '2D SCENE', 42, 560, 72, 0x142DCBFF, bold: true);
  return orbit;
}

TextField _buildOverlay(Stage stage) {
  final frame = Shape();
  frame.graphics
    ..moveTo(24, 82)
    ..lineTo(24, 24)
    ..lineTo(82, 24)
    ..strokeColor(0xFFB3F5FF, 2)
    ..moveTo(_stageWidth - 82, 24)
    ..lineTo(_stageWidth - 24, 24)
    ..lineTo(_stageWidth - 24, 82)
    ..strokeColor(0xFFB3F5FF, 2)
    ..moveTo(24, _stageHeight - 82)
    ..lineTo(24, _stageHeight - 24)
    ..lineTo(82, _stageHeight - 24)
    ..strokeColor(0xFFB3F5FF, 2)
    ..moveTo(_stageWidth - 82, _stageHeight - 24)
    ..lineTo(_stageWidth - 24, _stageHeight - 24)
    ..lineTo(_stageWidth - 24, _stageHeight - 82)
    ..strokeColor(0xFFB3F5FF, 2);

  final topBadge = Shape();
  topBadge.graphics
    ..rectRound(668, 22, 268, 58, 12, 12)
    ..fillColor(0xDD0B1428)
    ..rectRound(668, 22, 268, 58, 12, 12)
    ..strokeColor(0x665FE7FF, 1);

  final dragHint = Shape();
  dragHint.graphics
    ..rectRound(333, 570, 294, 44, 22, 22)
    ..fillColor(0xE6101A2D)
    ..rectRound(333, 570, 294, 44, 22, 22)
    ..strokeColor(0x775FE7FF, 1);

  stage
    ..addChild(frame)
    ..addChild(topBadge)
    ..addChild(dragHint);
  _addLabel(stage, 'PASS 03  ·  STAGEXL HUD', 688, 34, 12, 0xFF78E7FF, bold: true);
  final rotationLabel = _addLabel(stage, 'YAW    0°  PITCH   0°', 688, 54, 11, 0xFFB9C7D8);
  _addLabel(stage, 'GRAB + DRAG TO ROTATE', 386, 584, 12, 0xFFF4F8FF, bold: true);
  _addLabel(stage, 'THREE.JS CHARACTER', 378, 92, 11, 0x886FE8FF, bold: true);
  return rotationLabel;
}

TextField _addLabel(
  DisplayObjectContainer parent,
  String text,
  num x,
  num y,
  num size,
  int color, {
  bool bold = false,
}) {
  final label = TextField(text, TextFormat('Arial', size, color, bold: bold))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
  return label;
}

Future<_ThreeExampleBridge> _waitForThree() async {
  final global = _ThreeExampleGlobal(_globalThis);
  final ready = global.stageXLThree;
  if (ready != null) return ready;
  if (global.stageXLThreeError case final error?) throw StateError(error);

  final completer = Completer<void>();
  late final JSFunction listener;
  listener = ((JSAny? _) {
    window.removeEventListener('stagexl-three-ready', listener);
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  window.addEventListener('stagexl-three-ready', listener);

  if (global.stageXLThree != null || global.stageXLThreeError != null) {
    window.removeEventListener('stagexl-three-ready', listener);
  } else {
    await completer.future;
  }

  return global.stageXLThree ?? (throw StateError(global.stageXLThreeError ?? 'Three.js did not initialize.'));
}
