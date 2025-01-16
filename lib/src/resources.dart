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
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' show ImageBitmap, HTMLImageElement;
import 'dart:js_interop' show JS, JSObject, JSString, JSStringToString;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:retry/retry.dart';
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

@JS()
external JSObject? stageXLFileMap;
var stageXLStoragePrefix = '';

final _modulesCache = <String, Map<String, Object?>>{};
final _modules = {
  'assets/games/bonus',
  'assets/games/keno',
  'assets/games/reel',
  'texture_atlases/games/bonus',
  'texture_atlases/games/keno',
  'texture_atlases/games/reel',
};

Future<String?> getUrlHash(String url) async {
  if (stageXLFileMap == null) return url;

  final key = url.startsWith(stageXLStoragePrefix) ? url.replaceFirst(stageXLStoragePrefix, '') : url;
  final value = stageXLFileMap![key] as JSString?;

  // some audio files do not have a hash but all _modules do
  if (value == null && !_modules.any(key.startsWith)) {
    return null;
  }

  if (env.isAssetModules && _modules.any(key.startsWith)) {
    final dirs = dirname(key).split('/');

    // This is used to find the module asset map in the global asset map
    // e.g. globalKey = texture_atlases/games/reel/kongos_adventure
    final globalKey = dirs.take(4).join('/');

    // This is used to find the hashed url from the module asset map
    // e.g. moduleKey = widescreen/main@1x.json
    final moduleKey = dirs.length > 4 ? '${dirs.skip(4).join('/')}/${basename(key)}' : basename(key);
    final assetMap = await _loadModule(globalKey);

    return '$globalKey/${assetMap[moduleKey]}';
  }

  return '$stageXLStoragePrefix${(stageXLFileMap?[key] as JSString).toDart}';
}

Future<Map<String, Object?>> _loadModule(String key) async {
  if (_modulesCache.containsKey(key)) {
    return _modulesCache[key]!;
  }

  try {
    final moduleFileMap = '$stageXLStoragePrefix${(stageXLFileMap?[key] as JSString).toDart}';
    final response = await retry(() => http.get(Uri.parse('scripts/$moduleFileMap')));

    return _modulesCache[key] = jsonDecode(response.body) as Map<String, Object?>;
  } catch (e) {
    rethrow;
  }
}

enum CompressedTextureFileTypes {
  pvr,
  ktx
}
