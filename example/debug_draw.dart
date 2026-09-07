import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart' as html;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..renderEngine = html.window.location.search.contains('webgl') ? .WebGL2 : .WebGPU
    ..backgroundColor = 0xFF17202A;

  final canvas = html.document.querySelector('#stage') as html.HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: 960, height: 600, options: options);

  debugDraw
    ..wireframes = true
    ..wireframeColor = Color.Yellow
    ..masks = true
    ..maskColor = Color.Magenta;

  final scene = Sprite()
    ..x = 80
    ..y = 50;
  stage.addChild(scene);

  final bitmapData = BitmapData(150, 90, 0xFF8338EC);
  final bitmap = Bitmap(bitmapData)
    ..x = 520
    ..y = 430
    ..rotation = 0.15;
  scene.addChild(bitmap);

  final secondBitmap = Bitmap(BitmapData(120, 120, 0xFFFF9F1C))
    ..x = 730
    ..y = 430
    ..rotation = -0.2;
  scene.addChild(secondBitmap);

  final polygon = Shape()
    ..x = 130
    ..y = 120
    ..rotation = math.pi / 18;
  polygon.graphics
    ..moveTo(0, 120)
    ..lineTo(110, 0)
    ..lineTo(250, 45)
    ..lineTo(220, 180)
    ..lineTo(60, 220)
    ..closePath()
    ..fillColor(0xFF06D6A0);
  scene.addChild(polygon);

  final circles = Shape()
    ..x = 610
    ..y = 100
    ..rotation = -math.pi / 12;
  circles.graphics
    ..circle(120, 100, 95)
    ..fillColor(0xFFEF476F)
    ..circle(120, 100, 62)
    ..fillColor(0xFF118AB2)
    ..circle(120, 100, 28)
    ..fillColor(0xFFFFD166);
  scene.addChild(circles);

  final mesh = Shape()
    ..x = 390
    ..y = 270
    ..scaleX = 1.2
    ..scaleY = 0.85
    ..rotation = math.pi / 14;
  mesh.graphics
    ..moveTo(0, 80)
    ..lineTo(90, 0)
    ..lineTo(190, 40)
    ..lineTo(160, 150)
    ..lineTo(40, 175)
    ..closePath()
    ..fillColor(0xFF8338EC);
  mesh.mask = Mask.circle(80, 85, 70);
  scene.addChild(mesh);

  RenderLoop().addStage(stage);
}
