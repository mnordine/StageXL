part of stagexl.display;

/// The Bitmap class represents display objects that represent bitmap images.
///
/// The Bitmap constructor allows you to create a Bitmap object that contains a
/// reference to a [BitmapData] object. After you create a Bitmap object, use
/// the addChild() or addChildAt() method of the parent [DisplayObjectContainer]
/// instance to place the bitmap on the display list.
///
/// A Bitmap object can share its [BitmapData] reference among several Bitmap
/// objects, independent of translation or rotation properties. Because you can
/// create multiple Bitmap objects that reference the same [BitmapData] object,
/// multiple display objects can use the same complex [BitmapData] object
/// without incurring the memory overhead of a [BitmapData] object for each
/// display object instance.
///
/// Note: The Bitmap class is not a subclass of the [InteractiveObject] class,
/// so it cannot dispatch mouse or touch events. However, you can listen to
/// input events on the Bitmap's parent display object.

class Bitmap extends DisplayObject {
  /// The BitmapData object being referenced.
  BitmapData? bitmapData;

  Bitmap([this.bitmapData]);

  //---------------------------------------------------------------------------

  @override
  Rectangle<num> get bounds => bitmapData == null
      ? Rectangle<num>(0.0, 0.0, 0.0, 0.0)
      : Rectangle<num>(0.0, 0.0, bitmapData!.width, bitmapData!.height);

  @override
  DisplayObject? hitTestInput(num localX, num localY) {
    // We override the hitTestInput method for optimal performance.
    if (bitmapData == null) return null;
    if (localX < 0.0 || localX >= bitmapData!.width) return null;
    if (localY < 0.0 || localY >= bitmapData!.height) return null;
    return this;
  }

  @override
  void render(RenderState renderState) {
    if (bitmapData != null) bitmapData!.render(renderState);
  }

  @override
  void renderFiltered(RenderState renderState) {
    if (bitmapData != null) {
      final renderTextureQuad = bitmapData!.renderTextureQuad;
      renderState.renderTextureQuadFiltered(renderTextureQuad, filters);
    }
  }
}
