import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 1280;
const _stageHeight = 720;
const _textureCount = 8;
const _spriteSize = 48;

Future<void> main() async {
  final query = Uri.base.queryParameters;
  final engine = _engine(query['engine']);
  final spriteCount = int.tryParse(query['sprites'] ?? '') ?? 2048;
  final moving = query['moving'] != 'false';

  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF111720
    ..renderEngine = engine;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final statsElement = document.querySelector('#stats') as HTMLPreElement;
  final stage = engine == RenderEngine.WebGPU
      ? await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options)
      : Stage(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  final textures = _createTextures();
  final sprites = _createSprites(stage, textures, spriteCount);
  _addLabel(stage, 'StageXL Batch Benchmark', 20, 20, 24, 0xFFFFFFFF);
  _addLabel(stage, 'Use ?engine=webgpu or ?engine=webgl2, ?sprites=2048, ?moving=false', 20, 50, 13, 0xFFC8D3E5);

  var elapsed = 0.0;
  var sampleTime = 0.0;
  var sampleCount = 0;
  var frameTimeTotal = 0.0;
  var drawTotal = 0;
  var vertexTotal = 0;
  var indexTotal = 0;
  var bindGroupCreates = 0;
  var pipelineCreates = 0;
  var renderPasses = 0;
  var textureUploads = 0;

  stage.onEnterFrame.listen((event) {
    final delta = event.passedTime.toDouble();
    elapsed += delta;
    if (!moving) return;

    for (var i = 0; i < sprites.length; i++) {
      final sprite = sprites[i];
      final row = i ~/ 64;
      sprite.x += math.sin(elapsed * 1.7 + i * 0.031) * 0.08;
      sprite.y += math.cos(elapsed * 1.3 + row * 0.27) * 0.08;
    }
  });

  stage.onExitFrame.listen((_) {
    final stats = stage.renderContext.renderStatistics;
    final frameTime = stats.frameTimeMicroseconds / 1000.0;
    sampleTime += frameTime / 1000.0;
    sampleCount++;
    frameTimeTotal += frameTime;
    drawTotal += stats.drawCount;
    vertexTotal += stats.vertexCount;
    indexTotal += stats.indexCount;
    bindGroupCreates += stats.webgpuBindGroupCreateCount;
    pipelineCreates += stats.webgpuPipelineCreateCount;
    renderPasses += stats.webgpuRenderPassCount;
    textureUploads += stats.webgpuTextureUploadCount;

    if (sampleTime < 0.5) return;

    final avgFrameMs = frameTimeTotal / sampleCount;
    final avgDraws = drawTotal / sampleCount;
    final avgVertices = vertexTotal / sampleCount;
    final avgIndices = indexTotal / sampleCount;
    final avgPasses = renderPasses / sampleCount;
    statsElement.textContent = [
      'renderer: ${stage.renderEngine.name}',
      'sprites: $spriteCount',
      'textures: $_textureCount',
      'moving: $moving',
      'avg stage materialize: ${avgFrameMs.toStringAsFixed(2)} ms',
      'avg draws/frame: ${avgDraws.toStringAsFixed(1)}',
      'avg vertices/frame: ${avgVertices.toStringAsFixed(0)}',
      'avg indices/frame: ${avgIndices.toStringAsFixed(0)}',
      'avg webgpu passes/frame: ${avgPasses.toStringAsFixed(1)}',
      'webgpu bind-group creates/sample: $bindGroupCreates',
      'webgpu pipeline creates/sample: $pipelineCreates',
      'webgpu texture uploads/sample: $textureUploads',
    ].join('\n');

    sampleTime = 0;
    sampleCount = 0;
    frameTimeTotal = 0;
    drawTotal = 0;
    vertexTotal = 0;
    indexTotal = 0;
    bindGroupCreates = 0;
    pipelineCreates = 0;
    renderPasses = 0;
    textureUploads = 0;
  });
}

RenderEngine _engine(String? value) => switch (value?.toLowerCase()) {
      'webgpu' => RenderEngine.WebGPU,
      'canvas' || 'canvas2d' => RenderEngine.Canvas2D,
      _ => RenderEngine.WebGL2,
    };

List<BitmapData> _createTextures() {
  const colors = [
    0xFFFFC857,
    0xFF7B61FF,
    0xFF2EC4B6,
    0xFFFF5566,
    0xFFEAF2FF,
    0xFFB86BFF,
    0xFFFFA600,
    0xFF62D96B,
  ];

  return [
    for (var i = 0; i < _textureCount; i++)
      BitmapData(_spriteSize, _spriteSize, 0xFF1B2635)
        ..fillRect(Rectangle<num>(4, 4, 40, 40), colors[i])
        ..fillRect(Rectangle<num>(10, 10, 28, 10), 0x55FFFFFF)
        ..fillRect(Rectangle<num>(14, 29, 20, 8), 0x66000000),
  ];
}

List<Bitmap> _createSprites(Stage stage, List<BitmapData> textures, int count) {
  final sprites = <Bitmap>[];
  const columns = 64;
  const xSpacing = 19;
  const ySpacing = 20;

  for (var i = 0; i < count; i++) {
    final texture = textures[i % textures.length];
    final sprite = Bitmap(texture)
      ..x = 16 + (i % columns) * xSpacing
      ..y = 88 + (i ~/ columns) * ySpacing
      ..scaleX = 0.38
      ..scaleY = 0.38;
    sprites.add(sprite);
    stage.addChild(sprite);
  }

  return sprites;
}

void _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
}
