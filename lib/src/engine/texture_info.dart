part of stagexl.engine;

class TextureInfo {

  int target = gl.WebGL.TEXTURE_2D;
  int pixelFormat = gl.WebGL.RGBA;
  int pixelType = gl.WebGL.UNSIGNED_BYTE;

  @override
  bool operator == (Object other) =>
    other is TextureInfo
        && other.target == target
        && other.pixelFormat == pixelFormat
        && other.pixelType == pixelType;

  @override
  int get hashCode => JenkinsHash.hash3(target, pixelFormat, pixelType);
}
