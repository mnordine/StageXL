part of '../resources.dart';

class _SoundData {
  late final String url;
  late final SoundEngine engine;
}

class ResourceManager {
  final Map<String, ResourceManagerResource> _resourceMap =
      <String, ResourceManagerResource>{};
  
  final Map<String, ResourceRegistry<dynamic>> _registries =
    <String, ResourceRegistry<dynamic>>{};

  final AssetManifest _manifest;
  AssetManifest get manifest => _manifest;

  final _progressEvent = StreamController<num>.broadcast();
  Stream<num> get onProgress => _progressEvent.stream;

  ResourceManager() : _manifest = AssetManifest();
  ResourceManager.withManifest(AssetManifest manifest) : _manifest = manifest;
  ResourceManager.cloneManifest(ResourceManager other) : _manifest = other._manifest;

  T registry<T extends ResourceRegistry>(String kind, T Function(ResourceManager) factory) =>
    _registries.putIfAbsent(kind, () => factory(this)) as T;

  //----------------------------------------------------------------------------

  Future<ResourceManager> load() async {
    final futures = pendingResources.map((r) => r.complete);
    await Future.wait(futures);
    final errors = failedResources.length;
    if (errors > 0) {
      throw StateError('Failed to load $errors resource(s).');
    } else {
      return this;
    }
  }

  void dispose() {
    for (var resource in _resourceMap.values.toList(growable: false)) {
      final registry = _registries[resource.kind];
      if (registry != null) {
        registry.remove(resource.name, dispose: true);
      } else {
        _removeResource(resource.kind, resource.name);
      }
    }
  }

  //----------------------------------------------------------------------------

  List<ResourceManagerResource> get finishedResources =>
      _resourceMap.values.where((r) => r.value != null).toList();

  List<ResourceManagerResource> get pendingResources => _resourceMap.values
      .where((r) => r.value == null && r.error == null)
      .toList();

  List<ResourceManagerResource> get failedResources =>
      _resourceMap.values.where((r) => r.error != null).toList();

  List<ResourceManagerResource> get resources => _resourceMap.values.toList();

  //----------------------------------------------------------------------------

  BitmapDataResourceRegistry get bitmapDatas =>
    registry('BitmapData', BitmapDataResourceRegistry.new);

  bool containsBitmapData(String name) => bitmapDatas.contains(name);

  void addBitmapData(String name, String url,
      [BitmapDataLoadOptions? options]) =>
    bitmapDatas.add(name, url, options);

  void removeBitmapData(String name, {bool dispose = true}) =>
    bitmapDatas.remove(name, dispose: dispose);

  BitmapData getBitmapData(String name) => bitmapDatas.get(name);

  //----------------------------------------------------------------------------

  TextureAtlasResourceRegistry get textureAtlases =>
    registry('TextureAtlas', TextureAtlasResourceRegistry.new);

  bool containsTextureAtlas(String name) => textureAtlases.contains(name);

  void addTextureAtlas(String name, String url,
      [TextureAtlasFormat? textureAtlasFormat, BitmapDataLoadOptions? options]) =>
    textureAtlases.add(name, url, textureAtlasFormat, options);

  void removeTextureAtlas(String name, {bool dispose = true}) =>
    textureAtlases.remove(name, dispose: dispose);

  TextureAtlas getTextureAtlas(String name) => textureAtlases.get(name);

  //----------------------------------------------------------------------------

  VideoResourceRegistry get videos =>
    registry('Video', VideoResourceRegistry.new);

  bool containsVideo(String name) => videos.contains(name);

  void addVideo(String name, String url, [VideoLoadOptions? options]) =>
    videos.add(name, url, options);

  void removeVideo(String name) => videos.remove(name);

  Video getVideo(String name) => videos.get(name);

  //----------------------------------------------------------------------------

  SoundResourceRegistry get sounds =>
    registry('Sound', SoundResourceRegistry.new);

  bool containsSound(String name) => sounds.contains(name);

  void addSound(String name, String url, [SoundLoadOptions? options]) =>
    sounds.add(name, url, options);

