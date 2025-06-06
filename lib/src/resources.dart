/// This classes will help you to load and manage your resources (assets).
///
/// Use the [ResourceManager] class to load BitmapDatas, Sounds, Texts and
/// other resources for your application. The [TextureAtlas] class combines
/// a set of BitmapDatas to one render texture (which greatly improves the
/// performance of the WebGL renderer). The [SoundSprite] does a similar
/// thing for Sounds as the texture altas does for BitmapDatas.
///
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
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

part 'resources/asset_manifest.dart';
part 'resources/resource_manager.dart';
part 'resources/resource_manager_resource.dart';
part 'resources/resource_registry.dart';
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


enum CompressedTextureFileTypes {
  pvr,
  ktx
}
