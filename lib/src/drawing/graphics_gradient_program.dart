part of '../drawing.dart';

typedef _Parameters = ({RenderState renderState, GraphicsGradient gradient});

final _linearProgramGpu = RenderProgramSimpleWebGPU<_Parameters>(
  label: 'StageXL linear graphics gradient',
  shaderSource: _linearShaderGpu,
  uniformByteSize: 32,
  writeUniforms: _writeLinearUniformsGpu,
);

final _radialProgramGpu = RenderProgramSimpleWebGPU<_Parameters>(
  label: 'StageXL radial graphics gradient',
  shaderSource: _radialShaderGpu,
  uniformByteSize: 64,
  writeUniforms: _writeRadialUniformsGpu,
);

abstract class _GraphicsGradientProgram extends RenderProgramWebGL<void> {
  GraphicsGradient? activeGradient;

  // aVertexPosition:   Float32(x), Float32(y)
  // aVertexAlpha:      Float32(alpha)

  @override
  String get vertexShaderSource => isWebGL2 ? '''
    #version 300 es

    uniform mat4 uProjectionMatrix;

    in vec2 aVertexPosition;
    in float aVertexAlpha;

    out vec2 vTextCoord;
    out float vAlpha;

    void main() {
      vTextCoord = aVertexPosition;
      vAlpha = aVertexAlpha;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''' : '''

    uniform mat4 uProjectionMatrix;
    attribute vec2 aVertexPosition;
    attribute float aVertexAlpha;
    varying vec2 vTextCoord;
    varying float vAlpha;

    void main() {
      vTextCoord = aVertexPosition;
      vAlpha = aVertexAlpha;
      gl_Position = vec4(aVertexPosition, 0.0, 1.0) * uProjectionMatrix;
    }
    ''';

  //---------------------------------------------------------------------------

  @override
  void setupAttributes() {
    renderBufferVertex.bindAttribute(attributes['aVertexPosition'], 2, 12, 0);
    renderBufferVertex.bindAttribute(attributes['aVertexAlpha'], 1, 12, 8);
  }

  void configure(RenderState renderState, GraphicsGradient gradient);

  //---------------------------------------------------------------------------

  void renderGradient(
      RenderState renderState, Int16List ixList, Float32List vxList) {
    final alpha = renderState.globalAlpha;
    final matrix = renderState.globalMatrix;
    final ixListCount = ixList.length;
    final vxListCount = vxList.length >> 1;

    // check buffer sizes and flush if necessary

    final ixData = renderBufferIndex.data;
    final ixPosition = renderBufferIndex.position;
    if (ixPosition + ixListCount >= ixData.length) flush();

    final vxData = renderBufferVertex.data;
    final vxPosition = renderBufferVertex.position;
    if (vxPosition + vxListCount * 3 >= vxData.length) flush();

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

    final ma = matrix.a;
    final mb = matrix.b;
    final mc = matrix.c;
    final md = matrix.d;
    final mx = matrix.tx;
    final my = matrix.ty;

    for (var i = 0, o = 0; i < vxListCount; i++, o += 2) {
      final x = vxList[o + 0];
      final y = vxList[o + 1];
      vxData[vxIndex + 0] = mx + ma * x + mc * y;
      vxData[vxIndex + 1] = my + mb * x + md * y;
      vxData[vxIndex + 2] = alpha;
      vxIndex += 3;
    }

    renderBufferVertex.position += vxListCount * 3;
    renderBufferVertex.count += vxListCount;
  }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

class _LinearGraphicsGradientProgram extends _GraphicsGradientProgram {
  @override
  String get fragmentShaderSource => isWebGL2 ? '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;

    uniform sampler2D uSampler;
    uniform vec2 uvGradientStart;
    uniform vec2 uvGradientVector;

    in vec2 vTextCoord;
    in float vAlpha;

    out vec4 fragColor;

    void main() {
      vec2 pixelVector = vTextCoord - uvGradientStart;
      float t = dot(pixelVector,uvGradientVector)/dot(uvGradientVector,uvGradientVector);
      fragColor = texture(uSampler, vec2(0.5,t)) * vAlpha;
    }
    ''' : '''

    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec2 uvGradientStart;
    uniform vec2 uvGradientVector;

    varying vec2 vTextCoord;
    varying float vAlpha;

