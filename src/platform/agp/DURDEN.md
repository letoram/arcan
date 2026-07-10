# Durian Visual Bugs — Vulkan Backend

Live tracking of rendering bugs visible when running durian under arcan_vk.
Each bug has a screenshot reference, diagnosis, and fix status.

## Screenshot Feedback Loop — WORKING

### Automated via VK readback + PPM dump

The VK backend's `agp_save_output()` reads back the last-presented swapchain
image via staging buffer copy. A numbered PPM writer in the readback path
dumps `/tmp/vk_screenshot_N.ppm` on each `save_screenshot()` call.

**Setup:**
1. `durian/autorun.lua` registers a periodic timer that calls `save_screenshot()`
2. `agp_save_output()` does VkImage→staging buffer copy (PRESENT_SRC→TRANSFER_SRC barrier)
3. Debug code writes BGRA→RGB PPM to `/tmp/vk_screenshot_N.ppm` (sequential)
4. Convert: `magick /tmp/vk_screenshot_0.ppm /tmp/vk_screenshot_0.png`
5. Read the PNG via Claude's multimodal Read tool

**Run command:**
```bash
cd ~/test/arcan/zig-out/bin
rm -f /tmp/vk_screenshot*.ppm /tmp/arcan_vk_out.txt
DISPLAY=:0 ARCAN_APPLBASEPATH=/home/x/test/durian \
ARCAN_STATEBASEPATH=/tmp/arcan_state \
ARCAN_APPLTEMPPATH=/tmp/arcan_temp \
ARCAN_LOGPATH=/tmp/arcan_log \
timeout 15 ./arcan_vk -w 800 -h 600 durian > /tmp/arcan_vk_out.txt 2>&1
magick /tmp/vk_screenshot_0.ppm /tmp/vk_screenshot_0.png
```

**Why durian's save_screenshot PNG doesn't work:**
`findresource()` with `ARES_CREATE` fails because `application-temporary`
namespace path (`/usr/local/share/arcan/appl/durian`) doesn't exist. The
`arcan_warning()` error goes to the debug log (not stdout), so it fails
silently. The PPM dump bypasses the arcan namespace system entirely.

### Key technical details
- Swapchain format: B8G8R8A8_SRGB → BGRA pixels in staging buffer
- PPM needs RGB: pixel swizzle B↔R during write
- `STAGING_BUFFER_SIZE` = 32MB, handles up to native 3024x1710 (20MB)
- Sequential numbered files: `/tmp/vk_screenshot_0.ppm`, `_1.ppm`, etc.

---

## Bug List

### BUG-S1: Black rectangles in statusbar — FIXED

**Status**: FIXED (2026-02-26)

**Symptom**: Statusbar items rendered as black or near-black rectangles.
Custom shader draws had wrong textures and all UBO dynamic offsets were 0.

**Root cause — TWO bugs**:

1. **Stale texture in descriptor set**: `vk_env_bind_custom_shader` was called
   at `agp_shader_activate` time, but the engine sets the correct texture via
   `agp_activate_vstore` AFTER activate and BEFORE draw. The descriptor set
   captured `env.active_texture=0` (default white) instead of the real texture.
   This also caused the **recursive/kaleidoscope rendering** when the old envv
   path re-bound descriptor sets with `vk_env_bind_custom_shader`.

2. **dyn_off=0 logging artifact**: The original `[vk_cust]` bind log was
   rate-limited to 30 entries, which were exhausted by `agp_shader_envv`
   rebind calls (10-14 per shader activation). Non-zero offsets existed
   but were hidden by the log cap. The actual `[vk_ubo]` log confirmed
   `grp=2` was being used at activate time.

**Fix — deferred custom shader bind** (vk.zig):
- `vk_env_bind_custom_shader` now only saves parameters (pipeline, UBO buffer,
  stride, dynamic offset) without recording any Vulkan commands
- New `bindCustomShaderNow()` called from `vk_env_draw_quad` at draw time:
  allocates per-frame descriptor set, writes correct `env.active_texture` +
  UBO buffer, binds pipeline + descriptor set + push constants
- `agp_shader_envv` (vk_shdrmgmt.zig) calls `pushAll()` instead of
  `vk_env_bind_custom_shader` — syncs push constants without allocating
  descriptor sets (saves ~10x pool entries per frame)
