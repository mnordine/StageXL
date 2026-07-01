import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 980;
const _stageHeight = 620;
const _symbolWidth = 156;
const _symbolHeight = 135;

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

  _addLabel(stage, 'StageXL WebGPU Honeycomb Pattern', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Hexagon GraphicsPath filled with GraphicsPattern.repeatY', 28, 90, 14, 0xFFB9C7D8);

  final symbolStrip = _createSymbolStrip();
  final cells = [
    (x: 80, y: 190, symbol: 0),
    (x: 214, y: 116, symbol: 1),
    (x: 214, y: 264, symbol: 4),
    (x: 348, y: 190, symbol: 7),
    (x: 482, y: 116, symbol: 2),
    (x: 482, y: 264, symbol: 5),
    (x: 616, y: 190, symbol: 8),
  ];

  for (final cell in cells) {
    stage.addChild(_honeycombCell(symbolStrip, cell.symbol)
      ..x = cell.x
      ..y = cell.y);
  }
}

BitmapData _createSymbolStrip() {
  final bitmapData = BitmapData(_symbolWidth, _symbolHeight * 9, 0xFF2A1608);
  const colors = [
    0xFFFFC857,
    0xFF7B61FF,
    0xFF2EC4B6,
    0xFFFF5566,
    0xFFEAF2FF,
    0xFFB86BFF,
    0xFFFFA600,
    0xFF62D96B,
    0xFFFFE066,
  ];

  for (var symbol = 0; symbol < colors.length; symbol++) {
    final top = symbol * _symbolHeight;
    bitmapData
      ..fillRect(Rectangle<num>(0, top, _symbolWidth, _symbolHeight), 0xFF3B210F)
      ..fillRect(Rectangle<num>(22, top + 18, 112, 92), colors[symbol])
      ..fillRect(Rectangle<num>(36, top + 34, 84, 20), 0x66FFFFFF)
      ..fillRect(Rectangle<num>(56, top + 68, 44, 18), 0x66000000);
  }

  return bitmapData;
}

Shape _honeycombCell(BitmapData symbolStrip, int symbol) {
  final transform = Matrix.fromIdentity()
    ..translate(0, symbol * _symbolHeight);
  final pattern = GraphicsPattern.repeatY(symbolStrip.renderTextureQuad, transform);
  final shape = Shape();

  shape.graphics
    ..beginPath()
    ..moveTo(31, 0)
    ..lineTo(120, 0)
    ..lineTo(156, 67)
    ..lineTo(120, 135)
    ..lineTo(31, 135)
    ..lineTo(0, 67)
    ..closePath()
    ..fillPattern(pattern)
    ..beginPath()
    ..moveTo(31, 0)
    ..lineTo(120, 0)
    ..lineTo(156, 67)
    ..lineTo(120, 135)
    ..lineTo(31, 135)
    ..lineTo(0, 67)
    ..closePath()
    ..strokeColor(0xFFFFB13B, 4);

  return shape;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
