library;

import 'dart:js_interop';
import 'dart:math' hide Point, Rectangle;

import '../display.dart';
import '../engine.dart';
import '../geom.dart';
import '../internal/filter_helpers.dart';
import '../internal/tools.dart';

class DropShadowFilter extends BitmapFilter {
  static final _programs = RenderProgramSet<DropShadowFilter>(
    webGL: RenderProgramWebGL.callback(_renderWebGL),
    webGPU: RenderProgramWebGPU.callback(_renderWebGPU),
  );

  /// The distance from the object to the shadow.
  num distance;

  /// The angle where the shadow is casted to.
  num angle;

  var _blurX = 4;
  var _blurY = 4;
  var _quality = 1;
  int color;

  var knockout = false;
  var hideObject = false;

  final _renderPassSources = <int>[];
  final _renderPassTargets = <int>[];

  DropShadowFilter(
      [this.distance = 8,
      this.angle = pi / 4,
      this.color = 0xFF000000,
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
  //---------------------------------------------------------------------------

  @override
  BitmapFilter clone() => DropShadowFilter(
      distance, angle, color, blurX, blurY, quality, knockout, hideObject);

  @override
  RenderProgramSet<DropShadowFilter> get renderPrograms => _programs;

  @override
  Rectangle<int> get overlap {
    final shiftX = (distance * cos(angle)).round();
    final shiftY = (distance * sin(angle)).round();
    final sRect = Rectangle<int>(-1, -1, 2, 2);
    final dRect =
        Rectangle<int>(shiftX - blurX, shiftY - blurY, 2 * blurX, 2 * blurY);
    return sRect.boundingBox(dRect);
  }

  @override
  List<int> get renderPassSources => _renderPassSources;

  @override
  List<int> get renderPassTargets => _renderPassTargets;

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

  /// The quality of the shadow in the range from 1 to 5.
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
    final shiftX = (distance * cos(angle)).round();
    final shiftY = (distance * sin(angle)).round();

    final pixelRatio = renderTextureQuad.pixelRatio;
    final blurX = (this.blurX * pixelRatio).round();
    final blurY = (this.blurY * pixelRatio).round();
    final alphaChannel =
        BitmapDataChannel.getCanvasIndex(BitmapDataChannel.ALPHA);
    final stride = width * 4;

    shiftChannel(data, 3, width, height, shiftX, shiftY);

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

  static ({int passCount, num shiftX, num shiftY, num radiusX, num radiusY}) _parameters(
    RenderFilterContext context,
    DropShadowFilter filter,
  ) {
    final renderTexture = context.renderTextureQuad.renderTexture;
    final passCount = filter._renderPassSources.length;
    final passScale = pow(0.5, context.pass >> 1);
    final pixelRatio = sqrt(context.renderState.globalMatrix.det.abs());
    final pixelRatioScale = pixelRatio * passScale;
    final pixelRatioDistance = pixelRatio * filter.distance;
    return (
      passCount: passCount,
      shiftX: context.pass == 0 ? pixelRatioDistance * cos(filter.angle) / renderTexture.width : 0.0,
      shiftY: context.pass == 0 ? pixelRatioDistance * sin(filter.angle) / renderTexture.height : 0.0,
      radiusX: context.pass.isEven ? pixelRatioScale * filter.blurX / renderTexture.width : 0.0,
      radiusY: context.pass.isEven ? 0.0 : pixelRatioScale * filter.blurY / renderTexture.height,
    );
  }

  static void _renderWebGPU(RenderFilterContext context, DropShadowFilter filter) {
      final renderContext = context.renderContext as RenderContextWebGPU;
      final parameters = _parameters(context, filter);
      if (context.pass == parameters.passCount - 1) {
        if (!filter.knockout && !filter.hideObject) {
          renderContext.renderTextureQuad(context.renderState, context.renderTextureQuad);
        }
      } else {
        renderContext.filterSystem.renderDropShadowFilterQuad(
          context.renderState,
          context.renderTextureQuad,
          context.pass == parameters.passCount - 2 ? filter.color : filter.color | 0xFF000000,
          context.pass == parameters.passCount - 2 ? context.renderState.globalAlpha : 1.0,
          parameters.shiftX,
          parameters.shiftY,
          parameters.radiusX,
          parameters.radiusY,
        );
      }
  }

  static void _renderWebGL(RenderFilterContext context, DropShadowFilter filter) {
    final renderContext = context.renderContext as RenderContextWebGL;
    final parameters = _parameters(context, filter);
    if (context.pass == parameters.passCount - 1) {
      if (!filter.knockout && !filter.hideObject) {
        renderContext.renderTextureQuad(context.renderState, context.renderTextureQuad);
      }
    } else {
      final renderTexture = context.renderTextureQuad.renderTexture;
      final renderProgram = renderContext.getRenderProgram(
          r'$DropShadowFilterProgramWebGL', DropShadowFilterProgramWebGL.new);
      renderContext.activateRenderProgram(renderProgram);
      renderContext.activateRenderTexture(renderTexture);
      renderProgram.configure(
        context.pass == parameters.passCount - 2 ? filter.color : filter.color | 0xFF000000,
        context.pass == parameters.passCount - 2 ? context.renderState.globalAlpha : 1.0,
        parameters.shiftX,
        parameters.shiftY,
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

class DropShadowFilterProgramWebGL extends RenderProgramSimpleWebGL<DropShadowFilter> {
  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;
    uniform vec2 uRadius;
    uniform vec2 uShift;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;

    out vec2 vBlurCoords[7];

    void main() {
      vec2 texCoord = aVertexTextCoord - uShift;
      vBlurCoords[0] = texCoord - uRadius * 1.2;
      vBlurCoords[1] = texCoord - uRadius * 0.8;
      vBlurCoords[2] = texCoord - uRadius * 0.4;
      vBlurCoords[3] = texCoord;
      vBlurCoords[4] = texCoord + uRadius * 0.4;
      vBlurCoords[5] = texCoord + uRadius * 0.8;
      vBlurCoords[6] = texCoord + uRadius * 1.2;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    uniform vec2 uRadius;
    uniform vec2 uShift;

    attribute vec2 aVertexPosition;
    attribute vec2 aVertexTextCoord;

    varying vec2 vBlurCoords[7];

    void main() {
      vec2 texCoord = aVertexTextCoord - uShift;
      vBlurCoords[0] = texCoord - uRadius * 1.2;
      vBlurCoords[1] = texCoord - uRadius * 0.8;
      vBlurCoords[2] = texCoord - uRadius * 0.4;
      vBlurCoords[3] = texCoord;
      vBlurCoords[4] = texCoord + uRadius * 0.4;
      vBlurCoords[5] = texCoord + uRadius * 0.8;
      vBlurCoords[6] = texCoord + uRadius * 1.2;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  @override
  String get fragmentShaderSource => isWebGL2 ? '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;

    uniform sampler2D uSampler;
    uniform vec4 uColor;

    in vec2 vBlurCoords[7];
    out vec4 fragColor;

    void main() {
      float alpha = 0.0;
      alpha += texture(uSampler, vBlurCoords[0]).a * 0.00443;
      alpha += texture(uSampler, vBlurCoords[1]).a * 0.05399;
      alpha += texture(uSampler, vBlurCoords[2]).a * 0.24197;
      alpha += texture(uSampler, vBlurCoords[3]).a * 0.39894;
      alpha += texture(uSampler, vBlurCoords[4]).a * 0.24197;
      alpha += texture(uSampler, vBlurCoords[5]).a * 0.05399;
      alpha += texture(uSampler, vBlurCoords[6]).a * 0.00443;
      alpha *= uColor.a;
      fragColor = vec4(uColor.rgb * alpha, alpha);
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
  //---------------------------------------------------------------------------

  void configure(
      int color, num alpha, num shiftX, num shiftY, num radiusX, num radiusY) {
    final num r = colorGetR(color) / 255.0;
    final num g = colorGetG(color) / 255.0;
    final num b = colorGetB(color) / 255.0;
    final num a = colorGetA(color) / 255.0 * alpha;

    renderingContext.uniform2f(uniforms['uShift'], shiftX, shiftY);
    renderingContext.uniform2f(uniforms['uRadius'], radiusX, radiusY);
    renderingContext.uniform4f(uniforms['uColor'], r, g, b, a);
  }
}
