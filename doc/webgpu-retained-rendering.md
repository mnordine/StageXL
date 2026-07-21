# Retained rendering

StageXL scene extensions register a backend-neutral `RenderPipe` and identify it with a typed `RenderPipeId`. A pipe
receives a `RenderBuildContext`, which can add meshes, quads, masks, and child renderables but cannot access WebGL or
WebGPU systems. Registries belong to a renderer, not the process. Applications can install pipes through
`StageOptions.renderPipes`; self-contained extension objects can implement `RenderPipeProvider` to install their pipe
lazily into each renderer that encounters them.

Built-in bitmaps, display containers, bitmap containers, meshes, Scale9 bitmaps, viewport masks, Canvas shadow wrappers,
DOM overlays, and console glyphs use the same semantic collection API. Graphics and text still have an internal
`renderLegacy(RenderState)` compatibility path while their backend-specific operations are converted to instructions. It
is not the extension contract.

The frame is split into these phases:

1. `Stage` asks the render context to build a frame.
2. `RenderState` traverses visible display objects and dispatches them through `RenderPipeRegistry`.
3. Scene render pipes use `RenderBuildContext` to emit backend-neutral operations.
4. Instruction-builder pipes add or update typed retained slots and instructions in an `InstructionSet`.
5. Typed instruction pipes upload changed resources.
6. Instruction pipes execute the retained order through the selected backend.

Canvas2D and WebGL1/2 share a retained semantic command plan. Canvas2D's upload phase is intentionally empty. WebGL
replays the retained plan through its existing batch programs; moving its buffer writes completely into the upload phase
is still in progress. WebGPU uses specialized batch, mask, filter, projection, and render-group instruction pipes.

WebGPU batch, mask, and instruction systems are private backend details. StageXL_Spine now uses one render pipe for all
renderers, so its tinted meshes and clipping boundaries enter the instruction set in display-list order without a direct
batch-system compatibility hook.

## Structural validation

An instruction set is reused when its render roots, pipe IDs, explicit structure versions, instruction kinds,
mask/filter boundaries, resource identities, blend modes, and vertex/index counts still match. Transform, alpha, color
scale, tint, vertex values, index values, projection values, and explicit data versions update retained data without
rebuilding the instruction order.

`RenderDirtyState` keeps independent structure, transform, color, geometry, texture, blend, mask, and filter versions.
Versions are never globally cleared, so the same display object can be observed safely by multiple renderers or render
groups. Built-in transform, alpha, mask, filter, blend, bitmap texture, mesh geometry, and Scale9 mutations mark their
specific categories.

Visibility changes, child reordering, texture replacement, blend-mode changes, geometry resizing, filter topology
changes, and mask/filter/projection boundary changes rebuild only the affected retained instruction slots and batch run
plans. The private backing lists retain their capacity and expose only typed, active entries.

Mutable mask geometry is captured during traversal. This is required for renderers such as StageXL_Spine that reuse one
clipping-mask object for multiple slots before the retained instructions execute.

## Batching and uploads

Each retained batch instruction owns stable CPU arrays and WebGPU vertex/index buffers. A transform or color change only
marks vertex data dirty. Index data is uploaded independently when index values change. Dirty adjacent renderables are
coalesced into buffer ranges, so one changed item does not force a full-batch upload. Texture uploads and bind-group
refreshes happen during the upload phase before command encoding.

When `StageOptions.renderBundles` is enabled, stable batch instructions compile to render bundles after they have been
observed twice. Vertex or index data changes do not invalidate a bundle because its buffer identities and draw layout are
unchanged. Structural changes, buffer replacement, pipeline changes, or bind-group changes invalidate it.

## Render groups

Every independent render root has its own retained `InstructionSet`; the Stage and diagnostic console therefore behave as
implicit render groups. Set `DisplayObjectContainer.isRenderGroup` to retain a nested subtree independently. A nested
group is represented by an instruction in its parent's set, so masks, filters, projection changes, and sibling order stay
in the same execution timeline. A group's transform is retained on the group instruction and composed with the active
projection during execution. Moving a group therefore leaves descendant vertex buffers and render bundles unchanged.
Nested groups compose their local transforms recursively.
