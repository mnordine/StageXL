@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

// Run both normally and with --dart2js-args=-Dstagexl-debug-draw=true.
void main() {
  for (final mode in ['WebGL 2', 'WebGL 1', 'WebGL 1 without VAOs']) {
    final webgl1 = mode != 'WebGL 2';
    final noVao = mode == 'WebGL 1 without VAOs';
    group(mode, () {
      late RenderContextWebGL context;
      late HTMLCanvasElement canvas;
      late RenderState state;
      late _Trace trace;

      setUp(() {
        debugDraw
          ..wireframes = false
          ..wireframeColor = Color.Lime
          ..masks = false;
        canvas = HTMLCanvasElement()
          ..width = 64
          ..height = 64;
        if (noVao) {
          final gl = canvas.getContext('webgl', {'stencil': true, 'antialias': false}.jsify())
              as WebGLRenderingContext;
          final getExtension = gl.getProperty<JSFunction>('getExtension'.toJS);
          gl.setProperty('getExtension'.toJS, ((JSString name) => name.toDart == 'OES_vertex_array_object'
              ? null : getExtension.callAsFunction(gl, name)).toJS);
        }
        context = RenderContextWebGL(RenderSurface(canvas), powerPreference: .normal, forceWebGL1: webgl1);
        expect(context.isWebGL2, !webgl1);
        context.reset();
        state = RenderState(context);
        trace = _Trace(context.rawContext);
      });

      tearDown(() {
        debugDraw
          ..wireframes = false
          ..masks = false;
        context.dispose();
        final extension = context.rawContext.getExtension('WEBGL_lose_context') as WEBGL_lose_context?;
        extension?.loseContext();
      });

      test('triangle overlays upload only indices and leave subsequent draws intact', () {
        void draw() {
          context.clear(Color.Black);
          state.renderTriangle(4, 4, 56, 4, 4, 56, Color.Red);
          context.flush();
        }

        draw();
        final normal = _pixels(context);
        trace.reset();
        debugDraw.wireframes = true;
        draw();
        expect(trace.vertexBytes, 3 * 6 * 4);
        expect(trace.indexBytes, stagexlDebugDraw ? 6 + 12 : 6);
        expect(trace.lineDraws, stagexlDebugDraw ? 1 : 0);
        expect(trace.programsCreated, stagexlDebugDraw ? 1 : 0);
        if (!noVao) {
          expect(trace.bufferBindings, stagexlDebugDraw ? 4 : 2);
          expect(trace.attributeBindings, stagexlDebugDraw ? 1 : 0);
        }
        expect(_greenPixels(_pixels(context)), stagexlDebugDraw ? greaterThan(0) : 0);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);

        debugDraw.wireframes = false;
        trace.reset();
        draw();
        expect(_pixels(context), normal);
        expect(trace.vertexBytes, 72);
        expect(trace.indexBytes, 6);
        expect(trace.lineDraws, 0);
        expect(trace.programsCreated, 0);
        expect(trace.bufferBindings, 2);
        expect(trace.attributeBindings, 0);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);
      });

      test('multiple batch groups share their vertex upload and retain edge offsets', () {
        final bitmap = BitmapData(20, 20, Color.Red);
        void draw() {
          context.clear(Color.Black);
          state.reset(Matrix.fromIdentity()..translate(4, 4));
          state.renderTextureQuad(bitmap.renderTextureQuad);
          state.reset(Matrix.fromIdentity()..translate(36, 36), 1, .SCREEN);
          state.renderTextureQuad(bitmap.renderTextureQuad);
          context.flush();
        }

        draw();
        final normal = _pixels(context);
        trace.reset();
        debugDraw.wireframes = true;
        draw();
        expect(trace.vertexBytes, 8 * 9 * 4);
        expect(trace.indexBytes, stagexlDebugDraw ? 24 + 48 : 24);
        expect(trace.lineDraws, stagexlDebugDraw ? 2 : 0);
        if (!noVao) {
          expect(trace.bufferBindings, stagexlDebugDraw ? 8 : 4);
          expect(trace.attributeBindings, stagexlDebugDraw ? 6 : 4);
        }
        final pixels = _pixels(context);
        expect(_greenPixels(pixels, upperHalf: true), stagexlDebugDraw ? greaterThan(0) : 0);
        expect(_greenPixels(pixels, upperHalf: false), stagexlDebugDraw ? greaterThan(0) : 0);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);

        debugDraw.wireframes = false;
        draw();
        expect(_pixels(context), normal);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);
        bitmap.renderTexture.dispose();
      });

      test('wireframes survive nested stencil masks and filtered targets', () {
        debugDraw
          ..wireframes = true
          ..masks = true
          // The existing front overlay follows the restored parent stencil region.
          ..maskDrawOrder = .back;
        context.clear(Color.Black);
        final outer = Mask.circle(16, 16, 15);
        final inner = Mask.circle(16, 16, 10);
        context.beginRenderMask(state, outer);
        context.beginRenderMask(state, inner);
        state.renderTriangle(0, 0, 32, 0, 0, 32, Color.Red);
        context.endRenderMask(state, inner);
        context.endRenderMask(state, outer);
        final bitmap = BitmapData(12, 12, Color.Red);
        state.reset(Matrix.fromIdentity()..translate(40, 4));
        state.renderTextureQuadFiltered(bitmap.renderTextureQuad, [BlurFilter(2, 2)]);
        context.flush();
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);

        debugDraw.wireframes = false;
        state.reset();
        state.renderTriangle(32, 32, 60, 32, 32, 60, Color.Blue);
        context.flush();
        expect(_pixel(context, 36, 36), [0, 0, 255, 255]);
        expect(_pixel(context, 60, 60), [0, 0, 0, 255]);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);
        bitmap.renderTexture.dispose();
      });

      test('wireframe resources are recreated after context restoration', () async {
        debugDraw.wireframes = true;
        void draw() {
          context.reset();
          context.clear(Color.Black);
          state.renderTriangle(4, 4, 56, 4, 4, 56, Color.Red);
          context.flush();
        }

        draw();
        final before = _pixels(context);
        final extension = context.rawContext.getExtension('WEBGL_lose_context') as WEBGL_lose_context;
        final lost = canvas.onWebGlContextLost.first;
        extension.loseContext();
        await lost;
        final nextFrame = Completer<void>();
        window.requestAnimationFrame(((double _) => nextFrame.complete()).toJS);
        await nextFrame.future;
        final restored = canvas.onWebGlContextRestored.first;
        extension.restoreContext();
        await restored;
        draw();
        expect(_pixels(context), before);
        expect(context.rawContext.getError(), WebGLRenderingContext.NO_ERROR);
      });

      test('retained WebGL batches reuse vertices and preserve shader clipping', () {
        // This context was created on the same canvas; Stage shares it without replacing it.
        final stage = Stage(canvas, width: 64, height: 64, options: StageOptions()
          ..renderEngine = webgl1 ? .WebGL : .WebGL2
          ..sharedWebGLContext = context.rawContext
          ..stageScaleMode = .NO_SCALE
          ..stageAlign = .TOP_LEFT
          ..stageRenderMode = .AUTO
          ..backgroundColor = Color.Black
          ..maxPixelRatio = 1);
        final stageContext = stage.renderContext as RenderContextWebGL;
        final data = BitmapData(32, 32, Color.Red);
        final bitmap = Bitmap(data)..x = 4..y = 4..mask = Mask.rectangle(0, 0, 16, 16);
        stage.addChild(bitmap);
        stage.materialize(0, 16);
        final normal = _pixels(stageContext);
        trace.reset();
        debugDraw.wireframes = true;
        stage.materialize(1, 16);
        expect(trace.vertexBytes, 0);
        expect(trace.indexBytes, stagexlDebugDraw ? 24 : 0);
        final wire = _pixels(stageContext);
        expect(_greenPixels(wire), stagexlDebugDraw ? greaterThan(0) : 0);
        expect(_pixel(stageContext, 28, 28), [0, 0, 0, 255]);
        expect(stageContext.rawContext.getError(), WebGLRenderingContext.NO_ERROR);
        debugDraw.wireframes = false;
        stage.materialize(2, 16);
        expect(_pixels(stageContext), normal);
        stage.dispose();
        data.renderTexture.dispose();
      });

      test('mask overlays restore blend and vertex state for following content', () {
        debugDraw
          ..wireframes = true
          ..masks = true
          ..maskDrawOrder = .back;
        context.clear(Color.Black);
        state.renderTriangle(4, 4, 24, 4, 4, 24, Color.Red);
        context.flush();
        final gl = context.rawContext;
        final mask = Mask.rectangle(0, 0, 28, 28);
        context.activateBlendMode(.ADD);
        final src = gl.getParameter(WebGLRenderingContext.BLEND_SRC_RGB);
        final dst = gl.getParameter(WebGLRenderingContext.BLEND_DST_RGB);
        context.beginRenderMask(state, mask);
        expect(gl.getParameter(WebGLRenderingContext.BLEND_SRC_RGB), src);
        expect(gl.getParameter(WebGLRenderingContext.BLEND_DST_RGB), dst);
        context.endRenderMask(state, mask);

        debugDraw.wireframes = false;
        state.renderTriangle(32, 32, 60, 32, 32, 60, Color.Blue);
        context.flush();
        expect(_pixel(context, 36, 36), [0, 0, 255, 255]);
        expect(gl.getError(), WebGLRenderingContext.NO_ERROR);
      });
    });
  }
}

