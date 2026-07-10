@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' hide Float32List;

void main() {
  test('sync Stage constructor rejects WebGPU because device creation is async', () {
    final options = StageOptions()..renderEngine = .WebGPU;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;

    expect(
      () => Stage(canvas, options: options),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Stage.create'),
      )),
    );
  });

  test('StageOptions clone preserves WebGPU render engine', () {
    final options = StageOptions()..renderEngine = .WebGPU;

    expect(options.clone().renderEngine, RenderEngine.WebGPU);
  });

  test('WebGPU renders non-scissor masks through stencil pass when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..mask = Mask.circle(24, 24, 20);
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(2));
  });

  test('WebGPU restores nested stencil masks when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final container = Sprite()
      ..x = 4
      ..y = 4
      ..mask = .circle(28, 28, 26);

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 4
      ..y = 4
      ..mask = .circle(24, 24, 18);

    container.addChild(bitmap);
    stage.addChild(container);

    expect(() => stage.materialize(0, 16), returnsNormally);
  });

  test('WebGPU renders graphics gradient fills and strokes when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 96
      ..height = 96;
    final stage = await Stage.create(canvas, width: 96, height: 96, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final linear = GraphicsGradient.linear(0, 0, 40, 0)
      ..addColorStop(0, Color.Red)
      ..addColorStop(1, Color.Blue);
    final radial = GraphicsGradient.radial(68, 24, 0, 68, 24, 20)
      ..addColorStop(0, Color.White)
      ..addColorStop(1, Color.Black);
    final stroke = GraphicsGradient.linear(8, 70, 88, 70)
      ..addColorStop(0, Color.Green)
      ..addColorStop(1, Color.Yellow);
    final shape = Shape();
    shape.graphics
      ..rect(8, 8, 40, 32)
      ..fillGradient(linear)
      ..circle(68, 24, 20)
      ..fillGradient(radial)
      ..beginPath()
      ..moveTo(8, 70)
      ..lineTo(88, 70)
      ..strokeGradient(stroke, 8);
    stage.addChild(shape);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(3));
  });

  test('WebGPU renders ColorMatrixFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [ColorMatrixFilter.grayscale()];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU renders TintFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [TintFilter.fromColor(0xFF66CCFF)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU batches TintFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = BlendMode.ADD
        ..filters = [TintFilter.fromColor(i.isEven ? 0xFFFFCC44 : 0xFF66CCFF)];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU batches color-scale ColorMatrixFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final amberFilter = ColorMatrixFilter(
      [1, 0, 0, 0, 0, 0.75, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    final blueFilter = ColorMatrixFilter(
      [0.4, 0, 0, 0, 0, 0.8, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = .ADD
        ..filters = [
          if (i.isEven) amberFilter else blueFilter,
        ];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU batches stacked color-scale bitmap filters when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final colorScaleFilter = ColorMatrixFilter(
      [1, 0, 0, 0, 0, 0.75, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, 1],
      [0, 0, 0, 0],
    );
    for (var i = 0; i < 24; i++) {
      final bitmap = Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16
        ..blendMode = BlendMode.ADD
        ..filters = [
          TintFilter.fromColor(i.isEven ? 0xFFFFCC44 : 0xFF66CCFF),
          colorScaleFilter,
        ];
      stage.addChild(bitmap);
    }

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU renders ChromaKeyFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(48, 48, 0xFF00FF00)..fillRect(Rectangle<num>(12, 12, 24, 24), Color.Red);
    final bitmap = Bitmap(bitmapData)
      ..x = 8
      ..y = 8
      ..filters = [ChromaKeyFilter()];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  test('WebGPU renders custom one-texture filter programs when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
      ..x = 8
      ..y = 8
      ..filters = [_CustomTintFilter(0.25, 0.5, 1, 1)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(1));
  });

  for (final renderEngine in [RenderEngine.WebGL, RenderEngine.WebGL2]) {
    test('$renderEngine renders custom one-texture filter programs', () {
      final options = StageOptions()
        ..renderEngine = renderEngine
        ..backgroundColor = Color.Transparent
        ..stageRenderMode = .ONCE;
      final canvas = HTMLCanvasElement()
        ..width = 64
        ..height = 64;
      final stage = Stage(canvas, width: 64, height: 64, options: options);
      if (stage.renderEngine != renderEngine) return;

      final bitmap = Bitmap(BitmapData(48, 48, Color.Red))
        ..x = 8
        ..y = 8
        ..filters = [_CustomTintFilter(0.25, 0.5, 1, 0.75)];
      stage.addChild(bitmap);

      expect(() => stage.materialize(0, 16), returnsNormally);
      expect(stage.renderContext.renderStatistics.drawCount, greaterThanOrEqualTo(1));
    });
  }

  test('WebGPU batches batch-preserving filtered display objects when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 128
      ..height = 128;
    final stage = await Stage.create(canvas, width: 128, height: 128, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmapData = BitmapData(8, 8);
    final sprite = Sprite()
      ..blendMode = .ADD
      ..filters = [TintFilter.fromColor(0xFF66CCFF)];
    for (var i = 0; i < 24; i++) {
      sprite.addChild(Bitmap(bitmapData)
        ..x = (i % 6) * 16
        ..y = (i ~/ 6) * 16);
    }
    stage.addChild(sprite);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.drawCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchFlushCount, 1);
    expect(stage.renderContext.renderStatistics.webgpuBatchRunCount, 1);
  });

  test('WebGPU renders BlurFilter bitmap quads when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final bitmap = Bitmap(BitmapData(32, 32, Color.Red))
      ..x = 16
      ..y = 16
      ..filters = [BlurFilter(5)];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(3));
  });

  test('WebGPU renders stacked bitmap filters when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != .WebGPU) return;

    final bitmap = Bitmap(BitmapData(32, 32, Color.Red))
      ..x = 16
      ..y = 16
      ..filters = [
        BlurFilter(5),
        TintFilter.fromColor(0xFF66CCFF),
      ];
    stage.addChild(bitmap);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderPassCount, greaterThanOrEqualTo(4));
  });

  test('WebGPU reuses stable batch render bundles when available', () async {
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..backgroundColor = Color.Transparent
      ..stageRenderMode = .ONCE;
    final canvas = HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    final stage = await Stage.create(canvas, width: 64, height: 64, options: options);

    if (stage.renderEngine != RenderEngine.WebGPU) return;

    final texture = BitmapData(24, 24, Color.Red);
    stage
      ..addChild(Bitmap(texture)
        ..x = 4
        ..y = 4)
      ..addChild(Bitmap(texture)
        ..x = 32
        ..y = 32);

    expect(() => stage.materialize(0, 16), returnsNormally);
    expect(() => stage.materialize(16, 16), returnsNormally);
    expect(() => stage.materialize(32, 16), returnsNormally);
    expect(stage.renderContext.renderStatistics.webgpuRenderBundleCacheHitCount, greaterThanOrEqualTo(1));
  });
}

