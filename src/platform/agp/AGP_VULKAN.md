# AGP Vulkan Backend (`arcan-vk`)

Pure Vulkan replacement for the GL21 AGP backend. Runs durian and all appls
without any OpenGL dependency.

**See also:** [VK LWA nested compositor docs](../vk-lwa/ZIG.md)

## Build & Run

**Always build in Debug mode** (the default) until ready to push. Debug mode enables
Zig's UBSan for C code, catching undefined behavior (inf→int casts, signed overflow,
null derefs) that Release silently ignores.

```bash
# Build (Debug mode — default, keep it this way)
zig build arcan-vk -Dbuild_arcan_vk=true -Dwith_ffmpeg=false -Dbuild_a12=false

# Run — must cd into zig-out/bin/ so arcan finds sidecar binaries
# (arcan_frameserver, afsrv_terminal, etc.) in the same directory.
cd zig-out/bin/

# Run with welcome (basic rendering test)
./arcan_vk -w 800 -h 600 welcome

# Run with durian (full compositor test — custom shaders, RTs, stencil)
# Only env var needed is the path to durian's appl directory.
ARCAN_APPLBASEPATH=/home/x/test/durian ./arcan_vk -w 800 -h 600 durian

# Direct-to-display (TTY, no X/Wayland — uses VK_KHR_display)
# Automatically selected when DISPLAY is not set
```

**Important**: Run from `./zig-out/bin/` (not the repo root). Arcan discovers
sidecar binaries (`arcan_frameserver`, `afsrv_terminal`, etc.) relative to its
own executable path. No `ARCAN_RESOURCEPATH`, `ARCAN_STATEBASEPATH`, or other
env vars are needed — arcan resolves namespace paths from the install prefix
(which `zig build` sets to `zig-out/`). The only env var you may need is
`ARCAN_APPLBASEPATH` to point at durian (or another appl directory outside the
default search path).

When `DISPLAY` is set, creates an XCB window with `VK_KHR_xcb_surface`.
Otherwise falls back to `VK_KHR_display` for direct-to-display rendering.

## Dependencies

