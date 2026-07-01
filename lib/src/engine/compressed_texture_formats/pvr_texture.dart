part of '../../engine.dart';

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
  late final int _mipCount;
  late final List<int> _mipOffsets;
  late final List<int> _mipLengths;

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
    final depth = bytes.readUnsignedInt();
    final surfaceCount = bytes.readUnsignedInt();
    final faceCount = bytes.readUnsignedInt();
    _mipCount = bytes.readUnsignedInt();
    final metaDataSize = bytes.readUnsignedInt();

    if (depth != 1 || surfaceCount != 1 || faceCount != 1) {
      throw LoadError('PVR texture is not a 2D single-surface texture.');
    }
    if (_mipCount <= 0) {
      throw LoadError('PVR texture has no mip levels.');
    }

    _texDataOffset = bytes.offset + metaDataSize;
    _mipOffsets = List<int>.filled(_mipCount, 0);
    _mipLengths = List<int>.filled(_mipCount, 0);

    var currentOffset = _texDataOffset;
    for (var level = 0; level < _mipCount; level++) {
      final blocksX = (mipWidth(level) + blockWidth - 1) ~/ blockWidth;
      final blocksY = (mipHeight(level) + blockHeight - 1) ~/ blockHeight;
      final byteLength = blocksX * blocksY * blockByteLength;
      if (currentOffset + byteLength > _buffer.lengthInBytes) {
        throw LoadError('PVR texture data is truncated.');
      }

      _mipOffsets[level] = currentOffset;
      _mipLengths[level] = byteLength;
      currentOffset += byteLength;
    }
  }

  @override
  int get format {
    final ext = CompressedTexture.extensions;
    if (ext == null) {
      return -1;
    }

    return switch (_pvrFormat) {
      PvrFormat.etc1 => ext.etc1?.COMPRESSED_RGB_ETC1_WEBGL,
      PvrFormat.etc2_rgb => ext.etc?.COMPRESSED_RGB8_ETC2,
      PvrFormat.etc2_rgba => ext.etc?.COMPRESSED_RGBA8_ETC2_EAC,

      PvrFormat.bc1 => ext.s3tc?.COMPRESSED_RGBA_S3TC_DXT1_EXT,
      PvrFormat.bc3 => ext.s3tc?.COMPRESSED_RGBA_S3TC_DXT5_EXT,

      PvrFormat.astc_4x4 => ext.astc?.COMPRESSED_RGBA_ASTC_4x4_KHR,
      PvrFormat.astc_5x4 => ext.astc?.COMPRESSED_RGBA_ASTC_5x4_KHR,
      PvrFormat.astc_5x5 => ext.astc?.COMPRESSED_RGBA_ASTC_5x5_KHR,
      PvrFormat.astc_6x5 => ext.astc?.COMPRESSED_RGBA_ASTC_6x5_KHR,
      PvrFormat.astc_6x6 => ext.astc?.COMPRESSED_RGBA_ASTC_6x6_KHR,
      PvrFormat.astc_8x5 => ext.astc?.COMPRESSED_RGBA_ASTC_8x5_KHR,
      PvrFormat.astc_8x6 => ext.astc?.COMPRESSED_RGBA_ASTC_8x6_KHR,
      PvrFormat.astc_8x8 => ext.astc?.COMPRESSED_RGBA_ASTC_8x8_KHR,
      PvrFormat.astc_10x5 => ext.astc?.COMPRESSED_RGBA_ASTC_10x5_KHR,
      PvrFormat.astc_10x6 => ext.astc?.COMPRESSED_RGBA_ASTC_10x6_KHR,
      PvrFormat.astc_10x8 => ext.astc?.COMPRESSED_RGBA_ASTC_10x8_KHR,
      PvrFormat.astc_10x10 => ext.astc?.COMPRESSED_RGBA_ASTC_10x10_KHR,
      PvrFormat.astc_12x10 => ext.astc?.COMPRESSED_RGBA_ASTC_12x10_KHR,
      PvrFormat.astc_12x12 => ext.astc?.COMPRESSED_RGBA_ASTC_12x12_KHR,

      _ => null
    } ?? -1;
  }

  @override
  ByteData get textureData => _buffer.asByteData(_texDataOffset);

  @override
  String? get webGpuTextureFormat => switch (_pvrFormat) {
    PvrFormat.etc2_rgb => 'etc2-rgb8unorm',
    PvrFormat.etc2_rgba => 'etc2-rgba8unorm',
    PvrFormat.etc2_rgba1 => 'etc2-rgb8a1unorm',

    PvrFormat.bc1 => 'bc1-rgba-unorm',
    PvrFormat.bc3 => 'bc3-rgba-unorm',

    PvrFormat.astc_4x4 => 'astc-4x4-unorm',
    PvrFormat.astc_5x4 => 'astc-5x4-unorm',
    PvrFormat.astc_5x5 => 'astc-5x5-unorm',
    PvrFormat.astc_6x5 => 'astc-6x5-unorm',
    PvrFormat.astc_6x6 => 'astc-6x6-unorm',
    PvrFormat.astc_8x5 => 'astc-8x5-unorm',
    PvrFormat.astc_8x6 => 'astc-8x6-unorm',
    PvrFormat.astc_8x8 => 'astc-8x8-unorm',
    PvrFormat.astc_10x5 => 'astc-10x5-unorm',
    PvrFormat.astc_10x6 => 'astc-10x6-unorm',
    PvrFormat.astc_10x8 => 'astc-10x8-unorm',
    PvrFormat.astc_10x10 => 'astc-10x10-unorm',
    PvrFormat.astc_12x10 => 'astc-12x10-unorm',
    PvrFormat.astc_12x12 => 'astc-12x12-unorm',
    _ => null,
  };

  @override
  String? get webGpuRequiredFeature => switch (_pvrFormat) {
    PvrFormat.bc1 || PvrFormat.bc3 => 'texture-compression-bc',
    PvrFormat.etc2_rgb || PvrFormat.etc2_rgba || PvrFormat.etc2_rgba1 => 'texture-compression-etc2',
    PvrFormat.astc_4x4 ||
    PvrFormat.astc_5x4 ||
    PvrFormat.astc_5x5 ||
    PvrFormat.astc_6x5 ||
    PvrFormat.astc_6x6 ||
    PvrFormat.astc_8x5 ||
    PvrFormat.astc_8x6 ||
    PvrFormat.astc_8x8 ||
    PvrFormat.astc_10x5 ||
    PvrFormat.astc_10x6 ||
    PvrFormat.astc_10x8 ||
    PvrFormat.astc_10x10 ||
    PvrFormat.astc_12x10 ||
    PvrFormat.astc_12x12 => 'texture-compression-astc',
    _ => null,
  };

  @override
  int get blockWidth => switch (_pvrFormat) {
    PvrFormat.astc_4x4 => 4,
    PvrFormat.astc_5x4 || PvrFormat.astc_5x5 => 5,
    PvrFormat.astc_6x5 || PvrFormat.astc_6x6 => 6,
    PvrFormat.astc_8x5 || PvrFormat.astc_8x6 || PvrFormat.astc_8x8 => 8,
    PvrFormat.astc_10x5 || PvrFormat.astc_10x6 || PvrFormat.astc_10x8 || PvrFormat.astc_10x10 => 10,
    PvrFormat.astc_12x10 || PvrFormat.astc_12x12 => 12,
    _ => 4,
  };

  @override
  int get blockHeight => switch (_pvrFormat) {
    PvrFormat.astc_4x4 => 4,
    PvrFormat.astc_5x4 => 4,
    PvrFormat.astc_5x5 => 5,
    PvrFormat.astc_6x5 => 5,
    PvrFormat.astc_6x6 => 6,
    PvrFormat.astc_8x5 => 5,
    PvrFormat.astc_8x6 => 6,
    PvrFormat.astc_8x8 => 8,
    PvrFormat.astc_10x5 => 5,
    PvrFormat.astc_10x6 => 6,
    PvrFormat.astc_10x8 => 8,
    PvrFormat.astc_10x10 => 10,
    PvrFormat.astc_12x10 => 10,
    PvrFormat.astc_12x12 => 12,
    _ => 4,
  };

  @override
  int get blockByteLength => switch (_pvrFormat) {
    PvrFormat.bc1 || PvrFormat.etc1 || PvrFormat.etc2_rgb || PvrFormat.etc2_rgba1 => 8,
    PvrFormat.bc3 || PvrFormat.etc2_rgba => 16,
    PvrFormat.astc_4x4 ||
    PvrFormat.astc_5x4 ||
    PvrFormat.astc_5x5 ||
    PvrFormat.astc_6x5 ||
    PvrFormat.astc_6x6 ||
    PvrFormat.astc_8x5 ||
    PvrFormat.astc_8x6 ||
    PvrFormat.astc_8x8 ||
    PvrFormat.astc_10x5 ||
    PvrFormat.astc_10x6 ||
    PvrFormat.astc_10x8 ||
    PvrFormat.astc_10x10 ||
    PvrFormat.astc_12x10 ||
    PvrFormat.astc_12x12 => 16,
    _ => 16,
  };

  @override
  int get mipLevelCount => _mipCount;

  @override
  ByteData textureDataForMipLevel(int level) {
    if (level < 0 || level >= _mipCount) {
      throw RangeError.range(level, 0, _mipCount - 1, 'level');
    }

    return _buffer.asByteData(_mipOffsets[level], _mipLengths[level]);
  }
}
