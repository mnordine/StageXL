import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:stagexl/stagexl_worker.dart';

void main() {
  runStageXLWorker((host) async {
    Sound.defaultLoadOptions.opus = true;
    final clickSound = await Sound.load('music.opus');
    final options = StageOptions()
      ..renderEngine = .WebGPU
      ..inputEventMode = .MouseAndTouch
      ..stageAlign = .NONE
      ..stageScaleMode = .SHOW_ALL
      ..backgroundColor = 0xFF10141D;
    final stage = await host.createStage(width: 800, height: 500, options: options);
    final renderLoop = RenderLoop()..addStage(stage);

    final title = TextField(
      'StageXL OffscreenCanvas worker',
      TextFormat('Arial', 26, 0xFFFFFFFF),
    )
      ..x = 30
      ..y = 24
      ..autoSize = TextFieldAutoSize.LEFT;
    final detail = TextField(
      'The scene runtime runs in the worker; audio is hosted on the browser main thread.',
      TextFormat('Arial', 14, 0xFFB9C7D8),
    )
      ..x = 30
      ..y = 64
      ..autoSize = TextFieldAutoSize.LEFT;

    final card = Sprite()
      ..x = 400
      ..y = 285
      ..pivotX = 110
      ..pivotY = 80
      ..mouseCursor = MouseCursor.POINTER
      ..filters = [BlurFilter(2, 2)];
    card.graphics
      ..rect(0, 0, 220, 160)
      ..fillColor(0xFF2EC4B6)
      ..rect(14, 14, 192, 132)
      ..fillColor(0xFF182131);

    final prompt = TextField('Click or tap me', TextFormat('Arial', 19, 0xFFFFFFFF))
      ..x = 45
      ..y = 63
      ..autoSize = TextFieldAutoSize.LEFT;
    card.addChild(prompt);
    final status = TextField('Waiting for forwarded input', TextFormat('Arial', 14, 0xFFB9C7D8))
      ..x = 30
      ..y = 450
      ..autoSize = TextFieldAutoSize.LEFT;

    host.onMessage.listen((message) {
      if (message case {'kind': 'example:host-message'}) {
        status.text = 'Application message handled in worker';
        host.postMessage({'kind': 'example:host-message'});
      }
    });

    var direction = 1;
    SoundAnalyzer? soundAnalyzer;
    void reverse(InputEvent _) {
      direction *= -1;
      final channel = clickSound.playSegment(0, 1, false, SoundTransform(0.35));
      final analyzer = channel.soundAnalyzer!
        ..fftSize = 512
        ..smoothingTimeConstant = 0.2;
      soundAnalyzer = analyzer;
      channel.onComplete.first.then((_) {
        if (identical(soundAnalyzer, analyzer)) soundAnalyzer = null;
      });
      status.text = 'Input and audio handled through the worker host';
      host.postMessage({'kind': 'example:input'});
    }
    card.onMouseDown.listen(reverse);
    card.onTouchBegin.listen(reverse);

    stage
      ..addChild(title)
      ..addChild(detail)
      ..addChild(card)
      ..addChild(status);

    var elapsed = 0.0;
    stage.onEnterFrame.listen((event) {
      elapsed += event.passedTime.toDouble() * direction;
      card.rotation = math.sin(elapsed * 0.9) * 0.12;
      card.scaleX = card.scaleY = 1 + math.sin(elapsed * 1.3) * 0.04;
      if (soundAnalyzer case final analyzer?) {
        final level = analyzer.getFrequencyRangeLevel(30, 120);
        status.text = 'Worker audio bass level: ${level.toStringAsFixed(6)}';
      }
    });

    // Keep ownership explicit for applications that later stop or replace it.
    renderLoop.targetFramesPerSecond = 0;
  });
}
