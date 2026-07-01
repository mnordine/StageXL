import 'dart:js_interop';
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

  _addLabel(stage, 'StageXL WebGPU ChromaKeyFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Original green-screen source', 76, 436, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Bitmap ChromaKeyFilter', 366, 436, 14, 0xFFB9C7D8);
  _addLabel(stage, 'Sprite ChromaKeyFilter', 656, 436, 14, 0xFFB9C7D8);

  final bitmapData = _chromaSourceBitmapData();

  final original = Bitmap(bitmapData)
    ..x = 76
    ..y = 190;

  final bitmapFilter = ChromaKeyFilter();
  final filteredBitmap = Bitmap(bitmapData)
    ..x = 366
    ..y = 190
    ..filters = [bitmapFilter];

  final spriteFilter = ChromaKeyFilter();
  final filteredSprite = Sprite()
    ..x = 751
    ..y = 260
    ..pivotX = bitmapData.width / 2
    ..pivotY = bitmapData.height / 2
    ..filters = [spriteFilter];
  filteredSprite.addChild(Bitmap(bitmapData));

  stage
    ..addChild(_checkerBacking(52, 166))
    ..addChild(_checkerBacking(342, 166))
    ..addChild(_checkerBacking(632, 166))
    ..addChild(original)
    ..addChild(filteredBitmap)
    ..addChild(filteredSprite);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    filteredSprite.rotation = math.sin(elapsed * 0.85) * 0.14;
  });

  _bindControls(bitmapFilter, spriteFilter);
}

BitmapData _chromaSourceBitmapData() {
  final bitmapData = BitmapData(190, 140, 0xFF00FF00);

  final subject = Shape();
  subject.graphics
    ..circle(95, 44, 22)
    ..fillColor(0xFFFFD8BA)
    ..rect(57, 70, 76, 52)
    ..fillColor(0xFF4DA3FF)
    ..rect(70, 88, 50, 34)
    ..fillColor(0xFF1B2736)
    ..rect(58, 68, 74, 6)
    ..fillColor(0xFF74C0FF)
    ..circle(87, 40, 3)
    ..fillColor(0xFF1B2736)
    ..circle(103, 40, 3)
    ..fillColor(0xFF1B2736)
    ..rect(90, 49, 10, 3)
    ..fillColor(0xFFB65042)
    ..rect(47, 76, 14, 40)
    ..fillColor(0xFFFFD8BA)
    ..rect(129, 76, 14, 40)
    ..fillColor(0xFFFFD8BA);

  final edgeSpill = Shape();
  edgeSpill.graphics
    ..circle(95, 44, 25)
    ..fillColor(0xAA55FF55)
    ..rect(54, 67, 82, 58)
    ..fillColor(0x883CFF3C);

  bitmapData
    ..draw(edgeSpill)
    ..draw(subject)
    ..fillRect(Rectangle<num>(0, 0, 190, 10), 0xFF09D409)
    ..fillRect(Rectangle<num>(0, 130, 190, 10), 0xFF0AC90A);

  return bitmapData;
}

Shape _checkerBacking(num x, num y) {
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

void _bindControls(ChromaKeyFilter bitmapFilter, ChromaKeyFilter spriteFilter) {
  final solidInput = document.querySelector('#solidThreshold') as HTMLInputElement?;
  final invisibleInput = document.querySelector('#invisibleThreshold') as HTMLInputElement?;

  final solidValue = document.querySelector('#solidThresholdValue') as HTMLElement?;
  final invisibleValue = document.querySelector('#invisibleThresholdValue') as HTMLElement?;

  if (solidInput == null || invisibleInput == null) return;

  void applyValues() {
    var solidThreshold = int.tryParse(solidInput.value) ?? bitmapFilter.solidThreshold;
    var invisibleThreshold = int.tryParse(invisibleInput.value) ?? bitmapFilter.invisibleThreshold;

    solidThreshold = solidThreshold.clamp(1, 255);
    invisibleThreshold = invisibleThreshold.clamp(0, solidThreshold - 1);

    invisibleInput.value = invisibleThreshold.toString();
    solidInput.value = solidThreshold.toString();

    bitmapFilter.invisibleThreshold = invisibleThreshold;
    bitmapFilter.solidThreshold = solidThreshold;
    spriteFilter.invisibleThreshold = invisibleThreshold;
    spriteFilter.solidThreshold = solidThreshold;

    if (solidValue != null) {
      solidValue.textContent = solidThreshold.toString();
    }
    if (invisibleValue != null) {
      invisibleValue.textContent = invisibleThreshold.toString();
    }
  }

  final onInput = ((JSAny? _) {
    applyValues();
  }).toJS;

  solidInput.addEventListener('input', onInput);
  invisibleInput.addEventListener('input', onInput);
  applyValues();
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
