part of '../resources.dart';

abstract class TextureAtlasFormat {
  static TextureAtlasFormat json = _TextureAtlasFormatJson();
  static TextureAtlasFormat jsonArray = _TextureAtlasFormatJson();
  static const TextureAtlasFormat libGdx = _TextureAtlasFormatLibGDX();
  static const TextureAtlasFormat starlingXml = _TextureAtlasFormatStarlingXml();
  static const TextureAtlasFormat starlingJson = _TextureAtlasFormatStarlingJson();

  const TextureAtlasFormat();

  Future<TextureAtlas> load(TextureAtlasLoader textureAtlasLoader);
}
