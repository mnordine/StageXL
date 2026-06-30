import 'dart:js_interop';
import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 1280;
const _stageHeight = 780;

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

  final diffuseBitmapData = await BitmapData.load('bg.png');
  final normalBitmapData = await BitmapData.load('bg_n.png');

  final filter = NormalMapFilter(normalBitmapData)
    ..ambientColor = 0xCC303844
    ..lightColor = 0xFFFFF2CC
    ..lightZ = 90
    ..lightRadius = 480;

  final scale = math.min(1080 / diffuseBitmapData.width, 620 / diffuseBitmapData.height);
  final bitmap = Bitmap(diffuseBitmapData)
    ..x = 100
    ..y = 120
    ..scaleX = scale
    ..scaleY = scale
    ..filters = [filter];

  final frame = Shape();
  frame.graphics
    ..rect(bitmap.x - 16, bitmap.y - 16, diffuseBitmapData.width * scale + 32, diffuseBitmapData.height * scale + 32)
    ..fillColor(0xFF182131)
    ..rect(bitmap.x, bitmap.y, diffuseBitmapData.width * scale, diffuseBitmapData.height * scale)
    ..strokeColor(0x553A86FF, 2);

  _addLabel(stage, 'StageXL WebGPU NormalMapFilter', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Move pointer to position light', 28, 90, 14, 0xFFB9C7D8);

  stage
    ..addChild(frame)
    ..addChild(bitmap);

  _bindNormalMapControls(filter);

  stage.onEnterFrame.listen((event) {
    final local = bitmap.globalToLocal(stage.mousePosition);
    filter.lightX = local.x;
    filter.lightY = local.y;
  });
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}

void _bindNormalMapControls(NormalMapFilter filter) {
  final ambientColorInput = document.querySelector('#ambientColor') as HTMLInputElement?;
  final lightColorInput = document.querySelector('#lightColor') as HTMLInputElement?;
  final lightZInput = document.querySelector('#lightZ') as HTMLInputElement?;
  final lightRadiusInput = document.querySelector('#lightRadius') as HTMLInputElement?;
  final lightZValue = document.querySelector('#lightZValue') as HTMLElement?;
  final lightRadiusValue = document.querySelector('#lightRadiusValue') as HTMLElement?;

  if (ambientColorInput == null ||
      lightColorInput == null ||
      lightZInput == null ||
      lightRadiusInput == null) {
    return;
  }

  ambientColorInput.value = _rgbHex(filter.ambientColor);
  lightColorInput.value = _rgbHex(filter.lightColor);
  lightZInput.value = filter.lightZ.round().toString();
  lightRadiusInput.value = filter.lightRadius.round().toString();

  void applyControls() {
    filter.ambientColor = _mergeColorRgb(filter.ambientColor, ambientColorInput.value);
    filter.lightColor = _mergeColorRgb(filter.lightColor, lightColorInput.value);
    filter.lightZ = num.tryParse(lightZInput.value) ?? filter.lightZ;
    filter.lightRadius = num.tryParse(lightRadiusInput.value) ?? filter.lightRadius;

    if (lightZValue != null) lightZValue.textContent = filter.lightZ.round().toString();
    if (lightRadiusValue != null) lightRadiusValue.textContent = filter.lightRadius.round().toString();
  }

  final onInput = ((JSAny? _) {
    applyControls();
  }).toJS;

  ambientColorInput.addEventListener('input', onInput);
  lightColorInput.addEventListener('input', onInput);
  lightZInput.addEventListener('input', onInput);
  lightRadiusInput.addEventListener('input', onInput);
  applyControls();
}

String _rgbHex(int color) {
  final rgb = color & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

int _mergeColorRgb(int color, String hexRgb) {
  final rgb = int.tryParse(hexRgb.replaceFirst('#', ''), radix: 16);
  if (rgb == null) return color;
  return (color & 0xFF000000) | rgb;
}
