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
  RGB_2BPP,
  RGBA_2BPP,
  RGB_4BPP,
  RGBA_4BPP
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

    _texDataOffset = bytes.offset + metaDataSize;
  }

  int get format
  {
    switch (_pvrFormat)
    {
      case PvrFormat.RGB_2BPP:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_2BPPV1_IMG;
      case PvrFormat.RGB_4BPP:  return gl.CompressedTexturePvrtc.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;
      case PvrFormat.RGBA_2BPP: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_2BPPV1_IMG;
      case PvrFormat.RGBA_4BPP: return gl.CompressedTexturePvrtc.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;
    }

    return -1;
  }

  TypedData get textureData => _buffer.asByteData(_texDataOffset);
}