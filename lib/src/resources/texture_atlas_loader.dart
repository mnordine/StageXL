part of stagexl.resources;

/// The base class for a custom texture atlas loader.
///
/// Use the [TextureAtlas.withLoader] function to load a texture atlas
/// from a custom source by implementing a TextureAtlasLoader class.

abstract class TextureAtlasLoader {

  /// Get the source of the texture atlas.
  Future<String> getSource();

  /// Get the RenderTextureQuad for the texture atlas.
  Future<RenderTextureQuad> getRenderTextureQuad(String filename);
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderFile extends TextureAtlasLoader {

  String _sourceUrl = "";
  bool _webpAvailable = false;
  bool _corsEnabled = false;
  num _pixelRatio = 1.0;

  static bool _highDpi;

  _TextureAtlasLoaderFile(String sourceUrl, BitmapDataLoadOptions options) {

    if (options == null) options = BitmapData.defaultLoadOptions;

    var pixelRatio = 1.0;
    var pixelRatioRegexp = new RegExp(r"@(\d)x");
    var pixelRatioMatch = pixelRatioRegexp.firstMatch(sourceUrl);

    if (pixelRatioMatch != null) {
      var match = pixelRatioMatch;
      var maxPixelRatio = options.maxPixelRatio;
      var originPixelRatio = int.parse(match.group(1));
      var devicePixelRatio = env.devicePixelRatio;
      var loaderPixelRatio = minNum(devicePixelRatio, maxPixelRatio).round();

      if (!StageXL.environment.isSafari && _isHighDpi()) loaderPixelRatio = minNum(maxPixelRatio, 2);
      pixelRatio = loaderPixelRatio / originPixelRatio;

      sourceUrl = sourceUrl.replaceRange(match.start, match.end, "@${loaderPixelRatio}x");
    }

    _sourceUrl = sourceUrl;
    _webpAvailable = options.webp;
    _corsEnabled = options.corsEnabled;
    _pixelRatio = pixelRatio;
  }

  bool _isHighDpi()
  {
    if (_highDpi != null) return _highDpi;

    final diff = 300 - 56;
    final xs = new Iterable.generate(diff, (i) => 56 + i);
    final match = xs.firstWhere((x) => window.matchMedia('(max-resolution: ${x}dpi)').matches, orElse: () => 0);
    if (match == null) return false;

    _highDpi =  match > 100;
    return _highDpi;
  }

  @override
  Future<String> getSource() {
    return HttpRequest.getString(_sourceUrl);
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    var imageUrl = replaceFilename(_sourceUrl, filename);
    var imageLoader = new ImageLoader(imageUrl, _webpAvailable, _corsEnabled);
    var imageElement = await imageLoader.done;
    var renderTexture = new RenderTexture.fromImageElement(imageElement);
    var renderTextureQuad = renderTexture.quad.withPixelRatio(_pixelRatio);
    return renderTextureQuad;
  }
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderTextureAtlas extends TextureAtlasLoader {

  final TextureAtlas textureAtlas;
  final String namePrefix;
  final String source;

  _TextureAtlasLoaderTextureAtlas(this.textureAtlas, this.namePrefix, this.source);

  @override
  Future<String> getSource() {
    return new Future.value(this.source);
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    var name = this.namePrefix + getFilenameWithoutExtension(filename);
    var bitmapData = this.textureAtlas.getBitmapData(name);
    return bitmapData.renderTextureQuad;
  }
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderBitmapData extends TextureAtlasLoader {

  final BitmapData bitmapData;
  final String source;

  _TextureAtlasLoaderBitmapData(this.bitmapData, this.source);

  @override
  Future<String> getSource() {
    return new Future.value(this.source);
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) {
    return new Future.value(this.bitmapData.renderTextureQuad);
  }
}
