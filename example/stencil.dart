import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 990;
const _stageHeight = 620;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF10141D
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  _addLabel(stage, 'StageXL WebGPU stencil masks', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Single animated circle mask', 110, 104, 15, 0xFFDDE8F7);
  _addLabel(stage, 'Nested circle + star masks', 570, 104, 15, 0xFFDDE8F7);

  final singleMask = Mask.circle(0, 0, 92);
  final singleGrid = _tileGrid(10, 8, 28, const [0xFFFF5566, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF])
    ..x = 82
    ..y = 144
    ..mask = singleMask;
  final singleGuide = _circleGuide(92, 0xAAFFFFFF);
  stage
    ..addChild(singleGrid)
    ..addChild(singleGuide);

  final outerMask = Mask.circle(0, 0, 135);
  final starMask = Mask.graphics(_starGraphics(0, 0, 96, 42, 10));
  final nestedGroup = Sprite()
    ..x = 540
    ..y = 135
    ..mask = outerMask;
  final nestedGrid = _tileGrid(12, 9, 24, const [0xFF4CC9F0, 0xFFF72585, 0xFFB8F35D, 0xFFFFB703])
    ..x = 18
    ..y = 24
    ..mask = starMask;
  final restoreBand = _rectShape(26, 264, 270, 24, 0xFFEAF2FF);
  final restoreBandAccent = _rectShape(26, 264, 270, 24, 0x553A86FF);
  final outerGuide = _circleGuide(135, 0x88FFFFFF);
  final starGuide = Shape()
    ..graphics = _starGraphics(0, 0, 96, 42, 10, fillColor: null, strokeColor: 0xCCFFFFFF)
    ..alpha = 0.8;

  nestedGroup
    ..addChild(nestedGrid)
    ..addChild(restoreBand)
    ..addChild(restoreBandAccent)
    ..addChild(starGuide);
  stage
    ..addChild(nestedGroup)
    ..addChild(outerGuide);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    final singleX = 222 + math.sin(elapsed * 1.3) * 58;
    final singleY = 247 + math.cos(elapsed * 0.9) * 34;
    singleMask.transformationMatrix
      ..identity()
      ..translate(singleX - singleGrid.x, singleY - singleGrid.y);
    singleGuide
      ..x = singleX
      ..y = singleY;

    final outerX = nestedGroup.x + 154 + math.sin(elapsed * 0.65) * 18;
    final outerY = nestedGroup.y + 145 + math.cos(elapsed * 0.7) * 16;
    outerMask.transformationMatrix
      ..identity()
      ..translate(outerX - nestedGroup.x, outerY - nestedGroup.y);
    outerGuide
      ..x = outerX
      ..y = outerY;

    final starX = 156 + math.sin(elapsed * 1.1) * 48;
    final starY = 136 + math.cos(elapsed * 0.85) * 26;
    final starRotation = elapsed * 0.75;
    starMask.transformationMatrix.createBox(1, 1, starRotation, starX - nestedGrid.x, starY - nestedGrid.y);
    starGuide.transformationMatrix.createBox(
      1,
      1,
      starRotation,
      nestedGrid.x + starX,
      nestedGrid.y + starY,
    );
  });
}

Sprite _tileGrid(int columns, int rows, int size, List<int> colors) {
  final sprite = Sprite();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      final color = colors[(x + y * 2) % colors.length];
      sprite.addChild(_rectShape(x * size, y * size, size - 2, size - 2, color));
    }
  }
  return sprite;
}

Shape _rectShape(num x, num y, num width, num height, int color) {
  final shape = Shape()
    ..x = x
    ..y = y;
  shape.graphics
    ..rect(0, 0, width, height)
    ..fillColor(color);
  return shape;
}

Shape _circleGuide(num radius, int color) {
  final shape = Shape();
  shape.graphics
    ..circle(0, 0, radius)
    ..strokeColor(color, 3);
  return shape;
}

Graphics _starGraphics(
  num centerX,
  num centerY,
  num outerRadius,
  num innerRadius,
  int points, {
  int? fillColor = 0xFFFF00FF,
  int? strokeColor,
}) {
  final graphics = Graphics()..beginPath();
  for (var i = 0; i < points * 2; i++) {
    final radius = i.isEven ? outerRadius : innerRadius;
    final angle = -math.pi / 2 + i * math.pi / points;
    final x = centerX + math.cos(angle) * radius;
    final y = centerY + math.sin(angle) * radius;
    if (i == 0) {
      graphics.moveTo(x, y);
    } else {
      graphics.lineTo(x, y);
    }
  }
  graphics.closePath();
  if (fillColor != null) graphics.fillColor(fillColor);
  if (strokeColor != null) graphics.strokeColor(strokeColor, 3);
  return graphics;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
