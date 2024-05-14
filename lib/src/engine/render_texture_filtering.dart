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

  RenderTextureFiltering(this.value);

  // NOTE(CEksal): These are `static final` because the associated `WebGL` constants are not
  // `const`.
  static final RenderTextureFiltering NEAREST =
      RenderTextureFiltering(WebGL.NEAREST);
  static final RenderTextureFiltering LINEAR =
      RenderTextureFiltering(WebGL.LINEAR);
}
