part of stagexl.engine;

// https://registry.khronos.org/KTX/specs/1.0/ktxspec.v1.html
class KtxFormat {
  static const ktx_magic = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A];
  static const ktx_end_le = 0x04030201;
  static const ktx_end_be = 0x01020304;
}

class KtxTexture extends CompressedTexture {
  late final int _glInternalFormat;
  late final int _texDataOffset;
  late final int _imageSize;

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
        bytes.endian = Endian.big;
        break;
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

    /*final pixelDepth = */ bytes.readUnsignedInt();
    /*final numberOfArrayElements = */ bytes.readUnsignedInt();
    /*final numberOfFaces = */ bytes.readUnsignedInt();
    /*final numberOfMipmapLevels = */ bytes.readUnsignedInt();

    final bytesOfKeyValueData = bytes.readUnsignedInt();
    /*final keyValueDatas = */ List.generate(bytesOfKeyValueData, (_) => bytes.readByte());

    _imageSize = bytes.readUnsignedInt();
    _texDataOffset = bytes.offset;
  }

  // NOTE(CEksal): glInternalFormat stores the glEnum value of the format
  // being used, so we can just return it.
  @override
  int get format => _glInternalFormat;

  @override
  ByteData get textureData => _buffer.asByteData(_texDataOffset, _imageSize);
}