- `agp_shader_forceunif` writes directly to host-coherent UBO memory
  without descriptor rebind

**Verified**: Bind log now shows correct texture IDs matching draw texture IDs.
`dyn_off=64` and `dyn_off=128` visible. No pool exhaustion. Statusbar items
visible with color.

### BUG-S2: Garbled text after terminal resize — FIXED

**Status**: FIXED (2026-02-26)

**Symptom**: Text renders perfectly in the initial full-screen terminal, but
becomes garbled when durian splits the workspace (resizing terminals). All
text shows wrong glyph shapes at correct positions — classic stride/offset bug.

**Root cause**: `vk_env_update_texture_sub` received a pointer to the **full
framebuffer** (same as GL gets via `meta.buf`), but read pixel data from
offset 0 instead of the sub-region at `(x1, y1)`.

The GL backend handles this transparently with:
```c
GL_UNPACK_ROW_LENGTH = s->w;     // full framebuffer row width
GL_UNPACK_SKIP_ROWS  = meta.y1;  // offset to sub-region start row
GL_UNPACK_SKIP_PIXELS = meta.x1; // offset to sub-region start column
```

The VK backend must replicate this manually. The fix computes
`src_start = y * src_stride + x * 4` and offsets each row read. Also defaults
stride to `slot.width * 4` (full texture width) when stride=0, matching
GL's `GL_UNPACK_ROW_LENGTH = s->w`.

**Why it only appeared after resize**: Full-texture uploads (x=0, y=0,
w=full, h=full) worked because the offset was 0. After resize, durian sends
sub-region dirty updates with non-zero x1/y1, hitting the offset bug.

**Verified**: Split-layout screenshots show crisp, readable text in both panes.

### BUG-S3: Teal/blue horizontal band across screen

**Status**: NOT REPRODUCED after BUG-S1/S2 fixes

Was visible in early screenshots before the deferred bind fix. May have been
caused by the stale texture in the statusbar RT's custom shader draw. Not
visible in current screenshots.

### BUG-S4: Bottom content overflow

**Status**: NOT REPRODUCED in automated screenshot

The bottom of the screen looks correct — htop content renders cleanly.
May have been fixed by the per-frame descriptor set change or was only
visible in certain scroll states.

### BUG-S5: Mouse cursor doesn't track 1:1 after window resize — FIXED

**Status**: FIXED (2026-02-27)

**Symptom**: After resizing the XCB window (e.g. 800x600 → fullscreen), the
inner arcan cursor moves much slower than the host cursor. Mouse positioning
feels laggy and offset — the host cursor reaches the edge while the inner
cursor is still mid-screen.

**Root cause**: After XCB window resize (e.g. 800x600 → 3024x1710 fullscreen),
XCB mouse coordinates range over the new window size but the arcan canvas stays
at the original size. Mouse was clamped to 800x600 bounds, causing the cursor
to appear stuck at ~26% of the window.

Attempted fix 1: Call `arcan_video_resize_canvas()` — did not help because
durian's `VRES_AUTORES` gates on `lwa_autores` config (false for non-LWA).
Attempted fix 2: Remove `lwa_autores` guard — caused oscillation (resize loop
between 800x600 and 3024x1710, screen went dark).

**Fix**: Scale XCB mouse coordinates from window space to canvas space in
`processXcbInput`: `scaled_x = xcb_x * canvasw / swapchain_extent_w`. Don't
resize the canvas on window resize — the VK composite pass already scales
content via viewport (swapchain extent) vs projection (canvas size).

### BUG-S6: Entire scene too bright / washed out (double gamma) — FIXED

**Status**: FIXED (2026-02-27)

