part of stagexl.engine;

class CompressedExtensions {
  final WebGLCompressedTextureS3tc? s3tc;
  final WebGLCompressedTextureAstc? astc;
  final WebGLCompressedTexturePvrtc? pvrtc;
  final WebGLCompressedTextureEtc? etc;
  final WebGLCompressedTextureEtc1? etc1;

  CompressedExtensions(WebGL context):
    s3tc = CompressedTexture.dxtExtension(context),
    astc = CompressedTexture.astcExtension(context),
    pvrtc = CompressedTexture.pvrtcExtension(context),
    etc = CompressedTexture.etcExtension(context),
    etc1 = CompressedTexture.etc1Extension(context);
}

abstract class CompressedTexture {
  late final int width;
  late final int height;
  final ByteBuffer _buffer;
  static CompressedExtensions? extensions;

  CompressedTexture(this._buffer);

  static WebGLCompressedTextureS3tc? dxtExtension(WebGL context) =>
    (context.getExtension('WEBGL_compressed_texture_s3tc')
      ?? context.getExtension('WEBKIT_WEBGL_compressed_texture_s3tc')) as WebGLCompressedTextureS3tc?;

  static bool get supportsDxt => extensions?.s3tc != null;

  static WebGLCompressedTexturePvrtc? pvrtcExtension(WebGL context) =>
    (context.getExtension('WEBGL_compressed_texture_pvrtc')
      ?? context.getExtension('WEBKIT_WEBGL_compressed_texture_pvrtc')) as WebGLCompressedTexturePvrtc?;

  static bool get supportsPvrtc => extensions?.pvrtc != null;

  static WebGLCompressedTextureEtc? etcExtension(WebGL context) =>
    (context.getExtension('WEBGL_compressed_texture_etc')
      ?? context.getExtension('WEBGL_compressed_texture_etc')) as WebGLCompressedTextureEtc?;


  static bool get supportsEtc => extensions?.etc != null;

  static WebGLCompressedTextureEtc1? etc1Extension(WebGL context) =>
    (context.getExtension('WEBGL_compressed_texture_etc1')
      ?? context.getExtension('WEBKIT_WEBGL_compressed_texture_etc1')) as WebGLCompressedTextureEtc1?;

  static bool get supportsEtc1 => extensions?.etc1 != null;

  static WebGLCompressedTextureAstc? astcExtension(WebGL context) =>
    (context.getExtension('WEBGL_compressed_texture_astc')
      ?? context.getExtension('WEBKIT_WEBGL_compressed_texture_astc')) as WebGLCompressedTextureAstc?;

  static bool get supportsAstc => extensions?.astc != null;

  static void initExtensions(WebGL context) => extensions = CompressedExtensions(context);

  /// Texture data that can be passed to WebGL functions
  ByteData get textureData;

  /// Translates internal texture format to WebGL texture format enum
  int get format;
}
