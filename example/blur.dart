import 'dart:js_interop';
import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 760;
const _stageHeight = 460;

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

  _addLabel(stage, 'StageXL WebGPU BlurFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Original', 70, 354, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Bitmap BlurFilter', 290, 354, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Sprite BlurFilter', 510, 354, 14, 0xFFB9C7D8);

  final bitmapData = _filterBitmapData();
  final originalBitmap = Bitmap(bitmapData)
    ..x = 70
    ..y = 160;
  final bitmapBlurFilter = BlurFilter(6, 6);
  final blurredBitmap = Bitmap(bitmapData)
    ..x = 290
    ..y = 160
    ..filters = [bitmapBlurFilter];
  final spriteBlurFilter = BlurFilter(6, 6);
  final blurredSprite = Sprite()
    ..x = 595
    ..y = 220
    ..pivotX = bitmapData.width / 2
    ..pivotY = bitmapData.height / 2
    ..filters = [spriteBlurFilter];
  blurredSprite.addChild(Bitmap(bitmapData));

  stage
    ..addChild(_backing(54, 144))
    ..addChild(_backing(274, 144))
    ..addChild(_backing(494, 144))
    ..addChild(originalBitmap)
    ..addChild(blurredBitmap)
    ..addChild(blurredSprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    blurredSprite.rotation = math.sin(elapsed * 0.75) * 0.18;
  });

  _bindBlurControls(bitmapBlurFilter, spriteBlurFilter);
}

BitmapData _filterBitmapData() {
  final bitmapData = BitmapData(170, 130, 0xFF182131);
  const colors = [0xFFFF5566, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF, 0xFFEAF2FF];
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 6; x++) {
      final color = colors[(x + y * 2) % colors.length];
      bitmapData.fillRect(Rectangle<num>(12 + x * 25, 12 + y * 19, 19, 12), color);
    }
  }
  bitmapData
    ..fillRect(Rectangle<num>(44, 88, 82, 8), 0xFFFFFFFF)
    ..fillRect(Rectangle<num>(82, 50, 8, 82), 0xFFFFFFFF);
  return bitmapData;
}

Shape _backing(num x, num y) {
  final shape = Shape();
  shape.graphics
    ..rect(x, y, 202, 162)
    ..fillColor(0xFF182131)
    ..rect(x + 12, y + 12, 178, 138)
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

void _bindBlurControls(BlurFilter bitmapBlurFilter, BlurFilter spriteBlurFilter) {
  final blurXInput = document.querySelector('#blurX') as HTMLInputElement?;
  final blurYInput = document.querySelector('#blurY') as HTMLInputElement?;
  final qualityInput = document.querySelector('#blurQuality') as HTMLInputElement?;

  final blurXValue = document.querySelector('#blurXValue') as HTMLElement?;
  final blurYValue = document.querySelector('#blurYValue') as HTMLElement?;
  final qualityValue = document.querySelector('#blurQualityValue') as HTMLElement?;

  if (blurXInput == null || blurYInput == null || qualityInput == null) return;

  void applyValues() {
    final blurX = int.tryParse(blurXInput.value) ?? bitmapBlurFilter.blurX;
    final blurY = int.tryParse(blurYInput.value) ?? bitmapBlurFilter.blurY;
    final quality = int.tryParse(qualityInput.value) ?? bitmapBlurFilter.quality;

    bitmapBlurFilter
      ..blurX = blurX
      ..blurY = blurY
      ..quality = quality;

    spriteBlurFilter
      ..blurX = blurX
      ..blurY = blurY
      ..quality = quality;

    if (blurXValue != null) blurXValue.textContent = blurX.toString();
    if (blurYValue != null) blurYValue.textContent = blurY.toString();
    if (qualityValue != null) qualityValue.textContent = quality.toString();
  }

  final onInput = ((JSAny? _) {
    applyValues();
  }).toJS;

  blurXInput.addEventListener('input', onInput);
  blurYInput.addEventListener('input', onInput);
  qualityInput.addEventListener('input', onInput);
  applyValues();
}
