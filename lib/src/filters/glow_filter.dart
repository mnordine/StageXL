library;

import 'dart:js_interop';
import 'dart:math' hide Point, Rectangle;

import '../display.dart';
import '../engine.dart';
import '../geom.dart';
import '../internal/filter_helpers.dart';
import '../internal/tools.dart';

class GlowFilter extends BitmapFilter {
  static const _singlePassSources = [0];
  static const _singlePassTargets = [1];

  // Collapses each half of the seven-tap kernel while preserving its total weight and variance.
  static const _singlePassOffset = 0.5149258588391167;

  static final _programs = RenderProgramSet<GlowFilter>(
    webGL: RenderProgramWebGL.callback(_renderWebGL),
    webGPU: RenderProgramWebGPU.callback(_renderWebGPU),
  );

  var color = 0xFF000000;
  late int _blurX;
  late int _blurY;
  late int _quality;

  var knockout = false;
  var hideObject = false;

  final _renderPassSources = <int>[];
  final _renderPassTargets = <int>[];

  GlowFilter(
      [this.color = 0xFF000000,
      int blurX = 4,
      int blurY = 4,
      int quality = 1,
      this.knockout = false,
      this.hideObject = false]) {
    this.blurX = blurX;
    this.blurY = blurY;
    this.quality = quality;
  }

  //---------------------------------------------------------------------------

  @override
  BitmapFilter clone() =>
      GlowFilter(color, blurX, blurY, quality, knockout, hideObject);

  @override
  RenderProgramSet<GlowFilter> get renderPrograms => _programs;

  @override
  Rectangle<int> get overlap =>
      Rectangle<int>(-blurX, -blurY, 2 * blurX, 2 * blurY);

  @override
  List<int> get renderPassSources => _renderPassSources;

  @override
  List<int> get renderPassTargets => _renderPassTargets;

  @override
  List<int> renderPassSourcesFor(RenderEngine renderEngine) =>
      renderEngine == .WebGPU || renderEngine == .WebGL2 ? _singlePassSources : renderPassSources;

  @override
  List<int> renderPassTargetsFor(RenderEngine renderEngine) =>
      renderEngine == .WebGPU || renderEngine == .WebGL2 ? _singlePassTargets : renderPassTargets;

  //---------------------------------------------------------------------------

  /// The horizontal blur radius in the range from 0 to 64.

  int get blurX => _blurX;

  set blurX(int value) {
    RangeError.checkValueInInterval(value, 0, 64);
    _blurX = value;
  }

  /// The vertical blur radius in the range from 0 to 64.

  int get blurY => _blurY;

  set blurY(int value) {
    RangeError.checkValueInInterval(value, 0, 64);
    _blurY = value;
  }

  /// The quality of the glow in the range from 1 to 5.
  /// A small value is sufficent for small blur radii, a high blur
  /// radius may require a heigher quality setting.

  int get quality => _quality;

  set quality(int value) {
    RangeError.checkValueInInterval(value, 1, 5);

    _quality = value;
    _renderPassSources.clear();
    _renderPassTargets.clear();

    for (var i = 0; i < value; i++) {
      _renderPassSources.add(i * 2 + 0);
      _renderPassSources.add(i * 2 + 1);
      _renderPassTargets.add(i * 2 + 1);
      _renderPassTargets.add(i * 2 + 2);
    }

    _renderPassSources.add(0);
    _renderPassTargets.add(value * 2);
  }

  //---------------------------------------------------------------------------

  @override
  void apply(BitmapData bitmapData, [Rectangle<num>? rectangle]) {
    final renderTextureQuad = rectangle == null
        ? bitmapData.renderTextureQuad
        : bitmapData.renderTextureQuad.cut(rectangle);

    final sourceImageData = hideObject == false || knockout
        ? renderTextureQuad.getImageData()
        : null;

    final imageData = renderTextureQuad.getImageData();
    final data = imageData.data.toDart;
    final width = imageData.width;
    final height = imageData.height;

    final pixelRatio = renderTextureQuad.pixelRatio;
    final blurX = (this.blurX * pixelRatio).round();
    final blurY = (this.blurY * pixelRatio).round();
    final alphaChannel =
        BitmapDataChannel.getCanvasIndex(BitmapDataChannel.ALPHA);
    final stride = width * 4;

    for (var x = 0; x < width; x++) {
      blur(data, x * 4 + alphaChannel, height, stride, blurY);
    }

    for (var y = 0; y < height; y++) {
      blur(data, y * stride + alphaChannel, width, 4, blurX);
    }

    if (knockout) {
      setColorKnockout(data, color, sourceImageData!.data.toDart);
    } else if (hideObject) {
      setColor(data, color);
    } else {
      setColorBlend(data, color, sourceImageData!.data.toDart);
    }

    renderTextureQuad.putImageData(imageData);
  }

