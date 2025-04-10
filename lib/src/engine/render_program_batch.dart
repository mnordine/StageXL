part of '../engine.dart';

class RenderProgramBatch extends RenderProgram {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexColor:      Float32(r), Float32(g), Float32(b), Float32(a)
  // aVertexTexIndex:   Float32(textureIndex)

  static const int _maxTextures = 8; // Most WebGL implementations support at least 8 texture units

  final List<RenderTexture?> _textures = List.filled(_maxTextures, null);

  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;

    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;
    in vec4 aVertexColor;
    in float aVertexTexIndex;

    out vec2 vTextCoord;
    out vec4 vColor;
    out float vTexIndex;

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      vTexIndex = aVertexTexIndex;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    attribute vec2 aVertexPosition;
    attribute vec2 aVertexTextCoord;
    attribute vec4 aVertexColor;
    attribute float aVertexTexIndex;
    varying vec2 vTextCoord;
    varying vec4 vColor;
    varying float vTexIndex;

    void main() {
      vTextCoord = aVertexTextCoord;
      vColor = aVertexColor;
      vTexIndex = aVertexTexIndex;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  @override
  String get fragmentShaderSource {
    if (isWebGL2) {
      // For WebGL2, use individual samplers for clarity and compatibility
      // Use simple integer equality to select texture sampler
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        sb.write('''
        if (int(vTexIndex+0.1) == $i) {
          fragColor = texture(uSampler$i, vTextCoord) * vColor;
        }''');
      }
      // We still need a fallback case, but now just use transparent black
      sb.write('''
        else {
          fragColor = vec4(0.0, 0.0, 0.0, 0.0);
        }''');
      
      final ifStatements = sb.toString();
      
      // Generate uniform sampler declarations for WebGL 2
      final samplerDeclarations = List.generate(_maxTextures, 
          (i) => 'uniform sampler2D uSampler$i;').join('\n');
          
      return '''
      #version 300 es

      precision ${RenderProgram.fragmentPrecision} float;

      $samplerDeclarations

      in vec2 vTextCoord;
      in vec4 vColor;
      in float vTexIndex;

      out vec4 fragColor;

      void main() {
        $ifStatements
      }
      ''';
    } else {
      // WebGL 1 doesn't support array indexing with dynamic values,
      // so we need to use conditionals
      final samplerDeclarations = List.generate(_maxTextures, (i) => 'uniform sampler2D uSampler$i;').join('\n');

      // Use simple integer equality to select texture sampler
      final StringBuffer sb = StringBuffer();
      for (int i = 0; i < _maxTextures; i++) {
        if (i > 0) sb.write('else ');
        sb.write('''
        if (int(vTexIndex+0.1) == $i) {
          gl_FragColor = texture2D(uSampler$i, vTextCoord) * vColor;
        }''');
      }
      // We still need a fallback case, but now just use transparent black
      sb.write('''
        else {
          gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        }''');
      
      final ifStatements = sb.toString();

      return '''
      precision ${RenderProgram.fragmentPrecision} float;
      $samplerDeclarations
      varying vec2 vTextCoord;
      varying vec4 vColor;
      varying float vTexIndex;

      void main() {
        $ifStatements
      }
      ''';
    }
  }

  //---------------------------------------------------------------------------

  @override
  void activate(RenderContextWebGL renderContext) {
    super.activate(renderContext);

    if (isWebGL2) {
      // In WebGL 2, use individual samplers for clarity and compatibility
      for (var i = 0; i < _maxTextures; i++) {
        final uniformName = 'uSampler$i';
        if (uniforms.containsKey(uniformName)) {
          renderingContext.uniform1i(uniforms[uniformName], i);
        }
      }
    } else {
      // In WebGL 1, we need to set each sampler separately
      for (var i = 0; i < _maxTextures; i++) {
        renderingContext.uniform1i(uniforms['uSampler$i'], i);
      }
    }

    _clearTextures();
  }

