part of '../../engine.dart';

// https://registry.khronos.org/KTX/specs/1.0/ktxspec.v1.html
class KtxFormat {
  static const ktx_magic = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A];
  static const ktx_end_le = 0x04030201;
  static const ktx_end_be = 0x01020304;

  static const compRgbaS3tcDxt1Ext = 0x83F1;
  static const compRgbaS3tcDxt3Ext = 0x83F2;
  static const compRgbaS3tcDxt5Ext = 0x83F3;

  static const compRgb8Etc2 = 0x9274;
  static const compRgb8PunchthroughAlpha1Etc2 = 0x9276;
  static const compRgba8Etc2Eac = 0x9278;

  static const compRgbaAstc4x4Khr = 0x93B0;
  static const compRgbaAstc5x4Khr = 0x93B1;
  static const compRgbaAstc5x5Khr = 0x93B2;
  static const compRgbaAstc6x5Khr = 0x93B3;
  static const compRgbaAstc6x6Khr = 0x93B4;
  static const compRgbaAstc8x5Khr = 0x93B5;
  static const compRgbaAstc8x6Khr = 0x93B6;
  static const compRgbaAstc8x8Khr = 0x93B7;
  static const compRgbaAstc10x5Khr = 0x93B8;
  static const compRgbaAstc10x6Khr = 0x93B9;
  static const compRgbaAstc10x8Khr = 0x93BA;
  static const compRgbaAstc10x10Khr = 0x93BB;
  static const compRgbaAstc12x10Khr = 0x93BC;
  static const compRgbaAstc12x12Khr = 0x93BD;
}

class KtxTexture extends CompressedTexture {
  late final int _glInternalFormat;
  late final List<int> _mipOffsets;
  late final List<int> _mipLengths;
  late final int _mipLevelCount;

  KtxTexture(super.buffer) : super() {
    _parseHeader();
  }

  void _parseHeader() {
    final bytes = ByteArray.fromBuffer(_buffer);
    final magic = List.generate(12, (_) => bytes.readUnsignedByte());

    for (final entry in magic.asMap().entries) {
      if (entry.value != KtxFormat.ktx_magic[entry.key]) {
        throw LoadError('compressed texture has unrecognized magic, not a ktx header');
      }
    }

    final endianness = bytes.readUnsignedInt();
    switch (endianness) {
      case KtxFormat.ktx_end_le:
        // We're already reading in little endian
        break;
      case KtxFormat.ktx_end_be:
        // Switch the ByteArray to reading in big endian
        // TODO(CEksal): Test on big endian files to make sure they work as expected.
        print('warning: ktx file is big endian, this is untested');
        bytes.endian = .big;
      default:
        throw LoadError('compressed texture has unrecognized endianness, not a ktx header');
    }

    /*final glType = */ bytes.readUnsignedInt();
    /*final glTypeSize = */ bytes.readUnsignedInt();
    /*final glFormat = */ bytes.readUnsignedInt();
    _glInternalFormat = bytes.readUnsignedInt();
    /*final glBaseInternalFormat = */ bytes.readUnsignedInt();
    width = bytes.readUnsignedInt();
    height = bytes.readUnsignedInt();

    final pixelDepth = bytes.readUnsignedInt();
    final numberOfArrayElements = bytes.readUnsignedInt();
    final numberOfFaces = bytes.readUnsignedInt();
    var numberOfMipmapLevels = bytes.readUnsignedInt();

    if (pixelDepth > 1 || numberOfArrayElements > 0 || numberOfFaces != 1) {
      throw LoadError('KTX texture is not a 2D single-face texture.');
    }

    if (numberOfMipmapLevels == 0) {
      numberOfMipmapLevels = 1;
    }
    _mipLevelCount = numberOfMipmapLevels;

    final bytesOfKeyValueData = bytes.readUnsignedInt();
    /*final keyValueDatas = */ List.generate(bytesOfKeyValueData, (_) => bytes.readByte());

    _mipOffsets = List<int>.filled(_mipLevelCount, 0);
    _mipLengths = List<int>.filled(_mipLevelCount, 0);

    for (var level = 0; level < _mipLevelCount; level++) {
      if (bytes.bytesAvailable < 4) {
        throw LoadError('KTX texture is truncated before mip level size.');
      }

      final imageSize = bytes.readUnsignedInt();
      if (bytes.bytesAvailable < imageSize) {
        throw LoadError('KTX texture is truncated in mip level data.');
      }

      _mipOffsets[level] = bytes.offset;
      _mipLengths[level] = imageSize;
      bytes.offset += imageSize;

      final padding = (4 - (imageSize % 4)) % 4;
      if (bytes.bytesAvailable < padding) {
        throw LoadError('KTX texture is truncated in mip level padding.');
      }
      bytes.offset += padding;
    }
  }

