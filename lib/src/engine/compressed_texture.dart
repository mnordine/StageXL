part of stagexl.engine;

abstract class CompressedTexture {
  int width;
  int height;
  ByteBuffer _buffer;

  CompressedTexture();

  CompressedTexture.fromBuffer(this._buffer);

  /// Texture data that can be passed to WebGL functions
  TypedData get textureData;

  /// Translates internal texture format to WebGL texture format enum
  int get format;
}

enum PvrFormat {
  PVRTC_RGB_2BPP,
  PVRTC_RGBA_2BPP,
  PVRTC_RGB_4BPP,
  PVRTC_RGBA_4BPP,
  PVRTC_2_2BPP,
  PVRTC_2_4BPP,
  ETC1,
  DXT1,
  DXT3,
  DXT5,
  BC1,
  BC2,
  BC3,
  BC4,
  BC5,
  BC6,
  UYVY,
  YUY2,
  BW1_BPP,
  R9G9B9E5_SHARED,
  RGBG8888,
  GRGB8888,
  ETC2_RGB,
  ETC2_RGBA,
  ETC2_RGBA1,
  EAC_R11,
  ASTC_4x4,
  ASTC_5x4,
  ASTC_5x5
}

class PvrTexture extends CompressedTexture {

  int _texDataOffset;
  PvrFormat _pvrFormat;

  PvrTexture.fromBuffer(ByteBuffer buffer) : super.fromBuffer(buffer) {
    _parseHeader();
  }

  void _parseHeader() {
    final bytes = new ByteArray.fromBuffer(_buffer);

    final magic = bytes.readUnsignedInt();
    if (magic !=  0x03525650) {
      print('unrecognized magic');
      return;
    }

    const headerSize = 52;

    if (bytes.length <= headerSize) {
      print('not enough data to decode pvr');
      return;
    }

    final flags = bytes.readUnsignedInt();
    _pvrFormat = PvrFormat.values[bytes.readUnsignedInt()];
    print(PvrFormat.values[_pvrFormat.index]);
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
    switch (_pvrFormat)
    {
      case PvrFormat.PVRTC_RGB_2BPP:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_2BPPV1_IMG;
      case PvrFormat.PVRTC_RGB_4BPP:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;
      case PvrFormat.PVRTC_RGBA_2BPP: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_2BPPV1_IMG;
      case PvrFormat.PVRTC_RGBA_4BPP: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;

      case PvrFormat.ETC1:  return gl.CompressedTextureETC1.COMPRESSED_RGB_ETC1_WEBGL;
      case PvrFormat.ETC2_RGBA: return 0x9278; //gl.CompressedTextureETC1.COMPRESSED_RGBA_ETC2_WEBGL;
      case PvrFormat.ETC2_RGBA1: return 0x9279; //gl.CompressedTextureETC1.COMPRESSED_SRGB_ETC2_WEBGL;
    }

    return -1;
  }

  TypedData get textureData => _buffer.asByteData(_texDataOffset);
}