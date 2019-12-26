part of stagexl.resources;

class LoaderTuple {
  _TextureAtlasLoaderFile loader;
  Future<TextureAtlas> atlasFuture;

  LoaderTuple(this.loader, this.atlasFuture);
}

class TextureAtlas {
  /// A list with the frames in this texture atlas.
  final frames = <String, TextureAtlasFrame>{};

  /// The pixelRatio used for the BitmapDatas in the frames
  final double pixelRatio;

  TextureAtlas(this.pixelRatio);

  //---------------------------------------------------------------------------

  static LoaderTuple load(String url, [
      TextureAtlasFormat textureAtlasFormat,
      BitmapDataLoadOptions bitmapDataLoadOptions])
  {
    textureAtlasFormat ??= TextureAtlasFormat.JSONARRAY;

    final loader = new _TextureAtlasLoaderFile(url, bitmapDataLoadOptions);
    return new LoaderTuple(loader, textureAtlasFormat.load(loader));
  }


  static Future<TextureAtlas> fromTextureAtlas(
      TextureAtlas textureAtlas, String namePrefix, String source, [TextureAtlasFormat textureAtlasFormat])
  {
    textureAtlasFormat ??= TextureAtlasFormat.JSONARRAY;
    return textureAtlasFormat.load(new _TextureAtlasLoaderTextureAtlas(
      textureAtlas, namePrefix, source));
  }

  static Future<TextureAtlas> fromBitmapData(
      BitmapData bitmapData, String source, [TextureAtlasFormat textureAtlasFormat])
  {
    textureAtlasFormat ??= TextureAtlasFormat.JSONARRAY;
    return textureAtlasFormat.load(new _TextureAtlasLoaderBitmapData(
        bitmapData, source));
  }

  static Future<TextureAtlas> withLoader(
      TextureAtlasLoader textureAtlasLoader, [TextureAtlasFormat textureAtlasFormat])
  {
    textureAtlasFormat ??= TextureAtlasFormat.JSONARRAY;
    return textureAtlasFormat.load(textureAtlasLoader);
  }

  //---------------------------------------------------------------------------

  /// A list with the frame-names in this texture atlas.
  List<String> get frameNames => frames.keys.toList();

  /// Get a list of BitmapDatas of frames whose names starts with [namePrefix].
  List<BitmapData> getBitmapDatas(String namePrefix) => frames.values
      .where((f) => f.name.startsWith(namePrefix))
      .map((f) => f.bitmapData)
      .toList();

  /// Get the BitmapData of the frame with the given [name].
  ///
  /// The name of a frame is the original file name of the image
  /// without it's file extension.
  BitmapData getBitmapData(String name) {
    if (frames[name] != null) return frames[name].bitmapData;
    return null;
  }
}