  //---------------------------------------------------------------------------

  @override
  void renderFilter(RenderFilterContext context) => context.render(_programs, this);

  static ({int passCount, num radiusX, num radiusY}) _parameters(
    RenderFilterContext context,
    GlowFilter filter,
  ) {
    final renderTexture = context.renderTextureQuad.renderTexture;
    if (context.renderContext.renderEngine == .WebGPU || context.renderContext.renderEngine == .WebGL2) {
      final pixelRatio = sqrt(context.renderState.globalMatrix.det.abs());
      final qualityScale = sqrt((1.0 - pow(0.25, filter.quality)) / 0.75);
      return (
        passCount: 1,
        radiusX: pixelRatio * filter.blurX / renderTexture.width * _singlePassOffset * qualityScale,
        radiusY: pixelRatio * filter.blurY / renderTexture.height * _singlePassOffset * qualityScale,
      );
    }
    final passCount = filter._renderPassSources.length;
    final passScale = pow(0.5, context.pass >> 1);
    final pixelRatio = sqrt(context.renderState.globalMatrix.det.abs());
    final pixelRatioScale = pixelRatio * passScale;
    return (
      passCount: passCount,
      radiusX: context.pass.isEven ? pixelRatioScale * filter.blurX / renderTexture.width : 0.0,
      radiusY: context.pass.isEven ? 0.0 : pixelRatioScale * filter.blurY / renderTexture.height,
    );
  }

  static void _renderWebGPU(RenderFilterContext context, GlowFilter filter) {
      final renderContext = context.renderContext as RenderContextWebGPU;
      final parameters = _parameters(context, filter);
      if (parameters.passCount == 1) {
        renderContext.filterSystem.renderGlowFilterQuad(
          context.renderState,
          context.renderTextureQuad,
          filter.color,
          context.renderState.globalAlpha,
          parameters.radiusX,
          parameters.radiusY,
          sourceMode: filter.knockout ? 2 : filter.hideObject ? 0 : 1,
        );
        return;
      }
      if (context.pass == parameters.passCount - 1) {
        if (!filter.knockout && !filter.hideObject) {
          renderContext.renderTextureQuad(context.renderState, context.renderTextureQuad);
        }
      } else {
        renderContext.filterSystem.renderGlowFilterQuad(
          context.renderState,
          context.renderTextureQuad,
          context.pass == parameters.passCount - 2 ? filter.color : filter.color | 0xFF000000,
          context.pass == parameters.passCount - 2 ? context.renderState.globalAlpha : 1.0,
          parameters.radiusX,
          parameters.radiusY,
        );
      }
  }

  static void _renderWebGL(RenderFilterContext context, GlowFilter filter) {
    final renderContext = context.renderContext as RenderContextWebGL;
    final parameters = _parameters(context, filter);
    if (parameters.passCount == 1) {
      final renderTexture = context.renderTextureQuad.renderTexture;
      final renderProgram = renderContext.getRenderProgram(
          r'$GlowFilterProgramWebGL', GlowFilterProgramWebGL.new);
      renderContext.activateRenderProgram(renderProgram);
      renderContext.activateRenderTexture(renderTexture);
      renderProgram.configure(
        filter.color,
        context.renderState.globalAlpha,
        parameters.radiusX,
        parameters.radiusY,
        sourceMode: filter.knockout ? 2 : filter.hideObject ? 0 : 1,
      );
      renderProgram.renderTextureQuad(context.renderState, context.renderTextureQuad);
      renderProgram.flush();
      return;
    }
    if (context.pass == parameters.passCount - 1) {
      if (!filter.knockout && !filter.hideObject) {
        renderContext.renderTextureQuad(context.renderState, context.renderTextureQuad);
      }
    } else {
      final renderTexture = context.renderTextureQuad.renderTexture;
      final renderProgram = renderContext.getRenderProgram(
          r'$GlowFilterProgramWebGL', GlowFilterProgramWebGL.new);
      renderContext.activateRenderProgram(renderProgram);
      renderContext.activateRenderTexture(renderTexture);
      renderProgram.configure(
        context.pass == parameters.passCount - 2 ? filter.color : filter.color | 0xFF000000,
        context.pass == parameters.passCount - 2 ? context.renderState.globalAlpha : 1.0,
        parameters.radiusX,
        parameters.radiusY,
      );
      renderProgram.renderTextureQuad(context.renderState, context.renderTextureQuad);
      renderProgram.flush();
    }
  }
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------

class GlowFilterProgramWebGL extends RenderProgramSimpleWebGL<GlowFilter> {
  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;
    uniform vec2 uRadius;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;

