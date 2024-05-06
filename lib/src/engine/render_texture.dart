part of stagexl.engine;

class RenderTexture {
  int _width = 0;
  int _height = 0;

  CanvasImageSource? _source;
  HTMLCanvasElement? _canvas;
  RenderTextureFiltering _filtering = RenderTextureFiltering.LINEAR;
  RenderTextureWrapping _wrappingX = RenderTextureWrapping.CLAMP;
  RenderTextureWrapping _wrappingY = RenderTextureWrapping.CLAMP;
  RenderContextWebGL? _renderContext;

  int _contextIdentifier = -1;

  CompressedTexture? _compressedTexture;
  WebGL? _renderingContext;
  WebGLTexture? _texture;

  int _pixelFormat = WebGL.RGBA;
  int _pixelType = WebGL.UNSIGNED_BYTE;

  //-----------------------------------------------------------------------------------------------

  RenderTexture(int width, int height, int fillColor) {
    if (width <= 0) throw ArgumentError('width');
    if (height <= 0) throw ArgumentError('height');

    _width = width;
    _height = height;
    _source = _canvas = HTMLCanvasElement()
      ..width = _width
      ..height = _height;

    if (fillColor != 0) {
      final context = _canvas!.context2D;
      context.fillStyle = color2rgba(fillColor).toJS;
      context.fillRect(0, 0, _width, _height);
    }
  }

  RenderTexture.fromImageElement(HTMLImageElement imageElement) {
    _width = imageElement.width;
    _height = imageElement.height;
    _source = imageElement;
  }

  RenderTexture.fromImageBitmap(ImageBitmap image) {
    _width = image.width;
    _height = image.height;
    _source = image;
  }

  RenderTexture.fromCanvasElement(HTMLCanvasElement canvasElement) {
    _width = canvasElement.width;
    _height = canvasElement.height;
    _source = _canvas = canvasElement;
  }

  RenderTexture.fromVideoElement(HTMLVideoElement videoElement) {
    if (videoElement.readyState < 3) throw ArgumentError('videoElement');
    _width = videoElement.videoWidth;
    _height = videoElement.videoHeight;
    _source = videoElement;
    _globalFrameListeners.insert(0, _onGlobalFrame);
  }

  RenderTexture.rawWebGL(int width, int height)
      : _width = width,
        _height = height;

  RenderTexture.fromCompressedTexture(CompressedTexture texture) {
    _width = texture.width;
    _height = texture.height;

    _compressedTexture = texture;
  }

  //-----------------------------------------------------------------------------------------------

  int get width => _width;
  int get height => _height;

  CanvasImageSource? get source => _source;

  ImageBitmap? get imageBitmap => _source.isA<ImageBitmap>() ? _source as ImageBitmap : null;

  RenderTextureQuad get quad => RenderTextureQuad(
      this,
      Rectangle<int>(0, 0, _width, _height),
      Rectangle<int>(0, 0, _width, _height),
      0,
      1.0);

  HTMLCanvasElement get canvas {
    if (_source.isA<HTMLCanvasElement>()) {
      return _source as HTMLCanvasElement;
    } else if (_source.isA<HTMLImageElement>()) {
      final imageElement = _source as HTMLImageElement;
      _source = _canvas = HTMLCanvasElement()
        ..width = _width
        ..height = _height;
      
      _canvas!.context2D.drawImageScaled(imageElement, 0, 0, _width.toDouble(), _height.toDouble());
      return _canvas!;
    } else if (_source.isA<ImageBitmap>()) {
      final image = _source as ImageBitmap;
      _source = _canvas = HTMLCanvasElement()
        ..width = _width
        ..height = _height;

      // Note: We need to use js_util.callMethod, because Dart SDK
      // does not support ImageBitmap as a CanvasImageSource
      _canvas!.context2D.drawImage(
        image,
        0,
        0,
        _width,
        _height,
      );

      return _canvas!;
    } else {
      throw StateError('RenderTexture is read only.');
    }
  }

  WebGLTexture? get texture => _texture;
  int get contextIdentifier => _contextIdentifier;

  //-----------------------------------------------------------------------------------------------

  /// Get or set the filtering used for this RenderTexture.
  ///
  /// The default is [RenderTextureFiltering.LINEAR] which is fine
  /// for most use cases. In games with 2D pixel art it is sometimes better
  /// to use the [RenderTextureFiltering.NEAREST] filtering.

  RenderTextureFiltering get filtering => _filtering;

  set filtering(RenderTextureFiltering filtering) {
    if (_filtering == filtering) return;
    _filtering = filtering;

    if (_renderContext == null || _texture == null) return;
    if (_renderContext!.contextIdentifier != contextIdentifier) return;

    _renderContext!.activateRenderTexture(this);
    _renderingContext!.texParameteri(
        WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, _filtering.value);
    _renderingContext!.texParameteri(
        WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, _filtering.value);
  }

  //-----------------------------------------------------------------------------------------------

  RenderTextureWrapping get wrappingX => _wrappingX;

  set wrappingX(RenderTextureWrapping wrapping) {
    if (_wrappingX == wrapping) return;
    _wrappingX = wrapping;

    if (_renderContext == null || _texture == null) return;
    if (_renderContext!.contextIdentifier != contextIdentifier) return;

    _renderContext!.activateRenderTexture(this);
    _renderingContext!.texParameteri(
        WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, _wrappingX.value);
  }

  //-----------------------------------------------------------------------------------------------

