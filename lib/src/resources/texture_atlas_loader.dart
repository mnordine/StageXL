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

  /// Cancels any requests in progress
  void cancel() {}
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderFile extends TextureAtlasLoader {
  BitmapDataLoadOptions _loadOptions;
  BitmapDataLoadInfo _loadInfo;

  Future<HttpRequest> _sourceFuture;
  ImageLoader _imageLoader;
  HttpRequest _compressedTextureRequest;

  static const compressedTextureFormats = {'.pvr', '.pvr.gz'};

  _TextureAtlasLoaderFile(String url, BitmapDataLoadOptions options) {
    _loadOptions = options ?? BitmapData.defaultLoadOptions;
    _loadInfo = BitmapDataLoadInfo(url, _loadOptions.pixelRatios);
  }

  @override
  double getPixelRatio() => _loadInfo.pixelRatio;

  @override
  Future<String> getSource() async {
    _sourceFuture = HttpRequest.request(_loadInfo.loaderUrl, method: 'GET');

    final response = await _sourceFuture;
    _sourceFuture = null;

    return response.response;
  }

  @override
  void cancel() {
    print('aborting request for ${_loadInfo.loaderUrl}');

    _sourceFuture?.then((response) => response.abort());
    _sourceFuture = null;

    _imageLoader?.cancel();
    _imageLoader = null;

    _compressedTextureRequest?.abort();
    _compressedTextureRequest = null;
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    RenderTexture renderTexture;

    var loaderUrl = _loadInfo.loaderUrl;
    var pixelRatio = _loadInfo.pixelRatio;
    var imageUrl = replaceFilename(loaderUrl, filename);

    if (!_isCompressedTexture(filename)) {
      var webpAvailable = _loadOptions.webp;

      if (_loadOptions.imageBitmap) {
        final loader = ImageBitmapLoader(imageUrl, webpAvailable);
        final imageBitmap = await loader.done;
        renderTexture = RenderTexture.fromImageBitmap(imageBitmap);
      } else {
        var corsEnabled = _loadOptions.corsEnabled;
        _imageLoader = ImageLoader(imageUrl, webpAvailable, corsEnabled);
        var imageElement = await _imageLoader.done;
        renderTexture = RenderTexture.fromImageElement(imageElement);

        _imageLoader = null;
      }
    } else {
      renderTexture = await _loadCompressedTexture(imageUrl);
    }

    return renderTexture.quad.withPixelRatio(pixelRatio);
  }

  Future<RenderTexture> _loadCompressedTexture(String filename) {

    final completer = Completer<RenderTexture>();

    final request = _compressedTextureRequest = HttpRequest();
    request
      ..onReadyStateChange.listen((_) {
        if (request.readyState == HttpRequest.DONE && request.status == 200) {
          final buffer = request.response as ByteBuffer;
          final texture = _decodeCompressedTexture(buffer, CompressedTextureFileTypes.pvr);

          _compressedTextureRequest = null;

          completer.complete(texture);
        }
      })
      ..open('GET', filename, async: true)
      ..responseType = 'arraybuffer'
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
    final tex = PvrTexture.fromBuffer(buffer);
    return RenderTexture.fromCompressedTexture(tex);
  }

  bool _isCompressedTexture(String filename) => compressedTextureFormats.any((format) => filename.endsWith(format));
}

//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------

class _TextureAtlasLoaderTextureAtlas extends TextureAtlasLoader {
  final TextureAtlas textureAtlas;
  final String namePrefix;
  final String source;

  _TextureAtlasLoaderTextureAtlas(
      this.textureAtlas, this.namePrefix, this.source);

  @override
  double getPixelRatio() => textureAtlas.pixelRatio;

  @override
  Future<String> getSource() => Future.value(source);

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    var name = namePrefix + getFilenameWithoutExtension(filename);
    var bitmapData = textureAtlas.getBitmapData(name);
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
  double getPixelRatio() => bitmapData.renderTextureQuad.pixelRatio;

  @override
  Future<String> getSource() => Future.value(source);

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) {
    return Future.value(bitmapData.renderTextureQuad);
  }
}
