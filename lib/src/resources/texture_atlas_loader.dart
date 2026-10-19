part of '../resources.dart';

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
  final BitmapDataLoadOptions _loadOptions;
  final BitmapDataLoadInfo _loadInfo;
  final AssetManifest _manifest;

  BaseImageLoader? _imageLoader;
  RenderTexture? _renderTexture;
  final _fetchControllers = <AbortController>[];
  var _cancelled = false;

  static const compressedTextureFormats = {'.pvr', '.pvr.gz', '.ktx'};

  _TextureAtlasLoaderFile(String url, [BitmapDataLoadOptions? options, AssetManifest? manifest])
  : _loadOptions  = options ?? BitmapData.defaultLoadOptions,
    _loadInfo = BitmapDataLoadInfo(url, (options ?? BitmapData.defaultLoadOptions).pixelRatios),
    _manifest = manifest ?? AssetManifest();

  @override
  double getPixelRatio() => _loadInfo.pixelRatio;

  @override
  Future<String> getSource() async {
    if (_cancelled) throw LoadError('texture atlas load cancelled');
    final controller = AbortController();
    _fetchControllers.add(controller);

    final url = _manifest.mapUrl(_loadInfo.loaderUrl);

    try {
      final response = await window.fetch(url.toJS, RequestInit(signal: controller.signal)).toDart;

      if (_cancelled) {
        throw LoadError('texture atlas load cancelled');
      }

      if (!response.ok) {
        throw LoadError('failed to fetch $url: ${response.status} ${response.statusText}');
      }

      final text = (await response.text().toDart).toDart;

      if (_cancelled) {
        throw LoadError('texture atlas load cancelled');
      }

      return text;
    } catch (error, stackTrace) {
      if (_cancelled) {
        Error.throwWithStackTrace(LoadError('texture atlas load cancelled'), stackTrace);
      }

      Error.throwWithStackTrace(LoadError('failed to fetch $url', error), stackTrace);
    } finally {
      _fetchControllers.remove(controller);
    }
  }

  @override
  void cancel() {
    print('aborting request for ${_loadInfo.loaderUrl}');

    _cancelled = true;

    if (_fetchControllers.isNotEmpty) {
      for (final controller in _fetchControllers) {
        controller.abort();
      }
      _fetchControllers.clear();
    }

    _imageLoader?.cancel();
    _imageLoader = null;
    _renderTexture?.dispose();
    _renderTexture = null;
  }

  @override
  Future<RenderTextureQuad> getRenderTextureQuad(String filename) async {
    if (_cancelled) throw LoadError('texture atlas load cancelled');
    final loaderUrl = _loadInfo.loaderUrl;
    final pixelRatio = _loadInfo.pixelRatio;

    final RenderTexture renderTexture;

    if (_isCompressedTexture(filename)) {
      final imageUrl = _manifest.mapUrl(replaceFilename(loaderUrl, filename));
      renderTexture = await _loadCompressedTexture(imageUrl);
    } else {
      final match = RegExp(r'\.(png|jpg|jpeg)$').firstMatch(filename);
      if (match != null) {
        final baseName = filename.substring(0, match.start);
        if (_loadOptions.avif && await env.isAvifSupported) {
          filename = '$baseName.avif';
        } else if (_loadOptions.webp && await env.isWebpSupported) {
          filename = '$baseName.webp';
        }
      }

      if (_cancelled) throw LoadError('texture atlas load cancelled');
      final imageUrl = _manifest.mapUrl(replaceFilename(loaderUrl, filename));
      if (env.isImageBitmapSupported) {
        final loader = _imageLoader = ImageBitmapLoader(imageUrl);
        final imageLoader = await loader.done;
        renderTexture = .fromImageBitmap(imageLoader,
            sourceUrl: _loadOptions.releaseImageSources && !_loadOptions.readable ? imageUrl : null);
      } else {
        final corsEnabled = _loadOptions.corsEnabled;
        final imageLoader = _imageLoader = ImageLoader(imageUrl, corsEnabled);
        final imageElement = await imageLoader.done;
        renderTexture = .fromImageElement(imageElement,
            sourceUrl: _loadOptions.releaseImageSources && !_loadOptions.readable ? imageUrl : null,
            corsEnabled: corsEnabled);
      }
    }

    _imageLoader = null;
    if (_cancelled) {
      renderTexture.dispose();
      throw LoadError('texture atlas load cancelled');
    }
    _renderTexture = renderTexture;
    return renderTexture.quad.withPixelRatio(pixelRatio);
  }

  Future<RenderTexture> _loadCompressedTexture(String filename) async {
    if (_cancelled) throw LoadError('compressed texture load cancelled');
    final filenameParts = filename.split('.');
    var ext = filenameParts.last;

    if (ext == 'gz') {
      ext = filenameParts[filenameParts.length - 2];
    }

    final type = switch (ext) {
      'pvr' => CompressedTextureFileTypes.pvr,
      'ktx' => CompressedTextureFileTypes.ktx,
      _ => throw LoadError('unknown extension $ext'),
    };

    final controller = AbortController();
    _fetchControllers.add(controller);

    try {
      final buffer = await CompressedTextureLoader.load(filename, signal: controller.signal);
      if (_cancelled) throw LoadError('compressed texture load cancelled');
      final texture = switch (type) {
        .pvr => PvrTexture(buffer),
        .ktx => KtxTexture(buffer),
      };
      return RenderTexture.fromCompressedTexture(texture,
          sourceUrl: _loadOptions.releaseCompressedTextureBuffers ? filename : null);
    } catch (error, stackTrace) {
      if (_cancelled) {
        Error.throwWithStackTrace(
          LoadError('compressed texture load cancelled'),
          stackTrace,
        );
      }

      Error.throwWithStackTrace(
        LoadError('failed to fetch $filename', error),
        stackTrace,
      );
    } finally {
      _fetchControllers.remove(controller);
    }
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
