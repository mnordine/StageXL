part of stagexl.engine;

// http://cdn.imgtec.com/sdk-documentation/PVR+File+Format.Specification.pdf
class PvrFormat {
  static const pvrtc_rgb_2bpp = 0;
  static const pvrtc_rgba_2bpp = 1;
  static const pvrtc_rgb_4bpp = 2;
  static const pvrtc_rgba_4bpp = 3;
  static const pvrtc_2_2bpp = 4;
  static const pvrtc_2_4bpp = 5;

  static const etc1 = 6;

  static const dxt1 = 7;
  static const dxt2 = 8;
  static const dxt3 = 9;
  static const dxt4 = 10;
  static const dxt5 = 11;

  static const bc1 = 7;
  static const bc2 = 9;
  static const bc3 = 11;

  static const etc2_rgb = 22;
  static const etc2_rgba = 23;
  static const etc2_rgba1 = 24;

  static const astc_4x4 = 27;
  static const astc_5x4 = 28;
  static const astc_5x5 = 29;
  static const astc_6x5 = 30;
  static const astc_6x6 = 31;
  static const astc_8x5 = 32;
  static const astc_8x6 = 33;
  static const astc_8x8 = 34;
  static const astc_10x5 = 35;
  static const astc_10x6 = 36;
  static const astc_10x8 = 37;
  static const astc_10x10 = 38;
  static const astc_12x10 = 39;
  static const astc_12x12 = 40;
}

class PvrTexture extends CompressedTexture {
  late final int _texDataOffset;
  late final int _pvrFormat;

  PvrTexture(super.buffer) : super() {
    _parseHeader();
  }

  void _parseHeader() {
    final bytes = ByteArray.fromBuffer(_buffer);

    final magic = bytes.readUnsignedInt();
    if (magic != 0x03525650) {
      throw LoadError('compressed texture has unrecognized magic, not a pvr header');
    }

    const headerSize = 52;

    if (bytes.length <= headerSize) {
      throw LoadError('compressed texture does not have enough data to decode pvr');
    }

    /*final flags = */ bytes.readUnsignedInt();
    _pvrFormat = bytes.readUnsignedInt();
    /*final order = */ List.generate(4, (_) => bytes.readByte());
    /*final colorSpace =*/ bytes.readUnsignedInt();
    /*final channelType =*/ bytes.readUnsignedInt();
    height = bytes.readUnsignedInt();
    width = bytes.readUnsignedInt();
    /*final depth = */ bytes.readUnsignedInt();
    /*final surfaceCount =*/ bytes.readUnsignedInt();
    /*final faceCount =*/ bytes.readUnsignedInt();
    /*final mipCount =*/ bytes.readUnsignedInt();
    final metaDataSize = bytes.readUnsignedInt();

    _texDataOffset = bytes.offset + metaDataSize;
  }

  @override
  int get format {
    switch (_pvrFormat) {
      // NOTE(CEksal): These formats aren't exposed by `package:web`, so we instead import
      // from `dart:web_gl`. These could be replaced with the GLenum values directly.
      case PvrFormat.etc2_rgb:
        return CompressedTextureEtc.COMPRESSED_RGB8_ETC2;
      case PvrFormat.etc2_rgba:
        return CompressedTextureEtc.COMPRESSED_RGBA8_ETC2_EAC;

      // NOTE(CEksal): These are exported from `package:web`, so we'll use them instead.
      case PvrFormat.bc1:
        return WEBGL_compressed_texture_s3tc.COMPRESSED_RGBA_S3TC_DXT1_EXT;
      case PvrFormat.bc3:
        return WEBGL_compressed_texture_s3tc.COMPRESSED_RGBA_S3TC_DXT5_EXT;

      case PvrFormat.astc_4x4:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_4x4_KHR;
      case PvrFormat.astc_5x4:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_5x4_KHR;
      case PvrFormat.astc_5x5:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_5x5_KHR;
      case PvrFormat.astc_6x5:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_6x5_KHR;
      case PvrFormat.astc_6x6:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_6x6_KHR;
      case PvrFormat.astc_8x5:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_8x5_KHR;
      case PvrFormat.astc_8x6:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_8x6_KHR;
      case PvrFormat.astc_8x8:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_8x8_KHR;
      case PvrFormat.astc_10x5:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_10x5_KHR;
      case PvrFormat.astc_10x6:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_10x6_KHR;
      case PvrFormat.astc_10x8:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_10x8_KHR;
      case PvrFormat.astc_10x10:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_10x10_KHR;
      case PvrFormat.astc_12x10:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_12x10_KHR;
      case PvrFormat.astc_12x12:
        return WEBGL_compressed_texture_astc.COMPRESSED_RGBA_ASTC_12x12_KHR;

      default:
        return -1;
    }
  }

  @override
  ByteData get textureData => _buffer.asByteData(_texDataOffset);
}
