@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  test('Stage host renders to OffscreenCanvas and dispatches forwarded input', () async {
    final canvas = OffscreenCanvas(160, 90);
    final host = _TestOffscreenHost(canvas);
    final options = StageOptions()
      ..renderEngine = .WebGL2
      ..stageAlign = .TOP_LEFT
      ..stageScaleMode = .NO_SCALE
      ..maxPixelRatio = 2;
    final stage = await Stage.createWithHost(host, width: 160, height: 90, options: options);
    final sprite = Sprite();
    sprite.graphics
      ..rect(10, 10, 50, 40)
      ..fillColor(Color.Red);

    var mouseDownCount = 0;
    sprite.onMouseDown.listen((_) => mouseDownCount++);
    stage.addChild(sprite);
    stage.materialize(0, 0);
    stage.dispatchInputEvent(const StageMouseInput('mousedown', clientX: 20, clientY: 20));

    expect(host.attachedStage, same(stage));
    expect(host.focusCount, 1);
    expect(mouseDownCount, 1);
    expect(canvas.width, 320);
    expect(canvas.height, 180);

    stage.dispose();
    stage.dispatchInputEvent(const StageMouseInput('mousedown', clientX: 20, clientY: 20));

    expect(stage.isDisposed, isTrue);
    expect(stage.renderContext.isDisposed, isTrue);
    expect(host.attachedStage, isNull);
    expect(mouseDownCount, 1);
    expect(stage.dispose, returnsNormally);
  });

  test('BitmapData uses an OffscreenCanvas backing surface without a DOM dependency', () {
    final renderTexture = RenderTexture.fromOffscreenCanvas(OffscreenCanvas(8, 8));
    expect(renderTexture.context2D, isNotNull);
    expect(renderTexture.canvas, isNull);

    final bitmapData = BitmapData.fromRenderTextureQuad(renderTexture.quad)
      ..fillRect(Rectangle<num>(0, 0, 8, 8), Color.Blue);

    expect(bitmapData.getPixel32(2, 2), Color.Blue);
    expect(bitmapData.renderTexture.surface.width, 8);
    expect(bitmapData.renderTexture.surface.height, 8);
  });
}

class _TestOffscreenHost implements StageHost {
  final OffscreenCanvas canvas;
  Stage? attachedStage;
  var focusCount = 0;

  _TestOffscreenHost(this.canvas);

  @override
  num get devicePixelRatio => 2;

  @override
  RenderSurface get renderSurface => renderSurfaceFrom(canvas);

  @override
  StageViewport get viewport => const StageViewport(width: 160, height: 90);

  @override
  void attach(Stage stage) => attachedStage = stage;

  @override
  void detach(Stage stage) {
    if (identical(attachedStage, stage)) attachedStage = null;
  }

  @override
  void focus() => focusCount++;

  @override
  void setCursor(String cursor) {}

  @override
  void setViewportSize(int width, int height) {}
}