  // NOTE(CEksal): glInternalFormat stores the glEnum value of the format
  // being used, so we can just return it.
  @override
  int get format => _glInternalFormat;

  @override
  ByteData get textureData => textureDataForMipLevel(0);

  @override
  String? get webGpuTextureFormat => switch (_glInternalFormat) {
    KtxFormat.compRgbaS3tcDxt1Ext => 'bc1-rgba-unorm',
    KtxFormat.compRgbaS3tcDxt3Ext => 'bc2-rgba-unorm',
    KtxFormat.compRgbaS3tcDxt5Ext => 'bc3-rgba-unorm',

    KtxFormat.compRgb8Etc2 => 'etc2-rgb8unorm',
    KtxFormat.compRgb8PunchthroughAlpha1Etc2 => 'etc2-rgb8a1unorm',
    KtxFormat.compRgba8Etc2Eac => 'etc2-rgba8unorm',

    KtxFormat.compRgbaAstc4x4Khr => 'astc-4x4-unorm',
    KtxFormat.compRgbaAstc5x4Khr => 'astc-5x4-unorm',
    KtxFormat.compRgbaAstc5x5Khr => 'astc-5x5-unorm',
    KtxFormat.compRgbaAstc6x5Khr => 'astc-6x5-unorm',
    KtxFormat.compRgbaAstc6x6Khr => 'astc-6x6-unorm',
    KtxFormat.compRgbaAstc8x5Khr => 'astc-8x5-unorm',
    KtxFormat.compRgbaAstc8x6Khr => 'astc-8x6-unorm',
    KtxFormat.compRgbaAstc8x8Khr => 'astc-8x8-unorm',
    KtxFormat.compRgbaAstc10x5Khr => 'astc-10x5-unorm',
    KtxFormat.compRgbaAstc10x6Khr => 'astc-10x6-unorm',
    KtxFormat.compRgbaAstc10x8Khr => 'astc-10x8-unorm',
    KtxFormat.compRgbaAstc10x10Khr => 'astc-10x10-unorm',
    KtxFormat.compRgbaAstc12x10Khr => 'astc-12x10-unorm',
    KtxFormat.compRgbaAstc12x12Khr => 'astc-12x12-unorm',
    _ => null,
  };

  @override
  String? get webGpuRequiredFeature => switch (_glInternalFormat) {
    KtxFormat.compRgbaS3tcDxt1Ext || KtxFormat.compRgbaS3tcDxt3Ext || KtxFormat.compRgbaS3tcDxt5Ext =>
      'texture-compression-bc',
    KtxFormat.compRgb8Etc2 || KtxFormat.compRgb8PunchthroughAlpha1Etc2 || KtxFormat.compRgba8Etc2Eac =>
      'texture-compression-etc2',
    KtxFormat.compRgbaAstc4x4Khr ||
    KtxFormat.compRgbaAstc5x4Khr ||
    KtxFormat.compRgbaAstc5x5Khr ||
    KtxFormat.compRgbaAstc6x5Khr ||
    KtxFormat.compRgbaAstc6x6Khr ||
    KtxFormat.compRgbaAstc8x5Khr ||
    KtxFormat.compRgbaAstc8x6Khr ||
    KtxFormat.compRgbaAstc8x8Khr ||
    KtxFormat.compRgbaAstc10x5Khr ||
    KtxFormat.compRgbaAstc10x6Khr ||
    KtxFormat.compRgbaAstc10x8Khr ||
    KtxFormat.compRgbaAstc10x10Khr ||
    KtxFormat.compRgbaAstc12x10Khr ||
    KtxFormat.compRgbaAstc12x12Khr => 'texture-compression-astc',
    _ => null,
  };

