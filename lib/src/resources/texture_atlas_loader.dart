part of stagexl.resources;

/// The base class for a custom texture atlas loader.
///
/// Use the [TextureAtlas.withLoader] function to load a texture atlas
/// from a custom source by implementing a TextureAtlasLoader class.

abstract class TextureAtlasLoader {

  /// Get the pixel ratio of the texture atlas.
  double getPixelRatio();

  /// Get the source of the texture atlas.
  Future<String> getSource();

  /// Get the RenderTextureQuad for the texture atlas.
  Future<RenderTextureQuad> getRenderTextureQuad(String filename);
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderFile extends TextureAtlasLoader {

  BitmapDataLoadOptions _loadOptions;
  BitmapDataLoadInfo _loadInfo;

  static const compressedTextureFormats = const ['.pvr', '.pvr.gz'];

  _TextureAtlasLoaderFile(String url, BitmapDataLoadOptions options) {
    _loadOptions = options ?? BitmapData.defaultLoadOptions;
    _loadInfo = new BitmapDataLoadInfo(url, _loadOptions.pixelRatios);
  }

  @override
  double getPixelRatio() => _loadInfo.pixelRatio;

  @override
  Future<String> getSource() => HttpRequest.getString(_loadInfo.loaderUrl);

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    RenderTexture renderTexture;

    var loaderUrl = _loadInfo.loaderUrl;
    var pixelRatio = _loadInfo.pixelRatio;
    var imageUrl = replaceFilename(loaderUrl, filename);

    if (!_isCompressedTexture(filename)) {
      var webpAvailable = _loadOptions.webp;
      var corsEnabled = _loadOptions.corsEnabled;
      var imageLoader = new ImageLoader(imageUrl, webpAvailable, corsEnabled);
      var imageElement = await imageLoader.done;
      renderTexture = new RenderTexture.fromImageElement(imageElement);
    } else {
      renderTexture = await _loadCompressedTexture(imageUrl);
    }

    return renderTexture.quad.withPixelRatio(pixelRatio);
  }

  Future<RenderTexture> _loadCompressedTexture(String filename) {

    final completer = new Completer<RenderTexture>();

    final request = new HttpRequest()..responseType = 'arraybuffer';

    request
      ..onReadyStateChange.listen((_) {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {
          final buffer = request.response as ByteBuffer;
          print('buffer size: ${buffer.lengthInBytes}');
          final texture = _decodeCompressedTexture(buffer, CompressedTextureFileTypes.pvr);
          completer.complete(texture);
        }
      })
      ..open('GET', filename, async: true)
      ..send();

    return completer.future;
  }

  RenderTexture _decodeCompressedTexture(ByteBuffer buffer, CompressedTextureFileTypes type) {
    switch (type) {
      case CompressedTextureFileTypes.pvr: return _decodePvr(buffer);
    }

    return null;
  }

  RenderTexture _decodePvr(ByteBuffer buffer) {
    final tex = new PvrTexture.fromBuffer(buffer);
    return new RenderTexture.fromCompressedTexture(tex);
  }

  bool _isCompressedTexture(String filename) => compressedTextureFormats.any((format) => filename.endsWith(format));
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderTextureAtlas extends TextureAtlasLoader {

  final TextureAtlas textureAtlas;
  final String namePrefix;
  final String source;

  _TextureAtlasLoaderTextureAtlas(this.textureAtlas, this.namePrefix, this.source);

  @override
  double getPixelRatio() => this.textureAtlas.pixelRatio;

  @override
  Future<String> getSource() => new Future.value(this.source);

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
  double getPixelRatio() => this.bitmapData.renderTextureQuad.pixelRatio;

  @override
  Future<String> getSource() => new Future.value(this.source);

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) {
    return new Future.value(this.bitmapData.renderTextureQuad);
  }
}