  @override
  void setupAttributes() {
    // Position (x,y), TexCoord (u,v), Color (r,g,b,a), TexIndex
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, 36, 0);
    renderBufferVertex.bindAttribute(attributes['aVertexTextCoord'], 2, 36, 8);
    renderBufferVertex.bindAttribute(attributes['aVertexColor'], 4, 36, 16);
    renderBufferVertex.bindAttribute(attributes['aVertexTexIndex'], 1, 36, 32);
  }

  //---------------------------------------------------------------------------

  void _clearTextures() {
    for (var i = 0; i < _maxTextures; i++) {
      _textures[i] = null;
    }
  }

  @override
  void flush() {
    super.flush();
    _clearTextures();
  }

  //---------------------------------------------------------------------------

  /// Checks if the given texture is already in a slot or if there's an empty slot.
  /// Returns the texture index if available, or -1 if no slots are available.
  int _getTextureIndexIfAvailable(RenderTexture texture) {
    // First check if the texture is already bound
    for (var i = 0; i < _maxTextures; i++) {
      if (identical(_textures[i], texture)) {
        return i;
      }
    }

    // Find an empty slot
    for (var i = 0; i < _maxTextures; i++) {
      if (_textures[i] == null) {
        return i;
      }
    }

    // No slots available
    return -1;
  }
  
  /// Binds a texture directly to a texture slot without triggering a flush.
  void _bindTextureToSlot(RenderContextWebGL renderContext, RenderTexture texture, int index) {
    _textures[index] = texture;
    
    // Directly activate the texture without going through renderContext.activateRenderTextureAt
    // which would trigger a flush
    texture.activate(renderContext, WebGL.TEXTURE0 + index);
  }

  //---------------------------------------------------------------------------

  void renderTextureQuad(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTextureQuad renderTextureQuad) {

    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, renderContext,
          renderTextureQuad.renderTexture, ixList, vxList, 1, 1, 1, 1);
      return;
    }

    final texture = renderTextureQuad.renderTexture;
    
    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(texture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush();
      textureIndex = 0; // After flushing, slot 0 is guaranteed to be available
    }
    
    // Now we can bind the texture to a slot
    if (_textures[textureIndex] == null) {
      _bindTextureToSlot(renderContext, texture, textureIndex);
    }
    
    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 9 >= vxData.length) flush();

    final ixIndex = renderBufferIndex.position;
    final vxIndex = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // copy index list
    ixData[ixIndex + 0] = vxCount + 0;
    ixData[ixIndex + 1] = vxCount + 1;
    ixData[ixIndex + 2] = vxCount + 2;
    ixData[ixIndex + 3] = vxCount + 0;
    ixData[ixIndex + 4] = vxCount + 2;
    ixData[ixIndex + 5] = vxCount + 3;

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list
    final ma1 = vxList[0] * matrix.a + matrix.tx;
    final ma2 = vxList[8] * matrix.a + matrix.tx;
    final mb1 = vxList[0] * matrix.b + matrix.ty;
    final mb2 = vxList[8] * matrix.b + matrix.ty;
    final mc1 = vxList[1] * matrix.c;
    final mc2 = vxList[9] * matrix.c;
    final md1 = vxList[1] * matrix.d;
    final md2 = vxList[9] * matrix.d;


    // Vertex 0
    vxData[vxIndex + 00] = ma1 + mc1;                       // x
    vxData[vxIndex + 01] = mb1 + md1;                       // y
    vxData[vxIndex + 02] = vxList[2];                       // u
    vxData[vxIndex + 03] = vxList[3];                       // v
    vxData[vxIndex + 04] = 1.0;                             // r
    vxData[vxIndex + 05] = 1.0;                             // g
    vxData[vxIndex + 06] = 1.0;                             // b
    vxData[vxIndex + 07] = alpha;                           // a
    vxData[vxIndex + 08] = textureIndex.toDouble();         // texture index

    // Vertex 1
    vxData[vxIndex + 09] = ma2 + mc1;                       // x
    vxData[vxIndex + 10] = mb2 + md1;                       // y
    vxData[vxIndex + 11] = vxList[6];                       // u
    vxData[vxIndex + 12] = vxList[7];                       // v
    vxData[vxIndex + 13] = 1.0;                             // r
    vxData[vxIndex + 14] = 1.0;                             // g
    vxData[vxIndex + 15] = 1.0;                             // b
    vxData[vxIndex + 16] = alpha;                           // a
    vxData[vxIndex + 17] = textureIndex.toDouble();         // texture index

    // Vertex 2
    vxData[vxIndex + 18] = ma2 + mc2;                       // x
    vxData[vxIndex + 19] = mb2 + md2;                       // y
    vxData[vxIndex + 20] = vxList[10];                      // u
    vxData[vxIndex + 21] = vxList[11];                      // v
    vxData[vxIndex + 22] = 1.0;                             // r
    vxData[vxIndex + 23] = 1.0;                             // g
    vxData[vxIndex + 24] = 1.0;                             // b
    vxData[vxIndex + 25] = alpha;                           // a
    vxData[vxIndex + 26] = textureIndex.toDouble();         // texture index

    // Vertex 3
    vxData[vxIndex + 27] = ma1 + mc2;                       // x
    vxData[vxIndex + 28] = mb1 + md2;                       // y
    vxData[vxIndex + 29] = vxList[14];                      // u
    vxData[vxIndex + 30] = vxList[15];                      // v
    vxData[vxIndex + 31] = 1.0;                             // r
    vxData[vxIndex + 32] = 1.0;                             // g
    vxData[vxIndex + 33] = 1.0;                             // b
    vxData[vxIndex + 34] = alpha;                           // a
    vxData[vxIndex + 35] = textureIndex.toDouble();         // texture index

    renderBufferVertex.position += vxListCount * 9;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTexture renderTexture, Int16List ixList, Float32List vxList,
      num r, num g, num b, num a) {

    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(renderTexture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush();
      textureIndex = 0; // After flushing, slot 0 is guaranteed to be available
    }
    
    // Now we can bind the texture to a slot
    if (_textures[textureIndex] == null) {
      _bindTextureToSlot(renderContext, renderTexture, textureIndex);
    }
    final matrix = renderState.globalMatrix;
    final alpha = renderState.globalAlpha;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2;

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 9 >= vxData.length) flush();

    final ixIndex = renderBufferIndex.position;
    var vxIndex = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // copy index list
    for (var i = 0; i < ixListCount; i++) {
      ixData[ixIndex + i] = vxCount + ixList[i];
    }

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list
    final ma = matrix.a;
    final mb = matrix.b;
    final mc = matrix.c;
    final md = matrix.d;
    final mx = matrix.tx;
    final my = matrix.ty;

    final colorA = a * alpha;
    final colorR = r.toDouble();
    final colorG = g.toDouble();
    final colorB = b.toDouble();
    final texIdx = textureIndex.toDouble();

    for (var i = 0, o = 0; i < vxListCount; i++, o += 4) {
      final x = vxList[o + 0];
      final y = vxList[o + 1];
      vxData[vxIndex + 0] = mx + ma * x + mc * y;        // x
      vxData[vxIndex + 1] = my + mb * x + md * y;        // y
      vxData[vxIndex + 2] = vxList[o + 2];               // u
      vxData[vxIndex + 3] = vxList[o + 3];               // v
      vxData[vxIndex + 4] = colorR;                      // r
      vxData[vxIndex + 5] = colorG;                      // g
      vxData[vxIndex + 6] = colorB;                      // b
      vxData[vxIndex + 7] = colorA;                      // a
      vxData[vxIndex + 8] = texIdx;                      // texture index
      vxIndex += 9;
    }

    renderBufferVertex.position += vxListCount * 9;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  /// Render a quad with a color tint
  void renderTextureQuadTinted(
      RenderState renderState, RenderContextWebGL renderContext,
      RenderTextureQuad renderTextureQuad, num r, num g, num b, num a) {

    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, renderContext,
          renderTextureQuad.renderTexture, ixList, vxList, r, g, b, a);
      return;
    }

    final texture = renderTextureQuad.renderTexture;
    
    // Check if this texture will fit in the current batch
    var textureIndex = _getTextureIndexIfAvailable(texture);
    
    // If no slot is available, flush the batch and try again
    if (textureIndex < 0) {
      flush();
      textureIndex = 0; // After flushing, slot 0 is guaranteed to be available
    }
    
    // Now we can bind the texture to a slot
    if (_textures[textureIndex] == null) {
      _bindTextureToSlot(renderContext, texture, textureIndex);
    }
    
    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final vxList = renderTextureQuad.vxListQuad;
    const ixListCount = 6;
    const vxListCount = 4;

    // check buffer sizes and flush if necessary
    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 9 >= vxData.length) flush();

    final ixIndex = renderBufferIndex.position;
    final vxIndex = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    // copy index list
    ixData[ixIndex + 0] = vxCount + 0;
    ixData[ixIndex + 1] = vxCount + 1;
    ixData[ixIndex + 2] = vxCount + 2;
    ixData[ixIndex + 3] = vxCount + 0;
    ixData[ixIndex + 4] = vxCount + 2;
    ixData[ixIndex + 5] = vxCount + 3;

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list
    final ma1 = vxList[0] * matrix.a + matrix.tx;
    final ma2 = vxList[8] * matrix.a + matrix.tx;
    final mb1 = vxList[0] * matrix.b + matrix.ty;
    final mb2 = vxList[8] * matrix.b + matrix.ty;
    final mc1 = vxList[1] * matrix.c;
    final mc2 = vxList[9] * matrix.c;
    final md1 = vxList[1] * matrix.d;
    final md2 = vxList[9] * matrix.d;

    final colorA = a * alpha;
    final colorR = r.toDouble();
    final colorG = g.toDouble();
    final colorB = b.toDouble();
    final texIdx = textureIndex.toDouble();

    // Vertex 0
    vxData[vxIndex + 00] = ma1 + mc1;                       // x
    vxData[vxIndex + 01] = mb1 + md1;                       // y
    vxData[vxIndex + 02] = vxList[2];                       // u
    vxData[vxIndex + 03] = vxList[3];                       // v
    vxData[vxIndex + 04] = colorR;                          // r
    vxData[vxIndex + 05] = colorG;                          // g
    vxData[vxIndex + 06] = colorB;                          // b
    vxData[vxIndex + 07] = colorA;                          // a
    vxData[vxIndex + 08] = texIdx;                          // texture index

    // Vertex 1
    vxData[vxIndex + 09] = ma2 + mc1;                       // x
    vxData[vxIndex + 10] = mb2 + md1;                       // y
    vxData[vxIndex + 11] = vxList[6];                       // u
    vxData[vxIndex + 12] = vxList[7];                       // v
    vxData[vxIndex + 13] = colorR;                          // r
    vxData[vxIndex + 14] = colorG;                          // g
    vxData[vxIndex + 15] = colorB;                          // b
    vxData[vxIndex + 16] = colorA;                          // a
    vxData[vxIndex + 17] = texIdx;                          // texture index

    // Vertex 2
    vxData[vxIndex + 18] = ma2 + mc2;                       // x
    vxData[vxIndex + 19] = mb2 + md2;                       // y
    vxData[vxIndex + 20] = vxList[10];                      // u
    vxData[vxIndex + 21] = vxList[11];                      // v
    vxData[vxIndex + 22] = colorR;                          // r
    vxData[vxIndex + 23] = colorG;                          // g
    vxData[vxIndex + 24] = colorB;                          // b
    vxData[vxIndex + 25] = colorA;                          // a
    vxData[vxIndex + 26] = texIdx;                          // texture index

    // Vertex 3
    vxData[vxIndex + 27] = ma1 + mc2;                       // x
    vxData[vxIndex + 28] = mb1 + md2;                       // y
    vxData[vxIndex + 29] = vxList[14];                      // u
    vxData[vxIndex + 30] = vxList[15];                      // v
    vxData[vxIndex + 31] = colorR;                          // r
    vxData[vxIndex + 32] = colorG;                          // g
    vxData[vxIndex + 33] = colorB;                          // b
    vxData[vxIndex + 34] = colorA;                          // a
    vxData[vxIndex + 35] = texIdx;                          // texture index

    renderBufferVertex.position += vxListCount * 9;
    renderBufferVertex.count += vxListCount;
  }
}
