@TestOn('browser')
library;

import 'package:stagexl/stagexl.dart';
import 'package:test/test.dart';

void main() {
  test('dispose releases each backing texture and clears the frames', () {
    final textureAtlas = TextureAtlas(1);
    final firstBitmapData = BitmapData(8, 8);
    final secondBitmapData = BitmapData(8, 8);

    textureAtlas.frames['first'] = _createFrame(
      textureAtlas,
      firstBitmapData,
      'first',
    );
    textureAtlas.frames['first-alias'] = _createFrame(
      textureAtlas,
      firstBitmapData,
      'first-alias',
    );
    textureAtlas.frames['second'] = _createFrame(
      textureAtlas,
      secondBitmapData,
      'second',
    );

    expect(firstBitmapData.renderTexture.source, isNotNull);
    expect(secondBitmapData.renderTexture.source, isNotNull);

    textureAtlas.dispose();

    expect(textureAtlas.frames, isEmpty);
    expect(firstBitmapData.renderTexture.source, isNull);
    expect(secondBitmapData.renderTexture.source, isNull);
  });

  test('dispose can be called more than once', () {
    final textureAtlas = TextureAtlas(1);
    final bitmapData = BitmapData(8, 8);
    textureAtlas.frames['frame'] = _createFrame(
      textureAtlas,
      bitmapData,
      'frame',
    );

    textureAtlas.dispose();

    expect(textureAtlas.dispose, returnsNormally);
  });
}

TextureAtlasFrame _createFrame(
  TextureAtlas textureAtlas,
  BitmapData bitmapData,
  String name,
) => TextureAtlasFrame(
  textureAtlas,
  bitmapData.renderTextureQuad,
  name,
  0,
  0,
  0,
  bitmapData.width.toInt(),
  bitmapData.height.toInt(),
  0,
  0,
  bitmapData.width.toInt(),
  bitmapData.height.toInt(),
  null,
  null,
);
