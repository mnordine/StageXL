@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show HTMLCanvasElement;
import 'package:webgpu_interop/generated.dart' as gpu;

void main() {
  for (final antialias in [false, true]) {
    group(antialias ? 'WebGPU MSAA' : 'WebGPU', () => _tests(antialias));
  }
}

void _tests(bool antialias) {
  late HTMLCanvasElement canvas;
  late Stage stage;
  late RenderContextWebGPU context;
  late _GpuTrace trace;

  setUp(() async {
    debugDraw
      ..wireframes = false
      ..wireframeColor = Color.Lime
      ..masks = false
      ..maskColor = Color.Magenta
      ..maskDrawOrder = .front;
    canvas = HTMLCanvasElement()..width = 64..height = 64;
    stage = await Stage.create(canvas, width: 64, height: 64, options: StageOptions()
      ..renderEngine = .WebGPU
      ..stageScaleMode = .NO_SCALE
      ..stageAlign = .TOP_LEFT
      ..stageRenderMode = .AUTO
      ..backgroundColor = Color.Black
      ..maxPixelRatio = 1
      ..renderBundles = true
      ..antialias = antialias);
    expect(stage.renderEngine, RenderEngine.WebGPU, reason: 'This suite requires a real WebGPU device.');
    context = stage.renderContext as RenderContextWebGPU;
    context.canvasContext.configure(gpu.GPUCanvasConfiguration(device: context.device,
        format: context.preferredTextureFormat, alphaMode: 'opaque',
        usage: gpu.$GPUTextureUsage.RENDER_ATTACHMENT | gpu.$GPUTextureUsage.COPY_SRC));
    context.device.pushErrorScope('validation');
    trace = _GpuTrace(context.device);
  });

  tearDown(() async {
    expect(await context.device.popErrorScope().toDart, isNull, reason: 'WebGPU validation error');
    stage.dispose();
    expect(trace.liveDebugBuffers, isEmpty);
    debugDraw..wireframes = false..masks = false;
  });

  test('immediate wireframes reuse vertex uploads and draw each blend group', () async {
    final data = BitmapData(20, 20, Color.Red);
    final state = RenderState(context);
    void draw() {
      context.reset();
      context.clear(Color.Black);
      state.reset(Matrix.fromIdentity()..translate(4, 4));
      state.renderTextureQuad(data.renderTextureQuad);
      state.reset(Matrix.fromIdentity()..translate(36, 36), 1, .SCREEN);
      state.renderTextureQuad(data.renderTextureQuad);
      context.flush();
    }
    draw();
    final normal = await _pixels(context);
    trace.reset();
    debugDraw.wireframes = true;
    draw();
    expect(trace.vertexBytes, 8 * 9 * 4);
    expect(trace.edgeBytes, stagexlDebugDraw ? 4 * 24 : 0);
    final wire = await _pixels(context);
    expect(_green(wire, 0, 32), stagexlDebugDraw ? greaterThan(0) : 0);
    expect(_green(wire, 32, 64), stagexlDebugDraw ? greaterThan(0) : 0);
    debugDraw.wireframes = false;
    draw();
    expect(await _pixels(context), normal);
    data.renderTexture.dispose();
  });

  test('retained edges survive transforms, shader scissors, bundle toggles and structural changes', () async {
    final data = BitmapData(32, 32, Color.Red);
    final bitmap = Bitmap(data)..x = 4..y = 4..mask = Mask.rectangle(0, 0, 16, 16);
    stage.addChild(bitmap);
    for (var i = 0; i < 35; i++) {
      stage.materialize(i.toDouble(), 16);
    }
    expect(context.renderStatistics.webgpuRenderBundleCacheHitCount, greaterThan(0));
    final normal = await _pixels(context);

    trace.reset();
    debugDraw.wireframes = true;
    stage.materialize(36, 16);
    expect(trace.vertexBytes, 0);
    expect(trace.edgeBytes, stagexlDebugDraw ? 48 : 0);
    final wire = await _pixels(context);
    expect(_green(wire, 0, 64), stagexlDebugDraw ? greaterThan(0) : 0);
    expect(_pixel(wire, 28, 28), [0, 0, 0, 255]);

    trace.reset();
    bitmap.x = 8;
    stage.materialize(37, 16);
    expect(trace.vertexBytes, 0);
    expect(trace.edgeBytes, 0, reason: 'A transform must reuse the retained edges.');
    final moved = await _pixels(context);
    expect(_pixel(moved, 5, 5), [0, 0, 0, 255]);
    expect(_green(moved, 0, 64), stagexlDebugDraw ? greaterThan(0) : 0);

    bitmap.x = 4;
    debugDraw.wireframes = false;
    stage.materialize(38, 16);
    expect(await _pixels(context), normal);
    expect(context.renderStatistics.webgpuRenderBundleCacheHitCount, greaterThan(0));
    trace.reset();
    stage.addChild(Bitmap(data)..x = 36..y = 36);
    debugDraw.wireframes = true;
    stage.materialize(39, 16);
    expect(trace.edgeBytes, stagexlDebugDraw ? greaterThan(0) : 0);
    expect(_green(await _pixels(context), 32, 64), stagexlDebugDraw ? greaterThan(0) : 0);
    stage.releaseRenderPlan();
    expect(trace.liveDebugBuffers.where((buffer) => buffer.label == 'StageXL debug edges'), isEmpty);
    data.renderTexture.dispose();
  });

  test('retained mesh edits refresh edge indices without reuploading unchanged vertices', () async {
    final data = BitmapData(32, 32, Color.Red);
    final mesh = Mesh(data, 4, 1)
      ..setVertex(0, 4, 4, 0, 0)
      ..setVertex(1, 56, 4, 1, 0)
      ..setVertex(2, 4, 56, 0, 1)
      ..setVertex(3, 56, 56, 1, 1)
      ..setTriangleIndices(0, 0, 1, 2);
    stage.addChild(mesh);
    debugDraw.wireframes = true;
    stage.materialize(0, 16);
    final before = await _pixels(context);
    trace.reset();
    mesh.setTriangleIndices(0, 1, 3, 2);
    stage.materialize(1, 16);
    expect(trace.vertexBytes, 0);
    expect(trace.edgeBytes, stagexlDebugDraw ? 24 : 0);
    final after = await _pixels(context);
    expect(after, isNot(equals(before)));
    expect(_pixel(after, 8, 8), [0, 0, 0, 255]);
    expect(_green(after, 0, 64), stagexlDebugDraw ? greaterThan(0) : 0);
    trace.reset();
    stage.materialize(2, 16);
    expect(trace.edgeBytes, 0);
    data.renderTexture.dispose();
  });

  test('scissor and nested stencil overlays respect mask boundaries and runtime toggles', () async {
    final data = BitmapData(48, 48, Color.Red);
    final outer = Sprite()..mask = Mask.circle(16, 16, 14);
    outer.addChild(Bitmap(data)..mask = Mask.circle(16, 16, 9));
    stage.addChild(outer);
    final clipped = Sprite()..x = 36..y = 36..mask = Mask.rectangle(0, 0, 16, 16);
    clipped.addChild(Bitmap(data));
    stage.addChild(clipped);
    stage.materialize(0, 16);
    final normal = await _pixels(context);
    for (final order in MaskDrawOrder.values) {
      debugDraw..masks = true..maskDrawOrder = order;
      stage.materialize(1, 16);
      final pixels = await _pixels(context);
      expect(_pixel(pixels, 60, 60), [0, 0, 0, 255]);
      expect(_pixel(pixels, 2, 2), [0, 0, 0, 255]);
      if (stagexlDebugDraw && order == MaskDrawOrder.front) {
        expect(_pixel(pixels, 16, 16), [255, 0, 255, 255]);
        expect(_pixel(pixels, 40, 40), [255, 0, 255, 255]);
      }
    }
    debugDraw.masks = false;
    stage.materialize(2, 16);
    expect(await _pixels(context), normal);
    data.renderTexture.dispose();
  });

  test('wireframes on filtered targets leave subsequent content intact', () async {
    final data = BitmapData(20, 20, Color.Red);
    stage.addChild(Bitmap(data)..x = 4..y = 4..filters = [BlurFilter(2, 2)]);
    final blue = BitmapData(12, 12, Color.Blue);
    stage.addChild(Bitmap(blue)..x = 40..y = 40);
    stage.materialize(0, 16);
    final normal = await _pixels(context);
    debugDraw.wireframes = true;
    stage.materialize(1, 16);
    final wire = await _pixels(context);
    expect(_pixel(wire, 42, 48), [0, 0, 255, 255]);
    expect(_green(wire, 32, 64), stagexlDebugDraw ? greaterThan(0) : 0);
    debugDraw.wireframes = false;
    stage.materialize(2, 16);
    expect(await _pixels(context), normal);
    data.renderTexture.dispose();
    blue.renderTexture.dispose();
  });
}

