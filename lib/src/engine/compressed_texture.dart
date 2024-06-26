part of stagexl.engine;

abstract class CompressedTexture {
  late final int width;
  late final int height;
  final ByteBuffer _buffer;

  CompressedTexture(this._buffer);

  static bool supportsDxt(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_s3tc');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_s3tc');

    return ext != null;
  }

  static bool supportsPvrtc(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_pvrtc');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_pvrtc');

    return ext != null;
  }

  static bool supportsEtc(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_etc');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_etc');

    return ext != null;
  }

  static bool supportsEtc1(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_etc1');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_etc1');

    return ext != null;
  }

  static bool supportsAstc(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_astc');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_astc');

    return ext != null;
  }

  /// Texture data that can be passed to WebGL functions
  TypedData get textureData;

  /// Translates internal texture format to WebGL texture format enum
  int get format;
}
