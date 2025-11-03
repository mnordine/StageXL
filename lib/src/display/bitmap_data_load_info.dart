part of '../display.dart';

/// The BitmapDataLoadInfo creates information about the best matching image
/// file based on the specified image url, the pixelRatios and the current
/// display configuration.

class BitmapDataLoadInfo {
  final String _sourceUrl;
  String _loaderUrl;
  double _pixelRatio = 1;

  BitmapDataLoadInfo(String url, List<double> pixelRatios)
    : _sourceUrl = url,
      _loaderUrl = url {

    final pixelRatioRegexp = RegExp(r'@(\d+(.\d+)?)x');
    final pixelRatioMatch = pixelRatioRegexp.firstMatch(sourceUrl);

    if (pixelRatioMatch != null) {
      final match = pixelRatioMatch;
      final originPixelRatioFractions = (match.group(2) ?? '.').length - 1;
      final originPixelRatio = double.parse(match.group(1)!);
      final devicePixelRatio = env.devicePixelRatio;
      final loaderPixelRatio = pixelRatios.fold<num>(0.0, (a, b) {
        final aDelta = (a - devicePixelRatio).abs();
        final bDelta = (b - devicePixelRatio).abs();
        return aDelta < bDelta && a > 0.0 ? a : b;
      });
      final name = loaderPixelRatio.toStringAsFixed(originPixelRatioFractions);
      _loaderUrl = url.replaceRange(match.start + 1, match.end - 1, name);
      _pixelRatio = loaderPixelRatio / originPixelRatio;
    }
  }

  String get sourceUrl => _sourceUrl;
  String get loaderUrl => _loaderUrl;
  double get pixelRatio => _pixelRatio;

  bool get canReplaceExtension => _extensionPattern.firstMatch(loaderUrl) != null;

  String get loaderUrlWebp => _loaderUrlFor('webp');
  String get loaderUrlAvif => _loaderUrlFor('avif');

  static final _extensionPattern = RegExp(r'\.(png|jpg|jpeg)$');

  String _loaderUrlFor(String extension) {
    final match = _extensionPattern.firstMatch(loaderUrl);
    if (match != null) {
      return '${loaderUrl.substring(0, match.start)}.$extension';
    } else {
      return loaderUrl;
    }
  }
}