Future<Uint8List> _pixels(RenderContextWebGPU context) async {
  final buffer = context.device.createBuffer(gpu.GPUBufferDescriptor(size: 64 * 256,
      usage: gpu.$GPUBufferUsage.COPY_DST | gpu.$GPUBufferUsage.MAP_READ));
  final encoder = context.device.createCommandEncoder();
  encoder.copyTextureToBuffer(gpu.GPUImageCopyTexture(texture: context.commandSystem.swapTexture),
      gpu.GPUImageCopyBuffer(buffer: buffer, bytesPerRow: 256), gpu.GPUExtent3DDict(width: 64, height: 64));
  context.device.queue.submit([encoder.finish()].toJS);
  await buffer.mapAsync(gpu.$GPUMapMode.READ).toDart;
  final pixels = Uint8List.fromList(buffer.getMappedRange().toDart.asUint8List());
  buffer.unmap();
  buffer.destroy();
  if (context.preferredTextureFormat.startsWith('bgra')) {
    for (var i = 0; i < pixels.length; i += 4) {
      final blue = pixels[i];
      pixels[i] = pixels[i + 2];
      pixels[i + 2] = blue;
    }
  }
  return pixels;
}

List<int> _pixel(Uint8List pixels, int x, int y) => pixels.sublist((y * 64 + x) * 4, (y * 64 + x) * 4 + 4);

