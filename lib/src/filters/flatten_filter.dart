library;

import '../display.dart';
import '../engine.dart';

/// The FlattenFilter does not change the visual appearance of the BitmapData
/// or DisplayObject where it is applied to. This filter can be used to merge
/// the children of a DisplayObjectContainer to a flat texture. This is useful
/// for DisplayObjects with certain blend modes or alpha values.
///
/// Example:
///
///     var sprite = new Sprite();
///     sprite.addChild(background);
///     sprite.addChild(foreground);
///     sprite.addChild(text);
///     sprite.blendMode = BlendMode.ADD;
///     sprite.filters = [FlattenFilter()];

class FlattenFilter extends BitmapFilter {
  static final _programs = RenderProgramSet<void>(
    webGL: RenderProgramWebGL.callback(_render),
    webGPU: RenderProgramWebGPU.callback(_render),
  );

  static void _render(RenderFilterContext context, void _) {
    context.renderState.renderTextureQuad(context.renderTextureQuad);
  }

  @override
  BitmapFilter clone() => FlattenFilter();

  @override
  RenderProgramSet<void> get renderPrograms => _programs;

  @override
  void renderFilter(RenderFilterContext context) => context.render(_programs, null);
}
