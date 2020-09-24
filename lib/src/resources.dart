/// This classes will help you to load and manage your resources (assets).
///
/// Use the [ResourceManager] class to load BitmapDatas, Sounds, Texts and
/// other resources for your application. The [TextureAtlas] class combines
/// a set of BitmapDatas to one render texture (which greatly improves the
/// performance of the WebGL renderer). The [SoundSprite] does a similar
/// thing for Sounds as the texture altas does for BitmapDatas.
///
library stagexl.resources;

import 'dart:async';
import 'dart:convert';
import 'dart:js' show JsObject;
import 'dart:typed_data';
import 'dart:html' show HttpRequest;
import 'dart:web_gl' as gl;
import 'package:xml/xml.dart';

import 'display.dart';
import 'engine.dart';
import 'geom.dart';
import 'media.dart';
import 'internal/tools.dart';
import 'internal/image_loader.dart';

part 'resources/resource_manager.dart';
part 'resources/resource_manager_resource.dart';
part 'resources/sound_sprite.dart';
part 'resources/sound_sprite_segment.dart';
part 'resources/sprite_sheet.dart';
part 'resources/texture_atlas.dart';
part 'resources/texture_atlas_format.dart';
part 'resources/texture_atlas_format_json.dart';
part 'resources/texture_atlas_format_libgdx.dart';
part 'resources/texture_atlas_format_starling_json.dart';
part 'resources/texture_atlas_format_starling_xml.dart';
part 'resources/texture_atlas_frame.dart';
part 'resources/texture_atlas_loader.dart';

JsObject stageXLFileMap;
var stageXLStoragePrefix = '';

String getUrlHash(String url, {bool webp = false}) {
  if (stageXLFileMap == null) return url;

  if (webp) {
    print('getting webp instead of $url...');

    // This is a hack, since it will break if the hash format changes.
    final i = url.lastIndexOf('-');
    final j = url.lastIndexOf('@');
    url = url.substring(0, i) + url.substring(j);
    print('normalized url to $url');

    var match = RegExp(r'(png|jpg|jpeg)$').firstMatch(url);
    url = url.substring(0, match.start) + 'webp';
    print('new key: $url');
    return getUrlHash(url);
  }

  final key = url.replaceFirst(stageXLStoragePrefix, '');
  final value = stageXLFileMap[key];
  if (value == null) {
    print('$url not found in file map from key: $key');
    return null;
  }

  final newUrl = '$stageXLStoragePrefix${stageXLFileMap[key] as String}';
  print('getting url, key: $key, value: $value, new url: $newUrl');
  return newUrl;
}

enum CompressedTextureFileTypes {
  pvr
}
