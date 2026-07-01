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

  _addLabel(stage, 'StageXL WebGPU compressed texture (ASTC PVR)', 28, 26, 24, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 56, 15, 0xFFB9C7D8);

  var supportsAstc = false;
  final renderContext = stage.renderContext;
  if (renderContext is RenderContextWebGPU) {
    supportsAstc = renderContext.deviceSystem.enabledFeatures.contains('texture-compression-astc');
  }

  if (!supportsAstc) {
    _addLabel(
      stage,
      'This WebGPU adapter does not expose texture-compression-astc.',
      28,
      90,
      14,
      0xFFFF8A8A,
    );
    _addLabel(
      stage,
      'Try a device/browser with ASTC support to render AcornCrunch@2x_astc.pvr.',
      28,
      112,
      14,
      0xFFFFB8B8,
    );
    return;
  }

  final atlas = await TextureAtlas.load('acorn_astc.json').atlasFuture;
  final acorn = Bitmap(atlas.getBitmapData('AcornCrunch@2x_astc'))
    ..x = 292
    ..y = 112;

  final frame = Shape();
  frame.graphics
    ..rect(270, 96, 440, 440)
    ..fillColor(0xFF182131)
    ..rect(286, 112, 408, 408)
    ..strokeColor(0x553A86FF, 2);

  final hint = TextField(
    'Loaded through TextureAtlas -> PVR -> WebGPU compressed upload',
    TextFormat('Arial', 14, 0xFFB9C7D8),
  )
    ..x = 280
    ..y = 548
    ..autoSize = TextFieldAutoSize.LEFT;

  stage
    ..addChild(frame)
    ..addChild(acorn)
    ..addChild(hint);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    acorn.rotation = math.sin(elapsed * 0.9) * 0.08;
    acorn.scaleX = 0.97 + math.sin(elapsed * 0.7) * 0.03;
    acorn.scaleY = 0.97 + math.cos(elapsed * 0.7) * 0.03;
  });
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
