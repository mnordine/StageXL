import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
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

  final sourceBitmapData = _sourceBitmapData();
  final maskBitmapData = BitmapData(220, 220, 0x00000000);
  final alphaMaskFilter = AlphaMaskFilter(maskBitmapData);

  final source = Bitmap(sourceBitmapData)
    ..x = 300
    ..y = 180
    ..filters = [alphaMaskFilter];

  _addLabel(stage, 'StageXL WebGPU AlphaMaskFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Animated alpha mask over source bitmap', 28, 90, 14, 0xFFB9C7D8);

  final frame = Shape();
  frame.graphics
    ..rect(source.x - 16, source.y - 16, sourceBitmapData.width + 32, sourceBitmapData.height + 32)
    ..fillColor(0xFF182131)
    ..rect(source.x, source.y, sourceBitmapData.width, sourceBitmapData.height)
    ..strokeColor(0x553A86FF, 2);

  stage
    ..addChild(frame)
    ..addChild(source);

  final softMaskBrush = _softMaskBrush(160);
  final brushRadius = softMaskBrush.width / 2;

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    final cx = 110 + math.sin(elapsed * 1.15) * 58;
    final cy = 110 + math.cos(elapsed * 0.95) * 52;

    maskBitmapData.clear();
    maskBitmapData.draw(
      softMaskBrush,
      Matrix.fromIdentity()..translate(cx - brushRadius, cy - brushRadius),
    );

    alphaMaskFilter.matrix
      ..identity()
      ..translate(90 + math.sin(elapsed * 0.45) * 48, 70 + math.cos(elapsed * 0.4) * 40);
  });
}

BitmapData _softMaskBrush(int size) {
  final brush = BitmapData(size, size, 0x00000000);
  final center = size / 2;
  final circle = Shape();
  circle.graphics
    ..circle(center, center, center - 14)
    ..fillColor(0xFFFFFFFF);

  brush.draw(circle);
  brush.applyFilter(BlurFilter(14, 14, 2));
  return brush;
}

BitmapData _sourceBitmapData() {
  final bitmapData = BitmapData(380, 260, 0xFF182131);
  const colors = [0xFFFF5566, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF, 0xFFEAF2FF];
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 11; x++) {
      final color = colors[(x + y * 2) % colors.length];
      bitmapData.fillRect(Rectangle<num>(14 + x * 32, 14 + y * 24, 24, 16), color);
    }
  }
  bitmapData
    ..fillRect(Rectangle<num>(100, 172, 180, 10), 0xFFFFFFFF)
    ..fillRect(Rectangle<num>(184, 94, 12, 118), 0xFFFFFFFF);
  return bitmapData;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
