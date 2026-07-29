import 'dart:math' as math;

import 'package:stagexl/stagexl.dart';
import 'package:web/web.dart';

const _stageWidth = 1120;
const _stageHeight = 700;

Future<void> main() async {
  final options = StageOptions()
    ..stageAlign = .NONE
    ..stageScaleMode = .SHOW_ALL
    ..backgroundColor = 0xFF0B1020
    ..antialias = true
    ..renderEngine = _renderEngine(Uri.base.queryParameters['engine']);

  final canvas = document.querySelector('#stage') as HTMLCanvasElement;
  final stage = await Stage.create(
    canvas,
    width: _stageWidth,
    height: _stageHeight,
    options: options,
  );
  RenderLoop().addStage(stage);

  _addBackdrop(stage);
  _addLabel(stage, 'RENDER LAYERS', 42, 30, 13, 0xFF72E3FF, bold: true);
  _addLabel(
    stage,
    'Logical parents. Independent draw order.',
    42,
    54,
    30,
    0xFFF5F8FF,
    bold: true,
  );
  _addLabel(
    stage,
    'Cards keep their pilot parents and transforms.',
    44,
    96,
    15,
    0xFFA9B7D0,
  );
  _addLabel(
    stage,
    'The layer changes only where they are drawn.',
    44,
    117,
    15,
    0xFFA9B7D0,
  );

  final world = Sprite();
  stage.addChild(world);
  _addWorldPanel(world);

  final pilots = [
    _createPilot('NOVA', 0xFF735CFF, 0xFFB6A9FF, 255, 0.102, 0.03),
    _createPilot('EMBER', 0xFFFF5F7A, 0xFFFFB56B, 405, 0.083, 0.42),
    _createPilot('MINT', 0xFF23C9A8, 0xFF8CF6DA, 555, 0.091, 0.72),
  ];
  for (final pilot in pilots) {
    world.addChild(pilot.character);
  }

  _addForegroundStructure(world);

  final statusLayer = RenderLayer(sortableChildren: true);
  stage.addChild(statusLayer);
  for (final pilot in pilots) {
    statusLayer.attach(pilot.statusCard);
  }

  var layersEnabled = true;
  final toggle = document.querySelector('#layerToggle') as HTMLButtonElement;
  final mode = document.querySelector('#layerMode') as HTMLElement;
  final contract = document.querySelector('#layerContract') as HTMLElement;

  void updateControls() {
    final cardsKeepLogicalParents = pilots.every(
      (pilot) => pilot.statusCard.parent == pilot.character,
    );
    final cardsUseStatusLayer = pilots.every(
      (pilot) => pilot.statusCard.parentRenderLayer == statusLayer,
    );
    toggle.textContent = layersEnabled
        ? 'Disable render layer'
        : 'Enable render layer';
    toggle.className = layersEnabled ? 'layer-toggle is-on' : 'layer-toggle';
    mode.textContent = layersEnabled
        ? 'LAYERED: cards render above the gate'
        : 'LOGICAL: the gate can cover the cards';
    contract.textContent = [
      'card.parent == pilot: $cardsKeepLogicalParents',
      'card.parentRenderLayer == statusLayer: $cardsUseStatusLayer',
      'renderer: ${stage.renderEngine.name}',
    ].join('\n');
  }

  toggle.onClick.listen((_) {
    layersEnabled = !layersEnabled;
    for (final pilot in pilots) {
      if (layersEnabled) {
        statusLayer.attach(pilot.statusCard);
      } else {
        statusLayer.detach(pilot.statusCard);
      }
    }
    updateControls();
  });
  updateControls();

  var elapsed = 0.0;
  stage.onEnterFrame.listen((event) {
    elapsed += event.passedTime.toDouble();
    for (final pilot in pilots) {
      final progress = (elapsed * pilot.speed + pilot.phase) % 1;
      pilot.character
        ..x = 105 + progress * 910
        ..y = pilot.laneY + math.sin(elapsed * 2.4 + pilot.phase * 10) * 5;
      pilot.statusCard.zIndex = pilot.character.y.round();
      pilot.healthFill.scaleX =
          0.58 + math.sin(elapsed * 1.2 + pilot.phase * 8) * 0.28;
      pilot.beacon.alpha =
          0.55 + math.sin(elapsed * 3.6 + pilot.phase * 5) * 0.3;
    }
  });
}

RenderEngine _renderEngine(String? value) => switch (value) {
  'canvas' => .Canvas2D,
  'webgl1' => .WebGL,
  'webgpu' => .WebGPU,
  _ => .WebGL2,
};

void _addBackdrop(Stage stage) {
  final glow = Shape();
  glow.graphics
    ..circle(1000, 20, 360)
    ..fillColor(0x182C7DFF)
    ..circle(80, 650, 300)
    ..fillColor(0x1423C9A8);
  stage.addChild(glow);
}

void _addWorldPanel(Sprite world) {
  final panel = Shape();
  panel.graphics
    ..rectRound(32, 142, 1056, 516, 24, 24)
    ..fillColor(0xEE11182A)
    ..rectRound(32, 142, 1056, 516, 24, 24)
    ..strokeColor(0x445D759C, 2);
  world.addChild(panel);

  for (var row = 0; row < 3; row++) {
    final y = 255 + row * 150;
    final lane = Shape();
    lane.graphics
      ..rect(70, y + 42, 980, 2)
      ..fillColor(0x285D759C);
    world.addChild(lane);
    _addLabel(
      world,
      'LANE 0${row + 1}',
      58,
      y - 18,
      11,
      0xFF64738E,
      bold: true,
    );
  }

  _addLabel(world, 'LOGICAL WORLD', 58, 162, 12, 0xFF64738E, bold: true);
  _addLabel(
    world,
    'Pilots, scenery, and foreground gate share this parent tree',
    58,
    184,
    13,
    0xFF8391AA,
  );
}

