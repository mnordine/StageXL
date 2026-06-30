part of '../engine.dart';

class RenderStatistics {
  var drawCount = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var webgpuBindGroupCreateCount = 0;
  var webgpuFallbackCount = 0;
  var webgpuPipelineCreateCount = 0;
  var webgpuRenderBundleBuildCount = 0;
  var webgpuRenderBundleCacheHitCount = 0;
  var webgpuRenderPassCount = 0;
  var webgpuTextureUploadCount = 0;

  void reset() {
    drawCount = 0;
    vertexCount = 0;
    indexCount = 0;
    webgpuBindGroupCreateCount = 0;
    webgpuFallbackCount = 0;
    webgpuPipelineCreateCount = 0;
    webgpuRenderBundleBuildCount = 0;
    webgpuRenderBundleCacheHitCount = 0;
    webgpuRenderPassCount = 0;
    webgpuTextureUploadCount = 0;
  }

  @override
  String toString() =>
      'RenderStatistics: $drawCount draws, $vertexCount verices, $indexCount indices';
}
