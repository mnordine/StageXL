import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
const _stageHeight = 520;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF0F1624
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  _addLabel(stage, 'StageXL WebGPU stacked filters', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Original', 86, 418, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Blur + Tint (stacked bitmap filters)', 326, 418, 14, 0xFFB9C7D8);
  _addLabel(stage, 'DropShadow + ColorMatrix (stacked sprite filters)', 616, 418, 14, 0xFFB9C7D8);

  final bitmapData = _sampleBitmapData();

  final originalBitmap = Bitmap(bitmapData)
    ..x = 86
    ..y = 182;

  final blurFilter = BlurFilter(7, 7, 3);
  final tintFilter = TintFilter.fromColor(0xFF6CC9FF);
  final stackedBitmap = Bitmap(bitmapData)
    ..x = 356
    ..y = 182
    ..filters = [blurFilter, tintFilter];

  final dropShadowFilter = DropShadowFilter(14, math.pi / 3, 0xCC06090E, 6, 6, 2);
  final colorMatrixFilter = ColorMatrixFilter.grayscale();
  final stackedSprite = Sprite()
    ..x = 760
    ..y = 247
    ..pivotX = bitmapData.width / 2
    ..pivotY = bitmapData.height / 2
    ..filters = [dropShadowFilter, colorMatrixFilter];
  stackedSprite.addChild(Bitmap(bitmapData));

  stage
    ..addChild(_backing(62, 164))
    ..addChild(_backing(332, 164))
    ..addChild(_backing(602, 164))
    ..addChild(originalBitmap)
    ..addChild(stackedBitmap)
    ..addChild(stackedSprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    stackedSprite.rotation = math.sin(elapsed * 0.9) * 0.16;

    final blurWaveX = (math.sin(elapsed * 2.1) + 1.0) * 0.5;
    final blurWaveY = (math.sin(elapsed * 2.1 + math.pi / 2) + 1.0) * 0.5;
    blurFilter.blurX = 4 + (blurWaveX * 24).round();
    blurFilter.blurY = 4 + (blurWaveY * 24).round();
    dropShadowFilter.distance = 8 + math.sin(elapsed * 1.1) * 6;
    dropShadowFilter.angle = elapsed * 0.75;
  });
}

BitmapData _sampleBitmapData() {
  final bitmapData = BitmapData(170, 130, 0xFF1B2538);
  const colors = [0xFFFF5E62, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF, 0xFFEAF2FF];
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 6; x++) {
      final color = colors[(x + y * 2) % colors.length];
      bitmapData.fillRect(Rectangle<num>(12 + x * 25, 12 + y * 19, 19, 12), color);
    }
  }

  bitmapData
    ..fillRect(Rectangle<num>(42, 86, 86, 9), 0xFFFFFFFF)
    ..fillRect(Rectangle<num>(80, 47, 9, 84), 0xFFFFFFFF);
  return bitmapData;
}

Shape _backing(num x, num y) {
  final shape = Shape();
  shape.graphics
    ..rect(x, y, 228, 214)
    ..fillColor(0xFF182131)
    ..rect(x + 12, y + 12, 204, 190)
    ..strokeColor(0x553A86FF, 2);
  return shape;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
