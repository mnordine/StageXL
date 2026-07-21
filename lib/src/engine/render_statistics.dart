part of '../engine.dart';

class RenderStatistics {
  var dualSourceBlendingRequested = false;
  var dualSourceBlendingEnabled = false;
  var drawCount = 0;
  var frameTimeMicroseconds = 0;
  var renderObjectMicroseconds = 0;
  var renderFlushMicroseconds = 0;
  var vertexCount = 0;
  var indexCount = 0;
  var retainedInstructionBuildCount = 0;
  var retainedInstructionCount = 0;
  var retainedInstructionReuseCount = 0;
  var retainedInstructionUploadCount = 0;
  var webgpuBindGroupCreateCount = 0;
  var webgpuBatchBlendBreakCount = 0;
  var webgpuBatchFlushCount = 0;
  var webgpuBatchRunCount = 0;
  var webgpuBatchTextureBreakCount = 0;
  var webgpuBufferUploadMicroseconds = 0;
  var webgpuPassEncodeMicroseconds = 0;
  var webgpuFallbackCount = 0;
  var webgpuPipelineCreateCount = 0;
  var webgpuRenderBundleBuildCount = 0;
  var webgpuRenderBundleCacheHitCount = 0;
  var webgpuRenderPassCount = 0;
  var webgpuSubmitMicroseconds = 0;
  var webgpuTextureUploadCount = 0;
  var webgpuInstructionBuildCount = 0;
  var webgpuInstructionReuseCount = 0;
  var webgpuInstructionUploadCount = 0;
  var webgpuRenderableCount = 0;
  final webgpuFallbackCauses = <String>[];

  void addWebGpuFallbackCause(String cause) {
    webgpuFallbackCount++;
    webgpuFallbackCauses.add(cause);
  }

  void reset() {
    drawCount = 0;
    frameTimeMicroseconds = 0;
    renderObjectMicroseconds = 0;
    renderFlushMicroseconds = 0;
    vertexCount = 0;
    indexCount = 0;
    retainedInstructionBuildCount = 0;
    retainedInstructionCount = 0;
    retainedInstructionReuseCount = 0;
    retainedInstructionUploadCount = 0;
    webgpuBindGroupCreateCount = 0;
    webgpuBatchBlendBreakCount = 0;
    webgpuBatchFlushCount = 0;
    webgpuBatchRunCount = 0;
    webgpuBatchTextureBreakCount = 0;
    webgpuBufferUploadMicroseconds = 0;
    webgpuPassEncodeMicroseconds = 0;
    webgpuFallbackCount = 0;
    webgpuPipelineCreateCount = 0;
    webgpuRenderBundleBuildCount = 0;
    webgpuRenderBundleCacheHitCount = 0;
    webgpuRenderPassCount = 0;
    webgpuSubmitMicroseconds = 0;
    webgpuTextureUploadCount = 0;
    webgpuInstructionBuildCount = 0;
    webgpuInstructionReuseCount = 0;
    webgpuInstructionUploadCount = 0;
    webgpuRenderableCount = 0;
    webgpuFallbackCauses.clear();
  }

  @override
  String toString() =>
      'RenderStatistics: $drawCount draws, $vertexCount verices, $indexCount indices';
}
