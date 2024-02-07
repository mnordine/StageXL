// ignore_for_file: non_constant_identifier_names

part of stagexl.engine;

/// The RenderTextureFiltering defines the method that is used to determine
/// the texture color for a texture mapped pixel, using the colors of nearby
/// texels (pixels of the texture).
///
/// See also: [RenderTexture.filtering]
///
class RenderTextureFiltering {
  final int value;

  const RenderTextureFiltering(this.value);

  static final RenderTextureFiltering NEAREST =
      RenderTextureFiltering(WebGL.NEAREST);
  static final RenderTextureFiltering LINEAR =
      RenderTextureFiltering(WebGL.LINEAR);
}
