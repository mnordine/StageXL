import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 960;
const _stageHeight = 540;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .TOP_LEFT
    ..stageScaleMode = .NO_SCALE
    ..backgroundColor = 0xFF08111F
    ..renderEngine = .WebGPU;

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(canvas, width: _stageWidth, height: _stageHeight, options: options);
  final renderLoop = RenderLoop();
  renderLoop.addStage(stage);

  _addLabel(stage, 'StageXL WebGPU VideoObject', 28, 26, 26, 0xFFFFFFFF);
  _addLabel(stage, 'Renderer: ${stage.renderEngine.name}', 28, 60, 15, 0xFFB9C7D8);
  final status = _addLabel(stage, 'Loading stars.mp4', 28, 92, 15, 0xFFB9C7D8);

  final video = await Video.load('stars.mp4');
  video
    ..muted = true
    ..loop = true
    ..playsInline = true;

  final videoObject = VideoObject(video, true);
  final scale = math.min(720 / videoObject.bounds.width, 360 / videoObject.bounds.height);
  videoObject
    ..x = (_stageWidth - videoObject.bounds.width * scale) / 2
    ..y = 125
    ..scaleX = scale
    ..scaleY = scale;

  stage
    ..addChild(_frame(
      videoObject.x - 12,
      videoObject.y - 12,
      videoObject.bounds.width * scale + 24,
      videoObject.bounds.height * scale + 24,
    ))
    ..addChild(videoObject);

  status.text = 'VideoObject source: ${video.videoElement.videoWidth} x ${video.videoElement.videoHeight}';
  _bindControls(video);
}

Shape _frame(num x, num y, num width, num height) {
  final shape = Shape();
  shape.graphics
    ..rect(x, y, width, height)
    ..fillColor(0xFF111B2B)
    ..rect(x + 12, y + 12, width - 24, height - 24)
    ..strokeColor(0x884A9EFF, 2);
  return shape;
}

void _bindControls(Video video) {
  final playPause = document.querySelector('#playPause') as HTMLButtonElement?;
  if (playPause == null) return;

  void updateButton() {
    playPause.textContent = video.isPlaying ? 'Pause' : 'Play';
  }

  playPause.onClick.listen((_) {
    if (video.isPlaying) {
      video.pause();
    } else {
      video.play();
    }
    updateButton();
  });

  video.onPlay.listen((_) => updateButton());
  video.onPause.listen((_) => updateButton());
  updateButton();
}

TextField _addLabel(DisplayObjectContainer parent, String text, num x, num y, num size, int color) {
  final label = TextField(text, TextFormat('Arial', size, color))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
  return label;
}
