part of '../resources.dart';

/// Manages the resources of a specific kind. Each ResourceManager will
/// use a single instance of this class to manage resources of the claimed
/// kind.
///
/// In addition to the methods here, implementers should also have a method
/// with a signature similar to the following:
/// `void add(String name, ...)``
abstract class ResourceRegistry<T> {
  @protected
  final ResourceManagerProxy resources;

  @protected
  String get kind;

  ResourceRegistry(ResourceManager resources) : resources = ResourceManagerProxy._(resources);

  bool contains(String name) => resources.containsResource(kind, name);

  ResourceManagerResource? remove(String name, {bool dispose = false}) => resources.manager._removeResource(kind, name);

  T get(String name) => resources.getResourceValue(kind, name) as T;
}

class BitmapDataResourceRegistry extends ResourceRegistry<BitmapData> {
  @override
  final String kind = 'BitmapData';

  BitmapDataResourceRegistry(super.resources);

  void add(String name, String url, [BitmapDataLoadOptions? options]) {
    final loader = BitmapData.load(url, options, resources.manifest);
    resources.addResource(kind, name, url, loader);
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resourceManagerResource = super.remove(name);

    final bitmapData = resourceManagerResource?.value;
    if (bitmapData is BitmapData && dispose) {
      bitmapData.renderTexture.dispose();
    }

    return resourceManagerResource;
  }
}

class TextureAtlasResourceRegistry extends ResourceRegistry<TextureAtlas> {
  @override
  final String kind = 'TextureAtlas';

  final _loaders = <String, _TextureAtlasLoaderFile>{};

  TextureAtlasResourceRegistry(super.resources);

  void add(String name, String url, [TextureAtlasFormat? textureAtlasFormat, BitmapDataLoadOptions? options]) {
    textureAtlasFormat ??= TextureAtlasFormat.jsonArray;

    final tuple = TextureAtlas.load(url, textureAtlasFormat, options, resources.manifest);
    resources.addResource(kind, name, url, tuple.atlasFuture);

    _loaders[name] = tuple._loader;
    tuple.atlasFuture.then((_) => _loaders.remove(name)).catchError((_) => _loaders.remove(name));
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resourceManagerResource = super.remove(name);
    final textureAtlas = resourceManagerResource?.value;

    if (_loaders.containsKey(name)) {
      _loaders[name]!.cancel();
      _loaders.remove(name);
    }

    if (textureAtlas is TextureAtlas && dispose) {
      for (var textureAtlasFrame in textureAtlas.frames.values) {
        textureAtlasFrame.bitmapData.renderTexture.dispose();
      }
    }

    return resourceManagerResource;
  }
}

class VideoResourceRegistry extends ResourceRegistry<Video> {
  @override
  final String kind = 'Video';

  VideoResourceRegistry(super.resources);

  void add(String name, String url, [VideoLoadOptions? options]) {
    final loader = Video.load(url, options, resources.manifest);
    resources.addResource(kind, name, url, loader);
  }
}

class SoundResourceRegistry extends ResourceRegistry<Sound> {
  @override
  final String kind = 'Sound';

  // Key is name
  final _soundDatas = <String, _SoundData>{};

  SoundResourceRegistry(super.resources);

  void add(String name, String url, [SoundLoadOptions? options]) {
    final loader = Sound.load(url, options, resources.manifest) as Future<Sound?>;
    loader.catchError((_) {
      _soundDatas.remove(name);
      return null;
    });

    resources.addResource(kind, name, url, loader);

    _soundDatas[name] = _SoundData()
      ..url = url
      ..engine = options?.engine ?? Sound.defaultLoadOptions.engine ?? SoundMixer.engine;
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resourceManagerResource = super.remove(name);

    if (!_soundDatas.containsKey(name)) return resourceManagerResource;

    // TODO: Just Web Audio API for now, add support for Audio Element (IE 11)
    final data = _soundDatas[name]!;
    if (data.engine == SoundEngine.WebAudioApi) {
      WebAudioApiSound.cancel(data.url);
    }

    _soundDatas.remove(name);
    return resourceManagerResource;
  }
}

class SoundSpriteResourceRegistry extends ResourceRegistry<SoundSprite> {
  @override
  final String kind = 'SoundSprite';

  SoundSpriteResourceRegistry(super.resources);

  void add(String name, String url, [SoundLoadOptions? options]) {
    final loader = SoundSprite.load(resources.manifest.mapUrl(url), options);
    resources.addResource(kind, name, url, loader);
  }
}

class TextResourceRegistry extends ResourceRegistry<String> {
  @override
  final String kind = 'Text';

  TextResourceRegistry(super.resources);

  void add(String name, String text) {
    resources.addResource(kind, name, '', Future.value(text));
  }
}

class TextFileResourceRegistry extends ResourceRegistry<String> {
  @override
  final String kind = 'TextFile';

  TextFileResourceRegistry(super.resources);

  void add(String name, String url) {
    final mappedUrl = resources.manifest.mapUrl(url);
    final loader = http.get(Uri.parse(mappedUrl)).then((text) => text.body, onError: (error) {
      throw StateError('Failed to load text file.');
    });
    resources.addResource(kind, name, url, loader);
  }
}

class AssetManifestResourceRegistry extends ResourceRegistry<AssetManifest> {
  @override
  final String kind = 'AssetManifest';

  AssetManifestResourceRegistry(super.resources);

  void add(String name, String url, [String storagePrefix = '/']) {
    final mappedUrl = resources.manifest.mapUrl(url);
    final loader = http.get(Uri.parse(mappedUrl)).then((resp) {
      final parsed = json.decode(resp.body) as Map<String, dynamic>;
      return AssetManifest(parsed.cast<String, String>(), storagePrefix);
    }, onError: (error) {
      throw StateError('Failed to load asset manifest.');
    });

    resources.addResource(kind, name, url, loader);
  }
}

class CustomObjectResourceRegistry extends ResourceRegistry<dynamic> {
  @override
  final String kind = 'CustomObject';

  CustomObjectResourceRegistry(super.resources);

  void add(String name, Future loader) {
    resources.addResource(kind, name, '', loader);
  }
}
