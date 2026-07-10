import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
const _stageHeight = 620;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF10141D
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(
    canvas,
    width: _stageWidth,
    height: _stageHeight,
    options: options,
  );
  RenderLoop().addStage(stage);

  _addLabel(stage, 'StageXL WebGPU Graphics Gradients', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(
    stage,
    'Renderer: ${stage.renderEngine.name}',
    28,
    60,
    15,
    0xFFB9C7D8,
  );

  final linear = GraphicsGradient.linear(0, 0, 360, 160)
    ..addColorStop(0, 0xFFFF416C)
    ..addColorStop(0.5, 0xFFFFC857)
    ..addColorStop(1, 0xFF2EC4B6);
  final linearShape = Shape()
    ..x = 70
    ..y = 145;
  linearShape.graphics
    ..rectRound(0, 0, 360, 190, 26, 26)
    ..fillGradient(linear);

  final radial = GraphicsGradient.radial(180, 95, 0, 180, 95, 190)
    ..addColorStop(0, 0xFFFFFFFF)
    ..addColorStop(0.3, 0xFF7B61FF)
    ..addColorStop(1, 0xFF182131);
  final radialShape = Shape()
    ..x = 550
    ..y = 145;
  radialShape.graphics
    ..rectRound(0, 0, 360, 190, 26, 26)
    ..fillGradient(radial);

  final strokeGradient = GraphicsGradient.linear(0, 0, 760, 0)
    ..addColorStop(0, 0xFFFF5566)
    ..addColorStop(0.5, 0xFF7B61FF)
    ..addColorStop(1, 0xFF2EC4B6);
  final strokeShape = Shape()
    ..x = 110
    ..y = 425;
  strokeShape.graphics
    ..beginPath()
    ..moveTo(0, 80)
    ..bezierCurveTo(170, -60, 570, 220, 760, 30)
    ..strokeGradient(strokeGradient, 18, .ROUND, .ROUND);

  stage
    ..addChild(linearShape)
    ..addChild(radialShape)
    ..addChild(strokeShape);

  _animateGradients(stage, linear, radial, strokeGradient);
}

void _animateGradients(
  Stage stage,
  GraphicsGradient linear,
  GraphicsGradient radial,
  GraphicsGradient stroke,
) {
  stage.juggler.addTranslation(0, math.pi * 2, 6, Transition.linear, (phase) {
    final wave = math.sin(phase);
    final secondWave = math.sin(phase + math.pi / 2);

    linear
      ..startX = wave * 90
      ..endX = 360 + wave * 90;
    radial.endRadius = 150 + secondWave * 40;
    stroke
      ..startY = wave * 70
      ..endY = secondWave * 70;
  }, onComplete: () {
    _animateGradients(stage, linear, radial, stroke);
  });
}

void _addLabel(
  DisplayObjectContainer parent,
  String text,
  num x,
  num y,
  num size,
  int color,
) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
