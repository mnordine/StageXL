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
  late BitmapDataLoadOptions _loadOptions;
  late BitmapDataLoadInfo _loadInfo;

  BaseImageLoader? _imageLoader;
  bool _cancelled = false;

  static const compressedTextureFormats = {'.pvr', '.pvr.gz', '.ktx'};

  _TextureAtlasLoaderFile(String url, [BitmapDataLoadOptions? options]) {
    _loadOptions = options ?? BitmapData.defaultLoadOptions;
    _loadInfo = BitmapDataLoadInfo(url, _loadOptions.pixelRatios);
  }

  @override
  double getPixelRatio() => _loadInfo.pixelRatio;

  @override
  Future<String> getSource() async {
    final response = await http.get(Uri.parse(_loadInfo.loaderUrl));
    return response.body;
  }

  @override
  void cancel() {
    print('aborting request for ${_loadInfo.loaderUrl}');

    _cancelled = true;

    _imageLoader?.cancel();
    _imageLoader = null;
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    final loaderUrl = _loadInfo.loaderUrl;
    final pixelRatio = _loadInfo.pixelRatio;
    final imageUrl = replaceFilename(loaderUrl, filename);

    final RenderTexture renderTexture;

    if (_isCompressedTexture(filename)) {
      renderTexture = await _loadCompressedTexture(imageUrl);
    } else if (env.isImageBitmapSupported) {
      _imageLoader = ImageBitmapLoader(imageUrl, _loadOptions.webp);
      final image = await _imageLoader!.done;
      renderTexture = RenderTexture.fromImageBitmap(image as ImageBitmap);
    } else {
      final corsEnabled = _loadOptions.corsEnabled;
      _imageLoader = ImageLoader(imageUrl, _loadOptions.webp, corsEnabled);
      final imageElement = await _imageLoader!.done;
      renderTexture = RenderTexture.fromImageElement(imageElement as HTMLImageElement);
    }

    return renderTexture.quad.withPixelRatio(pixelRatio);
  }

  Future<RenderTexture> _loadCompressedTexture(String filename) {
    final filenameParts = filename.split('.');
    var ext = filenameParts.last;

    if (ext == 'gz') {
      ext = filenameParts[filenameParts.length - 2];
    }

    CompressedTextureFileTypes type;

    switch (ext) {
      case 'pvr':
        type = CompressedTextureFileTypes.pvr;
        break;
      case 'ktx':
        type = CompressedTextureFileTypes.ktx;
        break;
      default:
        throw LoadError('unknown extension $ext');
    }

    return http.get(Uri.parse(filename))
      .then((response) {
        if (_cancelled) {
          throw LoadError('compressed texture load cancelled');
        }
        if (response.statusCode == 200) {
          final buffer = response.bodyBytes.buffer;
          final texture = _decodeCompressedTexture(buffer, type);

          return texture;
        } else {
          throw LoadError('failed to GET $filename');
        }
      });
  }

  RenderTexture _decodeCompressedTexture(ByteBuffer buffer, CompressedTextureFileTypes type) {
    switch (type) {
      case CompressedTextureFileTypes.pvr:
        return _decodePvr(buffer);
      case CompressedTextureFileTypes.ktx:
        return _decodeKtx(buffer);
    }
  }

  RenderTexture _decodePvr(ByteBuffer buffer) {
    final tex = PvrTexture(buffer);
    return RenderTexture.fromCompressedTexture(tex);
  }

  RenderTexture _decodeKtx(ByteBuffer buffer) {
    final tex = KtxTexture(buffer);
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
    final name = namePrefix + getFilenameWithoutExtension(filename);
    final bitmapData = textureAtlas.getBitmapData(name);
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
  double getPixelRatio() => bitmapData.renderTextureQuad.pixelRatio.toDouble();

  @override
  Future<String> getSource() => Future.value(source);

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) =>
      Future.value(bitmapData.renderTextureQuad);
}
