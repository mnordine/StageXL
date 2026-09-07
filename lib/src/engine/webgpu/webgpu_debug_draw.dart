part of '../../engine.dart';

/// Index-only debug geometry. Retained instructions own their cached edges.
class _WebGpuDebugEdges {
  final GPUDevice device;
  GPUBuffer? buffer;
  var dirty = true;
  var _data = Uint32List(0);

  _WebGpuDebugEdges(this.device);

  void update(Uint32List triangles, int count) {
    if (!dirty) return;
    final edgeCount = count * 2;
    if (buffer == null || _data.length < edgeCount) {
      buffer?.destroy();
      _data = JSUint32Array.withLength(math.max(edgeCount, 6)).toDart;
      buffer = device.createBuffer(GPUBufferDescriptor(
        label: 'StageXL debug edges',
        size: _data.lengthInBytes,
        usage: $GPUBufferUsage.INDEX | $GPUBufferUsage.COPY_DST,
      ));
    }
    for (var i = 0; i < count; i += 3) {
      final edge = i * 2;
      final a = triangles[i];
      final b = triangles[i + 1];
      final c = triangles[i + 2];
      _data[edge] = a;
      _data[edge + 1] = b;
      _data[edge + 2] = b;
      _data[edge + 3] = c;
      _data[edge + 4] = c;
      _data[edge + 5] = a;
    }
    device.queue.writeBuffer(buffer!, 0, _data.toJS, 0, edgeCount);
    dirty = false;
  }

  void dispose() {
    buffer?.destroy();
    buffer = null;
    _data = Uint32List(0);
    dirty = true;
  }
}

class _WebGpuDebugColor {
  final GPUDevice device;
  final GPUBuffer buffer;
  late final GPUBindGroup bindGroup;
  final _data = JSFloat32Array.withLength(4).toDart;
  int? _color;

  _WebGpuDebugColor(this.device, GPUBindGroupLayout layout)
      : buffer = device.createBuffer(GPUBufferDescriptor(
          label: 'StageXL debug color',
          size: 16,
          usage: $GPUBufferUsage.UNIFORM | $GPUBufferUsage.COPY_DST,
        )) {
    bindGroup = device.createBindGroup(GPUBindGroupDescriptor(
      layout: layout,
      entries: [GPUBindGroupEntry(binding: 0, resource: GPUBufferBinding(buffer: buffer))].toJS,
    ));
  }

  void update(int color) {
    if (_color == color) return;
    _color = color;
    final alpha = colorGetA(color) / 255.0;
    _data[0] = colorGetR(color) / 255.0 * alpha;
    _data[1] = colorGetG(color) / 255.0 * alpha;
    _data[2] = colorGetB(color) / 255.0 * alpha;
    _data[3] = alpha;
    device.queue.writeBuffer(buffer, 0, _data.toJS, 0, 4);
  }
}

/// Separate debug pipelines consume the existing immediate/retained vertex layouts.
/// Normal shaders, vertex uploads, metadata, and bundle keys stay unchanged.
class _WebGpuDebugDraw {
  final RenderContextWebGPU context;
  final _pipelines = <({int kind, int samples, bool stencil, bool clipped}), GPURenderPipeline>{};
  late final _colorLayout = context.device.createBindGroupLayout(GPUBindGroupLayoutDescriptor(entries: [
    GPUBindGroupLayoutEntry(
      binding: 0,
      visibility: $GPUShaderStage.FRAGMENT,
      buffer: GPUBufferBindingLayout(type: 'uniform'),
    ),
  ].toJS));
  _WebGpuDebugColor? _wireColor;
  _WebGpuDebugColor? _maskColor;
  _WebGpuDebugEdges? _immediateEdges;

  _WebGpuDebugDraw(this.context);

  _WebGpuDebugEdges prepareImmediate(Uint32List indices, int count) {
    final edges = _immediateEdges ??= _WebGpuDebugEdges(context.device);
    edges.dirty = true;
    edges.update(indices, count);
    return edges;
  }

  void drawWireframe(
    GPURenderPassEncoder pass,
    GPUBuffer vertices,
    _WebGpuDebugEdges edges,
    int firstIndex,
    int count, {
    GPUBindGroup? metadata,
    bool shaderScissor = false,
  }) {
    final color = _wireColor ??= _WebGpuDebugColor(context.device, _colorLayout);
    color.update(debug_draw.debugDraw.wireframeColor);
    pass
      ..setPipeline(_pipeline(metadata == null ? 0 : 1, shaderScissor))
      ..setBindGroup(0, color.bindGroup)
      ..setBindGroup(1, context.pipelineSystem.projectionBindGroup)
      ..setVertexBuffer(0, vertices)
      ..setIndexBuffer(edges.buffer!, 'uint32');
    if (metadata != null) pass.setBindGroup(2, metadata);
    pass.drawIndexed(count * 2, 1, firstIndex * 2, 0, 0);
    context.renderStatistics.drawCount++;
    context.renderStatistics.indexCount += count * 2;
  }