    void main() {
      vec2 pixelVector = vTextCoord - uvGradientStart;
      float t = dot(pixelVector,uvGradientVector)/dot(uvGradientVector,uvGradientVector);
      gl_FragColor = texture2D(uSampler, vec2(0.5,t)) * vAlpha;
    }
    ''';

  @override
  void configure(RenderState renderState, GraphicsGradient gradient) {
    final m = renderState.globalMatrix;
    final g = gradient;

    final startX = m.tx + m.a * g.startX + m.c * g.startY;
    final startY = m.ty + m.b * g.startX + m.d * g.startY;
    final vectorX = (m.tx + m.a * g.endX + m.c * g.endY) - startX;
    var vectorY = (m.ty + m.b * g.endX + m.d * g.endY) - startY;

    // protect against zero length vector (linear gradient not defined for this case)
    if (vectorX == 0 && vectorY == 0) vectorY = 1;

    renderingContext.uniform1i(uniforms['uSampler'], 0);
    renderingContext.uniform2f(uniforms['uvGradientStart'], startX, startY);
    renderingContext.uniform2f(uniforms['uvGradientVector'], vectorX, vectorY);
  }
}

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

class _RadialGraphicsGradientProgram extends _GraphicsGradientProgram {
  @override
  String get fragmentShaderSource => isWebGL2 ? '''
    #version 300 es

    precision ${RenderProgramWebGL.fragmentPrecision} float;

    uniform sampler2D uSampler;
    uniform vec2 uvA;
    uniform vec3 uvB;
    uniform vec3 uvC;

    in vec2 vTextCoord;
    in float vAlpha;

    out vec4 fragColor;

    void main() {
      float a = uvA.x;
      float b = dot(uvB,vec3(vTextCoord,1));
      float c = dot(vTextCoord,vTextCoord) + dot(uvC,vec3(vTextCoord,1));
      float sign = uvA.y;
      float t = (-b + sign*sqrt(b*b-4.0*a*c))/(2.0*a);
      fragColor = texture(uSampler, vec2(0.5,t)) * vAlpha;
    }
    ''' : '''

    precision ${RenderProgramWebGL.fragmentPrecision} float;
    uniform sampler2D uSampler;
    uniform vec2 uvA;
    uniform vec3 uvB;
    uniform vec3 uvC;

    varying vec2 vTextCoord;
    varying float vAlpha;