Uint8List _pixels(RenderContextWebGL context) {
  final pixels = Uint8List(64 * 64 * 4);
  context.rawContext.readPixels(0, 0, 64, 64, WebGLRenderingContext.RGBA,
      WebGLRenderingContext.UNSIGNED_BYTE, pixels.toJS);
  return pixels;
}

List<int> _pixel(RenderContextWebGL context, int x, int y) {
  final offset = ((63 - y) * 64 + x) * 4;
  return _pixels(context).sublist(offset, offset + 4);
}

int _greenPixels(Uint8List pixels, {bool? upperHalf}) {
  final start = upperHalf == true ? pixels.length ~/ 2 : 0;
  final end = upperHalf == false ? pixels.length ~/ 2 : pixels.length;
  var count = 0;
  for (var i = start; i < end; i += 4) {
    if (pixels[i] == 0 && pixels[i + 1] == 255 && pixels[i + 2] == 0) count++;
  }
  return count;
}

class _Trace {
  var vertexBytes = 0;
  var indexBytes = 0;
  var lineDraws = 0;
  var programsCreated = 0;
  var bufferBindings = 0;
  var attributeBindings = 0;

  _Trace(WebGLRenderingContext gl) {
    final createProgram = gl.getProperty<JSFunction>('createProgram'.toJS);
    gl.setProperty('createProgram'.toJS, (() {
      programsCreated++;
      return createProgram.callAsFunction(gl);
    }).toJS);
    final bindBuffer = gl.getProperty<JSFunction>('bindBuffer'.toJS);
    gl.setProperty('bindBuffer'.toJS, ((JSNumber target, JSAny? buffer) {
      bufferBindings++;
      bindBuffer.callAsFunction(gl, target, buffer);
    }).toJS);
    final attribute = gl.getProperty<JSFunction>('vertexAttribPointer'.toJS);
    gl.setProperty('vertexAttribPointer'.toJS,
        ((JSNumber index, JSNumber size, JSNumber type, JSBoolean normalized, JSNumber stride, JSNumber offset) {
      attributeBindings++;
      attribute.callMethodVarArgs<JSAny?>('call'.toJS, [gl, index, size, type, normalized, stride, offset]);
    }).toJS);
    final upload = gl.getProperty<JSFunction>('bufferSubData'.toJS);
    gl.setProperty('bufferSubData'.toJS, ((JSNumber target, JSNumber offset, JSObject data) {
      final bytes = data.getProperty<JSNumber>('byteLength'.toJS).toDartInt;
      if (target.toDartInt == WebGLRenderingContext.ARRAY_BUFFER) vertexBytes += bytes;
      if (target.toDartInt == WebGLRenderingContext.ELEMENT_ARRAY_BUFFER) indexBytes += bytes;
      upload.callAsFunction(gl, target, offset, data);
    }).toJS);
    final draw = gl.getProperty<JSFunction>('drawElements'.toJS);
    gl.setProperty('drawElements'.toJS, ((JSNumber mode, JSNumber count, JSNumber type, JSNumber offset) {
      if (mode.toDartInt == WebGLRenderingContext.LINES) lineDraws++;
      draw.callAsFunction(gl, mode, count, type, offset);
    }).toJS);
  }

  void reset() {
    vertexBytes = 0;
    indexBytes = 0;
    lineDraws = 0;
    programsCreated = 0;
    bufferBindings = 0;
    attributeBindings = 0;
  }
}
