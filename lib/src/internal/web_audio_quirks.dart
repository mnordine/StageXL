// Chromium 152 can repeat the last render quantum at a buffer boundary;
// 153 and 154 still produce incorrect samples at that boundary. The fix landed
// in Chromium 155: https://chromium-review.googlesource.com/c/chromium/src/+/8365294
// Match the engine version so Chromium-based browsers share this workaround,
// while Chrome on iOS (CriOS, using WebKit) does not enable it.
bool needsWebAudioLoopGuard(String userAgent) {
  // Match Chrome/ or HeadlessChrome/ at a word boundary; capture the major
  // version's digits before the literal dot. The optional Headless group is non-capturing.
  // Example: 'Mozilla/5.0 HeadlessChrome/152.0.0.0 Safari/537.36' captures '152'.
  final match = RegExp(r'\b(?:Headless)?Chrome/(\d+)\.').firstMatch(userAgent);
  final major = int.tryParse(match?.group(1) ?? '');
  return major != null && major >= 152 && major < 155;
}
