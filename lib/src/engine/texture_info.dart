part of stagexl.engine;

class TextureInfo {

  int target = WebGL.TEXTURE_2D;
  int pixelFormat = WebGL.RGBA;
  int pixelType = WebGL.UNSIGNED_BYTE;

  @override
  bool operator == (Object other) =>
    other is TextureInfo
        && other.target == target
        && other.pixelFormat == pixelFormat
        && other.pixelType == pixelType;

  @override
  int get hashCode => Object.hash(target, pixelFormat, pixelType);
}