- `vulkan-devel` — Vulkan headers + loader
- `libdrm-devel` — for psep_open.c (shared with EGL-DRI)
- `libshaderc-devel` — runtime GLSL→SPIR-V (dlopen'd, graceful fallback)
- `libxcb-devel` — XCB windowed surface (optional, only for windowed mode)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ video.zig (platform)                                        │
│   Display enum, mode selection, synch loop, composite       │
│   XCB window management, ortho projection                   │
├─────────────────────────────────────────────────────────────┤
│ vk_wsi.zig (WSI)          │ vk_xcb.zig (XCB)               │
│   VK_KHR_display           │  VK_KHR_xcb_surface            │
│   Swapchain, present       │  Window create/resize/events    │
├────────────────────────────┴────────────────────────────────┤
│ vk.zig (AGP core)                                           │
│   VkEnv struct, Vulkan init, device/queue/memory            │
│   Texture management (create/update/destroy/bind)           │
│   Pipeline creation, vertex buffer ring, draw dispatch      │
│   Stencil/depth image, readback, descriptor sets            │
│   Bridge export functions for standalone objects             │
├─────────────────────────────────────────────────────────────┤
│ vk_shared.zig (standalone)  │ vk_shdrmgmt.zig (standalone)  │
│   Rendertarget management    │  Push constants cache          │
│   vstore create/update/drop  │  Shader compile (shaderc)      │
│   agp_draw_vobj / mesh       │  SPIR-V reflection + UBO       │
│   Blend, stencil, dirty      │  Uniform groups + activate     │
└──────────────────────────────┴──────────────────────────────┘
```

### Module vs Object Pattern

`vk.zig` and `vk_wsi.zig` are **Zig modules** imported by `video.zig`.
`vk_shared.zig` and `vk_shdrmgmt.zig` are **standalone objects** (no vulkan-zig
module). They communicate with `vk.zig` via `extern fn` / `export fn` bridge.

## Files

| File | Purpose |
|------|---------|
| `vk.zig` | Core VkEnv, pipeline, draw, bridge exports, readback, stencil/depth |
| `vk_shared.zig` | Rendertarget, vstore, draw_vobj, mesh, stencil, blend, dirty |
| `vk_shdrmgmt.zig` | Shader compilation (shaderc), SPIR-V reflection, uniform management |
| `vk_wsi.zig` | VK_KHR_display WSI: display enum, surface, swapchain, frame begin/end |
| `vk_xcb.zig` | VK_KHR_xcb_surface WSI: XCB window, surface, event polling |
| `vk_offscreen.zig` | Offscreen render target for LWA (no swapchain, staging readback) |
| `shaders/` | GLSL 450 sources + compiled .spv (basic_2d, color_2d) |
| `../vk-display/video.zig` | Platform video: display enum, mode selection, synch loop |
| `../vk-lwa/video.zig` | LWA platform: shmif client, offscreen render, pixel copy to parent |

## Phase Status

| Phase | Status | What |
|-------|--------|------|
| 1 | **DONE** | Clear screen — init, display enum, swapchain, clear color |
| 2 | **DONE** | Textures + SPIR-V shaders + basic 2D rendering + world composite |
| 3 | **DONE** | Streaming (all modes) + cursor drawing + rendertarget alloc/activate/clear |
| 4 | **DONE** | Custom shaders (GLSL preprocessor + shaderc) + single cmd buffer + stencil |
| 4b | **FIXED** | Durian no_stdout composite: world_rt tracking + viewport flip + depth clamping |
| 4b-input | **WIP** | XCB windowed input: mouse works, keyboard keysym translation (X11→SDL1.2) in progress |
| 4c | **WIP** | Vulkan LWA nested compositor (offscreen render + shmif) |
| 5 | **DONE** | DMA-BUF import (VK_EXT_external_memory_dma_buf) |

---

## Key Design Decisions

### Negative Viewport Height (Y-flip)

GL clip space: Y goes UP. Vulkan clip space: Y goes DOWN. The engine builds
GL-style orthographic projections → content renders upside down without correction.

Fix: Vulkan 1.1+ negative viewport height at both draw locations:
```zig
.y = height, .height = -height
```

The ortho projection also swaps bottom/top (`bottom=h, top=0`) to complete the
coordinate system match. No engine changes needed.

### Per-RT Viewport/Scissor

GL enables `GL_SCISSOR_TEST` globally and sets per-RT viewport + scissor in
`agp_activate_rendertarget` (glshared.c:1113-1115):
```c
ssize_t* vp = tgt->viewport;
env->scissor(vp[0], vp[1], vp[2], vp[3]);
env->viewport(vp[0], vp[1], vp[2], vp[3]);
```

The viewport values come from `agp_rendertarget_viewport(art, x, y, x+view_w, y+view_h)`
(arcan_lua.c:1407). In practice x/y are typically 0, so vp[2]=width, vp[3]=height.

VK implementation: `vk_env_set_rt_viewport()` bridge stores the 4 values.
`vk_env_draw_quad()` uses them for `cmdSetViewport` + `cmdSetScissor`. Without
this, all draws use the full RT extent — content bleeds across tile boundaries
(BUG-9).

### Per-RT Alpha Blend Factors

GL sets different alpha blend factors per-RT based on `RENDERTARGET_RETAIN_ALPHA`
(mode flag 16) in `agp_activate_rendertarget` (glshared.c:1058-1075):
```c
// Without RETAIN_ALPHA: additive alpha
env->blend_src_alpha = GL_ONE;
env->blend_dst_alpha = GL_ONE;
// With RETAIN_ALPHA: standard alpha
env->blend_src_alpha = GL_SRC_ALPHA;
env->blend_dst_alpha = GL_ONE_MINUS_SRC_ALPHA;
```

These alpha factors are used in `blend_func_separate()` for ALL blend modes.

VK implementation: `vk_env_set_blend_alpha(retain_alpha)` bridge sets
`env.blend_src_alpha` / `env.blend_dst_alpha`. `getBlendEquation()` reads them
instead of hardcoding `.one` / `.one_minus_src_alpha`.

### Depth Clamping

The engine uses GL-style projection matrices with depth range [-1, 1], but Vulkan
clips primitives to z in [0, w]. Without depth clamping, ALL 2D geometry (z_clip = -1)
gets clipped away. Fix: enable `depthClamp` device feature + `depth_clamp_enable = .true`
in the rasterizer.

### no_stdout Composite (Durian)

Durian calls `delete_image(WORLDID)` → `arcan_video_disable_worldid()` →
`stdoutp.art = NULL` and `no_stdout = true`.

In GL: `agp_activate_rendertarget(NULL)` binds FBO 0 (the screen), so workspace
content renders directly to the display.

In VK: no FBO 0. The composite code falls back through:
1. World RT's backing store (normal mode)
2. `vk_last_rendered_vstore()` — the workspace RT tracked by vk_shared.zig
3. World vobj's vstore (stale fallback)

### Single Command Buffer Architecture

One command buffer per frame shared across all RT passes and swapchain composite:

```
vk_env_begin_frame_cmd()     ← wait fence, reset cmd, begin recording
  arcan_vint_refresh()        ← engine: world RT → child RTs → world RT
    vk_env_begin_rt_pass()    ← transition image, begin rendering
    agp_draw_vobj() ...       ← record draws
    vk_env_end_rt_pass()      ← end rendering, transition back
  vk_wsi.beginFrame()         ← acquire swapchain image, begin rendering
  [composite draw]            ← fullscreen textured quad
  vk_wsi.endFrame()           ← end rendering, submit cmd, present
```

### EDS3 Dynamic State

With `VK_EXT_extended_dynamic_state3`, blend mode, color write mask, depth,
stencil, and cull mode are ALL dynamic state. One pipeline per shader/format pair,
per-draw-call state via `cmdSet*` commands.

---

## Runtime GLSL→SPIR-V Compilation

Durian defines ~48 shaders in GL2.1 GLSL. The Vulkan backend compiles them at
runtime via `libshaderc` (dlopen'd):

```
durian's GL2.1 GLSL → agp_shader_build() → preprocessor → shaderc → SPIR-V → VkPipeline
                                                                       ↓
                                                                 SPIR-V reflection → UBO layout
```

### GLSL Preprocessor (vk_shdrmgmt.zig)

Two-pass preprocessor translates GLSL 1.20 → 4.50:
- Pass 1: Parse declarations (attributes, varyings, uniform samplers, uniform scalars)
- Pass 2: Emit `#version 450`, layout qualifiers, UBO block, `gl_FragColor→_fragColor`

**CRITICAL**: shaderc compiled with strict Vulkan 1.3 target (NOT relaxed mode —
AGX driver crashes with relaxed SPIR-V).

### SPIR-V Reflection

Parses SPIR-V binary to extract auto-generated UBO layout:
- `OpDecorate ... Block` → UBO struct type
- `OpMemberDecorate ... Offset` → std140 byte offsets
- `OpMemberName` → member name strings
- `OpTypeFloat/Int/Vector/Matrix` → member sizes

Maps engine uniform names (`modelview`, `projection`, `obj_opacity`) to UBO offsets.

### Descriptor Set Layout (3 bindings)

| Binding | Type | Usage |
|---------|------|-------|
| 0 | combined_image_sampler | map_tu0 / map_diffuse |
| 1 | uniform_buffer_dynamic | custom shader UBO |
| 2 | combined_image_sampler | map_tu1, optional |

**ALL 3 bindings must be initialized** in every descriptor set (Asahi AGX crashes
on uninitialized descriptors). Dummy UBO buffer + dummy sampler for unused bindings.

### Uniform Paths

- **Built-in shaders** (slots 0, 1): Push constants (248 bytes)
- **Custom shaders** (slots 2+): UBO with dynamic offset per uniform group

### Shader ID Encoding (matches GL backend)

```
bits [0:15]  = slot index (0–65535)
bits [16:31] = group index (0–65535)
```

---

## Blend Mode Table (matches GL glshared.c)

| Mode | blend_en | src_color | dst_color | color_op | src_alpha | dst_alpha |
|------|----------|-----------|-----------|----------|-----------|-----------|
| NONE | false | one | zero | add | one | zero |
| NORMAL | true | src_alpha | 1-src_alpha | add | *per-RT* | *per-RT* |
| ADD | true | one | one | add | *per-RT* | *per-RT* |
| MULTIPLY | true | dst_color | 1-src_alpha | add | *per-RT* | *per-RT* |
| SUB | true | one | 1-src_alpha | reverse_sub | *per-RT* | *per-RT* |
| PREMUL | true | one | 1-src_alpha | add | *per-RT* | *per-RT* |

*per-RT* alpha factors: `ONE/ONE` (additive, default) or `SRC_ALPHA/ONE_MINUS_SRC_ALPHA`
(when `RENDERTARGET_RETAIN_ALPHA` flag is set on the RT).

## Stencil Flow

```
agp_prepare_stencil()   → stencil test ON, writes 1, color writes OFF
agp_draw_stencil()      → draws clipping quad
agp_activate_stencil()  → stencil test EQUAL/1, color writes ON
[draw content]          → visible only inside stencil mask
agp_disable_stencil()   → stencil OFF
```

Stencil image: `VK_FORMAT_S8_UINT`, created lazily. No extra pipeline variants.

## Async Readback (Double-Buffered)

Two staging buffers with separate fences (ping-pong):
- `agp_request_readback()` → copies texture to staging, signals fence
- `agp_poll_readback()` → polls previous fence, returns mapped pointer if ready

---

## Bridge Functions (vk.zig exports)

| Function | Purpose |
|----------|---------|
| `vk_env_create_texture` | Create VkImage + ImageView + descriptor set |
| `vk_env_update_texture` | Staging buffer upload |
| `vk_env_update_texture_sub` | Sub-region upload (handles stride != w*4) |
| `vk_env_destroy_texture` | Free GPU resources |
| `vk_env_bind_texture` | Set active texture for next draw |
| `vk_env_draw_quad` | Copy verts to ring buffer, cmdDraw |
| `vk_env_draw_mesh_verts` | Draw mesh vertices (triangle soup) |
| `vk_env_set_blend_mode` | Store blend mode |
| `vk_env_set_blend_alpha` | Per-RT alpha blend factors (RETAIN_ALPHA flag) |
| `vk_env_set_rt_viewport` | Per-RT viewport/scissor rect |
| `vk_env_bind_pipeline` | 0=basic_2d, 1=color_2d |
| `vk_env_push_constants` | memcpy 248-byte push constants |
| `vk_env_is_rendering` | true between beginFrame/endFrame |
| `vk_env_set_rendering_active` | Called by video.zig |
| `vk_env_set_swapchain_extent` | For viewport/scissor |
| `vk_env_begin_frame_cmd` | Wait fence, reset cmd, begin recording |
| `vk_env_submit_empty_frame` | Submit trivial cmd (skip-frame path) |
| `vk_env_begin_rt_pass` | Start offscreen RT rendering |
| `vk_env_end_rt_pass` | End offscreen RT rendering |
| `vk_env_create_shader_module` | Create VkShaderModule from SPIR-V |
| `vk_env_create_custom_pipeline` | Create VkPipeline from vert+frag modules |
| `vk_env_create_ubo` | Create UBO buffer + descriptor set |
| `vk_env_bind_custom_shader` | Bind pipeline + UBO with dynamic offset |
| `vk_env_readback_texture` | Synchronous readback to CPU buffer |
| `vk_env_import_dmabuf_texture` | Import DMA-BUF fd as VkImage texture |

## vulkan-zig Patterns

### Wrapper vs Dispatch
Use `vk.BaseWrapper`, `vk.InstanceWrapper`, `vk.DeviceWrapper` (convenience methods),
NOT the raw Dispatch types.

### Bool32
`.true` / `.false` (enum variants), NOT `vk.TRUE` / `vk.FALSE` (comptime_int).

### Create info pointers
Wrapper methods take `*const T` → use `&.{...}` not `.{...}`.

### Flags (packed struct)
`VK_STENCIL_FACE_FRONT_AND_BACK` → `.{ .front_bit = true, .back_bit = true }` (NOT `.front_and_back`)

### API Version
No `vk.API_VERSION_1_4`. Use `@bitCast(vk.makeApiVersion(0, 1, 4, 0))`.

### Required fields (no defaults in extern struct)
Many Vulkan structs need explicit initialization:
- `ImageMemoryBarrier2`: `.src_queue_family_index`, `.dst_queue_family_index`
- `RenderingAttachmentInfo`: `.resolve_mode = .{}`, `.resolve_image_layout = .undefined`
- `RenderingInfo`: `.view_mask = 0`
- `GraphicsPipelineCreateInfo`: `.base_pipeline_index = -1`

---

## Zig 0.15 Notes

- `alignedAlloc`: alignment is `?mem.Alignment` enum, use `.@"4"` not `@alignOf(u32)`
- Array-of-structs default init: `[_]MyStruct{.{}} ** N`
- `@intFromEnum` on vulkan-zig Format returns `i32`; cast via `@bitCast`
- `PipelineStageFlags2`: use `.all_transfer_bit` (not `.transfer_bit`)
- ShadercFns function pointers need `callconv(.c)` on aarch64

## Fixed: Durian All-Gray Regression (Phase 4b)

**Symptom**: Durian rendered all-gray. Shaders compiled OK, process ran, but
composite drew nothing visible.

**Root cause**: `world_rt` tracking in vk_shared.zig only set `world_rt` to the
first RT created (`agp_setup_rendertarget`). Durian's `delete_image(WORLDID)` →
`agp_drop_rendertarget` nulled it. No new setup calls → `vk_last_rendered_vstore()`
returned null → gray screen.

**Fix**: `agp_activate_rendertarget()` now always updates `world_rt` when a non-null
RT is activated, so it tracks the latest workspace RT.

**Additional fixes in same round**:
- **Viewport flip**: Negative viewport height only during RT passes (for GL Y-flip
  compat). Swapchain composite uses standard viewport — RT content is already in VK
  orientation. Previously both paths used negative viewport → double-flip → upside down.
- **XCB input**: `vk_xcb.zig` now buffers keyboard/mouse events from XCB, translates
  modifiers via xkbcommon, and `video.zig` bridges them to arcan_event structs.
- **xkbcommon init**: Uses `XKB_CONTEXT_NO_DEFAULT_INCLUDES` + explicit
  `/usr/share/X11/xkb` path to avoid Zig package cache path issue.
- **Keysym translation**: `xkbToSdl12()` converts X11 keysyms to SDL 1.2 format
  (arcan's keyboard.lua expects SDL 1.2 values).

## Bug Log

### BUG-1: RT draws invisible (statusbar + workspace content)

**Symptom**: In durian no_stdout mode, rendertarget content (statusbar, workspace) is
invisible when composited to the swapchain. Only cursor and popup menus (drawn directly
in the swapchain pass) render. The statusbar RT receives 13+ draw calls per frame but
ALL produce no visible output — readback shows only clear color.

**Root causes** (three bugs, all contributing):

**1. UBO descriptor binding mismatch (PRIMARY — why custom shader draws are invisible)**

The descriptor set layout is fixed: binding 0 = sampler, binding 1 = UBO, binding 2 = sampler.
The GLSL preprocessor (`preprocessGlsl`) uses an auto-incrementing `binding` counter.
Samplers get bindings first, then UBO gets the next binding.

For shaders WITH a sampler (e.g. `uniform sampler2D map_diffuse`):
sampler → binding 0, UBO → binding 1. Matches descriptor set. Works.

For shaders WITHOUT any sampler (e.g. `ui_statusbar` with only `uniform vec4 col`):
No sampler emitted, binding stays at 0. UBO → binding 0. WRONG — descriptor set has
sampler at 0, UBO at 1. Shader reads image descriptor data as UBO → garbage → invisible.

Most durian UI shaders (statusbar, sbar_item, dropshadow, etc.) have NO sampler,
so they ALL get binding 0 for the UBO and read garbage.

**Fix**: `if (binding < 1) binding = 1;` after the sampler emission loop in
`preprocessGlsl` (vk_shdrmgmt.zig). UBO is now always at binding 1.

**2. Vertex/fragment UBO layout conflict (fixed with push_constant)**

The preprocessor ran independently on vertex and fragment, generating incompatible UBO
blocks at the same binding. Vertex expected {mat4 modelview, mat4 projection}, fragment
expected {float obj_opacity, vec3 col}. Vertex read fragment data as matrices.

**Fix**: Vertex shader engine matrices now use `layout(push_constant)`, fragment keeps
all uniforms in UBO. No binding conflict.

**3. Pipeline depth/stencil format mismatch**

`createGraphicsPipeline()` hardcoded `depth_attachment_format = .d32_sfloat` and
`stencil_attachment_format = .s8_uint` in `PipelineRenderingCreateInfo`. But RT passes
(and swapchain passes) pass `p_depth_attachment = null` when `depth_active == false`.

Per Vulkan spec §8.3: *"If pDepthAttachment is NULL or its imageView is VK_NULL_HANDLE,
the pipeline's depthAttachmentFormat must be VK_FORMAT_UNDEFINED."*

Both swapchain and RT violated this. Swapchain draws worked anyway (driver leniency
for SRGB format on Asahi AGX). RT draws with UNORM pipelines silently failed.

**Fix**: Pass depth/stencil format as parameters to `createGraphicsPipeline()`:
- SRGB pipelines (swapchain): keep `.d32_sfloat` / `.s8_uint` (works on Asahi)
- UNORM pipelines (RT): use `.undefined` / `.undefined`
- Custom pipelines: use `.undefined` / `.undefined`

**Key insight**: Asahi AGX driver is strict about pipeline format compliance for
B8G8R8A8_UNORM but lenient for B8G8R8A8_SRGB. Both violate the spec but only UNORM
silently fails.

### BUG-2: Terminal launches but content not visible

**Symptom**: afsrv_terminal launches and streams frames, but the window shows black
(no text characters visible). Durian UI chrome (statusbar, borders) renders, but
frameserver client content does not appear.

**Root cause**: Same as BUG-1 — pipeline depth/stencil format mismatch. Terminal
texture is drawn into a workspace RT (UNORM format). The UNORM pipeline's hardcoded
`.d32_sfloat` / `.s8_uint` depth/stencil formats cause the draw to be silently
discarded by the Asahi AGX driver.

**Fix**: Same as BUG-1 — UNORM pipelines now use `.undefined` depth/stencil format.

**Durian META key issue**: Default META1 is `MENU` (SDL keysym 319). On Mac keyboards
via Xwayland, the MENU key doesn't exist. Workaround: edit `durian/keybindings.lua`,
change `["meta_1"] = "MENU"` to `["meta_1"] = "LCTRL"` or `["meta_1"] = "LSUPER"`.

### BUG-3 (FIXED): UBSan crash — scaleimage2 inf→int

**Symptom**: Crash in `arcan_lua.c:1528` — `inf is outside the range of representable
values of type 'int'` during durian `clock_pulse`.

**Root cause**: Durian Lua layout computes infinity (div by zero), passes to
`resize_image()`. UB in Release, caught by Debug UBSan.

**Fix**: `isfinite()` guard in `arcan_lua.c:scaleimage2`.

### BUG-4 (FIXED): TUI raster null pointer (vinf.text.raw)

**Symptom**: Crash in `arcan_raster.c:57` (`draw_box_px`) — null pointer when
rasterizing terminal text.

**Root cause**: VK `agp_resize_vstore` delegated to `agp_empty_vstore` which frees
`vinf.text.raw`. GL backend keeps it allocated. Engine's `tui_raster_renderagp` writes
pixels into this buffer.

**Fix**: Rewrote `agp_resize_vstore` to keep `vinf.text.raw` allocated.

### BUG-5 (FIXED): Attribute location swap — invisible custom shader draws

**Symptom**: ALL custom shader draws (ui_statusbar, ui_sbar_item, dropshadow, etc.)
execute but produce no visible change to the framebuffer. Built-in pipeline draws
(basic_2d, color_2d) work fine. Readback shows only clear color (30,30,30).

**Root cause**: The GLSL preprocessor (`preprocessGlsl`) assigned `layout(location=N)`
to vertex attributes based on **declaration order**, not semantic meaning. The default
vertex shader declares `texcoord` before `vertex`:
```glsl
attribute vec2 texcoord;   // parsed first → got location 0
attribute vec4 vertex;     // parsed second → got location 1
```
But the pipeline vertex input layout expects location 0 = position, location 1 = UV.
Result: the shader read UV data as position and position as UV.

**Fix**: Semantic location assignment in `preprocessGlsl`: `"vertex"` → location 0,
`"texcoord"` → location 1, others → incrementing from 2.

### BUG-6 (FIXED): UBO descriptor range violation for gid > 0

**Symptom**: Custom shader draws with non-zero uniform group index (gid > 0) may be
silently discarded. Each durian statusbar item uses a different group with its own color.

**Root cause**: `vk_env_create_ubo` set the descriptor `range = total_ubo_size`
(stride × MAX_GROUPS). Per Vulkan spec, for dynamic UBO:
`effective_offset + range ≤ buffer_size`. For gid > 0:
`gid*stride + total_size > total_size` — spec violation.

**Fix**: Descriptor range set to `stride` (one group's worth of data).

### BUG-7 (FIXED): Diagnostic white rectangle artifact

**Symptom**: White 50x50 rectangle at (10,10) drawn over the composited scene for the
first 60 frames. Added as a diagnostic draw.

**Fix**: Removed the diagnostic draw block from video.zig.

### BUG-8 (INVESTIGATE): Statusbar text black rectangles

**Symptom**: Statusbar items render as black rectangles instead of readable text.

**Hypothesis**: (a) Per-RT scissor/viewport not applied — text clipped wrong,
(b) alpha blend factors wrong — text alpha not composited correctly,
(c) crop shader UV uniforms not synced to UBO correctly.

### BUG-9 (INVESTIGATE): Content duplication in tiled layout

**Symptom**: Two terminal panes show identical content when only one terminal was opened.

**Hypothesis**: Without per-RT scissor, content bleeds across tile boundaries — both tile
positions show the full texture instead of being clipped. The viewport/scissor fix should
resolve this.

### BUG-10 (VERIFIED OK): Frame update / fence handling

Frame updates work correctly when content is dirty (nd > 0).

## Runtime Notes

**Run from `zig-out/bin/`**: Arcan finds sidecar binaries (arcan_frameserver, afsrv_*)
relative to its own executable path. Running from `zig-out/bin/` means they're in the
same directory and are discovered automatically. No `ARCAN_BINPATH` needed.

**Buffer delivery**: All built-in frameservers use shared memory CPU pixels
(STREAM_RAW_DIRECT). None use DMA-BUF. The Phase 5 DMA-BUF import is only exercised
by arcan-wayland bridged clients that call `arcan_shmif_signalhandle()`.

## Phase 5: DMA-BUF Import (DONE)

Import DMA-BUF file descriptors as Vulkan textures via `VK_EXT_external_memory_dma_buf`.

**Extensions** (confirmed on Asahi AGX Honeykrisp, Vulkan 1.4.318):
`VK_KHR_external_memory_fd`, `VK_EXT_external_memory_dma_buf`

**Import sequence:**
1. `getMemoryFdPropertiesKHR(.dma_buf_bit_ext, fd)` → memory type bits
2. `createImage` with `ExternalMemoryImageCreateInfo` pNext, `.linear` tiling
3. `allocateMemory` with `ImportMemoryFdInfoKHR` pNext — Vulkan takes fd ownership
4. `bindImageMemory` → `createImageView` → descriptor set (all 3 bindings for Asahi)
5. Transition to `shader_read_only_optimal`

**Error handling:** `errdefer` chain cleans up in reverse. After `allocateMemory` succeeds,
fd is owned by Vulkan; before that, caller retains ownership.

**DRM format mapping:**

| DRM fourcc | VkFormat |
|-----------|----------|
| `ARGB8888` / `XRGB8888` | `.b8g8r8a8_unorm` |
| `ABGR8888` / `XBGR8888` | `.r8g8b8a8_unorm` |

## Screenshot Tooling

- `scrot` (X11) cannot capture Vulkan surfaces through Xwayland — always black
- `spectacle` (KDE Wayland) captures Vulkan content correctly at compositor level
- `save_screenshot()` Lua API → `agp_save_output()` → staging buffer readback of last presented swapchain image

### BUG-S4 (FIXED): Statusbar text/icons — R8G8B8A8 format + raw buffer preserve

**Symptom**: Statusbar text and icon rendering produced wrong colors or garbled pixels.

**Root cause**: Two issues — (1) TUI raster output is R8G8B8A8 but texture format assumed
B8G8R8A8 swizzle. (2) `agp_resize_vstore` freed `vinf.text.raw` buffer that TUI raster
needs to write into.

**Fix**: Use R8G8B8A8_UNORM for TUI textures, preserve raw buffer in resize.

### BUG-S5 (FIXED): Mouse coordinates wrong after XCB window resize

**Symptom**: After maximizing or resizing the XCB window, mouse clicks landed at wrong
positions (offset/scaled incorrectly).

**Root cause**: Mouse coords from XCB are in window space (e.g., 3024x1710 after maximize)
but arcan canvas stays at original size (e.g., 1600x1200). No coordinate scaling.

**Fix**: Scale mouse coordinates from XCB window space to canvas space:
`canvas_x = xcb_x * canvasw / windoww` in `processXcbInput`.

### BUG-S6 (FIXED): Garbled terminal icon — GPU use-after-free in out-of-frame RT

**Symptom**: Terminal icon in durian statusbar was garbled — magenta + SPIR-V text
fragments in readback data. Circle icons (destroy/minimize/maximize) rendered correctly.

**Root cause**: GPU use-after-free during out-of-frame render-to-texture.
`arcan_video_resampleobject()` creates an RT, renders the source texture onto it via
`forceupdate`, then calls `deleteobject(dst)` which cascades to destroy the source
texture (e.g., tex=37). `vk_env_destroy_texture(37)` frees VkImageView/VkImage/VkDeviceMemory
while `env.cmd` still has pending draw commands referencing tex=37's descriptor set. When
env.cmd is eventually submitted (in the readback function), the GPU reads freed memory →
undefined behavior.

**Why circles worked**: They're synthesized on-demand during frame rendering (normal cmd
flow, no intermediate texture destruction). Terminal icon synthesis from PNG files triggers
`resample_image` during Lua init (out-of-frame), where the source is destroyed before submit.

**TDD approach used** (9 diagnostic steps):
1. Green clear color → clear didn't show up → rendering pass not executing?
2. 0xAA staging buffer fill → overwritten → copy DID execute, data = SPIR-V text fragments
3. undefined old_layout for first-use → still garbage
4. VkImage handle logging → handles matched (same image, correct target)
5. Direct cmdClearColorImage via upload_cmd → CYAN → image CAN be written to
6. cmdClearColorImage via env.cmd → ZEROS → env.cmd seemed broken?
7. Split env.cmd + immediate readback → YELLOW after split → env.cmd CAN write
8. Added destroy/update texture logging → found tex=37 DESTROYED before env.cmd flush
9. Root cause confirmed: destroy before submit = use-after-free

**Fix** (`vk_env_destroy_texture` in vk.zig): If `env.cmd_recording` is true, flush the
command buffer (end RT pass if active → end cmd → submit with upload_fence → wait) before
destroying texture resources.

**Also fixed**: Staging buffer missing `transfer_dst_bit` (needed for `cmdCopyImageToBuffer`
in readback path — buffer was created with only `transfer_src_bit`).

### BUG-S7 (KNOWN): XCB resize is Xwayland-scaled, not actual resize

**Symptom**: When the XCB window is maximized or resized by the Wayland compositor, the
content appears blurry/upscaled. XCB `CONFIGURE_NOTIFY` still reports the original size
(e.g., 1600x1200) even though `xwininfo` shows the actual display size (e.g., 3024x1710).

**Root cause**: Xwayland scaling. The Wayland compositor (KDE/Kwin) scales the X11 surface
to fill the maximized area at the compositor level. The XCB window buffer stays at its
original resolution — the compositor just bilinear-upscales it. XCB never receives a
configure notify with the actual display dimensions.

**Workaround**: Launch arcan_vk at native screen resolution (`-w 3024 -h 1890`) so there's
no upscaling needed. The `-w`/`-h` values are cached in arcan's database per-appl, so only
needed on first run.

**Proper fix (TODO)**: Would need Xwayland `wp_viewport` awareness or Wayland native surface
(not XCB) to get true surface dimensions. Alternatively, detect screen DPI / scale factor
from XCB screen properties and auto-select window size.

### BUG-S8 (FIXED): Text replaced by white rectangles after redraws

**Symptom**: All places with text (workspace buttons, statusbar labels, terminal content)
progressively turn into solid white rectangles after a few redraws. Initially text renders
correctly, then gets replaced by white squares. Affects all text at all resolutions.

**Repro**: Open durian menu (Global → navigate) 2-3 times. After that, text across the
entire UI progressively turns white.

**Root cause**: Texture slot exhaustion. `next_texture_id` was a monotonically incrementing
counter (1, 2, 3, ... 255). When durian destroyed a text texture (menu close, text change),
the slot was freed (`slot.* = .{}`) but the ID was never recycled. After ~255 texture
create/destroy cycles (which happens fast during menu navigation), `next_texture_id` hit
`MAX_TEXTURES` (256). Every new texture allocation returned ID 0 — the default 1x1 white
pixel texture. So all new text rendered as solid white rectangles, progressively worse as
old textures aged out.

**Fix**: Added `findFreeTextureSlot()` in vk.zig — tries fast sequential path first, then
scans for freed slots (where `in_use == false`). Both `vk_env_create_texture` and
`vk_env_import_dmabuf_texture` now use it.

**Secondary fix**: Added `cmd_recording` guard to `vk_env_update_texture` when texture
dimensions change (same use-after-free pattern as BUG-S6's destroy fix). Previously only
`vk_env_destroy_texture` had this guard.

### BUG-S9 (INVESTIGATE): Top bar not at top of window

**Symptom**: Durian's statusbar/HUD bar doesn't reach the top edge of the XCB window.
There is a visible black gap at the top of the window. Content renders correctly but is
shifted down or the canvas is shorter than the window.

**Observed dimensions**:
- Requested: `-w 3024 -h 1890`
- XCB screen reports: 3024x1890 px
- Swapchain created at: 3024x1710 (XCB constrains, 180px less = KDE panel)
- Canvas set to: 3024x1710 (from swapchain extent)
- Resize event fires: `swapchain 3024x1710, canvas stays 3024x1710 (scaled)`
- VRESW/VRESH: should be 3024x1710 (from `platform_video_dimensions()`)
- Composite source: `last-rendered RT (glid=48)` instead of screen composite

**Investigation plan**:

1. **Check initial swapchain extent vs canvas**: The XCB window is created at 3024x1890
   (requested size). But `caps.current_extent` may return 3024x1890 initially (before the
   compositor constrains it). So the initial canvas might be 1890, then the resize handler
   fires but doesn't update canvas. Verify by logging `state.canvasw/canvash` before and
   after the resize handler.

2. **Check composite source**: Log says `using last-rendered RT (glid=48)` — this means
   `vk_screen_composite_vstore()` returned NULL on those frames. If the screen composite
   isn't being used, the world scene graph may be drawn at the wrong resolution. Check why
   screen composite returns null and whether `last-rendered RT (glid=48)` has the right
   dimensions.

3. **Check projection/viewport mismatch**: If the orthographic projection was built with
   canvas height=1890 but the swapchain is 1710, the quad from (0,0) to (3024,1890) maps
   into a larger clip space than the viewport can show → bottom is clipped, top has gap.
   Verify `state.projection` is rebuilt after resize.

4. **Check `vk_shared_set_screen_size` on resize**: This updates the screen composite
   texture size. If it's called with 3024x1710 but the canvas/projection is still 1890,
   there's a dimension mismatch. The screen composite texture is smaller than what the
   engine draws into it.

5. **Key test**: Launch with `-w 3024 -h 1710` (matching actual window after constraint)
   to see if the gap disappears. If yes, confirms the issue is a transient mismatch between
   the initial requested size and the final constrained size.

6. **Proper fix direction**: Either (a) detect the XCB window's actual size before creating
   the swapchain (query window geometry after map), or (b) update canvas + projection in the
   resize handler when swapchain extent changes, or (c) rebuild projection after initial
   swapchain creation using actual extent (not requested extent).

## Next Steps

1. **Visual feedback loop** — vktest appl auto-screenshots, Claude reads PNG, compare VK vs GL
2. **Investigate BUG-8** — Statusbar text: may be fixed by per-RT viewport/scissor + blend
3. **Investigate BUG-9** — Content duplication: should be fixed by per-RT scissor
4. **Phase 4c: VK LWA** — `platform_video_init()` fails, needs Vulkan headless init debugging
5. **XCB resize-relayout** — Emit `EVENT_VIDEO_DISPLAY_RESET` on configure notify, resize world vstore + RTs
