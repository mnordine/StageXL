part of '../../engine.dart';

class WebGpuFilterSystem {
  static const _floatsPerVertex = 6;
  static const _bytesPerVertex = _floatsPerVertex * 4;

  final RenderContextWebGPU renderContext;
  late final GPUBindGroupLayout _colorMatrixBindGroupLayout;
  late final GPUPipelineLayout _colorMatrixPipelineLayout;
  late final GPUShaderModule _colorMatrixShaderModule;
  late GPUBuffer _vertexBuffer;
  late GPUBuffer _indexBuffer;
  late GPUBuffer _uniformBuffer;
  final _colorMatrixPipelines = <BlendMode, Map<bool, GPURenderPipeline>>{};
  var _vertexCapacity = 0;
  var _indexCapacity = 0;

  WebGpuFilterSystem(this.renderContext) {
    final device = renderContext.device;
    _colorMatrixBindGroupLayout = device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
      GPUBindGroupLayoutEntry(
        binding: 0,
        visibility: $GPUShaderStage.FRAGMENT,
        sampler: GPUSamplerBindingLayout(type: 'filtering'),
      ),
      GPUBindGroupLayoutEntry(
        binding: 1,
        visibility: $GPUShaderStage.FRAGMENT,
        texture: GPUTextureBindingLayout(sampleType: 'float'),
      ),
      GPUBindGroupLayoutEntry(
        binding: 2,
        visibility: $GPUShaderStage.FRAGMENT,
        buffer: GPUBufferBindingLayout(type: 'uniform'),
      ),
    ].toJS));
    _colorMatrixPipelineLayout =
        device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [_colorMatrixBindGroupLayout].toJS));
    _colorMatrixShaderModule = device.createShaderModule(GPUShaderModuleDescriptor(code: _colorMatrixShaderSource));
    _vertexBuffer = _createVertexBuffer(_bytesPerVertex * 4);
    _indexBuffer = _createIndexBuffer(12);
    _uniformBuffer = device.createBuffer(GPUBufferDescriptor(
      size: 80,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.UNIFORM,
    ));
  }

  void renderTextureQuadFiltered(
      RenderState renderState, RenderTextureQuad renderTextureQuad, List<RenderFilter> renderFilters) {
    final firstFilter = renderFilters.length == 1 ? renderFilters[0] : null;

    if (renderFilters.isEmpty) return;
    if (firstFilter != null && firstFilter.isSimple && firstFilter.supportsWebGPU) {
      renderContext.flush();
      firstFilter.renderFilter(renderState, renderTextureQuad, 0);
      return;
    }

    _throwUnsupported();
  }

  void renderObjectFiltered(RenderState renderState, RenderObject renderObject) {
    if (renderObject.filters.isEmpty) return;
    _throwUnsupported();
  }

  void renderColorMatrixFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List colorMatrixList,
    Float32List colorOffsetList,
  ) {
    final uniformData = Float32List(20);
    final alpha = renderState.globalAlpha;
    uniformData
      ..setRange(0, 12, colorMatrixList, 0)
      ..setRange(12, 16, [
        colorMatrixList[12] * alpha,
        colorMatrixList[13] * alpha,
        colorMatrixList[14] * alpha,
        colorMatrixList[15] * alpha,
      ])
      ..setRange(16, 20, [
        colorOffsetList[0] / 255,
        colorOffsetList[1] / 255,
        colorOffsetList[2] / 255,
        colorOffsetList[3] / 255 * alpha,
      ]);

    _renderTextureQuadWithColorMatrixUniform(renderState, renderTextureQuad, uniformData);
  }

  void renderTintFilterQuad(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    num factorR,
    num factorG,
    num factorB,
    num factorA,
  ) {
    final alpha = renderState.globalAlpha;
    final uniformData = Float32List(20);
    uniformData[0] = factorR.toDouble();
    uniformData[5] = factorG.toDouble();
    uniformData[10] = factorB.toDouble();
    uniformData[15] = factorA.toDouble() * alpha;
    _renderTextureQuadWithColorMatrixUniform(renderState, renderTextureQuad, uniformData);
  }

  void _renderTextureQuadWithColorMatrixUniform(
    RenderState renderState,
    RenderTextureQuad renderTextureQuad,
    Float32List uniformData,
  ) {
    final ixList = renderTextureQuad.ixList;
    final vxList = renderTextureQuad.vxList;
    final vertexCount = vxList.length >> 2;
    if (vertexCount == 0 || ixList.isEmpty) return;

    final vertices = Float32List(vertexCount * _floatsPerVertex);
    final indices = Uint16List(ixList.length.isOdd ? ixList.length + 1 : ixList.length);
    final combined = Matrix3D.fromIdentity()
      ..copyFrom2DAndConcat(renderState.globalMatrix, renderContext.activeProjectionMatrix);

    var vertexIndex = 0;
    for (var i = 0, sourceIndex = 0; i < vertexCount; i++, sourceIndex += 4) {
      final x = vxList[sourceIndex + 0];
      final y = vxList[sourceIndex + 1];
      final clipX = combined.m00 * x + combined.m10 * y + combined.m30;
      final clipY = combined.m01 * x + combined.m11 * y + combined.m31;
      final clipZ = combined.m02 * x + combined.m12 * y + combined.m32;
      final clipW = combined.m03 * x + combined.m13 * y + combined.m33;
      vertices[vertexIndex++] = clipX;
      vertices[vertexIndex++] = clipY;
      vertices[vertexIndex++] = clipZ * 0.5 + clipW * 0.5;
      vertices[vertexIndex++] = clipW;
      vertices[vertexIndex++] = vxList[sourceIndex + 2];
      vertices[vertexIndex++] = vxList[sourceIndex + 3];
    }

    for (var i = 0; i < ixList.length; i++) {
      indices[i] = ixList[i];
    }

    final vertexBytes = vertices.lengthInBytes;
    final indexBytes = indices.lengthInBytes;
    _ensureVertexCapacity(vertexBytes);
    _ensureIndexCapacity(indexBytes);
    renderContext.device.queue
      ..writeBuffer(_vertexBuffer, 0, vertices.buffer.toJS)
      ..writeBuffer(_indexBuffer, 0, indices.buffer.toJS)
      ..writeBuffer(_uniformBuffer, 0, uniformData.buffer.toJS);

    final texture = renderTextureQuad.renderTexture;
    final bindGroup = renderContext.device.createBindGroup(GPUBindGroupDescriptor(
      layout: _colorMatrixBindGroupLayout,
      entries: [
        GPUBindGroupEntry(binding: 0, resource: renderContext.textureSystem.getSampler(texture)),
        GPUBindGroupEntry(binding: 1, resource: renderContext.textureSystem.getTextureView(texture)),
        GPUBindGroupEntry(binding: 2, resource: GPUBufferBinding(buffer: _uniformBuffer, offset: 0, size: 80)),
      ].toJS,
    ));
    renderContext.renderStatistics.webgpuBindGroupCreateCount++;

    final stencilValue = renderContext.maskSystem.activeStencilValue;
    final pass = renderContext.commandSystem.beginColorPass(null);
    pass
      ..setPipeline(_getColorMatrixPipeline(renderState.globalBlendMode, stencilValue > 0))
      ..setBindGroup(0, bindGroup)
      ..setVertexBuffer(0, _vertexBuffer, 0, vertexBytes)
      ..setIndexBuffer(_indexBuffer, 'uint16', 0, indexBytes);
    if (stencilValue > 0) {
      pass.setStencilReference(stencilValue);
    }
    pass.drawIndexed(ixList.length, 1, 0, 0, 0);
    pass.end();
    renderContext.commandSystem.submit();

    final statistics = renderContext.renderStatistics;
    statistics.drawCount++;
    statistics.vertexCount += vertexCount;
    statistics.indexCount += ixList.length;
  }

  GPURenderPipeline _getColorMatrixPipeline(BlendMode blendMode, bool stencilTest) {
    final blendPipelines = _colorMatrixPipelines.putIfAbsent(blendMode, () => <bool, GPURenderPipeline>{});
    return blendPipelines.putIfAbsent(stencilTest, () => _createColorMatrixPipeline(blendMode, stencilTest));
  }

  GPURenderPipeline _createColorMatrixPipeline(BlendMode blendMode, bool stencilTest) {
    renderContext.renderStatistics.webgpuPipelineCreateCount++;
    return renderContext.device.createRenderPipeline(GPURenderPipelineDescriptor(
      label: 'StageXL color matrix filter pipeline',
      layout: _colorMatrixPipelineLayout,
      vertex: GPUVertexState(
        module: _colorMatrixShaderModule,
        entryPoint: 'vs_main',
        buffers: [
          GPUVertexBufferLayout(
            arrayStride: _bytesPerVertex,
            attributes: [
              GPUVertexAttribute(format: 'float32x4', offset: 0, shaderLocation: 0),
              GPUVertexAttribute(format: 'float32x2', offset: 16, shaderLocation: 1),
            ].toJS,
          ),
        ].toJS,
      ),
      fragment: GPUFragmentState(
        module: _colorMatrixShaderModule,
        entryPoint: 'fs_main',
        targets: [
          GPUColorTargetState(
            format: renderContext.preferredTextureFormat,
            blend: renderContext.pipelineSystem.getBlendState(blendMode),
          ),
        ].toJS,
      ),
      primitive: GPUPrimitiveState(topology: 'triangle-list'),
      depthStencil: _depthStencilState(stencilTest),
      multisample: GPUMultisampleState(count: 1),
    ));
  }

  GPUDepthStencilState _depthStencilState(bool stencilTest) {
    final stencilFace = stencilTest
        ? GPUStencilFaceState(compare: 'equal', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep')
        : GPUStencilFaceState(compare: 'always', failOp: 'keep', depthFailOp: 'keep', passOp: 'keep');
    return GPUDepthStencilState(
      format: 'depth24plus-stencil8',
      depthWriteEnabled: false,
      depthCompare: 'always',
      stencilFront: stencilFace,
      stencilBack: stencilFace,
      stencilReadMask: 0xFF,
      stencilWriteMask: 0,
    );
  }

  GPUBuffer _createVertexBuffer(int size) {
    _vertexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.VERTEX,
    ));
  }

  GPUBuffer _createIndexBuffer(int size) {
    _indexCapacity = size;
    return renderContext.device.createBuffer(GPUBufferDescriptor(
      size: size,
      usage: $GPUBufferUsage.COPY_DST | $GPUBufferUsage.INDEX,
    ));
  }

  void _ensureVertexCapacity(int size) {
    if (size <= _vertexCapacity) return;
    _vertexBuffer.destroy();
    _vertexBuffer = _createVertexBuffer(size * 2);
  }

  void _ensureIndexCapacity(int size) {
    if (size <= _indexCapacity) return;
    _indexBuffer.destroy();
    _indexBuffer = _createIndexBuffer(size * 2);
  }

  void _throwUnsupported() {
    renderContext.renderStatistics.webgpuFallbackCount++;
    throw UnsupportedError('WebGPU filter parity requires the WGSL multi-pass filter implementation.');
  }

  static const _colorMatrixShaderSource = '''
    @group(0) @binding(0) var stageSampler: sampler;
    @group(0) @binding(1) var stageTexture: texture_2d<f32>;

    struct ColorMatrixUniforms {
      matrixR: vec4<f32>,
      matrixG: vec4<f32>,
      matrixB: vec4<f32>,
      matrixA: vec4<f32>,
      offset: vec4<f32>,
    };

    @group(0) @binding(2) var<uniform> colorMatrix: ColorMatrixUniforms;

    struct VertexInput {
      @location(0) clip: vec4<f32>,
      @location(1) uv: vec2<f32>,
    };

    struct VertexOutput {
      @builtin(position) position: vec4<f32>,
      @location(0) uv: vec2<f32>,
    };

    @vertex
    fn vs_main(input: VertexInput) -> VertexOutput {
      var output: VertexOutput;
      output.position = input.clip;
      output.uv = input.uv;
      return output;
    }

    @fragment
    fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
      let sampleColor = textureSample(stageTexture, stageSampler, input.uv);
      let safeAlpha = max(sampleColor.a, 0.000001);
      let color = vec4<f32>(sampleColor.rgb / safeAlpha, sampleColor.a);
      let transformed = colorMatrix.offset + vec4<f32>(
        dot(color, colorMatrix.matrixR),
        dot(color, colorMatrix.matrixG),
        dot(color, colorMatrix.matrixB),
        dot(color, colorMatrix.matrixA)
      );
      return vec4<f32>(transformed.rgb * transformed.a, transformed.a);
    }
  ''';
}
