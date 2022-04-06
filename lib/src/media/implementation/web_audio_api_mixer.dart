part of stagexl.media;

class WebAudioApiMixer {
  static final AudioContext audioContext = AudioContext();

  AudioNode? _inputNode;
  late final GainNode _volumeNode;

  WebAudioApiMixer([AudioNode? inputNode]) {
    _inputNode = inputNode ?? audioContext.destination;
    _volumeNode = audioContext.createGain();
    _volumeNode.connectNode(_inputNode!);
  }

  void applySoundTransform(SoundTransform soundTransform) {
    final time = audioContext.currentTime;

    // Sometimes in Safari the current time is null.
    // Unfortunately, I don't think there is any
    // practical workaround, so just silently return here.
    if (time == null) return;

    final value = pow(soundTransform.volume, 2);
    _volumeNode.gain?.setValueAtTime(value, time);
  }

  AudioNode get inputNode => _volumeNode;
}
