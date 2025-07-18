import 'package:web/web.dart';

import 'package:stagexl/stagexl.dart';

Future<void> main() async {
  StageXL.stageOptions
    ..stageAlign = StageAlign.TOP_LEFT
    ..stageScaleMode = StageScaleMode.EXACT_FIT
    ..renderEngine = RenderEngine.WebGL2;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = Stage(canvas, width: 990, height: 620);
  RenderLoop().addStage(stage);

  final resources = ResourceManager()
    ..addBitmapData('bg', 'bonus.png')
    ..addBitmapData('burst', 'BurstOfFruit.png')
    ..addBitmapData('captive', 'CaptiveHearts.png')
    ..addBitmapData('chase', 'ChaseThe8s.png')
    ..addBitmapData('cherry', 'CherryMasterDeluxe.png');

  await resources.load();

  Bitmap(resources.getBitmapData('bg')).addTo(stage);

  Bitmap(resources.getBitmapData('burst'))
    ..x = 100
    ..y = 100
    ..blendMode = BlendMode.ADD
    ..addTo(stage);

  Bitmap(resources.getBitmapData('captive'))
    ..x = 200
    ..y = 100
    ..blendMode = BlendMode.MULTIPLY
    ..addTo(stage);

  Bitmap(resources.getBitmapData('chase'))
    ..x = 100
    ..y = 200
    ..blendMode = BlendMode.SCREEN
    ..addTo(stage);

  Bitmap(resources.getBitmapData('cherry'))
    ..x = 200
    ..y = 200
    ..blendMode = BlendMode.NORMAL
    ..addTo(stage);
}
