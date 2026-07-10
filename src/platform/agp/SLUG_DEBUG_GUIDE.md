# Slug GPU Text Rendering — Debugging Guide

## Architecture Overview

```
afsrv_terminal (child process)
  → TUI cells via shmif shared memory
  → parent arcan receives packed cell data

arcan parent:
  tui_raster_renderagp()           ← CPU: rasterize backgrounds to pixel buffer
  agp_stream_prepare(RAW_DIRECT)   ← upload pixel buffer to GPU texture (synchronous)
  tui_raster_gpu_flush()           ← get queued GpuCellInstance buffer
  agp_slug_draw_instances()        ← GPU: instanced draw into same texture
  agp_stream_commit()              ← no-op for RAW_DIRECT
  
synchDisplay()                     ← composite all vstores to swapchain
```

## Data Flow — How a glyph gets from htop to screen

### 1. Cell data arrives
- `drawglyph()` in `arcan_raster.zig:415` — each non-empty cell enters GPU path
- CPU fills background via `draw_box_px()`
- GPU instance queued in `ctx.gpu_instance_buf[]`

### 2. Atlas lookup
- `slug_atlas_lookup()` in `arcan_ttf.zig:1818` — C-ABI export
- `atlasLookup()` does: font_ptr → TTF_Font wrapper → .font → TTF_Font_Internal → .tt → TrueType
- **CRITICAL**: font_ptr is `*TTF_Font` (wrapper), NOT `*TTF_Font_Internal`. Must dereference.
- Extracts curves via `slug_glyph.zig:extractCurves()` → `buildGlyphGpuData()`
- Returns: em_min/max, band_transform, glyph_data (band texture location)
- Cache: 512-slot hash with codepoint+font_hash collision detection

### 3. Instance buffer
- `GpuCellInstance` = 96 bytes: cell_pos(8) + cell_size(8) + em_min(8) + em_max(8) + band_transform(16) + glyph_data(16) + fg_color(16) + bg_color(16)
- Matches vertex shader binding 1, locations 2-9
- Instances with failed atlas lookup get default values: em=(0,0)-(1,1), gd=(0,0,0,0)

### 4. Texture upload & draw
- `agp_slug_draw_instances()` in `vk_shared.zig:1214`
- Uploads instance data (96 bytes × count) to GPU buffer
- Creates/recreates curve (R32G32B32A32_SFLOAT) and band (R16G16B16A16_UINT) textures from atlas
- Calls `vk_env_slug_draw_with_textures()` in `vk.zig:1166`

### 5. Vulkan draw
- Opens RT pass on vstore texture (same one CPU pixels were uploaded to)
- Binds slug pipeline (2 vertex bindings: quad + instances)
- Allocates per-frame descriptor set: binding 0 = curveTexture, binding 1 = dummy UBO, binding 2 = bandTexture
- `cmdDraw(6, instance_count, 0, 0)` — 6 vertices per quad × N instances
- **Immediately submits** env.cmd with fence wait (commands would be discarded by synchDisplay otherwise)

### 6. Composite
- `synchDisplay()` draws the vstore texture to swapchain as a textured quad
- The slug output is already baked into the vstore — no separate pass needed

## Key Files

| File | Role |
|------|------|
| `src/engine/arcan_raster.zig` | GpuCellInstance struct, drawglyph() GPU path, flush |
| `src/engine/arcan_ttf.zig` | Glyph atlas: cache, curve extraction, C-ABI exports |
| `src/engine/slug_glyph.zig` | extractCurves(), buildGlyphGpuData() |
| `src/engine/arcan_renderfun.zig:2190-2210` | Call site: stream_prepare → slug_draw → commit |
| `src/platform/agp/vk_shared.zig:1214` | agp_slug_draw_instances(): upload + texture mgmt |
| `src/platform/agp/vk.zig:1166` | vk_env_slug_draw_with_textures(): Vulkan draw |
| `src/platform/agp/vk.zig:837` | createSlugPipeline(): pipeline state |
| `src/platform/agp/shaders/slug_glyph.vert` | Vertex shader: instance → NDC positioning |
| `src/platform/agp/shaders/slug_glyph.frag` | Fragment shader: Slug curve evaluation |
| `src/platform/agp/shaders/slug_debug_frag.frag` | Debug shader: solid fg color fill |

## How to Inspect Data (no screenshots needed)

