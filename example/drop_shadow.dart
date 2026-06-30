import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
const _stageHeight = 620;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFFF7FAFF
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  _addLabel(stage, 'StageXL WebGPU DropShadowFilter', 28, 26, 26, 0xFF132038);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFF2E3A50);
  _addLabel(stage, 'Animated angle and distance', 28, 90, 14, 0xFF2E3A50);

  final bitmapData = _filterBitmapData();

  final backing = Shape();
  backing.graphics
    ..rect(210, 140, 560, 340)
    ..fillColor(0xFFFFFFFF)
    ..rect(226, 156, 528, 308)
    ..strokeColor(0x5537638A, 2);

  final shadowFilter = DropShadowFilter(
    18,
    math.pi / 3,
    0xCC101010,
    10,
    10,
    2,
  );

  final sprite = Sprite()
    ..x = 490
    ..y = 310
    ..pivotX = bitmapData.width / 2
    ..pivotY = bitmapData.height / 2
    ..filters = [shadowFilter];

  final bitmap = Bitmap(bitmapData);
  sprite.addChild(bitmap);

  stage
    ..addChild(backing)
    ..addChild(sprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    sprite.rotation = math.sin(elapsed * 0.7) * 0.16;
    shadowFilter.angle = elapsed * 0.95;
    shadowFilter.distance = 14 + math.sin(elapsed * 1.15) * 8;
  });
}

BitmapData _filterBitmapData() {
  final bitmapData = BitmapData(190, 140, 0x00000000);
  const colors = [0xFFFF5566, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF, 0xFFEAF2FF];
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 6; x++) {
      final color = colors[(x + y * 2) % colors.length];
      bitmapData.fillRect(Rectangle<num>(14 + x * 28, 14 + y * 20, 21, 13), color);
    }
  }
  bitmapData
    ..fillRect(Rectangle<num>(52, 96, 90, 9), 0xFFFFFFFF)
    ..fillRect(Rectangle<num>(92, 55, 9, 84), 0xFFFFFFFF);
  return bitmapData;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
