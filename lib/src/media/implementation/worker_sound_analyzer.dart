part of '../../media.dart';

class WorkerSoundAnalyzer extends SoundAnalyzer {
  final int _channelId;
  late final StreamSubscription<SoundWorkerAnalysisResult> _analysisSubscription;
  Uint8List? _workerByteFrequencyData;
  ({num minHz, num maxHz})? _pendingRange;
  ({num minHz, num maxHz})? _cachedRange;
  var _fftSize = 2048;
  num _sampleRate = 0;
  var _minDecibels = -100.0;
  var _maxDecibels = -30.0;
  var _smoothingTimeConstant = 0.8;
  var _frequencyRangeLevel = 0.0;
  var _configurationDirty = false;
  var _requestPending = false;

  WorkerSoundAnalyzer(this._channelId) {
    _analysisSubscription = SoundMixer._workerAdapter!.onAnalysis
        .where((result) => result.channelId == _channelId)
        .listen(_onAnalysis);
  }

  @override
  int get fftSize => _fftSize;

  @override
  set fftSize(int value) {
    if (_fftSize == value) return;
    _fftSize = value;
    _workerByteFrequencyData = null;
    _cachedRange = null;
    _configurationDirty = true;
  }

  @override
  int get frequencyBinCount => _fftSize ~/ 2;

  @override
  num get sampleRate => _sampleRate;

  @override
  double get minDecibels => _minDecibels;

  @override
  set minDecibels(num value) {
    final doubleValue = value.toDouble();
    if (_minDecibels == doubleValue) return;
    _minDecibels = doubleValue;
    _configurationDirty = true;
  }

  @override
  double get maxDecibels => _maxDecibels;

  @override
  set maxDecibels(num value) {
    final doubleValue = value.toDouble();
    if (_maxDecibels == doubleValue) return;
    _maxDecibels = doubleValue;
    _configurationDirty = true;
  }

  @override
  double get smoothingTimeConstant => _smoothingTimeConstant;

  @override
  set smoothingTimeConstant(num value) {
    final doubleValue = value.toDouble();
    if (_smoothingTimeConstant == doubleValue) return;
    _smoothingTimeConstant = doubleValue;
    _configurationDirty = true;
  }

  @override
  void getByteFrequencyData(Uint8List data) {
    final frequencyData = _workerByteFrequencyData;
    if (frequencyData == null) {
      data.fillRange(0, data.length, 0);
    } else {
      final length = min(data.length, frequencyData.length);
      data.setRange(0, length, frequencyData);
      if (length < data.length) data.fillRange(length, data.length, 0);
    }
    _requestByteFrequencyData();
  }

  @override
  double getFrequencyRangeLevel(num minHz, num maxHz) {
    final range = (minHz: minHz, maxHz: maxHz);
    final level = _cachedRange == range ? _frequencyRangeLevel : 0.0;
    _requestFrequencyRangeLevel(range);
    return level;
  }

  void _requestByteFrequencyData() {
    if (_requestPending) return;
    _syncConfiguration();
    _requestPending = true;
    SoundMixer._workerAdapter!.requestByteFrequencyData(_channelId);
  }

  void _requestFrequencyRangeLevel(({num minHz, num maxHz}) range) {
    if (_requestPending) return;
    _syncConfiguration();
    _requestPending = true;
    _pendingRange = range;
    SoundMixer._workerAdapter!.requestFrequencyRangeLevel(_channelId, range.minHz, range.maxHz);
  }

  void _syncConfiguration() {
    if (!_configurationDirty) return;
    _configurationDirty = false;
    SoundMixer._workerAdapter!.configureAnalyzer(
      _channelId,
      fftSize: _fftSize,
      minDecibels: _minDecibels,
      maxDecibels: _maxDecibels,
      smoothingTimeConstant: _smoothingTimeConstant,
    );
  }

  void _onAnalysis(SoundWorkerAnalysisResult result) {
    _sampleRate = result.sampleRate;
    if (result.byteFrequencyData case final data?) {
      _workerByteFrequencyData = data;
    }
    if (result.frequencyRangeLevel case final level?) {
      _frequencyRangeLevel = level;
      _cachedRange = _pendingRange;
    }
    _pendingRange = null;
    _requestPending = false;
  }

  void dispose() => unawaited(_analysisSubscription.cancel());
}
