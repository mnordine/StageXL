part of '../engine.dart';

class RenderProgramSimple extends RenderProgram {
  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexTextCoord:  Float32(u), Float32(v)
  // aVertexAlpha:      Float32(alpha)

  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;
    in vec2 aVertexPosition;
    in vec2 aVertexTextCoord;
    in float aVertexAlpha;

    out vec2 vTextCoord;
    out float vAlpha;

    void main() {
      vTextCoord = aVertexTextCoord;
      vAlpha = aVertexAlpha;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    attribute vec2 aVertexPosition;
    attribute vec2 aVertexTextCoord;
    attribute float aVertexAlpha;
    varying vec2 vTextCoord;
    varying float vAlpha;

    void main() {
      vTextCoord = aVertexTextCoord;
      vAlpha = aVertexAlpha;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  @override
  String get fragmentShaderSource => isWebGL2 ? '''
    #version 300 es

    precision ${RenderProgram.fragmentPrecision} float;
    uniform sampler2D uSampler;

    in vec2 vTextCoord;
    in float vAlpha;

    out vec4 fragColor;

    void main() {
      fragColor = texture(uSampler, vTextCoord) * vAlpha;
    }
    ''' : '''

    precision ${RenderProgram.fragmentPrecision} float;
    uniform sampler2D uSampler;
    varying vec2 vTextCoord;
    varying float vAlpha;

    void main() {
      gl_FragColor = texture2D(uSampler, vTextCoord) * vAlpha;
    }
    ''';

  //---------------------------------------------------------------------------

  @override
  void activate(RenderContextWebGL renderContext) {
    super.activate(renderContext);

    renderingContext.uniform1i(uniforms['uSampler'], 0);
  }

  @override
  void setupAttributes() {
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, 20, 0);
    renderBufferVertex.bindAttribute(attributes['aVertexTextCoord'], 2, 20, 8);
    renderBufferVertex.bindAttribute(attributes['aVertexAlpha'], 1, 20, 16);
  }

  //---------------------------------------------------------------------------

  void renderTextureQuad(
      RenderState renderState, RenderTextureQuad renderTextureQuad) {
    if (renderTextureQuad.hasCustomVertices) {
      final ixList = renderTextureQuad.ixList;
      final vxList = renderTextureQuad.vxList;
      renderTextureMesh(renderState, ixList, vxList);
      return;
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
    if (vxPosition + vxListCount * 5 >= vxData.length) flush();

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

    vxData[vxIndex + 00] = ma1 + mc1;
    vxData[vxIndex + 01] = mb1 + md1;
    vxData[vxIndex + 02] = vxList[2];
    vxData[vxIndex + 03] = vxList[3];
    vxData[vxIndex + 04] = alpha;

    vxData[vxIndex + 05] = ma2 + mc1;
    vxData[vxIndex + 06] = mb2 + md1;
    vxData[vxIndex + 07] = vxList[6];
    vxData[vxIndex + 08] = vxList[7];
    vxData[vxIndex + 09] = alpha;

    vxData[vxIndex + 10] = ma2 + mc2;
    vxData[vxIndex + 11] = mb2 + md2;
    vxData[vxIndex + 12] = vxList[10];
    vxData[vxIndex + 13] = vxList[11];
    vxData[vxIndex + 14] = alpha;

    vxData[vxIndex + 15] = ma1 + mc2;
    vxData[vxIndex + 16] = mb1 + md2;
    vxData[vxIndex + 17] = vxList[14];
    vxData[vxIndex + 18] = vxList[15];
    vxData[vxIndex + 19] = alpha;

    renderBufferVertex.position += vxListCount * 5;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMesh(
      RenderState renderState, Int16List ixList, Float32List vxList) {
    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 2;

    // check buffer sizes and flush if necessary

    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 5 >= vxData.length) flush();

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

    for (var i = 0, o = 0; i < vxListCount; i++, o += 4) {
      final x = vxList[o + 0];
      final y = vxList[o + 1];
      vxData[vxIndex + 0] = mx + ma * x + mc * y;
      vxData[vxIndex + 1] = my + mb * x + md * y;
      vxData[vxIndex + 2] = vxList[o + 2];
      vxData[vxIndex + 3] = vxList[o + 3];
      vxData[vxIndex + 4] = alpha;
      vxIndex += 5;
    }

    renderBufferVertex.position += vxListCount * 5;
    renderBufferVertex.count += vxListCount;
  }

  //---------------------------------------------------------------------------

  void renderTextureMapping(RenderState renderState, Matrix mappingMatrix,
      Int16List ixList, Float32List vxList) {
    final alpha = renderState.globalAlpha;
    final globalMatrix = renderState.globalMatrix;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 1;

    // check buffer sizes and flush if necessary

    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 5 >= vxData.length) flush();

    // copy index list

    final ixIndex = renderBufferIndex.position;
    var vxIndex = renderBufferVertex.position;
    final vxCount = renderBufferVertex.count;

    for (var i = 0; i < ixListCount; i++) {
      ixData[ixIndex + i] = vxCount + ixList[i];
    }

    renderBufferIndex.position += ixListCount;
    renderBufferIndex.count += ixListCount;

    // copy vertex list

    final ma = globalMatrix.a;
    final mb = globalMatrix.b;
    final mc = globalMatrix.c;
    final md = globalMatrix.d;
    final mx = globalMatrix.tx;
    final my = globalMatrix.ty;

    final ta = mappingMatrix.a;
    final tb = mappingMatrix.b;
    final tc = mappingMatrix.c;
    final td = mappingMatrix.d;
    final tx = mappingMatrix.tx;
    final ty = mappingMatrix.ty;

    for (var i = 0, o = 0; i < vxListCount; i++, o += 2) {
      final x = vxList[o + 0];
      final y = vxList[o + 1];
      vxData[vxIndex + 0] = mx + ma * x + mc * y;
      vxData[vxIndex + 1] = my + mb * x + md * y;
      vxData[vxIndex + 2] = tx + ta * x + tc * y;
      vxData[vxIndex + 3] = ty + tb * x + td * y;
      vxData[vxIndex + 4] = alpha;
      vxIndex += 5;
    }

    renderBufferVertex.position += vxListCount * 5;
    renderBufferVertex.count += vxListCount;
  }
}
