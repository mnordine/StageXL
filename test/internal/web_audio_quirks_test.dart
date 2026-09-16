import 'package:stagexl/src/internal/web_audio_quirks.dart';
import 'package:test/test.dart';

void main() {
  for (final major in [151, 152, 153, 154, 155, 156]) {
    test('Chrome $major only uses a guard for affected engine versions', () {
      final expected = [152, 153, 154].contains(major);
      expect(needsWebAudioLoopGuard('Mozilla/5.0 Chrome/$major.0.0.0 Safari/537.36'), expected);
      expect(needsWebAudioLoopGuard('Mozilla/5.0 HeadlessChrome/$major.0.0.0 Safari/537.36'), expected);
    });
  }

  test('uses the Chromium version for Edge, Opera and Android', () {
    expect(needsWebAudioLoopGuard('Mozilla/5.0 Chrome/152.0.0.0 Safari/537.36 Edg/152.0.0.0'), isTrue);
    expect(needsWebAudioLoopGuard('Mozilla/5.0 Chrome/153.0.0.0 Safari/537.36 OPR/135.0.0.0'), isTrue);
    expect(needsWebAudioLoopGuard('Mozilla/5.0 (Linux; Android 10; K) Chrome/154.0.0.0 Mobile Safari/537.36'), isTrue);
    expect(needsWebAudioLoopGuard('Mozilla/5.0 Chrome/155.0.0.0 Safari/537.36 Edg/155.0.0.0'), isFalse);
  });

  test('does not enable the guard for other engines or unknown versions', () {
    for (final userAgent in [
      'Mozilla/5.0 AppleWebKit/605.1.15 Version/26.0 Safari/605.1.15',
      'Mozilla/5.0 Gecko/20100101 Firefox/152.0',
      'Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 CriOS/152.0.0.0 Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 EdgiOS/152.0.0.0 Mobile/15E148 Safari/604.1',
      'Chrome/invalid',
      '',
    ]) {
      expect(needsWebAudioLoopGuard(userAgent), isFalse, reason: userAgent);
    }
  });
}
