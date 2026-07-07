part of '../engine.dart';

class RenderStatistics {
  var drawCount = 0;
  var vertexCount = 0;
  var indexCount = 0;

  void reset() {
    drawCount = 0;
    vertexCount = 0;
    indexCount = 0;
  }

  @override
  String toString() =>
      'RenderStatistics: $drawCount draws, $vertexCount verices, $indexCount indices';
}
