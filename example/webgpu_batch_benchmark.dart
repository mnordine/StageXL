import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 1280;
const _stageHeight = 720;
const _defaultTextureCount = 8;
const _spriteSize = 48;

Future<void> main() async {
  final query = Uri.base.queryParameters;
  final engine = _engine(query['engine']);
  final spriteCount = int.tryParse(query['sprites'] ?? '') ?? 2048;
  final textureCount = int.tryParse(query['textures'] ?? '') ?? _defaultTextureCount;
  final moving = query['moving'] != 'false';
  final useBitmapContainer = query['container'] == 'bitmap';
  final antialias = query['antialias'] == 'true';
  final renderBundles = query['bundles'] == 'true';
  final scissorMasks = query['scissors'] == 'true';
  final shaderScissors = query['shader_scissors'] == 'true';
  final dualSourceBlending = query['dual_source'] == 'true';
  final mixedBlendModes = query['blend_modes'] == 'true';

  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF111720
    ..antialias = antialias
    ..renderBundles = renderBundles
    ..dualSourceBlending = dualSourceBlending
    ..renderEngine = engine;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final statsElement = document.querySelector('#stats') as HTMLPreElement;
  final stage = engine == RenderEngine.WebGPU
      ? await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options)
      : Stage(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  final textures = _createTextures(textureCount);
  final void Function(Bitmap sprite) addSprite;
  if (useBitmapContainer) {
    final spriteParent = BitmapContainer();
    stage.addChild(spriteParent);
    addSprite = spriteParent.addChild;
  } else {
    addSprite = stage.addChild;
  }
  final sprites = _createSprites(addSprite, textures, spriteCount);
  if (mixedBlendModes) {
    final blendModes = [BlendMode.NORMAL, BlendMode.ADD, BlendMode.SCREEN, BlendMode.MULTIPLY];
    for (var i = 0; i < sprites.length; i++) {
      sprites[i].blendMode = blendModes[i % blendModes.length];
    }
  }
  if (scissorMasks) {
    for (final sprite in sprites) {
      sprite.mask = shaderScissors
          ? .shaderRect(4, 4, _spriteSize - 8, _spriteSize - 8)
          : .rectangle(4, 4, _spriteSize - 8, _spriteSize - 8);
    }
  }
  _addLabel(stage, 'StageXL Batch Benchmark', 20, 20, 24, 0xFFFFFFFF);
  _addLabel(
    stage,
    'Use ?engine=webgpu or ?engine=webgl2, ?sprites=2048, ?textures=16, '
    '?moving=false, ?container=bitmap, ?bundles=true, ?scissors=true, ?shader_scissors=true, '
    '?dual_source=true, ?blend_modes=true',
    20,
    50,
    13,
    0xFFC8D3E5,
  );

  var elapsed = 0.0;
  var sampleTime = 0.0;
  var sampleCount = 0;
  var frameTimeTotal = 0.0;
  var renderObjectTotal = 0.0;
  var renderFlushTotal = 0.0;
  var webgpuBufferUploadTotal = 0.0;
  var webgpuPassEncodeTotal = 0.0;
  var webgpuSubmitTotal = 0.0;
  var batchFlushes = 0;
  var batchRuns = 0;
  var batchBlendBreaks = 0;
  var batchTextureBreaks = 0;
  var drawTotal = 0;
  var vertexTotal = 0;
  var indexTotal = 0;
  var bindGroupCreates = 0;
  var pipelineCreates = 0;
  var renderBundleBuilds = 0;
  var renderBundleHits = 0;
  var renderPasses = 0;
  var textureUploads = 0;
  var instructionBuilds = 0;
  var instructionReuses = 0;
  var instructionUploads = 0;

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
    renderObjectTotal += stats.renderObjectMicroseconds / 1000.0;
    renderFlushTotal += stats.renderFlushMicroseconds / 1000.0;
    webgpuBufferUploadTotal += stats.webgpuBufferUploadMicroseconds / 1000.0;
    webgpuPassEncodeTotal += stats.webgpuPassEncodeMicroseconds / 1000.0;
    webgpuSubmitTotal += stats.webgpuSubmitMicroseconds / 1000.0;
    batchFlushes += stats.webgpuBatchFlushCount;
    batchRuns += stats.webgpuBatchRunCount;
    batchBlendBreaks += stats.webgpuBatchBlendBreakCount;
    batchTextureBreaks += stats.webgpuBatchTextureBreakCount;
    drawTotal += stats.drawCount;
    vertexTotal += stats.vertexCount;
    indexTotal += stats.indexCount;
    bindGroupCreates += stats.webgpuBindGroupCreateCount;
    pipelineCreates += stats.webgpuPipelineCreateCount;
    renderBundleBuilds += stats.webgpuRenderBundleBuildCount;
    renderBundleHits += stats.webgpuRenderBundleCacheHitCount;
    renderPasses += stats.webgpuRenderPassCount;
    textureUploads += stats.webgpuTextureUploadCount;
    instructionBuilds += stats.webgpuInstructionBuildCount;
    instructionReuses += stats.webgpuInstructionReuseCount;
    instructionUploads += stats.webgpuInstructionUploadCount;

    if (sampleTime < 0.5) return;

    final avgFrameMs = frameTimeTotal / sampleCount;
    final avgRenderObjectMs = renderObjectTotal / sampleCount;
    final avgRenderFlushMs = renderFlushTotal / sampleCount;
    final avgWebGpuBufferUploadMs = webgpuBufferUploadTotal / sampleCount;
    final avgWebGpuPassEncodeMs = webgpuPassEncodeTotal / sampleCount;
    final avgWebGpuSubmitMs = webgpuSubmitTotal / sampleCount;
    final avgBatchFlushes = batchFlushes / sampleCount;
    final avgBatchRuns = batchRuns / sampleCount;
    final avgDraws = drawTotal / sampleCount;
    final avgVertices = vertexTotal / sampleCount;
    final avgIndices = indexTotal / sampleCount;
    final avgPasses = renderPasses / sampleCount;
    statsElement.textContent = [
      'renderer: ${stage.renderEngine.name}',
      'sprites: $spriteCount',
      'textures: $textureCount',
      'container: ${useBitmapContainer ? 'bitmap' : 'stage'}',
      'antialias: $antialias',
      'render bundles: $renderBundles',
      'scissor masks: $scissorMasks',
      'shader scissors: $shaderScissors',
      'dual-source blending: ${stage.renderContext.renderStatistics.dualSourceBlendingEnabled}',
      'mixed blend modes: $mixedBlendModes',
      'moving: $moving',
      'avg stage materialize: ${avgFrameMs.toStringAsFixed(2)} ms',
      'avg render object: ${avgRenderObjectMs.toStringAsFixed(2)} ms',
      'avg render flush: ${avgRenderFlushMs.toStringAsFixed(2)} ms',
      'avg draws/frame: ${avgDraws.toStringAsFixed(1)}',
      'avg vertices/frame: ${avgVertices.toStringAsFixed(0)}',
      'avg indices/frame: ${avgIndices.toStringAsFixed(0)}',
      'avg webgpu passes/frame: ${avgPasses.toStringAsFixed(1)}',
      'avg webgpu buffer upload: ${avgWebGpuBufferUploadMs.toStringAsFixed(2)} ms',
      'avg webgpu pass encode: ${avgWebGpuPassEncodeMs.toStringAsFixed(2)} ms',
      'avg webgpu submit: ${avgWebGpuSubmitMs.toStringAsFixed(2)} ms',
      'avg webgpu batch flushes/frame: ${avgBatchFlushes.toStringAsFixed(1)}',
      'avg webgpu batch runs/frame: ${avgBatchRuns.toStringAsFixed(1)}',
      'webgpu blend breaks/sample: $batchBlendBreaks',
      'webgpu texture breaks/sample: $batchTextureBreaks',
      'webgpu bind-group creates/sample: $bindGroupCreates',
      'webgpu pipeline creates/sample: $pipelineCreates',
      'webgpu render-bundle builds/sample: $renderBundleBuilds',
      'webgpu render-bundle hits/sample: $renderBundleHits',
      'webgpu texture uploads/sample: $textureUploads',
      'webgpu instruction builds/sample: $instructionBuilds',
      'webgpu instruction reuses/sample: $instructionReuses',
      'webgpu instruction uploads/sample: $instructionUploads',
    ].join('\n');

    sampleTime = 0;
    sampleCount = 0;
    frameTimeTotal = 0;
    renderObjectTotal = 0;
    renderFlushTotal = 0;
    webgpuBufferUploadTotal = 0;
    webgpuPassEncodeTotal = 0;
    webgpuSubmitTotal = 0;
    batchFlushes = 0;
    batchRuns = 0;
    batchBlendBreaks = 0;
    batchTextureBreaks = 0;
    drawTotal = 0;
    vertexTotal = 0;
    indexTotal = 0;
    bindGroupCreates = 0;
    pipelineCreates = 0;
    renderBundleBuilds = 0;
    renderBundleHits = 0;
    renderPasses = 0;
    textureUploads = 0;
    instructionBuilds = 0;
    instructionReuses = 0;
    instructionUploads = 0;
  });
}

RenderEngine _engine(String? value) => switch (value?.toLowerCase()) {
      'webgpu' => RenderEngine.WebGPU,
      'webgl' || 'webgl1' => RenderEngine.WebGL,
      'webgl2' => RenderEngine.WebGL2,
      'canvas' || 'canvas2d' => RenderEngine.Canvas2D,
      _ => RenderEngine.WebGL2,
    };

List<BitmapData> _createTextures(int textureCount) {
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
    for (var i = 0; i < textureCount; i++)
      BitmapData(_spriteSize, _spriteSize, 0xFF1B2635)
        ..fillRect(Rectangle<num>(4, 4, 40, 40), colors[i % colors.length])
        ..fillRect(Rectangle<num>(10, 10, 28, 10), 0x55FFFFFF)
        ..fillRect(Rectangle<num>(14, 29, 20, 8), 0x66000000),
  ];
}

List<Bitmap> _createSprites(void Function(Bitmap sprite) addSprite, List<BitmapData> textures, int count) {
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
    addSprite(sprite);
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
