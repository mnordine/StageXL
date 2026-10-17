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

  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    _textLoads.remove(name)?.call();
    return resources.manager._removeResource(kind, name);
  }

  T get(String name) => resources.getResourceValue(kind, name) as T;

  void _checkName(String name) {
    if (contains(name)) throw StateError("ResourceManager already contains a resource called '$name'");
  }

  final _textLoads = <String, void Function()>{};

  Future<String> _loadText(String name, String url) {
    final controller = AbortController();
    final completer = Completer<String>();
    void cancel() {
      controller.abort();
      if (!completer.isCompleted) completer.completeError(LoadCancelledError());
    }
    _textLoads[name] = cancel;
    Future<void> load() async {
      try {
        final text = await _loadResourceText(url, controller.signal);
        if (!completer.isCompleted) completer.complete(text);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      } finally {
        if (identical(_textLoads[name], cancel)) _textLoads.remove(name);
      }
    }
    unawaited(load());
    return completer.future;
  }
}

class BitmapDataResourceRegistry extends ResourceRegistry<BitmapData> {
  @override
  final kind = 'BitmapData';

  final _loads = <String, Future<BitmapData>>{};

  BitmapDataResourceRegistry(super.resources);

  void add(String name, String url, [BitmapDataLoadOptions? options]) {
    _checkName(name);
    final loader = BitmapData.load(url, options, resources.manifest);
    _loads[name] = loader;
    resources.addResource(kind, name, url, loader);
    final resource = resources.manager._resourceMap['$kind.$name'];
    unawaited(loader.then<void>((bitmap) {
      if (!identical(resources.manager._resourceMap['$kind.$name'], resource)) bitmap.renderTexture.dispose();
      if (identical(_loads[name], loader)) _loads.remove(name);
    }, onError: (Object _) {
      if (identical(_loads[name], loader)) _loads.remove(name);
    }));
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resourceManagerResource = super.remove(name);

    final loader = _loads.remove(name);
    if (loader != null) BitmapData.cancelLoad(loader);
    final bitmapData = resourceManagerResource?.value;
    if (bitmapData is BitmapData && dispose) {
      bitmapData.renderTexture.dispose();
    }

    return resourceManagerResource;
  }
}

class TextureAtlasResourceRegistry extends ResourceRegistry<TextureAtlas> {
  @override
  final kind = 'TextureAtlas';

  final _loaders = <String, _TextureAtlasLoaderFile>{};

  TextureAtlasResourceRegistry(super.resources);

  void add(String name, String url, [TextureAtlasFormat? textureAtlasFormat, BitmapDataLoadOptions? options]) {
    _checkName(name);
    textureAtlasFormat ??= .jsonArray;

    final tuple = TextureAtlas.load(url, textureAtlasFormat, options, resources.manifest);
    resources.addResource(kind, name, url, tuple.atlasFuture);

    _loaders[name] = tuple._loader;
    void removeLoader() {
      if (identical(_loaders[name], tuple._loader)) _loaders.remove(name);
    }
    tuple.atlasFuture.then((_) => removeLoader(), onError: (Object _) => removeLoader());
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
      for (final textureAtlasFrame in textureAtlas.frames.values) {
        textureAtlasFrame.bitmapData.renderTexture.dispose();
      }
    }

    return resourceManagerResource;
  }
}

class VideoResourceRegistry extends ResourceRegistry<Video> {
  @override
  final kind = 'Video';

  final _loaders = <String, Future<Video>>{};

  VideoResourceRegistry(super.resources);

  void add(String name, String url, [VideoLoadOptions? options]) {
    _checkName(name);
    final loader = Video.load(url, options, resources.manifest);
    resources.addResource(kind, name, url, loader);
    _loaders[name] = loader;
    final resource = resources.manager._resourceMap['$kind.$name'];
    unawaited(loader.then<void>((video) {
      if (!identical(resources.manager._resourceMap['$kind.$name'], resource)) video.dispose();
      if (identical(_loaders[name], loader)) _loaders.remove(name);
    }, onError: (Object _) {
      if (identical(_loaders[name], loader)) _loaders.remove(name);
    }));
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resource = super.remove(name);
    if (resource == null) return null;
    if (resource.value case final Video video) {
      if (dispose) video.dispose();
    } else {
      final loader = _loaders.remove(name);
      if (loader != null) Video.cancel(loader);
    }
    return resource;
  }
}

