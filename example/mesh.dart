import 'dart:math' as math;
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart' hide Float32List;

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

  _addLabel(stage, 'StageXL WebGPU Mesh', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  _addLabel(stage, 'Animated grid deformation over a textured mesh', 28, 90, 14, 0xFFB9C7D8);

  final bitmapData = _meshBitmapData();
  final mesh = Mesh.fromGrid(bitmapData, 14, 10)
    ..x = 255
    ..y = 165;

  final backing = Shape();
  backing.graphics
    ..rect(239, 149, 502, 322)
    ..fillColor(0xFF182131)
    ..rect(255, 165, bitmapData.width, bitmapData.height)
    ..strokeColor(0x553A86FF, 2);

  final baseVertices = Float32List.fromList(mesh.vxList);

  stage
    ..addChild(backing)
    ..addChild(mesh);

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();

    for (var vertex = 0; vertex < mesh.vertexCount; vertex++) {
      final offset = vertex << 2;
      final baseX = baseVertices[offset + 0];
      final baseY = baseVertices[offset + 1];
      final u = baseVertices[offset + 2];
      final v = baseVertices[offset + 3];
      final dx = math.sin(elapsed * 1.2 + u * math.pi * 3.0 + v * math.pi * 1.5) * 10;
      final dy = math.cos(elapsed * 1.05 + u * math.pi * 1.4 + v * math.pi * 2.6) * 12;
      mesh.setVertex(vertex, baseX + dx, baseY + dy, u, v);
    }
  });
}

BitmapData _meshBitmapData() {
  final bitmapData = BitmapData(470, 290, 0xFF182131);
  const colors = [0xFFFF5566, 0xFFFFC857, 0xFF2EC4B6, 0xFF7B61FF, 0xFFEAF2FF];
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 13; x++) {
      final color = colors[(x + y * 2) % colors.length];
      bitmapData.fillRect(Rectangle<num>(18 + x * 34, 18 + y * 26, 26, 18), color);
    }
  }
  bitmapData
    ..fillRect(Rectangle<num>(124, 196, 220, 12), 0xFFFFFFFF)
    ..fillRect(Rectangle<num>(226, 110, 14, 134), 0xFFFFFFFF);
  return bitmapData;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
