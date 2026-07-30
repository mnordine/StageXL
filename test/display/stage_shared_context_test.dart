@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' hide WebGL;

void main() {
  test('Stage adopts and restores an existing WebGL context without clearing its color buffer', () {
    final canvas = HTMLCanvasElement()
      ..width = 32
      ..height = 32;
    final context = _createContext(canvas);
    if (context == null) return;

    final options = StageOptions()
      ..renderEngine = context.isA<WebGL2RenderingContext>() ? .WebGL2 : .WebGL
      ..sharedWebGLContext = context
      ..clearBeforeRender = false
      ..stageRenderMode = .ONCE
      ..maxPixelRatio = 1;
    final stage = Stage(canvas, width: 32, height: 32, options: options);
    final renderContext = stage.renderContext as RenderContextWebGL;

    expect(renderContext.rawContext, same(context));

    context
      ..clearColor(1, 0, 0, 1)
      ..clear(WebGL.COLOR_BUFFER_BIT)
      ..disable(WebGL.BLEND)
      ..enable(WebGL.DEPTH_TEST)
      ..bindFramebuffer(WebGL.FRAMEBUFFER, context.createFramebuffer());

    stage.materialize(0, 16);

    expect((context.getParameter(WebGL.BLEND) as JSBoolean).toDart, isTrue);
    expect((context.getParameter(WebGL.DEPTH_TEST) as JSBoolean).toDart, isFalse);
    expect(context.getParameter(WebGL.FRAMEBUFFER_BINDING), isNull);

    final pixel = Uint8List(4);
    context.readPixels(16, 16, 1, 1, WebGL.RGBA, WebGL.UNSIGNED_BYTE, pixel.toJS);
    expect(pixel, orderedEquals([255, 0, 0, 255]));

    stage.dispose();
  });

  test('StageOptions clone preserves shared rendering options', () {
    final canvas = HTMLCanvasElement();
    final context = _createContext(canvas);
    if (context == null) return;

    final options = StageOptions()
      ..sharedWebGLContext = context
      ..clearBeforeRender = false;
    final clone = options.clone();

    expect(clone.sharedWebGLContext, same(context));
    expect(clone.clearBeforeRender, isFalse);
  });
}

WebGLRenderingContext? _createContext(HTMLCanvasElement canvas) {
  final attributes = {
    'alpha': true,
    'depth': true,
    'stencil': true,
    'antialias': false,
  }.jsify();
  return (canvas.getContext('webgl2', attributes) ?? canvas.getContext('webgl', attributes))
      as WebGLRenderingContext?;
}
