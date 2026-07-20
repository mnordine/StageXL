part of '../display.dart';

class StageConsole extends DisplayObject {
  final _fontImage =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAcAAAAAOAQAAAACQy/GuAAABsE'
      'lEQVR4Aa3OMWsTUQDA8f97eV6fEpvT6YZgX4qDYwoOAdE+IQ5OfoXzG7S46KA8HZSC1PQLaN'
      'Cln8ElFxyaQWg3XZQLBAyi5BqjJDHeE7whoE7i7xP8+He1Wq38WGkLIFmyphryV2JQAQnIhw'
      'E6tQCR6Sc3dq80tsBmQVTrHlSeVZvT8flwr3p7u3/Q27va3MnMWKEA2e0oRAjI8uWN1f3rZ9'
      'YjhNNU392Ud7bPckGuf9LB62sblQ874E3OqbEEefRyrsNRywFs5sL5FOIuizSqQ0IO2JMApM'
      'AA4DQS/77+dZEBgMIhVor/Wi6nkAIgHAvAw0zTCz3fkCDOubJD3IorDgifH+8yydrNvleQsL'
      'IaNPDuB1zkMIH+8MjACAknnr564vCf28dOg4n5QrnFAoFu1JmNF70i3MPGQIT1DiTp91h0gA'
      'QAbGkfBeRrcjrYwgAImAOMYf7rDUhAKchC7rsgRDyYxYCLO33FoAUWBaTkFD5WgQQkhnzzkq'
      'MweTtq+7tMhnin9YTDF4/chDftUsKcoW97B2RQEIC24GDJWsNvDAWRVrjHUgmWhOMPEf/DT5'
      'NSmGlKVHTvAAAAAElFTkSuQmCC';

  final _glyphs = <RenderTextureQuad>[];
  final _matrix = Matrix.fromIdentity();
  final _lines = <String>[];

  var _consoleWidth = 0;
  var _consoleHeight = 0;

  StageConsole() {
    BitmapData.load(_fontImage).then(_calculateGlyphs);
  }

  //----------------------------------------------------------------------------

  EventStream<Event> get onUpdate => on<Event>('Update');

  Iterable<String> get lines => _lines;

  //----------------------------------------------------------------------------

  void updateRenderStatistics(RenderStatistics stats) {
    clear();
    print('FRAME MS${_formatMicroseconds(stats.frameTimeMicroseconds).padLeft(9)}');
    print('OBJECT MS${_formatMicroseconds(stats.renderObjectMicroseconds).padLeft(8)}');
    print('FLUSH MS${_formatMicroseconds(stats.renderFlushMicroseconds).padLeft(9)}');
    print('DRAWCALLS${stats.drawCount.toString().padLeft(6)}');
    print('VERTICES${stats.vertexCount.toString().padLeft(7)}');
    print('INDICES${stats.indexCount.toString().padLeft(8)}');
    print('BATCH FLUSH${stats.webgpuBatchFlushCount.toString().padLeft(5)}');
    print('BATCH RUNS${stats.webgpuBatchRunCount.toString().padLeft(6)}');
    print('BLEND BREAK${stats.webgpuBatchBlendBreakCount.toString().padLeft(5)}');
    print('TEX BREAK${stats.webgpuBatchTextureBreakCount.toString().padLeft(7)}');
    print('BINDGROUPS${stats.webgpuBindGroupCreateCount.toString().padLeft(6)}');
    print('PIPELINES${stats.webgpuPipelineCreateCount.toString().padLeft(7)}');
    print('TEX UPLOAD${stats.webgpuTextureUploadCount.toString().padLeft(6)}');
    print('INSTR BUILD${stats.webgpuInstructionBuildCount.toString().padLeft(4)}');
    print('INSTR REUSE${stats.webgpuInstructionReuseCount.toString().padLeft(4)}');
    print('INSTR UPLOAD${stats.webgpuInstructionUploadCount.toString().padLeft(3)}');
    print('RENDERABLES${stats.webgpuRenderableCount.toString().padLeft(5)}');
    print('PASSES${stats.webgpuRenderPassCount.toString().padLeft(10)}');
    print('BUNDLE BUILD${stats.webgpuRenderBundleBuildCount.toString().padLeft(4)}');
    print('BUNDLE HIT${stats.webgpuRenderBundleCacheHitCount.toString().padLeft(6)}');
    print('BUFFER MS${_formatMicroseconds(stats.webgpuBufferUploadMicroseconds).padLeft(6)}');
    print('ENCODE MS${_formatMicroseconds(stats.webgpuPassEncodeMicroseconds).padLeft(6)}');
    print('SUBMIT MS${_formatMicroseconds(stats.webgpuSubmitMicroseconds).padLeft(6)}');
    print('FALLBACKS${stats.webgpuFallbackCount.toString().padLeft(7)}');

    for (final cause in stats.webgpuFallbackCauses) {
      print('WGPU ${cause.toUpperCase()}');
    }
  }

  void clear() {
    _lines.clear();
    _consoleWidth = 0;
    _consoleHeight = 0;
  }

  void print(String line) {
    _lines.add(line);
    _consoleWidth = line.length > _consoleWidth ? line.length : _consoleWidth;
    _consoleHeight = _consoleHeight + 1;
  }

  @override
  void render(RenderState renderState) {
    if (_glyphs.isEmpty) return;

    dispatchEvent(Event('Update'));
    for (var y = 0; y < _consoleHeight; y++) {
      for (var x = 0; x < _consoleWidth; x++) {
        var index = x < _lines[y].length ? _lines[y].codeUnitAt(x) - 32 : 0;
        if (index < 0 || index >= 64) index = 0;
        _matrix.setTo(1.0, 0.0, 0.0, 1.0, x * 7, y * 14);
        renderState.push(_matrix, 1.0, .NORMAL);
        renderState.renderTextureQuad(_glyphs[index]);
        renderState.pop();
      }
    }
  }

  //----------------------------------------------------------------------------

  void _calculateGlyphs(BitmapData fontBitmapData) {
    fontBitmapData.renderTexture.filtering = .NEAREST;
    for (var i = 0; i < 64; i++) {
      final rectangle = Rectangle<int>(i * 7, 0, 7, 14);
      _glyphs.add(fontBitmapData.renderTextureQuad.cut(rectangle));
    }
  }

  String _formatMicroseconds(int microseconds) => (microseconds / 1000).toStringAsFixed(2);
}
