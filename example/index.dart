import 'package:web/web.dart' as html;
import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';

void main() {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..renderEngine = .WebGL;

  final canvas = html.document.querySelector('#stage') as html.HTMLCanvasElement;
  final stage = Stage(canvas, width: 990, height: 620, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  final bitmapData = BitmapData(100, 100, Color.Red);
  final bitmap = Bitmap(bitmapData);
  bitmap.x = 100;
  bitmap.y = 100;
  bitmap.rotation = math.pi / 4;
  stage.addChild(bitmap);
}
