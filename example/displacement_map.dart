import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 1280;
const _stageHeight = 780;

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

  final mapBitmapData = await BitmapData.load('displacement.webp');

  final displacementFilter = DisplacementMapFilter(mapBitmapData, null, 96, 72);

  final panel = Shape();
  panel.graphics
    ..rect(96, 180, 1088, 420)
    ..fillColor(0xFF182131)
    ..rect(108, 192, 1064, 396)
    ..strokeColor(0x553A86FF, 2);

  final text = TextField(
    'STAGEXL',
    TextFormat(
      'Arial Black',
      230,
      0xFFEAF2FF,
      bold: true,
      strokeWidth: 6,
      strokeColor: 0xFF5AC8FF,
    ),
  )
    ..x = 148
    ..y = 234
    ..filters = [displacementFilter]
    ..autoSize = TextFieldAutoSize.LEFT;

  _addLabel(stage, 'StageXL WebGPU DisplacementMapFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Animated displacement.webp map over a large text field', 28, 90, 14, 0xFFB9C7D8);

  stage
    ..addChild(panel)
    ..addChild(text);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    final pointerX = (stage.mousePosition.x / _stageWidth).clamp(0.0, 1.0);
    final pointerY = (stage.mousePosition.y / _stageHeight).clamp(0.0, 1.0);
    final dynamicMapScaleX = 0.72 + pointerX * 0.5;
    final dynamicMapScaleY = 0.72 + pointerY * 0.5;

    displacementFilter.matrix
      ..identity()
      ..scale(
        dynamicMapScaleX + math.sin(elapsed * 0.33) * 0.08,
        dynamicMapScaleY + math.cos(elapsed * 0.27) * 0.08,
      )
      ..rotate(math.sin(elapsed * 0.22) * 0.22)
      ..translate(
        90 + math.sin(elapsed * 0.61) * 140 + stage.mousePosition.x * 0.04,
        70 + math.cos(elapsed * 0.51) * 120 + stage.mousePosition.y * 0.04,
      );
  });
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
