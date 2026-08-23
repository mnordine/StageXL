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
    ..renderEngine = .WebGPU
    ..hdr = true;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  final statistics = stage.renderContext.renderStatistics;
  final hdrState = stage.renderEngine == .WebGPU
      ? statistics.hdrEnabled ? 'HDR: on' : 'HDR: unsupported'
      : 'Renderer: ${stage.renderEngine.name}';
  _addLabel(stage, 'StageXL WebGPU HDR', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, hdrState, 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Standard Dynamic Range', 130, 436, 14, 0xFFB9C7D8);
  _addLabel(stage, 'High Dynamic Range', 620, 436, 14, 0xFFB9C7D8);

  final bitmapData = _hdrSourceBitmapData();

  final sdrSprite = Sprite()
    ..x = 250
    ..y = 260;
  sdrSprite.addChild(_glowBitmap(bitmapData));

  final hdrSprite = Sprite()
    ..x = 740
    ..y = 260;
  for (var i = 0; i < 8; i++) {
    hdrSprite.addChild(_glowBitmap(bitmapData));
  }

  stage.addChild(_backing(52, 166));
  stage.addChild(_backing(542, 166));
  stage.addChild(sdrSprite);
  stage.addChild(hdrSprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    final scale = 1.0 + math.sin(elapsed * 2.2) * 0.08;
    sdrSprite.scaleX = scale;
    sdrSprite.scaleY = scale;
    hdrSprite.scaleX = scale;
    hdrSprite.scaleY = scale;
  });
}

/// Draws the same additive glow stack twice: the right one renders with the
/// WebGPU HDR canvas and exceeds standard dynamic range white on HDR displays.
///
/// The left glow is drawn into a BitmapData first. BitmapData pixels are clamped
/// to standard dynamic range, which is exactly how the SDR reference should look.

BitmapData _hdrSourceBitmapData() {
  final bitmapData = BitmapData(240, 240, 0x00000000);
  final shape = Shape();
  shape.graphics
    ..circle(120, 120, 90)
    ..fillColor(0xFF3038FF)
    ..circle(120, 120, 60)
    ..fillColor(0xFF66CCFF)
    ..circle(120, 120, 30)
    ..fillColor(0xFFFFFFFF);
  bitmapData.draw(shape);
  return bitmapData;
}

Bitmap _glowBitmap(BitmapData source) => Bitmap(source)
  ..blendMode = .ADD
  ..scaleX = 0.35
  ..scaleY = 0.35;

Shape _backing(num x, num y) {
  final shape = Shape();
  shape.graphics
    ..rect(x, y, 386, 258)
    ..fillColor(0xFF182131)
    ..rect(x + 12, y + 12, 362, 234)
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
