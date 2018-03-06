part of stagexl.engine;

abstract class CompressedTexture {
  int width;
  int height;
  ByteBuffer _buffer;

  CompressedTexture();

  CompressedTexture.fromBuffer(this._buffer);

  static bool supportsDxt5(gl.RenderingContext context)
  {
    var ext = context.getExtension('WEBGL_compressed_texture_s3tc');
    ext ??= context.getExtension('WEBKIT_WEBGL_compressed_texture_s3tc');

    print('supports s3tc? ${ext != null}');

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

// http://cdn.imgtec.com/sdk-documentation/PVR+File+Format.Specification.pdf
class PvrFormat {
  static const pvrtc_rgb_2bpp  = 0;
  static const pvrtc_rgba_2bpp = 1;
  static const pvrtc_rgb_4bpp  = 2;
  static const pvrtc_rgba_4bpp = 3;
  static const pvrtc_2_2bpp    = 4;
  static const pvrtc_2_4bpp    = 5;

  static const etc1 = 6;

  static const dxt1 = 7;
  static const dxt2 = 8;
  static const dxt3 = 9;
  static const dxt4 = 10;
  static const dxt5 = 11;

  static const bc1 = 7;
  static const bc2 = 9;
  static const bc3 = 11;

  static const etc2_rgb   = 22;
  static const etc2_rgba  = 23;
  static const etc2_rgba1 = 24;

  static const astc_4x4   = 27;
  static const astc_5x4   = 28;
  static const astc_5x5   = 29;
  static const astc_6x5   = 30;
  static const astc_6x6   = 31;
  static const astc_8x5   = 32;
  static const astc_8x6   = 33;
  static const astc_8x8   = 34;
  static const astc_10x5  = 35;
  static const astc_10x6  = 36;
  static const astc_10x8  = 37;
  static const astc_10x10 = 38;
  static const astc_12x10 = 39;
  static const astc_12x12 = 40;
}

class PvrTexture extends CompressedTexture {

  int _texDataOffset;
  int _pvrFormat;

  PvrTexture.fromBuffer(ByteBuffer buffer) : super.fromBuffer(buffer) {
    _parseHeader();
  }

  void _parseHeader() {
    final bytes = new ByteArray.fromBuffer(_buffer);

    final magic = bytes.readUnsignedInt();
    if (magic !=  0x03525650) {
      print('unrecognized magic, not a pvr header');
      return;
    }

    const headerSize = 52;

    if (bytes.length <= headerSize) {
      print('not enough data to decode pvr');
      return;
    }

    final flags = bytes.readUnsignedInt();
    _pvrFormat = bytes.readUnsignedInt();
    print('pvr format: $_pvrFormat');
    final order = new List.generate(4, (_) => bytes.readByte());
    final colorSpace = bytes.readUnsignedInt();
    final channelType = bytes.readUnsignedInt();
    height = bytes.readUnsignedInt();
    width = bytes.readUnsignedInt();
    final depth = bytes.readUnsignedInt();
    final surfaceCount = bytes.readUnsignedInt();
    final faceCount = bytes.readUnsignedInt();
    final mipCount = bytes.readUnsignedInt();
    final metaDataSize = bytes.readUnsignedInt();

    print('flags: $flags');
    print('order: $order');
    print('color space: $colorSpace');
    print('channel type: $channelType');
    print('depth: $depth');
    print('surface count: $surfaceCount');
    print('face count: $faceCount');
    print('mip count: $mipCount');
    print('meta data size: $metaDataSize');
    print('width: $width');
    print('height: $height');

    _texDataOffset = bytes.offset + metaDataSize;
  }

  int get format
  {
    // https://www.khronos.org/registry/webgl/extensions/WEBGL_compressed_texture_etc/
    const rgb8_etc2      = 0x9274;
    const rgba8_etc2_eac = 0x9278;

    // https://www.khronos.org/registry/webgl/extensions/WEBGL_compressed_texture_astc/
    const rgba_astc_4x4_khr = 0x93B0;
    const rgba_astc_5x4_khr = 0x93B1;
    const rgba_astc_5x5_khr = 0x93B2;
    const rgba_astc_6x5_khr = 0x93B3;
    const rgba_astc_6x6_khr = 0x93B4;
    const rgba_astc_8x5_khr = 0x93B5;
    const rgba_astc_8x6_khr = 0x93B6;
    const rgba_astc_8x8_khr = 0x93B7;
    const rgba_astc_10x5_khr = 0x93B8;
    const rgba_astc_10x6_khr = 0x93B9;
    const rgba_astc_10x8_khr = 0x93BA;
    const rgba_astc_10x10_khr = 0x93BB;
    const rgba_astc_12x10_khr = 0x93BC;
    const rgba_astc_12x12_khr = 0x93BD;

    switch (_pvrFormat)
    {
      case PvrFormat.pvrtc_rgb_2bpp:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_2BPPV1_IMG;
      case PvrFormat.pvrtc_rgb_4bpp:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;
      case PvrFormat.pvrtc_rgba_2bpp: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_2BPPV1_IMG;
      case PvrFormat.pvrtc_rgba_4bpp: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;

      case PvrFormat.etc1: return gl.CompressedTextureETC1.COMPRESSED_RGB_ETC1_WEBGL;
      case PvrFormat.etc2_rgb: return rgb8_etc2;
      case PvrFormat.etc2_rgba: return rgba8_etc2_eac;

      case PvrFormat.bc1: return gl.CompressedTextureS3TC.COMPRESSED_RGBA_S3TC_DXT1_EXT;
      case PvrFormat.bc3: return gl.CompressedTextureS3TC.COMPRESSED_RGBA_S3TC_DXT5_EXT;

      case PvrFormat.astc_4x4: return rgba_astc_4x4_khr;
      case PvrFormat.astc_5x4: return rgba_astc_5x4_khr;
      case PvrFormat.astc_5x5: return rgba_astc_5x5_khr;
      case PvrFormat.astc_6x5: return rgba_astc_6x5_khr;
      case PvrFormat.astc_6x6: return rgba_astc_6x6_khr;
      case PvrFormat.astc_8x5: return rgba_astc_8x5_khr;
      case PvrFormat.astc_8x6: return rgba_astc_8x6_khr;
      case PvrFormat.astc_8x8: return rgba_astc_8x8_khr;
      case PvrFormat.astc_10x5: return rgba_astc_10x5_khr;
      case PvrFormat.astc_10x6: return rgba_astc_10x6_khr;
      case PvrFormat.astc_10x8: return rgba_astc_10x8_khr;
      case PvrFormat.astc_10x10: return rgba_astc_10x10_khr;
      case PvrFormat.astc_12x10: return rgba_astc_12x10_khr;
      case PvrFormat.astc_12x12: return rgba_astc_12x12_khr;

      default: return -1;
    }
  }

  TypedData get textureData => _buffer.asByteData(_texDataOffset);
}