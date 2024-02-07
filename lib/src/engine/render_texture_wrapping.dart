// ignore_for_file: non_constant_identifier_names

part of stagexl.engine;

class RenderTextureWrapping {
  final int value;

  const RenderTextureWrapping(this.value);

  static final RenderTextureWrapping REPEAT =
      RenderTextureWrapping(WebGL.REPEAT);
  static final RenderTextureWrapping CLAMP =
      RenderTextureWrapping(WebGL.CLAMP_TO_EDGE);
}
