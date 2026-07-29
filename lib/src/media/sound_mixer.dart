part of '../media.dart';

bool _isAudioContextSupported() => window.has('AudioContext');

class SoundMixer {
  static SoundEngine? _engineDetected;
  static SoundEngine? _engineOverride;
  static var _soundTransform = SoundTransform();
  static final _audioContextStateChanges = StreamController<SoundMixerAudioContextState>.broadcast();

  static WebAudioApiMixer? _webAudioApiMixer;
  static AudioElementMixer? _audioElementMixer;

  //---------------------------------------------------------------------------

  /// Get or set the [SoundEngine] that is used to load and play sounds.
  ///
  /// The engine is automatically detected based on the best engine supported
  /// by the browser. It is possible to override the detected engine with a
  /// different one. Setting the engine to `null` will switch back to the
  /// automatically detected engine.

  static SoundEngine get engine {
    _initEngine();
    return _engineOverride ?? _engineDetected!;
  }

  static set engine(SoundEngine value) {
    _engineOverride = value;
    _initEngine();
  }

  //---------------------------------------------------------------------------

  static SoundTransform get soundTransform => _soundTransform;

  static set soundTransform(SoundTransform value) {
    _initEngine();
    _soundTransform = value;
    _webAudioApiMixer?.applySoundTransform(_soundTransform);
    _audioElementMixer?.applySoundTransform(_soundTransform);
  }

  //---------------------------------------------------------------------------

  /// The current Web Audio context state and clock, or `null` when Web Audio is
  /// not the active sound engine.

  static SoundMixerAudioContextState? get audioContextState {
    _initEngine();
    return _getAudioContextState();
  }

  /// Emits whenever the browser reports a Web Audio context state change.

  static Stream<SoundMixerAudioContextState> get onAudioContextStateChange {
    _initEngine();
    return _audioContextStateChanges.stream;
  }

  //---------------------------------------------------------------------------

  /// A helper method to unlock audio on mobile devices.
  ///
  /// Some mobile devices (like iOS) do not allow audio playback by default.
  /// Call this method from a click or touch-end event to unlock the website for
  /// audio playback.
  ///
  ///     stage.onMouseClick.first.then((e) {
  ///       SoundMixer.unlockMobileAudio();
  ///     });

  static void unlockMobileAudio() => unlockMobileAudioAsync().ignore();

  /// Unlocks Web Audio during a user interaction and reports the resulting
  /// context state.
  ///
  /// Unlike [unlockMobileAudio], errors are returned to the caller.

  static Future<SoundMixerAudioContextState?> unlockMobileAudioAsync() async {
    if (engine != .WebAudioApi) return null;

    final context = WebAudioApiMixer.audioContext;
    final resumeFuture = context.resume().toDart;
    final source = context.createBufferSource();
    source.buffer = context.createBuffer(1, 1, 22050);
    source.connect(context.destination);
    source.start(0);
    await resumeFuture;
    return _getAudioContextState();
  }

  /// Suspends the Web Audio context and reports the resulting state.

  static Future<SoundMixerAudioContextState?> suspendAudioContext() async {
    if (engine != .WebAudioApi) return null;

    await WebAudioApiMixer.audioContext.suspend().toDart;
    return _getAudioContextState();
  }

  /// Resumes the Web Audio context and reports the resulting state.

  static Future<SoundMixerAudioContextState?> resumeAudioContext() async {
    if (engine != .WebAudioApi) return null;

    await WebAudioApiMixer.audioContext.resume().toDart;
    return _getAudioContextState();
  }

  //---------------------------------------------------------------------------
  //---------------------------------------------------------------------------

  static void _initEngine() {
    if (_engineDetected != null) return;

    _engineDetected = .AudioElement;
    _audioElementMixer = AudioElementMixer();

    if (_isAudioContextSupported()) {
      _engineDetected = .WebAudioApi;
      _webAudioApiMixer = WebAudioApiMixer();
      WebAudioApiMixer.audioContext.addEventListener('statechange', ((html.Event _) {
        final state = _getAudioContextState();
        if (state != null) _audioContextStateChanges.add(state);
      }).toJS);
    }

    final ua = html.window.navigator.userAgent;

    if (ua.contains('IEMobile')) {
      if (ua.contains('9.0')) {
        _engineDetected = .Mockup;
      }
    }

    if (ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod')) {
      if (ua.contains('OS 3') || ua.contains('OS 4') || ua.contains('OS 5')) {
        _engineDetected = .Mockup;
      }
    }

    if (AudioLoader.supportedTypes.isEmpty) {
      _engineDetected = .Mockup;
    }

    print('StageXL sound engine  : ${engine.name}');
  }

  static SoundMixerAudioContextState? _getAudioContextState() {
    if ((_engineOverride ?? _engineDetected) != .WebAudioApi) return null;

    final context = WebAudioApiMixer.audioContext;
    return SoundMixerAudioContextState(context.state, context.currentTime);
  }
}

final class SoundMixerAudioContextState {
  final String state;
  final num currentTime;

  const SoundMixerAudioContextState(this.state, this.currentTime);

  @override
  String toString() => '$state at ${currentTime.toStringAsFixed(3)}s';
}
