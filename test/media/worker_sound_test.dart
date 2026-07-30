@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

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
    final baseline = ResourceDiagnostics.snapshot();
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
    expect(ResourceDiagnostics.snapshot().growthSince(baseline), isEmpty);
  });

  test('forwards the global mixer transform', () {
    SoundMixer.soundTransform = SoundTransform(0.3, -0.1);
    expect(adapter.mixerTransform, (volume: 0.3, pan: -0.1));
  });

  test('resource manager disposal stops active sound channels', () async {
    final baseline = ResourceDiagnostics.snapshot();
    final resources = ResourceManager()
      ..addSound('/audio/test.opus', '/audio/test.opus', SoundLoadOptions()..opus = true);
    await resources.load();
    final channel = resources.getSound('/audio/test.opus').play(true);

    expect(channel.stopped, isFalse);

    resources.dispose();

    expect(channel.stopped, isTrue);
    expect(ResourceDiagnostics.snapshot().growthSince(baseline), isEmpty);
  });

  test('uses a backpressured scalar request for frequency ranges', () async {
    final sound = await Sound.load('/audio/test.opus', SoundLoadOptions()..opus = true);
    final channel = sound.play();
    final analyzer = channel.soundAnalyzer!;
    final channelId = adapter.lastChannelId;

    analyzer
      ..fftSize = 512
      ..minDecibels = -64
      ..maxDecibels = -16
      ..smoothingTimeConstant = 0.16;

    expect(analyzer.getFrequencyRangeLevel(30, 120), 0);
    expect(adapter.analyzerConfiguration, (
      channelId: channelId,
      fftSize: 512,
      minDecibels: -64,
      maxDecibels: -16,
      smoothingTimeConstant: 0.16,
    ));
    expect(adapter.rangeRequests, [(channelId: channelId, minHz: 30, maxHz: 120)]);
    expect(analyzer.getFrequencyRangeLevel(30, 120), 0);
    expect(adapter.rangeRequests.length, 1);

    adapter.completeRangeAnalysis(channelId, 0.42);

    analyzer
      ..fftSize = 512
      ..minDecibels = -64
      ..maxDecibels = -16
      ..smoothingTimeConstant = 0.16;
    expect(analyzer.getFrequencyRangeLevel(30, 120), 0.42);
    expect(analyzer.sampleRate, 48000);
    expect(adapter.rangeRequests.length, 2);
    expect(adapter.analyzerConfigurationCount, 1);
    channel.stop();
  });

  test('supports full byte frequency data when requested', () async {
    final sound = await Sound.load('/audio/test.opus', SoundLoadOptions()..opus = true);
    final channel = sound.play();
    final analyzer = channel.soundAnalyzer!..fftSize = 32;
    final channelId = adapter.lastChannelId;
    final data = Uint8List(analyzer.frequencyBinCount);

    analyzer.getByteFrequencyData(data);
    expect(data, everyElement(0));
    expect(adapter.byteDataRequests, [channelId]);

    adapter.completeByteAnalysis(channelId, Uint8List.fromList(List.generate(16, (index) => index)));
    analyzer.getByteFrequencyData(data);

    expect(data, List.generate(16, (index) => index));
    expect(adapter.byteDataRequests, [channelId, channelId]);
    channel.stop();
  });
}

class _TestSoundWorkerAdapter implements SoundWorkerAdapter {
  @override
  final supportedTypes = ['opus'];
  final _completeController = StreamController<int>.broadcast(sync: true);
  final _analysisController = StreamController<SoundWorkerAnalysisResult>.broadcast(sync: true);
  final positions = <int, num>{};
  final paused = <int, bool>{};
  final transforms = <int, ({num volume, num pan})>{};
  final rangeRequests = <({int channelId, num minHz, num maxHz})>[];
  final byteDataRequests = <int>[];
  List<String>? loadedUrls;
  Map<String, Object?>? lastPlay;
  ({num volume, num pan})? mixerTransform;
  ({
    int channelId,
    int fftSize,
    num minDecibels,
    num maxDecibels,
    num smoothingTimeConstant,
  })? analyzerConfiguration;
  bool? ignoreErrors;
  bool? corsEnabled;
  var analyzerConfigurationCount = 0;
  var lastChannelId = -1;
  var _nextChannelId = 0;

  @override
  Stream<int> get onChannelComplete => _completeController.stream;

  @override
  Stream<SoundWorkerAnalysisResult> get onAnalysis => _analysisController.stream;

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
  void configureAnalyzer(
    int channelId, {
    required int fftSize,
    required num minDecibels,
    required num maxDecibels,
    required num smoothingTimeConstant,
  }) {
    analyzerConfigurationCount++;
    analyzerConfiguration = (
      channelId: channelId,
      fftSize: fftSize,
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
      smoothingTimeConstant: smoothingTimeConstant,
    );
  }

  @override
  void requestByteFrequencyData(int channelId) => byteDataRequests.add(channelId);

  @override
  void requestFrequencyRangeLevel(int channelId, num minHz, num maxHz) =>
      rangeRequests.add((channelId: channelId, minHz: minHz, maxHz: maxHz));

  @override
  void stopChannel(int channelId) => complete(channelId);

  @override
  void setSoundTransform(SoundTransform soundTransform) =>
      mixerTransform = (volume: soundTransform.volume, pan: soundTransform.pan);

  @override
  void unlock() {}

  void complete(int channelId) => _completeController.add(channelId);

  void completeRangeAnalysis(int channelId, double level) => _analysisController.add(
    SoundWorkerAnalysisResult(channelId, 48000, frequencyRangeLevel: level),
  );

  void completeByteAnalysis(int channelId, Uint8List data) => _analysisController.add(
    SoundWorkerAnalysisResult(channelId, 48000, byteFrequencyData: data),
  );
}
