part of stagexl.media;

class WebAudioApiMixer {
  static final AudioContext audioContext = AudioContext();

  AudioNode _inputNode;
  final GainNode _volumeNode;

  WebAudioApiMixer([AudioNode inputNode]) : _volumeNode = audioContext.createGain() {
    _inputNode = inputNode ?? audioContext.destination;
    if (_inputNode != null) _volumeNode.connectNode(_inputNode);
  }

  void applySoundTransform(SoundTransform soundTransform) {
    if (audioContext.currentTime == null) return;

    var time = audioContext.currentTime;
    var value = pow(soundTransform.volume, 2);
    _volumeNode.gain?.setValueAtTime(value, time);
  }

  AudioNode get inputNode => _volumeNode;
}
