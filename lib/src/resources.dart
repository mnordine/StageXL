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
import 'package:web/web.dart' show HttpRequest, ImageBitmap, ImageElement, XHRGetters, XMLHttpRequest;
import 'dart:js' show JsObject;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'display.dart';
import 'engine.dart';
import 'errors.dart';
import 'geom.dart';
import 'internal/environment.dart' as env;
import 'internal/image_bitmap_loader.dart';
import 'internal/image_loader.dart';
import 'internal/tools.dart';
import 'media.dart';

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

JsObject? stageXLFileMap;
var stageXLStoragePrefix = '';

String? getUrlHash(String url, {bool webp = false}) {
  if (stageXLFileMap == null) return url;

  if (webp) {
    // This is a hack, since it will break if the hash format changes.
    final i = url.lastIndexOf('-');
    final j = url.lastIndexOf('@');
    url = url.substring(0, i) + url.substring(j);

    final match = RegExp(r'(png|jpg|jpeg)$').firstMatch(url);
    url = url.substring(0, match!.start) + 'webp'; // ignore: prefer_interpolation_to_compose_strings
    return getUrlHash(url);
  }

  final key = url.replaceFirst(stageXLStoragePrefix, '');
  final value = stageXLFileMap![key];
  if (value == null) return null;

  final newUrl = '$stageXLStoragePrefix${stageXLFileMap![key] as String}';
  return newUrl;
}

enum CompressedTextureFileTypes {
  pvr,
  ktx
}