class SoundResourceRegistry extends ResourceRegistry<Sound> {
  @override
  final kind = 'Sound';

  // Key is name
  final _soundDatas = <String, _SoundData>{};

  SoundResourceRegistry(super.resources);

  void add(String name, String url, [SoundLoadOptions? options]) {
    _checkName(name);
    final data = _SoundData()
      ..url = url
      ..engine = options?.engine ?? Sound.defaultLoadOptions.engine ?? SoundMixer.engine;
    final loader = data.loader = Sound.load(url, options, resources.manifest);
    _soundDatas[name] = data;
    unawaited(loader.then<void>((sound) {
      if (sound is AudioElementSound && !identical(_soundDatas[name], data)) sound.dispose();
    }, onError: (Object _) {
      if (identical(_soundDatas[name], data)) _soundDatas.remove(name);
    }));
    resources.addResource(kind, name, url, loader);
  }

  @override
  ResourceManagerResource? remove(String name, {bool dispose = false}) {
    final resourceManagerResource = super.remove(name);

    if (!_soundDatas.containsKey(name)) return resourceManagerResource;

    final data = _soundDatas[name]!;
    if (data.engine == .WebAudioApi) {
      WebAudioApiSound.cancelLoad(data.loader);
    } else if (data.engine == .AudioElement) {
      AudioElementSound.cancel(data.loader);
      final sound = resourceManagerResource?.value;
      if (dispose && sound is AudioElementSound) sound.dispose();
    }

    _soundDatas.remove(name);
    return resourceManagerResource;
  }
}

class SoundSpriteResourceRegistry extends ResourceRegistry<SoundSprite> {
  @override
  final kind = 'SoundSprite';

  SoundSpriteResourceRegistry(super.resources);

  void add(String name, String url, [SoundLoadOptions? options]) {
    _checkName(name);
    final loader = SoundSprite.load(resources.manifest.mapUrl(url), options);
    resources.addResource(kind, name, url, loader);
  }
}

class TextResourceRegistry extends ResourceRegistry<String> {
  @override
  final kind = 'Text';

  TextResourceRegistry(super.resources);

  void add(String name, String text) {
    _checkName(name);
    resources.addResource(kind, name, '', Future.value(text));
  }
}

class TextFileResourceRegistry extends ResourceRegistry<String> {
  @override
  final kind = 'TextFile';

  TextFileResourceRegistry(super.resources);

  void add(String name, String url) {
    _checkName(name);
    final mappedUrl = resources.manifest.mapUrl(url);
    final loader = _loadText(name, mappedUrl);
    resources.addResource(kind, name, url, loader);
  }
}

class AssetManifestResourceRegistry extends ResourceRegistry<AssetManifest> {
  @override
  final kind = 'AssetManifest';

  AssetManifestResourceRegistry(super.resources);

  void add(String name, String url, [String storagePrefix = '/']) {
    _checkName(name);
    final mappedUrl = resources.manifest.mapUrl(url);
    final loader = _loadText(name, mappedUrl).then((text) {
      final parsed = json.decode(text) as Map<String, dynamic>;
      return AssetManifest(parsed.cast<String, String>(), storagePrefix);
    });

    resources.addResource(kind, name, url, loader);
  }
}

class CustomObjectResourceRegistry extends ResourceRegistry<dynamic> {
  @override
  final kind = 'CustomObject';

  CustomObjectResourceRegistry(super.resources);

  void add(String name, Future loader) {
    _checkName(name);
    resources.addResource(kind, name, '', loader);
  }
}

Future<String> _loadResourceText(String url, AbortSignal signal) async {
  final response = await window.fetch(url.toJS, RequestInit(signal: signal)).toDart;
  if (!response.ok) {
    throw LoadError('Failed to load $url. (${response.status} ${response.statusText})');
  }
  return (await response.text().toDart).toDart;
}