  RenderTextureWrapping get wrappingY => _wrappingY;

  set wrappingY(RenderTextureWrapping wrapping) {
    if (_wrappingY == wrapping) return;
    _wrappingY = wrapping;

    if (_renderContext == null || _texture == null) return;
    if (_renderContext!.contextIdentifier != contextIdentifier) return;

    _renderContext!.activateRenderTexture(this);
    _renderingContext!.texParameteri(
        WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, _wrappingY.value);
  }

  int get pixelFormat => _pixelFormat;

  set pixelFormat(int value) {
    if (pixelFormat == value) return;

    _pixelFormat = value;
    update();
  }

  int get pixelType => _pixelType;

  set pixelType(int value) {
    if (pixelType == value) return;

    _pixelType = value;
    update();
  }

  //-----------------------------------------------------------------------------------------------

  /// Call the dispose method to release memory allocated by WebGL.

  void dispose() {
    if (_texture != null) {
      _renderingContext?.deleteTexture(_texture);
    }

    if (_source is ImageBitmap) {
      try {
        (_source as ImageBitmap).close();
      } catch (_) {
        // Some browsers don't support ImageBitmap.close(). Ignore.
      }
    }

    _texture = null;
    _compressedTexture = null;
    _source = null;
    _canvas = null;
    _renderingContext = null;
    _contextIdentifier = -1;
    _globalFrameListeners.remove(_onGlobalFrame);
  }

  //-----------------------------------------------------------------------------------------------

  void resize(int width, int height) {
    if (_source.isA<HTMLVideoElement>()) {
      throw StateError('RenderTexture is not resizeable.');
    } else if (_width == width && _height == height) {
      // there is no need to resize the texture

    } else if (_source == null) {
      _width = width;
      _height = height;

      if (_renderContext == null || _texture == null) return;
      if (_renderContext!.contextIdentifier != contextIdentifier) return;

      _renderContext!.activateRenderTexture(this);
      _updateTexture(_renderContext!);
    } else {
      _width = width;
      _height = height;
      _source = _canvas = HTMLCanvasElement()
        ..width = _width
        ..height = _height;
    }
  }

  //-----------------------------------------------------------------------------------------------

  /// Update the underlying WebGL texture with the source of this RenderTexture.
  ///
  /// The source of the RenderTexture is an ImageElement, HTMLCanvasElement or
  /// VideoElement. If changes are made to the source you have to call the
  /// [update] method to apply those changes to the WebGL texture.
  ///
  /// The progress in a VideoElement will automatically updated the
  /// RenderTexture and you don't need to call the [update] method.

  void update() {
    if (_renderContext == null || _texture == null) return;
    if (_renderContext!.contextIdentifier != contextIdentifier) return;

    _renderContext!.flush();
    _renderContext!.activateRenderTexture(this);

    final scissors = _renderingContext!.isEnabled(WebGL.SCISSOR_TEST);
    if (scissors) _renderingContext!.disable(WebGL.SCISSOR_TEST);

    _updateTexture(_renderContext!);

    if (scissors) _renderingContext!.enable(WebGL.SCISSOR_TEST);
  }

  void _updateTexture(RenderContextWebGL renderContext) {
    final renderingContext = renderContext.rawContext;

    final target = WebGL.TEXTURE_2D;

    if (_source != null) {
      renderingContext.texImage2D(target, 0, pixelFormat, pixelFormat.toJS, pixelType.toJS, _source!);
    } else if (_compressedTexture != null) {
      final tex = _compressedTexture!;
      renderingContext.compressedTexImage2D(target, 0, tex.format, tex.width, tex.height, 0, tex.textureData.toJS);
    } else {
      // ignore: avoid_redundant_argument_values
      renderingContext.texImage2D(target, 0, pixelFormat, width.toJS, height.toJS, 0.toJS, pixelFormat, pixelType, null);
    }
  }

  //-----------------------------------------------------------------------------------------------

  void activate(RenderContextWebGL renderContext, int textureSlot) {
    if (contextIdentifier != renderContext.contextIdentifier) {
      _renderContext = renderContext;
      _contextIdentifier = renderContext.contextIdentifier;
      final renderingContext = _renderingContext = renderContext.rawContext;
      _texture = renderingContext.createTexture();

      final target = WebGL.TEXTURE_2D;

      renderingContext.activeTexture(textureSlot);
      renderingContext.bindTexture(target, _texture);

      final scissors = renderingContext.isEnabled(WebGL.SCISSOR_TEST);
      if (scissors) renderingContext.disable(WebGL.SCISSOR_TEST);

      _updateTexture(renderContext);

      if (scissors) renderingContext.enable(WebGL.SCISSOR_TEST);

      renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_S, _wrappingX.value);
      renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_WRAP_T, _wrappingY.value);
      renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, _filtering.value);
      renderingContext.texParameteri(
          WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, _filtering.value);
    } else {
      _renderingContext!.activeTexture(textureSlot);
      _renderingContext!.bindTexture(WebGL.TEXTURE_2D, _texture);
    }
  }

  //-----------------------------------------------------------------------------------------------

  num _videoUpdateTime = -1.0;

  void _onGlobalFrame(num deltaTime) {
    if (source.isA<HTMLVideoElement>()) {
      final videoElement = source as HTMLVideoElement;
      final currentTime = videoElement.currentTime;
      if (_videoUpdateTime != currentTime) {
        _videoUpdateTime = currentTime;
        update();
      }
    }
  }
}