    void main() {
      float a = uvA.x;
      float b = dot(uvB,vec3(vTextCoord,1));
      float c = dot(vTextCoord,vTextCoord) + dot(uvC,vec3(vTextCoord,1));
      float sign = uvA.y;
      float t = (-b + sign*sqrt(b*b-4.0*a*c))/(2.0*a);
      gl_FragColor = texture2D(uSampler, vec2(0.5,t)) * vAlpha;
    }
    ''';

  @override
  void configure(RenderState renderState, GraphicsGradient gradient) {
    final m = renderState.globalMatrix;
    final g = gradient;

    final scaleR = sqrt(m.a * m.a +
        m.c * m.c); // we are simplifying here, assuming uniform scale
    final startX = m.tx + m.a * g.startX + m.c * g.startY;
    final startY = m.ty + m.b * g.startX + m.d * g.startY;
    final vectorX = (m.tx + m.a * g.endX + m.c * g.endY) - startX;
    final vectorY = (m.ty + m.b * g.endX + m.d * g.endY) - startY;
    final startRadius = g.startRadius * scaleR;
    var radiusOffset = (g.endRadius - g.startRadius) * scaleR;

    // protect against equal start-end circles (radial gradient not defined for this case)
    if (vectorX == 0 && vectorY == 0 && radiusOffset == 0) radiusOffset = 1;

    final a =
        vectorX * vectorX + vectorY * vectorY - radiusOffset * radiusOffset;
    final b0 = -2 * vectorX;
    final b1 = -2 * vectorY;
    final b2 = 2 * startX * vectorX +
        2 * startY * vectorY -
        2 * startRadius * radiusOffset;
    final c0 = -2 * startX;
    final c1 = -2 * startY;
    final c2 = startX * startX + startY * startY - startRadius * startRadius;
    final sign = radiusOffset >= 0 ? -1 : 1;

    renderingContext.uniform1i(uniforms['uSampler'], 0);
    renderingContext.uniform2f(uniforms['uvA'], a, sign);
    renderingContext.uniform3f(uniforms['uvB'], b0, b1, b2);
    renderingContext.uniform3f(uniforms['uvC'], c0, c1, c2);
  }
}

void _writeLinearUniformsGpu(_Parameters parameters, Float32List data) {
  final m = parameters.renderState.globalMatrix;
  final g = parameters.gradient;
  final startX = m.tx + m.a * g.startX + m.c * g.startY;
  final startY = m.ty + m.b * g.startX + m.d * g.startY;
  final vectorX = (m.tx + m.a * g.endX + m.c * g.endY) - startX;
  var vectorY = (m.ty + m.b * g.endX + m.d * g.endY) - startY;
  if (vectorX == 0 && vectorY == 0) vectorY = 1;
  data[0] = startX;
  data[1] = startY;
  data[2] = vectorX;
  data[3] = vectorY;
  data[4] = parameters.renderState.globalAlpha;
  data[5] = 0;
  data[6] = 0;
  data[7] = 0;
}

void _writeRadialUniformsGpu(_Parameters parameters, Float32List data) {
  final m = parameters.renderState.globalMatrix;
  final g = parameters.gradient;
  final scaleR = sqrt(m.a * m.a + m.c * m.c);
  final startX = m.tx + m.a * g.startX + m.c * g.startY;
  final startY = m.ty + m.b * g.startX + m.d * g.startY;
  final vectorX = (m.tx + m.a * g.endX + m.c * g.endY) - startX;
  final vectorY = (m.ty + m.b * g.endX + m.d * g.endY) - startY;
  final startRadius = g.startRadius * scaleR;
  var radiusOffset = (g.endRadius - g.startRadius) * scaleR;
  if (vectorX == 0 && vectorY == 0 && radiusOffset == 0) radiusOffset = 1;

  data[0] = vectorX * vectorX + vectorY * vectorY - radiusOffset * radiusOffset;
  data[1] = radiusOffset >= 0 ? -1 : 1;
  data[2] = parameters.renderState.globalAlpha;
  data[3] = 0;
  data[4] = -2 * vectorX;
  data[5] = -2 * vectorY;
  data[6] = 2 * startX * vectorX + 2 * startY * vectorY - 2 * startRadius * radiusOffset;
  data[7] = 0;
  data[8] = -2 * startX;
  data[9] = -2 * startY;
  data[10] = startX * startX + startY * startY - startRadius * startRadius;
  data[11] = 0;
  data[12] = 0;
  data[13] = 0;
  data[14] = 0;
  data[15] = 0;
}

const _gpuHeader = '''
  @group(0) @binding(0) var gradientSampler: sampler;
  @group(0) @binding(1) var gradientTexture: texture_2d<f32>;
  struct VertexInput { @location(0) clip: vec4<f32>, @location(1) position: vec2<f32>, };
  struct VertexOutput { @builtin(position) clip: vec4<f32>, @location(0) position: vec2<f32>, };
  @vertex
  fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.clip = input.clip;
    output.position = input.position;
    return output;
  }
''';

const _linearShaderGpu = '''
  $_gpuHeader
  struct Uniforms { geometry: vec4<f32>, alpha: vec4<f32>, };
  @group(0) @binding(2) var<uniform> gradient: Uniforms;
  @fragment
  fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let pixelVector = input.position - gradient.geometry.xy;
    let t = dot(pixelVector, gradient.geometry.zw) / dot(gradient.geometry.zw, gradient.geometry.zw);
    return textureSample(gradientTexture, gradientSampler, vec2<f32>(0.5, t)) * gradient.alpha.x;
  }
''';

const _radialShaderGpu = '''
  $_gpuHeader
  struct Uniforms { a: vec4<f32>, b: vec4<f32>, c: vec4<f32>, unused: vec4<f32>, };
  @group(0) @binding(2) var<uniform> gradient: Uniforms;
  @fragment
  fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let b = dot(gradient.b.xyz, vec3<f32>(input.position, 1));
    let c = dot(input.position, input.position) + dot(gradient.c.xyz, vec3<f32>(input.position, 1));
    let discriminant = max(b * b - 4.0 * gradient.a.x * c, 0.0);
    let t = (-b + gradient.a.y * sqrt(discriminant)) / (2.0 * gradient.a.x);
    return textureSample(gradientTexture, gradientSampler, vec2<f32>(0.5, t)) * gradient.a.z;
  }
''';