### Instance data
The first large flush (>50 instances) dumps to `/tmp/slug_instances.bin` (raw 96-byte structs) and prints first 15 instances to stderr. Look for:
```
[INST 4] pos=(48.0,14.0) sz=(12.0,14.0) em=(60,-12)-(540,710) bt=(0.0167,...) gd=(1671,0,7,7) fg=(0.54,0.75,0.72,1.00)
```
- `pos`: pixel position in vstore — should tile in grid (0, 12, 24... for x)
- `sz`: cell size — typically (7,14) or (12,14) depending on font
- `em`: em-space bounding box — should be in font units (0-2048 range). (0,0)-(1,1) = atlas lookup failed
- `bt`: band transform — scale ~0.01, offset negative. All zeros = bad
- `gd`: (band_loc_x, band_loc_y, bandMaxX, bandMaxY) — non-zero for real glyphs
- `fg`: foreground RGBA normalized — alpha should be 1.0

### Atlas data
Printed on first draw with textures:
```
[DUMP_ATLAS] curve: ptr=... texels=2802 width=4096  band: ptr=... texels=5376 width=4096
[DUMP_CURVE] first 2 texels (8 f32s): curve[0]=21.00 ...
[DUMP_BAND] first 4 texels (16 u16s): band[0]=6 band[1]=8 ...
```
- Curve texels: each glyph uses 2 texels per curve (p1/p2 in texel 0, p3 in texel 1)
- Band texels: headers (curve_count, list_offset) then curve list entries (curve_texel_x, curve_texel_y)
- band[0]=6 means hband 0 has 6 curves. band[1]=8 means curve list starts at texel 8

### Pipeline status
```
[SLUG] agp_slug_draw_instances called: count=2375 tex_id=52
[SLUG] curve tex=55 (4096x1) band tex=57 (4096x2)
[SLUG_DRAW_TEX] begin rt_pass tex=52 396x588 curve=55 band=57 valid=true
[SLUG_DRAW_TEX] drawing 2375 instances with_tex=true
```

## Common Failure Modes

### "No visible GPU output at all"
**Cause**: Slug draw commands discarded before GPU submission.
**Check**: Is `vk_env_slug_draw_with_textures()` ending with immediate submit (endCommandBuffer + queueSubmit2 + waitForFences)?
**Test**: Add `cmdClearAttachments` to bright magenta inside the RT pass. If magenta visible, RT works.

### "All instances have em=(0,0)-(1,1)"
**Cause**: Atlas lookup failing for every glyph.
**Check**: Look for `[GLYPH_ATLAS] font_ref.font is null` or `font.tt is null` in stderr.
**Common**: The font_ptr must be dereferenced as `*TTF_Font` wrapper first, not cast directly to `*TTF_Font_Internal`.

### "Coverage = 0 (bg color everywhere)"
**Cause**: Slug shader can't evaluate curves — wrong texture data or addressing.
**Check**: Dump band[0] — is curve_count > 0? Dump curve[0] — are control points non-zero?
**Test**: Replace slug_glyph.frag main() with diagnostic: output green if band0.x > 0, red if zero.

### "Only 21 instances (title bar only)"
**Cause**: Terminal content hasn't arrived yet, or TUI mode not active.
**Check**: Wait longer (terminal takes a few seconds to start). Look for `agp_stream_prepare` with the terminal's glid.

### "Textures created but 0 bytes"
**Cause**: Font change invalidation (`slug_atlas_invalidate()`) reset atlas between caching and upload.
**Check**: Look for `[GLYPH_ATLAS] invalidated` messages — should only happen at startup.

## Shader Recompilation

Shaders are pre-compiled SPIR-V embedded via `@embedFile`. To modify:
```bash
cd src/platform/agp/shaders
# Edit .frag or .vert source
glslc -fshader-stage=frag slug_glyph.frag -o slug_glyph_frag.spv
glslc -fshader-stage=vert slug_glyph.vert -o slug_glyph_vert.spv
# Then rebuild arcan
cd /home/x/test/arcan && rm -rf .zig-cache zig-out && zig build
```

To switch between real and debug shaders, change `@embedFile` in `vk_shared.zig:1228`:
- `slug_glyph_frag.spv` — real Slug curve evaluation
- `slug_debug_frag.spv` — solid fg-color fill (proves pipeline works)

## Build & Run

```bash
rm -rf .zig-cache zig-out && zig build    # always clean build
./zig-out/bin/arcan 2>/tmp/arcan.log      # stderr has all debug output
# In another terminal:
grep "SLUG\|DUMP\|GLYPH_ATLAS\|INST " /tmp/arcan.log | head -50
```
