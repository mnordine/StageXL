# Blend Mode Optimization Implementation

## Overview

This document describes the implementation of blend mode switching optimization in StageXL's `RenderProgramBatch` class. The optimization reduces redundant WebGL state changes and buffer uploads when rendering objects with different blend modes.

## Problem Statement

The original implementation had performance issues when switching between blend modes:

**Before (StageXL):**
```
blendFunc: ONE, ONE
bufferSubData: ELEMENT_ARRAY_BUFFER, 0, [..(6)..]
bufferSubData: ARRAY_BUFFER, 0, [..(36)..]
drawElements: TRIANGLES, 6 indices
blendFunc: ONE, ONE_MINUS_SRC_ALPHA
bufferSubData: ELEMENT_ARRAY_BUFFER, 0, [..(36)..]
bufferSubData: ARRAY_BUFFER, 0, [..(216)..]
drawElements: TRIANGLES, 36 indices
```

**After (Optimized like PixiJS):**
```
drawElements: TRIANGLES, 144 indices
blendFuncSeparate: DST_COLOR, ONE_MINUS_SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA
drawElements: TRIANGLES, 6 indices, offset: 288
blendFunc: ONE, ONE
drawElements: TRIANGLES, 6 indices, offset: 300
```

## Implementation Details

### New Components

#### 1. DrawCommand Class
```dart
class DrawCommand {
  final int indexCount;
  final int indexOffset;
  final BlendMode blendMode;
  final RenderTexture texture;
  final int textureIndex;
}
```

#### 2. Batching Infrastructure
- `_drawCommands`: List of draw commands to execute
- `_aggregateVertexData`: CPU-side vertex data buffer
- `_aggregateIndexData`: CPU-side index data buffer
- `_renderContextWebGL`: Reference to WebGL render context

### Algorithm Changes

#### Phase 1: Aggregate Geometry
1. During `renderTextureQuad()` and `renderTextureMesh()` calls:
   - Append vertex and index data to CPU-side lists
   - Calculate vertex offsets dynamically: `_aggregateVertexData.length ~/ 9`
   - Calculate index offsets: `_aggregateIndexData.length - indexCount`
   - Create `DrawCommand` objects with blend mode and texture info
   - No immediate GPU uploads

#### Phase 2: Optimized Upload and Draw
1. In `_executeBatchedCommands()`:
   - Upload all vertex and index data in single `bufferSubData` calls
   - Iterate through `DrawCommand` list
   - Only call `activateBlendMode()` when blend mode changes
   - Use `drawElements()` with calculated byte offsets

### Key Optimizations

#### Blend Mode Switching
```dart
BlendMode? currentBlendMode;
for (final command in _drawCommands) {
  // Only change blend mode if different
  if (!identical(command.blendMode, currentBlendMode)) {
    _renderContextWebGL!.activateBlendMode(command.blendMode);
    currentBlendMode = command.blendMode;
  }
  
  // Draw with offset
  renderingContext.drawElements(WebGL.TRIANGLES, command.indexCount, 
      WebGL.UNSIGNED_SHORT, command.indexOffset * 2);
}
```

#### Buffer Management
- **Before**: Multiple `bufferSubData` calls per object
- **After**: Single `bufferSubData` call per frame for all batched objects

#### Texture Activation
- Uses existing `activateRenderTextureAt()` method with caching
- Maintains texture slot management for multi-texturing

### Buffer Size Checks
```dart
// Check if we need to flush due to buffer size limits
if (!needsFlush && _aggregateIndexData.length + ixListCount >= renderBufferIndex.data.length) {
   needsFlush = true;
   textureIndex = 0;
}
```

### Flush Behavior
- **Immediate Mode**: Falls back to original `super.flush()` when no commands are batched
- **Batched Mode**: Executes `_executeBatchedCommands()` for optimized rendering
- **Cleanup**: Clears all aggregate data after each flush

## Performance Benefits

1. **Reduced GPU State Changes**: Blend modes only change when necessary
2. **Fewer Buffer Uploads**: Single upload per frame instead of per object
3. **Optimized Draw Calls**: Uses indexed drawing with offsets
4. **Better Batching**: More objects can be rendered in a single batch

## Compatibility

- Maintains full backward compatibility
- Works with existing texture management
- Supports both WebGL1 and WebGL2
- Integrates with existing VAO (Vertex Array Object) system

## Technical Notes

- Vertex stride remains 36 bytes (9 floats per vertex)
- Index offsets are calculated as byte offsets (`* 2` for 16-bit indices)
- Texture index management remains unchanged
- Automatic fallback to immediate mode when batching is not beneficial

## Future Considerations

- Could be extended to optimize texture switching in similar manner
- Potential for further batching of shader uniform changes
- Opportunity to implement instanced rendering for identical objects