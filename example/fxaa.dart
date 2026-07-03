import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
const _stageHeight = 560;

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

  _addLabel(stage, 'StageXL WebGPU FxaaFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Original', 76, 436, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Bitmap FxaaFilter', 366, 436, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Sprite FxaaFilter', 656, 436, 14, 0xFFB9C7D8);

  final bitmapData = _fxaaSourceBitmapData();

  final original = Bitmap(bitmapData)
    ..x = 76
    ..y = 190;

  final bitmapFilter = FxaaFilter();
  final filteredBitmap = Bitmap(bitmapData)
    ..x = 366
    ..y = 190
    ..filters = [bitmapFilter];

  final spriteFilter = FxaaFilter();
  final filteredSprite = Sprite()
    ..x = 751
    ..y = 260
    ..pivotX = bitmapData.width / 2
    ..pivotY = bitmapData.height / 2
    ..filters = [spriteFilter];
  filteredSprite.addChild(Bitmap(bitmapData));

  stage
    ..addChild(_backing(52, 166))
    ..addChild(_backing(342, 166))
    ..addChild(_backing(632, 166))
    ..addChild(original)
    ..addChild(filteredBitmap)
    ..addChild(filteredSprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    filteredSprite.rotation = math.sin(elapsed * 0.85) * 0.16;
  });
}

BitmapData _fxaaSourceBitmapData() {
  final bitmapData = BitmapData(190, 140, 0xFF161E2D);

  final shape = Shape();
  shape.graphics
    ..moveTo(12, 116)
    ..lineTo(70, 20)
    ..lineTo(88, 20)
    ..lineTo(30, 116)
    ..lineTo(12, 116)
    ..fillColor(0xFFF2F6FF)
    ..moveTo(63, 116)
    ..lineTo(121, 20)
    ..lineTo(139, 20)
    ..lineTo(81, 116)
    ..lineTo(63, 116)
    ..fillColor(0xFFF2F6FF)
    ..moveTo(114, 116)
    ..lineTo(172, 20)
    ..lineTo(178, 30)
    ..lineTo(126, 116)
    ..lineTo(114, 116)
    ..fillColor(0xFFF2F6FF)
    ..moveTo(11, 102)
    ..lineTo(79, 102)
    ..lineTo(75, 110)
    ..lineTo(7, 110)
    ..lineTo(11, 102)
    ..fillColor(0xFFFF5C72)
    ..moveTo(62, 84)
    ..lineTo(130, 84)
    ..lineTo(126, 92)
    ..lineTo(58, 92)
    ..lineTo(62, 84)
    ..fillColor(0xFFFFC857)
    ..moveTo(113, 66)
    ..lineTo(181, 66)
    ..lineTo(177, 74)
    ..lineTo(109, 74)
    ..lineTo(113, 66)
    ..fillColor(0xFF2EC4B6)
    ..moveTo(14, 20)
    ..lineTo(176, 20)
    ..lineTo(176, 28)
    ..lineTo(14, 28)
    ..lineTo(14, 20)
    ..fillColor(0xFF6E7FA9);

  bitmapData.draw(shape);
  return bitmapData;
}

Shape _backing(num x, num y) {
  final shape = Shape();
  const outerWidth = 238;
  const outerHeight = 258;
  const innerX = 12;
  const innerY = 12;
  const innerWidth = 214;
  const innerHeight = 234;
  const tileSize = 18;

  shape.graphics
    ..rect(x, y, outerWidth, outerHeight)
    ..fillColor(0xFF182131);

  for (var py = 0; py < innerHeight; py += tileSize) {
    for (var px = 0; px < innerWidth; px += tileSize) {
      final tileColor = ((px ~/ tileSize) + (py ~/ tileSize)).isEven ? 0xFF2A344A : 0xFF1F283B;
      shape.graphics
        ..rect(x + innerX + px, y + innerY + py, tileSize, tileSize)
        ..fillColor(tileColor);
    }
  }

  shape.graphics
    ..rect(x + innerX, y + innerY, innerWidth, innerHeight)
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
