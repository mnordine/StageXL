@TestOn('browser')
library;

import 'dart:async';

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  final adapter = _TestSoundWorkerAdapter();

  setUpAll(() => SoundMixer.useWorkerAdapter(adapter));

  test('loads mapped audio through the worker adapter', () async {
    final options = SoundLoadOptions()
      ..mp3 = false
      ..mp4 = false
      ..ogg = false
      ..opus = true
      ..ac3 = false
      ..wav = false
      ..ignoreErrors = false
      ..corsEnabled = true;
    final manifest = AssetManifest({'audio/test.opus': 'audio/test.hashed.opus'});

    final sound = await Sound.load('/audio/test.opus', options, manifest);

    expect(sound.engine, SoundEngine.Worker);
    expect(sound.length, 3.5);
    expect(adapter.loadedUrls, ['/audio/test.hashed.opus']);
    expect(adapter.ignoreErrors, isFalse);
    expect(adapter.corsEnabled, isTrue);
    expect(Sound.supportedTypes, ['opus']);
  });

  test('forwards channel controls and completion', () async {
    final sound = await Sound.load('/audio/test.opus', SoundLoadOptions()..opus = true);
    final channel = sound.playSegment(0.5, 2, true, SoundTransform(0.75, -0.25));
    final channelId = adapter.lastChannelId;

    expect(adapter.lastPlay, {
      'soundId': 7,
      'startTime': 0.5,
      'duration': 2,
      'loop': true,
      'volume': 0.75,
      'pan': -0.25,
    });

    channel.position = 1.25;
    channel.pause();
    channel.soundTransform = SoundTransform(0.4, 0.2);

    expect(adapter.positions[channelId], 1.25);
    expect(adapter.paused[channelId], isTrue);
    expect(adapter.transforms[channelId], (volume: 0.4, pan: 0.2));

    final completed = channel.onComplete.first;
    adapter.complete(channelId);
    await completed;
    expect(channel.stopped, isTrue);
  });

  test('forwards the global mixer transform', () {
    SoundMixer.soundTransform = SoundTransform(0.3, -0.1);
    expect(adapter.mixerTransform, (volume: 0.3, pan: -0.1));
  });
}

class _TestSoundWorkerAdapter implements SoundWorkerAdapter {
  @override
  final supportedTypes = ['opus'];
  final _completeController = StreamController<int>.broadcast(sync: true);
  final positions = <int, num>{};
  final paused = <int, bool>{};
  final transforms = <int, ({num volume, num pan})>{};
  List<String>? loadedUrls;
  Map<String, Object?>? lastPlay;
  ({num volume, num pan})? mixerTransform;
  bool? ignoreErrors;
  bool? corsEnabled;
  var lastChannelId = -1;
  var _nextChannelId = 0;

  @override
  Stream<int> get onChannelComplete => _completeController.stream;

  @override
  Future<SoundWorkerLoadResult> load(
    List<String> urls, {
    required bool ignoreErrors,
    required bool corsEnabled,
  }) async {
    loadedUrls = urls;
    this.ignoreErrors = ignoreErrors;
    this.corsEnabled = corsEnabled;
    return const SoundWorkerLoadResult(7, 3.5);
  }

  @override
  Future<SoundWorkerLoadResult> loadDataUrl(
    String dataUrl, {
    required bool ignoreErrors,
  }) async => const SoundWorkerLoadResult(8, 1);

  @override
  int play(
    int soundId, {
    required num startTime,
    required num duration,
    required bool loop,
    required SoundTransform soundTransform,
  }) {
    lastPlay = {
      'soundId': soundId,
      'startTime': startTime,
      'duration': duration,
      'loop': loop,
      'volume': soundTransform.volume,
      'pan': soundTransform.pan,
    };
    return lastChannelId = _nextChannelId++;
  }

  @override
  void setChannelPosition(int channelId, num position) => positions[channelId] = position;

  @override
  void setChannelPaused(int channelId, bool paused) => this.paused[channelId] = paused;

  @override
  void setChannelSoundTransform(int channelId, SoundTransform soundTransform) =>
      transforms[channelId] = (volume: soundTransform.volume, pan: soundTransform.pan);

  @override
  void stopChannel(int channelId) => complete(channelId);

  @override
  void setSoundTransform(SoundTransform soundTransform) =>
      mixerTransform = (volume: soundTransform.volume, pan: soundTransform.pan);

  @override
  void unlock() {}

  void complete(int channelId) => _completeController.add(channelId);
}