_Pilot _createPilot(
  String name,
  int color,
  int accent,
  double laneY,
  double speed,
  double phase,
) {
  final character = Sprite();

  final shadow = Shape();
  shadow.graphics
    ..ellipse(-34, 22, 68, 18)
    ..fillColor(0x52000000);

  final avatar = Shape();
  avatar.graphics
    ..circle(0, 0, 28)
    ..fillColor(color)
    ..circle(-8, -7, 7)
    ..fillColor(0xFFF7FAFF)
    ..circle(10, -7, 7)
    ..fillColor(0xFFF7FAFF)
    ..rectRound(-16, 9, 32, 8, 5, 5)
    ..fillColor(0xAA07101E)
    ..circle(0, 0, 28)
    ..strokeColor(accent, 3);

  final beacon = Shape()
    ..x = 20
    ..y = -22;
  beacon.graphics
    ..circle(0, 0, 6)
    ..fillColor(0xFFFFFFFF);

  final statusCard = Sprite()
    ..x = -66
    ..y = -88;
  final connector = Shape();
  connector.graphics
    ..rect(64, 42, 3, 26)
    ..fillColor(0x8872E3FF);
  final card = Shape();
  card.graphics
    ..rectRound(0, 0, 132, 46, 13, 13)
    ..fillColor(0xF2182238)
    ..rectRound(0, 0, 132, 46, 13, 13)
    ..strokeColor(accent, 2);
  final marker = Shape();
  marker.graphics
    ..rectRound(9, 10, 8, 26, 4, 4)
    ..fillColor(color);
  final healthTrack = Shape();
  healthTrack.graphics
    ..rectRound(24, 29, 96, 6, 4, 4)
    ..fillColor(0xFF303C55);
  final healthFill = Shape()
    ..x = 24
    ..y = 29;
  healthFill.graphics
    ..rectRound(0, 0, 96, 6, 4, 4)
    ..fillColor(accent);
  final nameLabel =
      TextField(name, TextFormat('Arial', 12, 0xFFF5F8FF, bold: true))
        ..x = 24
        ..y = 7
        ..autoSize = TextFieldAutoSize.LEFT;

  statusCard
    ..addChild(connector)
    ..addChild(card)
    ..addChild(marker)
    ..addChild(healthTrack)
    ..addChild(healthFill)
    ..addChild(nameLabel);
  character
    ..addChild(shadow)
    ..addChild(avatar)
    ..addChild(beacon)
    ..addChild(statusCard);

  return _Pilot(
    character: character,
    statusCard: statusCard,
    healthFill: healthFill,
    beacon: beacon,
    laneY: laneY,
    speed: speed,
    phase: phase,
  );
}

void _addForegroundStructure(Sprite world) {
  final gate = Sprite();

  final shadow = Shape();
  shadow.graphics
    ..rectRound(400, 205, 320, 405, 24, 24)
    ..fillColor(0xB5000000);
  gate.addChild(shadow);

  final body = Shape();
  body.graphics
    ..rectRound(386, 188, 320, 405, 24, 24)
    ..fillColor(0xF329344A)
    ..rectRound(386, 188, 320, 405, 24, 24)
    ..strokeColor(0xFF607292, 3)
    ..rectRound(410, 232, 272, 317, 16, 16)
    ..fillColor(0xFF1B2437);
  gate.addChild(body);

  for (var i = 0; i < 9; i++) {
    final stripe = Shape();
    stripe.graphics
      ..rect(418 + i * 31, 240, 12, 301)
      ..fillColor(i.isEven ? 0x144DD8FF : 0x0AFFFFFF);
    gate.addChild(stripe);
  }

  final badge = Shape();
  badge.graphics
    ..rectRound(455, 365, 182, 64, 14, 14)
    ..fillColor(0xFF11192A)
    ..rectRound(455, 365, 182, 64, 14, 14)
    ..strokeColor(0x665D759C, 2);
  gate.addChild(badge);
  _addLabel(gate, 'FOREGROUND', 480, 377, 11, 0xFF72E3FF, bold: true);
  _addLabel(gate, 'OCCLUDER', 480, 395, 18, 0xFFF5F8FF, bold: true);
  _addLabel(
    gate,
    'Cards pass behind this gate when the layer is disabled',
    424,
    568,
    12,
    0xFFA9B7D0,
  );

  world.addChild(gate);
}

TextField _addLabel(
  DisplayObjectContainer parent,
  String text,
  num x,
  num y,
  num size,
  int color, {
  bool bold = false,
}) {
  final label = TextField(text, TextFormat('Arial', size, color, bold: bold))
    ..x = x
    ..y = y
    ..autoSize = TextFieldAutoSize.LEFT;
  parent.addChild(label);
  return label;
}

final class _Pilot {
  final Sprite character;
  final Sprite statusCard;
  final Shape healthFill;
  final Shape beacon;
  final double laneY;
  final double speed;
  final double phase;

  const _Pilot({
    required this.character,
    required this.statusCard,
    required this.healthFill,
    required this.beacon,
    required this.laneY,
    required this.speed,
    required this.phase,
  });
}
