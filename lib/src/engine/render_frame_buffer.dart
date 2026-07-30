part of '../engine.dart';

class RenderFrameBuffer {
  RenderTexture? _renderTexture;
  RenderStencilBuffer? _renderStencilBuffer;
  late RenderContextWebGL _renderContext;

  var _contextIdentifier = -1;
  WebGLFramebuffer? _framebuffer;
  WebGL? _renderingContext;

  final _maskStates = <_MaskState>[];
  var _framebufferAllocated = false;

  RenderFrameBuffer.rawWebGL(int width, int height) {
    _renderTexture = .rawWebGL(width, height);
    _renderStencilBuffer = .rawWebGL(width, height);
  }

  //---------------------------------------------------------------------------

  int? get width => _renderTexture?.width;

  int? get height => _renderTexture?.height;

  int get contextIdentifier => _contextIdentifier;

  RenderTexture? get renderTexture => _renderTexture;

  RenderStencilBuffer? get renderStencilBuffer => _renderStencilBuffer;

  //---------------------------------------------------------------------------

  /// Call the dispose method to release memory allocated by WebGL.

  void dispose() {
    _renderTexture?.dispose();
    _renderStencilBuffer?.dispose();
    _releaseWebGLFramebuffer(delete: true);
    _renderTexture = null;
    _renderStencilBuffer = null;
  }

  void _releaseWebGLFramebuffer({required bool delete}) {
    if (delete && _framebuffer != null) {
      _renderingContext?.deleteFramebuffer(_framebuffer);
    }
    if (_framebufferAllocated) {
      ResourceDiagnostics.unregister(.webglFramebuffer);
      _framebufferAllocated = false;
    }
    _contextIdentifier = -1;
    _framebuffer = null;
  }

  //---------------------------------------------------------------------------

  void activate(RenderContextWebGL renderContext) {
    if (contextIdentifier != renderContext.contextIdentifier) {
      _renderContext = renderContext;
      _contextIdentifier = renderContext.contextIdentifier;
      _renderingContext = renderContext.rawContext;
      _framebuffer = renderContext.rawContext.createFramebuffer();
      if (_framebuffer != null) {
        ResourceDiagnostics.register(.webglFramebuffer);
        _framebufferAllocated = true;
      }

      if (_renderTexture != null) {
        _renderContext.activateRenderTexture(_renderTexture!);
      }

      if (_renderStencilBuffer != null) {
        _renderContext.activateRenderStencilBuffer(_renderStencilBuffer!);
      }

      const target = WebGL.FRAMEBUFFER;
      const color = WebGL.COLOR_ATTACHMENT0;
      const colorTarget = WebGL.TEXTURE_2D;
      final colorData = _renderTexture!.texture;
      const stencil = WebGL.DEPTH_STENCIL_ATTACHMENT;
      const stencilTarget = WebGL.RENDERBUFFER;
      final stencilData = _renderStencilBuffer!.renderbuffer;

      _renderingContext!.bindFramebuffer(target, _framebuffer);
      _renderingContext!
          .framebufferTexture2D(target, color, colorTarget, colorData, 0);
      _renderingContext!
          .framebufferRenderbuffer(target, stencil, stencilTarget, stencilData);
    } else {
      _renderingContext!.bindFramebuffer(WebGL.FRAMEBUFFER, _framebuffer);
    }
  }
}
