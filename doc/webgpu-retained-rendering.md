# WebGPU retained rendering

StageXL keeps its `DisplayObject.render(RenderState)` extension point. The WebGPU backend records the low-level output of
that API instead of requiring display objects to implement backend-specific node types.

The frame is split into these phases:

1. `Stage` asks the render context to build a frame.
2. `RenderState` traverses visible display objects and reports them to the scene render pipe.
3. WebGPU render pipes add or update retained instructions in an `InstructionSet`.
4. Instruction pipes upload dirty buffers and textures.
5. Instruction pipes execute the retained order through WebGPU render passes.

WebGL and Canvas2D keep their immediate rendering behavior.

## Structural validation

An instruction set is reused when its render roots, instruction kinds, mask/filter boundaries, resource identities,
blend modes, and vertex/index counts still match. Transform, alpha, color scale, tint, vertex values, index values, and
projection values update retained data without rebuilding the instruction order.

Visibility changes, child reordering, texture replacement, blend-mode changes, geometry resizing, filter topology
changes, and mask/filter/projection boundary changes rebuild only the affected retained instruction slots and batch run
plans. The backing instruction and renderable lists retain their capacity.

## Batching and uploads

Each retained batch instruction owns stable CPU arrays and WebGPU vertex/index buffers. A transform or color change only
marks vertex data dirty. Index data is uploaded independently when index values change. Texture uploads and bind-group
refreshes happen during the upload phase before command encoding.

When `StageOptions.renderBundles` is enabled, stable batch instructions compile to render bundles after they have been
observed twice. Vertex or index data changes do not invalidate a bundle because its buffer identities and draw layout are
unchanged. Structural changes, buffer replacement, pipeline changes, or bind-group changes invalidate it.

## Render groups

Every independent render root has its own retained `InstructionSet`; the Stage and diagnostic console therefore behave as
implicit render groups. Nested public render groups are intentionally deferred. Filters and masks can switch render
targets, so nested groups need explicit render-target and effect ownership before their instruction sets can be safely
cached or bundled independently.