int _green(Uint8List pixels, int top, int bottom) {
  var count = 0;
  for (var i = top * 256; i < bottom * 256; i += 4) {
    if (pixels[i + 1] > 0 && pixels[i + 2] == 0) count++;
  }
  return count;
}

class _GpuTrace {
  var vertexBytes = 0;
  var edgeBytes = 0;
  final liveDebugBuffers = <gpu.GPUBuffer>[];

  _GpuTrace(gpu.GPUDevice device) {
    final create = device.getProperty<JSFunction>('createBuffer'.toJS);
    device.setProperty('createBuffer'.toJS, ((gpu.GPUBufferDescriptor descriptor) {
      final buffer = create.callAsFunction(device, descriptor) as gpu.GPUBuffer;
      if (buffer.label.startsWith('StageXL debug')) {
        liveDebugBuffers.add(buffer);
        final destroy = buffer.getProperty<JSFunction>('destroy'.toJS);
        buffer.setProperty('destroy'.toJS, (() {
          liveDebugBuffers.remove(buffer);
          destroy.callAsFunction(buffer);
        }).toJS);
      }
      return buffer;
    }).toJS);
    final queue = device.queue;
    final write = queue.getProperty<JSFunction>('writeBuffer'.toJS);
    queue.setProperty('writeBuffer'.toJS,
        ((gpu.GPUBuffer buffer, JSNumber offset, JSObject data, JSNumber? start, JSNumber? length) {
      final elementSize = data.getProperty<JSNumber?>('BYTES_PER_ELEMENT'.toJS)?.toDartInt ?? 1;
      final bytes = length == null ? data.getProperty<JSNumber>('byteLength'.toJS).toDartInt
          : length.toDartInt * elementSize;
      if (buffer.usage & gpu.$GPUBufferUsage.VERTEX != 0) vertexBytes += bytes;
      if (buffer.label == 'StageXL debug edges') edgeBytes += bytes;
      write.callMethodVarArgs<JSAny?>('call'.toJS, [queue, buffer, offset, data, ?start, ?length]);
    }).toJS);
  }

  void reset() {
    vertexBytes = 0;
    edgeBytes = 0;
  }
}