  void removeSound(String name) => sounds.remove(name);

  Sound getSound(String name) => sounds.get(name);

  //----------------------------------------------------------------------------

  SoundSpriteResourceRegistry get soundSprites =>
    registry('SoundSprite', SoundSpriteResourceRegistry.new);

  bool containsSoundSprite(String name) => soundSprites.contains(name);

  void addSoundSprite(String name, String url, [SoundLoadOptions? options]) =>
    soundSprites.add(name, url, options);

  void removeSoundSprite(String name) => soundSprites.remove(name);

  SoundSprite getSoundSprite(String name) => soundSprites.get(name);

  //----------------------------------------------------------------------------

  TextResourceRegistry get texts =>
    registry('Text', TextResourceRegistry.new); 

  bool containsText(String name) => texts.contains(name);

  void addText(String name, String text) => texts.add(name, text);

  void removeText(String name) => texts.remove(name);

  String getText(String name) => texts.get(name);

  //----------------------------------------------------------------------------

  TextFileResourceRegistry get textFiles =>
    registry('TextFile', TextFileResourceRegistry.new);

  bool containsTextFile(String name) => textFiles.contains(name);

  void addTextFile(String name, String url) => textFiles.add(name, url);

  void removeTextFile(String name) => textFiles.remove(name);

  String getTextFile(String name) => textFiles.get(name);

  //----------------------------------------------------------------------------

  AssetManifestResourceRegistry get assetManifests =>
    registry('AssetManifest', AssetManifestResourceRegistry.new);
  
  void useAssetManifest(AssetManifest manifest) {
    _manifest.extend(manifest);
  }

  //----------------------------------------------------------------------------

  CustomObjectResourceRegistry get customObjects =>
    registry('CustomObject', CustomObjectResourceRegistry.new);

  bool containsCustomObject(String name) =>
    customObjects.contains(name);

  void addCustomObject(String name, Future loader) =>
    customObjects.add(name, loader);

  void removeCustomObject(String name) => customObjects.remove(name);

  dynamic getCustomObject(String name) => customObjects.get(name);

  //----------------------------------------------------------------------------

  bool _containsResource(String kind, String name) {
    final key = '$kind.$name';
    return _resourceMap.containsKey(key);
  }

  ResourceManagerResource? _removeResource(String kind, String name) {
    final key = '$kind.$name';
    return _resourceMap.remove(key);
  }

  void _addResource(String kind, String name, String url, Future loader) {
    final key = '$kind.$name';
    final resource = ResourceManagerResource(kind, name, url, loader);

    if (_resourceMap.containsKey(key)) {
      throw StateError(
          "ResourceManager already contains a resource called '$name'");
    } else {
      _resourceMap[key] = resource;
    }

    resource.complete.then((_) {
      final finished = finishedResources.length;
      final progress = finished / _resourceMap.length;
      _progressEvent.add(progress);
    });
  }

  dynamic _getResourceValue(String kind, String name) {
    final key = '$kind.$name';
    final resource = _resourceMap[key];
    if (resource == null) {
      throw StateError("Resource '$name' does not exist.");
    } else if (resource.value != null) {
      return resource.value;
    } else if (resource.error != null) {
      // ignore: only_throw_errors
      throw resource.error!;
    } else {
      throw StateError("Resource '$name' has not finished loading yet.");
    }
  }
}

/// A proxy type, used by a ResourceRegistry to add/remove/get/check for
/// resources, and to access the AssetManifest in use by this registry.
extension type ResourceManagerProxy._(ResourceManager manager) {
  /// The asset manifest in use by this resource manager
  AssetManifest get manifest => manager._manifest;

  void addResource(String kind, String name, String url, Future loader) =>
    manager._addResource(kind, name, url, loader);

  void removeResource(String kind, String name) =>
    manager._removeResource(kind, name);

  dynamic getResourceValue(String kind, String name) =>
    manager._getResourceValue(kind, name);

  bool containsResource(String kind, String name) =>
    manager._containsResource(kind, name);
}
