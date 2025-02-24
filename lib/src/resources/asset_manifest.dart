part of '../resources.dart';

class AssetManifest {
  final Map<String, String> _manifest;
  final String storagePrefix;

  AssetManifest([Map<String, String>? manifest, this.storagePrefix = '/']) : _manifest = manifest ?? {};

  factory AssetManifest.merge(Iterable<AssetManifest> manifests) {
    final mergedManifest = <String, String>{};
    for (final manifest in manifests) {
      mergedManifest.addAll(manifest._manifest);
    }

    return AssetManifest(mergedManifest);
  }

  @internal
  void extend(AssetManifest manifest) {
    _manifest.addAll(manifest._manifest);
  }

  String mapUrl(String url) {
    final originalUrl = url.startsWith(storagePrefix) ? url.replaceFirst(storagePrefix, '') : url;
    final mapped = _manifest[originalUrl];
    if (mapped == null) return url;

    return '$storagePrefix$mapped';
  }
}
