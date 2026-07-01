part of '../engine.dart';

class CompressedTextureMipLevel {
    final int width;
    final int height;
    final ByteData data;

    CompressedTextureMipLevel(this.width, this.height, this.data);
}

class CompressedExtensions {
  final WebGLCompressedTextureS3tc? s3tc;
  final WebGLCompressedTextureAstc? astc;
  final WebGLCompressedTexturePvrtc? pvrtc;
  final WebGLCompressedTextureEtc? etc;
  final WebGLCompressedTextureEtc1? etc1;

  CompressedExtensions(WebGL context)
      : s3tc = CompressedTexture.dxtExtension(context),
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
      (context.getExtension('WEBGL_compressed_texture_s3tc') ??
          context.getExtension('WEBKIT_WEBGL_compressed_texture_s3tc')) as WebGLCompressedTextureS3tc?;

  static bool get supportsDxt => extensions?.s3tc != null;

  static WebGLCompressedTexturePvrtc? pvrtcExtension(WebGL context) =>
      (context.getExtension('WEBGL_compressed_texture_pvrtc') ??
          context.getExtension('WEBKIT_WEBGL_compressed_texture_pvrtc')) as WebGLCompressedTexturePvrtc?;

  static bool get supportsPvrtc => extensions?.pvrtc != null;

  static WebGLCompressedTextureEtc? etcExtension(WebGL context) =>
      (context.getExtension('WEBGL_compressed_texture_etc') ?? context.getExtension('WEBGL_compressed_texture_etc'))
          as WebGLCompressedTextureEtc?;

  static bool get supportsEtc => extensions?.etc != null;

  static WebGLCompressedTextureEtc1? etc1Extension(WebGL context) =>
      (context.getExtension('WEBGL_compressed_texture_etc1') ??
          context.getExtension('WEBKIT_WEBGL_compressed_texture_etc1')) as WebGLCompressedTextureEtc1?;

  static bool get supportsEtc1 => extensions?.etc1 != null;

  static WebGLCompressedTextureAstc? astcExtension(WebGL context) =>
      (context.getExtension('WEBGL_compressed_texture_astc') ??
          context.getExtension('WEBKIT_WEBGL_compressed_texture_astc')) as WebGLCompressedTextureAstc?;

  static bool get supportsAstc => extensions?.astc != null;

  static void initExtensions(WebGL context) => extensions = CompressedExtensions(context);

  /// Texture data that can be passed to WebGL functions
  ByteData get textureData;

  /// Translates internal texture format to WebGL texture format enum
  int get format;

    /// Translates internal texture format to WebGPU texture format string.
    ///
    /// Returns null if this compressed texture format has no WebGPU equivalent.
    String? get webGpuTextureFormat;

    /// WebGPU feature required to sample this compressed format.
    ///
    /// Returns null if no optional feature is required.
    String? get webGpuRequiredFeature;

    /// Block width in texels for this compressed format.
    int get blockWidth;

    /// Block height in texels for this compressed format.
    int get blockHeight;

    /// Bytes per compressed block.
    int get blockByteLength;

    /// Number of mip levels contained in this texture.
    int get mipLevelCount;

    /// Returns data for the requested mip level.
    ByteData textureDataForMipLevel(int level);

    bool supportsWebGpu(Set<String> enabledFeatures) {
        final requiredFeature = webGpuRequiredFeature;
        return webGpuTextureFormat != null
                && (requiredFeature == null || enabledFeatures.contains(requiredFeature));
    }

    int mipWidth(int level) => math.max(1, width >> level);

    int mipHeight(int level) => math.max(1, height >> level);

    int bytesPerRowForMipLevel(int level) {
        final blocksX = (mipWidth(level) + blockWidth - 1) ~/ blockWidth;
        return blocksX * blockByteLength;
    }

    int rowsPerImageForMipLevel(int level) {
        final blocksY = (mipHeight(level) + blockHeight - 1) ~/ blockHeight;
        return blocksY;
    }

    int webGpuWidthForMipLevel(int level) => _alignToBlock(mipWidth(level), blockWidth);

    int webGpuHeightForMipLevel(int level) => _alignToBlock(mipHeight(level), blockHeight);

    int get webGpuWidth => webGpuWidthForMipLevel(0);

    int get webGpuHeight => webGpuHeightForMipLevel(0);

  int _alignToBlock(int value, int blockSize) => ((value + blockSize - 1) ~/ blockSize) * blockSize;
}