**Symptom**: The VK backend output was much brighter/lighter than the GL backend.
The GL (SDL) backend shows a near-black desktop background (#1E1E1E), bright
yellow workspace number (#EFD469), and colored icons. The VK backend showed
medium-gray background and statusbar items that appeared as featureless dark
rectangles by comparison.

**Root cause**: Double gamma correction. The VK swapchain used B8G8R8A8_SRGB
format. When the composite pass wrote the already-gamma-encoded RT content
(B8G8R8A8_UNORM) to the SRGB swapchain, the GPU applied an additional
linear→SRGB conversion (brightening). The GL backend uses no SRGB conversion
anywhere — all framebuffers are RGBA8 UNORM equivalent.

**Comparison (before fix)**:
- GL: RT (gamma) → screen (gamma) → SDL display → correct appearance
- VK: RT (gamma/UNORM) → swapchain (SRGB) → double gamma → too bright

**Fix**: Changed swapchain format from B8G8R8A8_SRGB to B8G8R8A8_UNORM in
three files:
- `vk_wsi.zig`: Swapchain struct default, `createSwapchain()` format selection
- `vk.zig`: `VkEnv.swapchain_format` default, `vk_env_get_swapchain_format()` fallback

**Verified**: Desktop background now matches GL: VK=#1E1E1E, GL=#1E1E1E.
Statusbar background: VK=#3D3D3D, GL=#3D3D3D. Exact pixel match on neutral
grays confirms the gamma pipeline is now correct.

### BUG-S9: Statusbar text labels not visible — FIXED

**Status**: FIXED (2026-02-27)

**Symptom**: Statusbar item backgrounds render as colored rectangles, but text
labels (workspace "1", "Go", "+") are not visible on top. Also, colors of all
non-gray elements were R/B swapped (e.g., yellow #EFD469 appeared as cyan #69D4EF).

**Root cause — TWO bugs**:

1. **`agp_resize_vstore` destroyed rendered text data**: The VK implementation
   freed the existing `vinf.text.raw` buffer and allocated a new zero-filled one.
   But `arcan_renderfun.c:process_chain()` renders text INTO the raw buffer
   BEFORE calling `agp_resize_vstore`, so freeing it destroyed the rendered text.
   The GL backend's `alloc_buffer()` only allocates if `raw == NULL`, preserving
   existing data. Fix: match GL behavior — only allocate if raw is null.

2. **R/B channel swap (BGRA vs RGBA)**: All textures were created as
   `VK_FORMAT_B8G8R8A8_UNORM` but arcan's `av_pixel` stores pixels in RGBA byte
   order (R in byte 0). VK interprets B8G8R8A8 as B in byte 0, swapping R↔B.
   This was invisible for grays (R=G=B) but wrong for colors (yellow→cyan).
   Fix: changed texture format to `VK_FORMAT_R8G8B8A8_UNORM` in
   `createTextureInternal` (image + view) and both built-in and custom shader
   UNORM pipelines.

**Files changed**:
- `vk_shared.zig`: `agp_resize_vstore` — don't free raw, only alloc if null
- `vk.zig`: `createTextureInternal` — R8G8B8A8_UNORM for image + view;
  UNORM pipeline creation — R8G8B8A8; removed diagnostic logging
- `vk_shdrmgmt.zig`: custom shader UNORM pipeline — format 37 (R8G8B8A8)

**Verified**: Workspace "1" text: VK=#EFD469, SDL=#EFD469 — exact pixel match.

### BUG-S10: Statusbar icon renders as garbled noise — FIXED

**Status**: FIXED (2026-02-27)

**Root cause**: Vulkan images start with undefined content. When a texture was
first used as a rendertarget, `vk_env_begin_rt_pass` used `.load_op = .load`
which preserved the undefined (garbage) memory. Icon RTs have `TGTFL_NOCLEAR`
set by the engine, so `agp_rendertarget_clear()` is never called before the
first draw — the icon shader rendered on top of garbage.

**Fix**: Added `rt_initialized` flag to `TextureSlot`. On the first
`vk_env_begin_rt_pass`, use `.load_op = .clear` (transparent black). On
subsequent passes, use `.load_op = .load` to preserve content as before.

### BUG-S11: Some statusbar items render as pure black rectangles — FIXED

**Status**: FIXED (2026-02-27) — fixed by BUG-S9 (agp_resize_vstore + R8G8B8A8)

The black rectangles were caused by the same two bugs as BUG-S9: destroyed
texture data (agp_resize_vstore freeing raw) and R/B color swap. With correct
pixel data preserved and proper format, icon items now render with visible
content.

### BUG-S12: Green statusbar underline missing — OPEN

**Status**: OPEN (2026-02-27)

**Symptom**: In the SDL backend, a thin green/teal line appears directly under
the statusbar, spanning the full window width. This line is not visible in the
VK backend. The statusbar transitions directly from bar background (#3D3D3D)
to desktop background (#1E1E1E) with no colored line between them.

**Hypothesis**: The green line may be drawn as a separate 1px-high quad with a
solid color or a custom shader. It could be missing because: (a) the draw call
doesn't produce visible output in VK (same issue as BUG-S11), (b) the line is
drawn at a sub-pixel position that gets clipped, or (c) the line's rendertarget
is not being composited into the final scene.

### BUG-S7: save_screenshot() PNG path broken — OPEN

**Status**: OPEN (2026-02-27)

**Symptom**: `save_screenshot() -- couldn't resolve path.` in stderr. Durian's
`save_screenshot()` Lua call fails because `findresource()` with `ARES_CREATE`
can't resolve the output path. The PPM debug dump in the VK backend still works.

**Root cause**: The `application-temporary` namespace path
(`/usr/local/share/arcan/appl/durian`) doesn't exist. The `arcan_warning()`
error goes to the debug log.

### BUG-S8: launch_avfeed() fails for decode archetype — OPEN

**Status**: OPEN (2026-02-27)

**Symptom**: `launch_avfeed(), requested mode (decode) missing from detected
and allowed frameserver archetypes (), rejected.` The frameserver binary
`arcan_frameserver` or `afsrv_decode` can't be found/launched.

**Root cause**: The system-binaries namespace path needs to contain the
frameserver executables. May need `-B` to point to zig-out/bin, or the
frameservers need to be built and placed correctly.

---

## VK vs SDL Comparison (2026-02-27, post BUG-S9 fix)

**Test**: 800x600 window, durian, no connected clients (empty desktop).

| Element | SDL (reference) | VK (R8G8B8A8) | Match? |
|---------|-----------------|---------------|--------|
| Desktop background | #1E1E1E (near-black) | #1E1E1E | YES |
| Statusbar bg (right) | #3D3D3D (grey24) | #3D3D3D | YES |
| Statusbar bg (left items area) | #2B2B2B (grey17) | #2B2B2B | YES |
| Workspace "1" text | #EFD469 (bright yellow) | #EFD469 | YES |
| "Go" text | White glyph on grey bg | Visible, correct color | YES |
| ">_" terminal icon | White glyph on grey bg | Garbled noise/crosshatch | NO |
| "+" icon | White glyph on grey bg | Visible | YES |
| Green statusbar underline | Thin green/teal line | Not visible | NO |
| Mouse cursor | N/A (spectacle) | White arrow, renders OK | — |

**Key finding**: After the R8G8B8A8 + agp_resize_vstore fixes, text labels and
most icons are correct. Remaining issue: missing green underline (BUG-S12).

---

## Shader Reference (durian statusbar)

| Slot | Name | Uniforms | Sampler | Purpose |
|------|------|----------|---------|---------|
| 3 | iconmgr_circle | 2 (radius, color) | no | Round icon mask |
| 4 | iconmgr_colorize | 1 (color) | yes (map_tu0) | Icon tinting |
| 5 | ui_statusbar | 1 (col) | no | Bar background fill |
| 6 | ui_sbar_item | 3 (factor, mix_u, col) | yes (map_tu0) | Icon/item draw |
| 7 | ui_sbar_item_bg | 5 (border, factor, obj_col, col_bg, obj_output_sz) | no | Item background box |
| 8 | ui_sbar_msg_text | 0 | yes (map_tu0) | Text label passthrough |
| 9 | ui_sbar_msg_bg | 1 (col) | no | Text label background |
| 10 | ui_dropshadow | 7 (opacity, radius, sigma, obj_output_sz, color, weight, mix_factor) | yes (map_tu0) | Bar drop shadow |

## Diagnostic Logging

Current log tags:
- `[vk_draw]` — draw call quad coords + modelview translation + RT id
- `[vk_ubo]` — UBO uniform values at shader activation
- `[vk_rt]` — rendertarget viewport + activation
- `[vk_diag]` — per-draw state (tex, blend, pipeline) — built-in shaders only
- `[vk_cust]` — per-draw + per-bind state for custom shaders (tex, blend, pipe, UBO, dyn_off)
- `[vk_save]` — agp_save_output readback tracing
