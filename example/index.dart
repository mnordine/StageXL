import 'package:web/web.dart';
import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  // final stage = Stage(canvas, width: 990, height: 620, options: options);
  final stage = await Stage.create(canvas, width: 990, height: 620, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  final bitmapData = BitmapData(100, 100, Color.Red);
  final bitmap = Bitmap(bitmapData);
  bitmap.x = 100;
  bitmap.y = 100;
  bitmap.rotation = math.pi / 4;
  stage.addChild(bitmap);
}