  void drawMask() {
    final color = _maskColor ??= _WebGpuDebugColor(context.device, _colorLayout);
    color.update(debug_draw.debugDraw.maskColor);
    final pass = context.commandSystem.beginColorPass(null);
    pass
      ..setPipeline(_pipeline(2, false))
      ..setBindGroup(0, color.bindGroup)
      ..setStencilReference(context._maskSystem.activeStencilValue)
      ..draw(3)
      ..end();
    context.renderStatistics.drawCount++;
    context.commandSystem.submit();
  }

  GPURenderPipeline _pipeline(int kind, bool clipped) {
    final key = (kind: kind, samples: context.sampleCount,
        stencil: context._maskSystem.activeStencilValue > 0, clipped: clipped);
    return _pipelines.putIfAbsent(key, () {
      final module = context.device.createShaderModule(GPUShaderModuleDescriptor(
        label: 'StageXL debug shader',
        code: _shader(kind, clipped),
      ));
      final layout = context.device.createPipelineLayout(GPUPipelineLayoutDescriptor(bindGroupLayouts: [
        _colorLayout,
        if (kind != 2) context.pipelineSystem.projectionBindGroupLayout,
        if (kind == 1) context.pipelineSystem.retainedMetadataBindGroupLayout,
      ].toJS));
      return context.device.createRenderPipeline(GPURenderPipelineDescriptor(
        label: kind == 2 ? 'StageXL debug mask' : 'StageXL debug wireframe',
        layout: layout,
        vertex: GPUVertexState(module: module, entryPoint: 'vs_main', buffers: <GPUVertexBufferLayout>[
          if (kind != 2) GPUVertexBufferLayout(arrayStride: kind == 1 ? 20 : 36, attributes: [
            GPUVertexAttribute(format: 'float32x2', offset: 0, shaderLocation: 0),
            if (kind == 1) GPUVertexAttribute(format: 'float32', offset: 16, shaderLocation: 1),
          ].toJS),
        ].toJS),
        fragment: GPUFragmentState(module: module, entryPoint: 'fs_main', targets: [
          GPUColorTargetState(format: context.preferredTextureFormat,
              blend: context.pipelineSystem.getBlendState(BlendMode.NORMAL)),
        ].toJS),
        primitive: GPUPrimitiveState(topology: kind == 2 ? 'triangle-list' : 'line-list'),
        depthStencil: context.pipelineSystem._depthStencilState(key.stencil ? 1 : 0),
        multisample: GPUMultisampleState(count: key.samples),
      ));
    });
  }

  String _shader(int kind, bool clipped) {
    const color = '@group(0) @binding(0) var<uniform> debugColor: vec4<f32>;';
    if (kind == 2) {
      return '''
        $color
        @vertex fn vs_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
          let x = f32((index << 1u) & 2u) * 2.0 - 1.0;
          let y = f32(index & 2u) * 2.0 - 1.0;
          return vec4<f32>(x, y, 0.0, 1.0);
        }
        @fragment fn fs_main() -> @location(0) vec4<f32> { return debugColor; }
      ''';
    }
    final retained = kind == 1;
    final metadata = retained ? '''
      struct RenderableData {
        transform: vec4<f32>,
        translationColor: vec4<f32>,
        colorTexture: vec4<f32>,
        ${clipped ? 'clipRect: vec4<f32>,' : ''}
      };
      @group(2) @binding(0) var<storage, read> renderables: array<RenderableData>;
    ''' : '';
    final transform = retained ? '''
      let item = renderables[u32(input.renderableIndex + 0.5)];
      let position = vec2<f32>(
        item.translationColor.x + item.transform.x * input.position.x + item.transform.z * input.position.y,
        item.translationColor.y + item.transform.y * input.position.x + item.transform.w * input.position.y,
      );
      ${clipped ? 'output.clipRect = item.clipRect;' : ''}
    ''' : 'let position = input.position;';
    return '''
      $color
      @group(1) @binding(0) var<uniform> projectionMatrix: mat4x4<f32>;
      $metadata
      struct VertexInput {
        @location(0) position: vec2<f32>,
        ${retained ? '@location(1) renderableIndex: f32,' : ''}
      };
      struct VertexOutput {
        @builtin(position) position: vec4<f32>,
        ${clipped ? '@location(0) @interpolate(flat) clipRect: vec4<f32>,' : ''}
      };
      @vertex fn vs_main(input: VertexInput) -> VertexOutput {
        var output: VertexOutput;
        $transform
        output.position = vec4<f32>(position, 0.0, 1.0) * projectionMatrix;
        output.position.z = output.position.z * 0.5 + output.position.w * 0.5;
        return output;
      }
      @fragment fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
        ${clipped ? '''
        if (input.clipRect.z >= input.clipRect.x &&
            (input.position.x < input.clipRect.x || input.position.y < input.clipRect.y ||
             input.position.x >= input.clipRect.z || input.position.y >= input.clipRect.w)) { discard; }
        ''' : ''}
        return debugColor;
      }
    ''';
  }

  void dispose() {
    _immediateEdges?.dispose();
    _wireColor?.buffer.destroy();
    _maskColor?.buffer.destroy();
    _immediateEdges = null;
    _wireColor = null;
    _maskColor = null;
    _pipelines.clear();
  }
}
