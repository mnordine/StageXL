@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  test('RenderLayer changes draw order without changing logical transforms', () {
      final canvas = HTMLCanvasElement()
        ..width = 16
        ..height = 8;

      final stage = _createStage(canvas);
      final world = Sprite()..x = 4;
      final red = Bitmap(BitmapData(8, 8, Color.Red));
      final blue = Bitmap(BitmapData(8, 8, Color.Blue))..x = 4;
      final layer = RenderLayer();

      world.addChild(red);
      stage
        ..addChild(world)
        ..addChild(blue)
        ..addChild(layer);
      layer.attach(red);

      expect(red.parent, same(world));
      expect(red.parentRenderLayer, same(layer));

      stage.materialize(0, 16);

      final context = canvas.getContext('2d') as CanvasRenderingContext2D;
      expect(context.getImageData(1, 4, 1, 1).data.toDart[3], 0);
      expect(context.getImageData(6, 4, 1, 1).data.toDart.sublist(0, 4), [
        255,
        0,
        0,
        255,
      ]);

      stage.addChildAt(layer, 0);
      stage.materialize(16, 16);

      expect(context.getImageData(6, 4, 1, 1).data.toDart.sublist(0, 4), [
        0,
        0,
        255,
        255,
      ]);
    },
  );

  test('RenderLayer automatically sorts attached objects by zIndex', () {
    final canvas = HTMLCanvasElement()
      ..width = 8
      ..height = 8;
    final stage = _createStage(canvas);
    final red = Bitmap(BitmapData(8, 8, Color.Red))..zIndex = 1;
    final blue = Bitmap(BitmapData(8, 8, Color.Blue));
    final layer = RenderLayer(sortableChildren: true);

    stage
      ..addChild(red)
      ..addChild(blue)
      ..addChild(layer);
    layer
      ..attach(red)
      ..attach(blue);

    stage.materialize(0, 16);

    final context = canvas.getContext('2d') as CanvasRenderingContext2D;
    expect(context.getImageData(4, 4, 1, 1).data.toDart.sublist(0, 4), [
      255,
      0,
      0,
      255,
    ]);

    blue.zIndex = 2;
    stage.materialize(16, 16);

    expect(context.getImageData(4, 4, 1, 1).data.toDart.sublist(0, 4), [
      0,
      0,
      255,
      255,
    ]);
  });

  test('RenderLayer reassigns objects between layers', () {
    final child = Bitmap();
    final first = RenderLayer();
    final second = RenderLayer();

    expect(first.attach(child), same(child));
    expect(first.renderLayerChildren, [child]);

    second.attach(child);

    expect(first.renderLayerChildren, isEmpty);
    expect(second.renderLayerChildren, [child]);
    expect(child.parentRenderLayer, same(second));

    expect(second.detach(child), same(child));
    expect(child.parentRenderLayer, isNull);
  });

  test('removing a logical subtree detaches all layered descendants', () {
    final root = Sprite();
    final parent = Sprite();
    final child = Bitmap();
    final layer = RenderLayer();

    parent.addChild(child);
    root.addChild(parent);
    layer.attach(child);

    root.removeChild(parent);

    expect(child.parentRenderLayer, isNull);
    expect(layer.renderLayerChildren, isEmpty);

    root.addChild(parent);
    expect(child.parentRenderLayer, isNull);
  });
}

Stage _createStage(HTMLCanvasElement canvas) {
  final options = StageOptions()
    ..renderEngine = .Canvas2D
    ..backgroundColor = Color.Transparent;

  return Stage(
    canvas,
    width: canvas.width,
    height: canvas.height,
    options: options,
  );
}