    out vec2 vTextCoord;

    void main() {
      vTextCoord = aVertexTextCoord;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    uniform vec2 uRadius;

    attribute vec2 aVertexPosition;
    attribute vec2 aVertexTextCoord;

    varying vec2 vBlurCoords[7];

    void main() {
      vBlurCoords[0] = aVertexTextCoord - uRadius * 1.2;
      vBlurCoords[1] = aVertexTextCoord - uRadius * 0.8;
      vBlurCoords[2] = aVertexTextCoord - uRadius * 0.4;
      vBlurCoords[3] = aVertexTextCoord;
      vBlurCoords[4] = aVertexTextCoord + uRadius * 0.4;
      vBlurCoords[5] = aVertexTextCoord + uRadius * 0.8;
      vBlurCoords[6] = aVertexTextCoord + uRadius * 1.2;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  @override
  String get fragmentShaderSource => isWebGL2 ? '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;

    uniform sampler2D uSampler;
    uniform vec4 uColor;
    uniform vec2 uRadius;
    uniform float uSourceAlpha;
    uniform int uSourceMode;

    in vec2 vTextCoord;
    
    out vec4 fragColor;

    void main() {
      const float sideWeight = 0.300474132757172;
      const float centerWeight = 0.399051734485656;
      float alpha = texture(uSampler, vTextCoord - uRadius).a * sideWeight * sideWeight;
      alpha += texture(uSampler, vTextCoord + vec2(0.0, -uRadius.y)).a * centerWeight * sideWeight;
      alpha += texture(uSampler, vTextCoord + vec2(uRadius.x, -uRadius.y)).a * sideWeight * sideWeight;
      alpha += texture(uSampler, vTextCoord + vec2(-uRadius.x, 0.0)).a * sideWeight * centerWeight;
      alpha += texture(uSampler, vTextCoord).a * centerWeight * centerWeight;
      alpha += texture(uSampler, vTextCoord + vec2(uRadius.x, 0.0)).a * sideWeight * centerWeight;
      alpha += texture(uSampler, vTextCoord + vec2(-uRadius.x, uRadius.y)).a * sideWeight * sideWeight;
      alpha += texture(uSampler, vTextCoord + vec2(0.0, uRadius.y)).a * centerWeight * sideWeight;
      alpha += texture(uSampler, vTextCoord + uRadius).a * sideWeight * sideWeight;
      alpha *= uColor.a;
      vec4 effect = vec4(uColor.rgb * alpha, alpha);
      vec4 source = texture(uSampler, vTextCoord);
      if (uSourceMode == 2) {
        effect *= 1.0 - source.a;
      } else if (uSourceMode == 1) {
        source *= uSourceAlpha;
        effect = source + effect * (1.0 - source.a);
      }
      fragColor = effect;
    }
    ''' : '''

    precision ${RenderProgramWebGL.fragmentPrecision} float;

    uniform sampler2D uSampler;
    uniform vec4 uColor;

    varying vec2 vBlurCoords[7];

    void main() {
      float alpha = 0.0;
      alpha += texture2D(uSampler, vBlurCoords[0]).a * 0.00443;
      alpha += texture2D(uSampler, vBlurCoords[1]).a * 0.05399;
      alpha += texture2D(uSampler, vBlurCoords[2]).a * 0.24197;
      alpha += texture2D(uSampler, vBlurCoords[3]).a * 0.39894;
      alpha += texture2D(uSampler, vBlurCoords[4]).a * 0.24197;
      alpha += texture2D(uSampler, vBlurCoords[5]).a * 0.05399;
      alpha += texture2D(uSampler, vBlurCoords[6]).a * 0.00443;
      alpha *= uColor.a;
      gl_FragColor = vec4(uColor.rgb * alpha, alpha);
    }
    ''';

  //---------------------------------------------------------------------------

  void configure(
    int color,
    num alpha,
    num radiusX,
    num radiusY, {
    int sourceMode = 0,
  }) {
    final num r = colorGetR(color) / 255.0;
    final num g = colorGetG(color) / 255.0;
    final num b = colorGetB(color) / 255.0;
    final num a = colorGetA(color) / 255.0 * alpha;

    renderingContext.uniform2f(uniforms['uRadius'], radiusX, radiusY);
    renderingContext.uniform4f(uniforms['uColor'], r, g, b, a);
    if (isWebGL2) {
      renderingContext.uniform1f(uniforms['uSourceAlpha'], alpha);
      renderingContext.uniform1i(uniforms['uSourceMode'], sourceMode);
    }
  }
}
