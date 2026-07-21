part of '../display.dart';

abstract class BitmapDrawable implements LegacyRenderObject {
  void collectRenderables(RenderBuildContext context);

  @override
  @Deprecated('Use collectRenderables(RenderBuildContext).')
  void renderLegacy(RenderState renderState);
}