typedef _TintParameters = ({double red, double green, double blue, double alpha});

class _CustomTintFilter extends BitmapFilter {
  static const _webGPUShaderSource = '''
      @group(0) @binding(0) var stageSampler: sampler;
      @group(0) @binding(1) var stageTexture: texture_2d<f32>;

      struct TintUniforms {
        colorScale: vec4<f32>,
      };

      @group(0) @binding(2) var<uniform> tint: TintUniforms;

      struct VertexInput {
        @location(0) clip: vec4<f32>,
        @location(1) uv: vec2<f32>,
      };

      struct VertexOutput {
        @builtin(position) position: vec4<f32>,
        @location(0) uv: vec2<f32>,
      };

      @vertex
      fn vs_main(input: VertexInput) -> VertexOutput {
        var output: VertexOutput;
        output.position = input.clip;
        output.uv = input.uv;
        return output;
      }

      @fragment
      fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
        return textureSample(stageTexture, stageSampler, input.uv) * tint.colorScale;
      }
    ''';
  static final _webGPUProgram = _TintProgramWebGPU();
  static final _programs = RenderProgramSet<_TintParameters>(
    webGL: _TintProgramWebGL(),
    webGPU: _webGPUProgram,
  );

  static void _writeUniforms(_TintParameters parameters, Float32List uniformData) {
    uniformData[0] = parameters.red;
    uniformData[1] = parameters.green;
    uniformData[2] = parameters.blue;
    uniformData[3] = parameters.alpha;
  }

  final double factorR;
  final double factorG;
  final double factorB;
  final double factorA;

  _CustomTintFilter(this.factorR, this.factorG, this.factorB, this.factorA);

  @override
  RenderProgramSet<_TintParameters> get renderPrograms => _programs;

  @override
  BitmapFilter clone() => _CustomTintFilter(factorR, factorG, factorB, factorA);

  @override
  void renderFilter(RenderFilterContext context) {
    context.render(
      _programs,
      (
        red: factorR,
        green: factorG,
        blue: factorB,
        alpha: factorA * context.renderState.globalAlpha,
      ),
    );
  }
}

final class _TintProgramWebGL extends RenderProgramSimpleWebGL<_TintParameters> {
  @override
  String get fragmentShaderSourceWebGL2 => '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec4 uTint;
    in vec2 vTextCoord;
    out vec4 fragColor;

    void main() {
      fragColor = texture(uSampler, vTextCoord) * uTint;
    }
    ''';

  @override
  String get fragmentShaderSourceWebGL1 => '''
    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec4 uTint;
    varying vec2 vTextCoord;

    void main() {
      gl_FragColor = texture2D(uSampler, vTextCoord) * uTint;
    }
    ''';

  @override
  void uploadParameters(_TintParameters parameters) {
    renderingContext.uniform4f(
      uniforms['uTint'],
      parameters.red,
      parameters.green,
      parameters.blue,
      parameters.alpha,
    );
  }
}

final class _TintProgramWebGPU extends RenderProgramSimpleWebGPU<_TintParameters> {
  _TintProgramWebGPU()
      : super(
          label: 'StageXL custom test tint filter pipeline',
          shaderSource: _CustomTintFilter._webGPUShaderSource,
          uniformByteSize: 16,
          writeUniforms: _CustomTintFilter._writeUniforms,
        );
}
