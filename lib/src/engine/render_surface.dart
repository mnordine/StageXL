part of '../engine.dart';

/// A rendering surface supported by StageXL.
///
/// Both an `HTMLCanvasElement` and an `OffscreenCanvas` implement this API.
/// Keeping the renderer expressed in terms of this small surface contract
/// prevents the WebGL and WebGPU backends from depending on the DOM.
extension type RenderSurface(JSObject _) implements JSObject {
  external int get width;
  external set width(int value);

  external int get height;
  external set height(int value);

  external JSAny? getContext(String contextId, [JSAny? options]);

  external void addEventListener(String type, JSFunction listener);
}

RenderSurface renderSurfaceFrom(JSObject canvas) => RenderSurface(canvas);

bool get isDocumentAvailable => _globalScope.has('document');

RenderSurface createRenderSurface(int width, int height) {
  final JSObject canvas;
  if (isDocumentAvailable) {
    canvas = HTMLCanvasElement();
  } else {
    canvas = OffscreenCanvas(width, height);
  }
  return RenderSurface(canvas)
    ..width = width
    ..height = height;
}

CanvasRenderingContext2D renderSurfaceContext2D(RenderSurface surface) =>
    surface.getContext('2d') as CanvasRenderingContext2D;