  @override
  int get blockWidth => switch (_glInternalFormat) {
    KtxFormat.compRgbaAstc4x4Khr => 4,
    KtxFormat.compRgbaAstc5x4Khr || KtxFormat.compRgbaAstc5x5Khr => 5,
    KtxFormat.compRgbaAstc6x5Khr || KtxFormat.compRgbaAstc6x6Khr => 6,
    KtxFormat.compRgbaAstc8x5Khr || KtxFormat.compRgbaAstc8x6Khr || KtxFormat.compRgbaAstc8x8Khr => 8,
    KtxFormat.compRgbaAstc10x5Khr ||
    KtxFormat.compRgbaAstc10x6Khr ||
    KtxFormat.compRgbaAstc10x8Khr ||
    KtxFormat.compRgbaAstc10x10Khr => 10,
    KtxFormat.compRgbaAstc12x10Khr || KtxFormat.compRgbaAstc12x12Khr => 12,
    _ => 4,
  };

  @override
  int get blockHeight => switch (_glInternalFormat) {
    KtxFormat.compRgbaAstc4x4Khr => 4,
    KtxFormat.compRgbaAstc5x4Khr => 4,
    KtxFormat.compRgbaAstc5x5Khr => 5,
    KtxFormat.compRgbaAstc6x5Khr => 5,
    KtxFormat.compRgbaAstc6x6Khr => 6,
    KtxFormat.compRgbaAstc8x5Khr => 5,
    KtxFormat.compRgbaAstc8x6Khr => 6,
    KtxFormat.compRgbaAstc8x8Khr => 8,
    KtxFormat.compRgbaAstc10x5Khr => 5,
    KtxFormat.compRgbaAstc10x6Khr => 6,
    KtxFormat.compRgbaAstc10x8Khr => 8,
    KtxFormat.compRgbaAstc10x10Khr => 10,
    KtxFormat.compRgbaAstc12x10Khr => 10,
    KtxFormat.compRgbaAstc12x12Khr => 12,
    _ => 4,
  };

  @override
  int get blockByteLength => switch (_glInternalFormat) {
    KtxFormat.compRgbaS3tcDxt1Ext ||
    KtxFormat.compRgb8Etc2 ||
    KtxFormat.compRgb8PunchthroughAlpha1Etc2 => 8,
    KtxFormat.compRgbaS3tcDxt3Ext ||
    KtxFormat.compRgbaS3tcDxt5Ext ||
    KtxFormat.compRgba8Etc2Eac ||
    KtxFormat.compRgbaAstc4x4Khr ||
    KtxFormat.compRgbaAstc5x4Khr ||
    KtxFormat.compRgbaAstc5x5Khr ||
    KtxFormat.compRgbaAstc6x5Khr ||
    KtxFormat.compRgbaAstc6x6Khr ||
    KtxFormat.compRgbaAstc8x5Khr ||
    KtxFormat.compRgbaAstc8x6Khr ||
    KtxFormat.compRgbaAstc8x8Khr ||
    KtxFormat.compRgbaAstc10x5Khr ||
    KtxFormat.compRgbaAstc10x6Khr ||
    KtxFormat.compRgbaAstc10x8Khr ||
    KtxFormat.compRgbaAstc10x10Khr ||
    KtxFormat.compRgbaAstc12x10Khr ||
    KtxFormat.compRgbaAstc12x12Khr => 16,
    _ => 16,
  };

  @override
  int get mipLevelCount => _mipLevelCount;

  @override
  ByteData textureDataForMipLevel(int level) {
    if (level < 0 || level >= _mipLevelCount) {
      throw RangeError.range(level, 0, _mipLevelCount - 1, 'level');
    }

    return _buffer.asByteData(_mipOffsets[level], _mipLengths[level]);
  }
}
