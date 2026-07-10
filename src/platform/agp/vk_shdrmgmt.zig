// AGP Vulkan 1.4 Backend — Shader Management
// Runtime GLSL→SPIR-V compilation via libshaderc, SPIR-V reflection for UBO layout,
// 256-slot shader management with uniform groups matching the GL backend (shdrmgmt.c).

const std = @import("std");
const builtin = @import("builtin");
const use_zig_dlopen = (builtin.link_mode == .static and (builtin.abi == .musl or !builtin.link_libc));
const zig_dl = struct {
    extern fn zig_dlopen(path_or_null: ?[*:0]const u8, flags: c_int) ?*anyopaque;
    extern fn zig_dlsym(handle: ?*anyopaque, name_c: [*:0]const u8) ?*anyopaque;
    extern fn zig_foreign_begin() callconv(.c) void;
    extern fn zig_foreign_end() callconv(.c) void;
};

const c = struct {
    pub extern fn printf(fmt: [*:0]const u8, ...) callconv(.c) c_int;
};

// Bridge functions in vk.zig
extern fn vk_env_bind_pipeline(shid: u32) void;
extern fn vk_env_push_constants(data: ?[*]const u8, size: u32) void;
extern fn vk_env_is_rendering() bool;
extern fn vk_env_is_rt_rendering() bool;
extern fn vk_env_create_shader_module(spv_ptr: [*]const u8, spv_len: u32) u64;
extern fn vk_env_destroy_shader_module(handle: u64) void;
extern fn vk_env_create_custom_pipeline(vert_handle: u64, frag_handle: u64, format_val: u32) u64;
extern fn vk_env_destroy_pipeline(handle: u64) void;
extern fn vk_env_create_ubo(size: u32, stride: u32, out_mapped: *?[*]u8, out_desc_set: *u64) u64;
extern fn vk_env_get_last_ubo_memory() u64;
extern fn vk_env_destroy_ubo(buf_handle: u64, mem_handle: u64, desc_handle: u64) void;
extern fn vk_env_get_ubo_alignment() u32;
extern fn vk_env_get_swapchain_format() u32;
extern fn vk_env_bind_custom_shader(pipeline_handle: u64, ubo_buf_handle: u64, ubo_stride: u32, dynamic_offset: u32) void;
extern fn vk_env_update_ubo_texture(desc_handle: u64, tex_id: u32) void;

const BROKEN_SHADER: u32 = 0xffffffff;
const MAX_SLOTS: usize = 256;
const MAX_UNIFORMS: usize = 32;
const MAX_GROUPS: usize = 64;
const NUM_ENVV: usize = 14;

// Push Constants Cache
// Layout matches PushConstants in vk.zig (248 bytes total)
const PushCache = extern struct {
    modelview: [16]f32 = .{ // 0: identity
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    projection: [16]f32 = .{ // 64: identity
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    texturem: [16]f32 = .{ // 128: identity
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    opacity: f32 = 1.0, // 192
    trans_blend: f32 = 0.0, // 196
    trans_move: f32 = 0.0, // 200
    trans_rotate: f32 = 0.0, // 204
    trans_scale: f32 = 1.0, // 208
    sz_input: [2]f32 = .{ 0, 0 }, // 212
    sz_output: [2]f32 = .{ 0, 0 }, // 220
    sz_storage: [2]f32 = .{ 0, 0 }, // 228
    rtgt_id: i32 = 0, // 236
    fract_timestamp: f32 = 0.0, // 240
    timestamp: i32 = 0, // 244 (total: 248)
};

comptime {
    if (@sizeOf(PushCache) != 248) {
        @compileError("PushCache must be exactly 248 bytes");
    }
}

// envv slot -> offset and size in PushCache
const EnvvInfo = struct { offset: u32, size: u32 };

const envv_table = [NUM_ENVV]EnvvInfo{
    .{ .offset = 0, .size = 64 }, // 0: MODELVIEW_MATR
    .{ .offset = 64, .size = 64 }, // 1: PROJECTION_MATR
    .{ .offset = 128, .size = 64 }, // 2: TEXTURE_MATR
    .{ .offset = 192, .size = 4 }, // 3: OBJ_OPACITY
    .{ .offset = 196, .size = 4 }, // 4: TRANS_BLEND
    .{ .offset = 200, .size = 4 }, // 5: TRANS_MOVE
    .{ .offset = 204, .size = 4 }, // 6: TRANS_ROTATE
    .{ .offset = 208, .size = 4 }, // 7: TRANS_SCALE
    .{ .offset = 212, .size = 8 }, // 8: SIZE_INPUT
    .{ .offset = 220, .size = 8 }, // 9: SIZE_OUTPUT
    .{ .offset = 228, .size = 8 }, // 10: SIZE_STORAGE
    .{ .offset = 236, .size = 4 }, // 11: RTGT_ID
    .{ .offset = 240, .size = 4 }, // 12: FRACT_TIMESTAMP_F
    .{ .offset = 244, .size = 4 }, // 13: TIMESTAMP_D
};

var push_cache: PushCache = .{};
var active_shader: u32 = 0;

fn pushAll() void {
    vk_env_push_constants(@ptrCast(&push_cache), @sizeOf(PushCache));
}

// Uniform Metadata
const UniformInfo = struct {
    name: [64]u8 = .{0} ** 64,
    name_len: u8 = 0,
    ubo_offset: u32 = 0, // offset within the std140 UBO
    size: u32 = 0, // bytes (4=float, 8=vec2, 12=vec3, 16=vec4/mat4col)
    stype: u32 = 0, // shdrutype enum value for forceunif matching
};

// Uniform Group
// Each group is a snapshot of custom uniform values within the UBO.
// Groups share the same UBO buffer at different dynamic offsets.
const GroupSlot = struct {
    in_use: bool = false,
};

// Shader Slot
const ShaderSlot = struct {
    in_use: bool = false,
    label: [128]u8 = .{0} ** 128,
    label_len: u8 = 0,

    // Stored source for lookupprgs
    vert_src: ?[*]u8 = null,
    frag_src: ?[*]u8 = null,

    // Vulkan handles (as u64 for cross-module portability)
    vert_module: u64 = 0,
    frag_module: u64 = 0,
    pipeline_srgb: u64 = 0,
    pipeline_unorm: u64 = 0,

    // UBO resources
    ubo_buffer: u64 = 0,
    ubo_memory: u64 = 0,
    ubo_descriptor: u64 = 0,
    ubo_mapped: ?[*]u8 = null,
    ubo_stride: u32 = 0, // aligned stride per group

    // Uniform metadata
    uniforms: [MAX_UNIFORMS]UniformInfo = [_]UniformInfo{.{}} ** MAX_UNIFORMS,
    n_uniforms: u32 = 0,
    ubo_raw_size: u32 = 0, // unaligned size of UBO struct from reflection

    // Engine uniform offsets within UBO (-1 = not present)
    envv_offsets: [NUM_ENVV]i32 = .{-1} ** NUM_ENVV,
    envv_sizes: [NUM_ENVV]u32 = .{0} ** NUM_ENVV,

    // Uniform groups
    groups: [MAX_GROUPS]GroupSlot = [_]GroupSlot{.{}} ** MAX_GROUPS,
    group_count: u32 = 0,

    // Which default parts were used (bitmask: 1=default vert, 2=default frag)
    shmask: u8 = 0,
};

var slots: [MAX_SLOTS]ShaderSlot = [_]ShaderSlot{.{}} ** MAX_SLOTS;
var alloc_ofs: usize = 2; // start scanning after built-in slots 0, 1

/// Select UNORM pipeline when rendering to offscreen RT, SRGB for swapchain.
fn slotPipeline(slot: *const ShaderSlot) u64 {
    const is_rt = vk_env_is_rt_rendering();
    if (is_rt and slot.pipeline_unorm != 0) {
        return slot.pipeline_unorm;
    }
    return slot.pipeline_srgb;
}

// Shaderc dlopen
const ShadercFns = struct {
    compiler_init: *const fn () callconv(.c) ?*anyopaque,
    compiler_release: *const fn (?*anyopaque) callconv(.c) void,
    options_init: *const fn () callconv(.c) ?*anyopaque,
    options_release: *const fn (?*anyopaque) callconv(.c) void,
    options_set_forced_version_profile: *const fn (?*anyopaque, c_int, c_int) callconv(.c) void,
    options_set_target_env: *const fn (?*anyopaque, c_int, u32) callconv(.c) void,
    options_set_auto_bind_uniforms: *const fn (?*anyopaque, bool) callconv(.c) void,
    options_set_auto_map_locations: *const fn (?*anyopaque, bool) callconv(.c) void,
    options_set_auto_combined_image_sampler: *const fn (?*anyopaque, bool) callconv(.c) void,
    options_set_vulkan_rules_relaxed: *const fn (?*anyopaque, bool) callconv(.c) void,
    compile_into_spv: *const fn (?*anyopaque, [*]const u8, usize, c_int, [*:0]const u8, [*:0]const u8, ?*anyopaque) callconv(.c) ?*anyopaque,
    result_release: *const fn (?*anyopaque) callconv(.c) void,
    result_get_compilation_status: *const fn (?*anyopaque) callconv(.c) c_int,
    result_get_bytes: *const fn (?*anyopaque) callconv(.c) ?[*]const u8,
    result_get_length: *const fn (?*anyopaque) callconv(.c) usize,
    result_get_error_message: *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
};

var shaderc: ?ShadercFns = null;
var shaderc_compiler: ?*anyopaque = null;
var shaderc_lib: ?std.DynLib = null;
var shaderc_dl_handle: ?*anyopaque = null;

fn dlsymT(comptime T: type, handle: ?*anyopaque, name: [*:0]const u8) ?T {
    if (use_zig_dlopen) {
        const ptr = zig_dl.zig_dlsym(handle, name) orelse return null;
        return @ptrCast(@alignCast(ptr));
    } else unreachable;
}

/// Called from vk.zig init to resolve shaderc symbols early.
export fn agp_shaderc_preload(handle: ?*anyopaque) callconv(.c) bool {
    if (shaderc != null) return true;
    const h = handle orelse return false;
    // resolveShadercSymbols calls zig_dlsym which does its own TLS switch,
    // and warmup calls shaderc which needs glibc TLS
    if (use_zig_dlopen) zig_dl.zig_foreign_begin();
    defer if (use_zig_dlopen) zig_dl.zig_foreign_end();
    return resolveShadercSymbols(h);
}


fn loadShaderc() bool {
    if (shaderc != null) return true;

    if (use_zig_dlopen) {
        return loadShadercViaDlopen();
    } else {
        return loadShadercViaStd();
    }
}

fn resolveShadercSymbols(handle: ?*anyopaque) bool {
    const fns = ShadercFns{
        .compiler_init = dlsymT(*const fn () callconv(.c) ?*anyopaque, handle, "shaderc_compiler_initialize") orelse return false,
        .compiler_release = dlsymT(*const fn (?*anyopaque) callconv(.c) void, handle, "shaderc_compiler_release") orelse return false,
        .options_init = dlsymT(*const fn () callconv(.c) ?*anyopaque, handle, "shaderc_compile_options_initialize") orelse return false,
        .options_release = dlsymT(*const fn (?*anyopaque) callconv(.c) void, handle, "shaderc_compile_options_release") orelse return false,
        .options_set_forced_version_profile = dlsymT(
            *const fn (?*anyopaque, c_int, c_int) callconv(.c) void, handle, "shaderc_compile_options_set_forced_version_profile",
        ) orelse return false,
        .options_set_target_env = dlsymT(
            *const fn (?*anyopaque, c_int, u32) callconv(.c) void, handle, "shaderc_compile_options_set_target_env",
        ) orelse return false,
        .options_set_auto_bind_uniforms = dlsymT(
            *const fn (?*anyopaque, bool) callconv(.c) void, handle, "shaderc_compile_options_set_auto_bind_uniforms",
        ) orelse return false,
        .options_set_auto_map_locations = dlsymT(
            *const fn (?*anyopaque, bool) callconv(.c) void, handle, "shaderc_compile_options_set_auto_map_locations",
        ) orelse return false,
        .options_set_auto_combined_image_sampler = dlsymT(
            *const fn (?*anyopaque, bool) callconv(.c) void, handle, "shaderc_compile_options_set_auto_combined_image_sampler",
        ) orelse return false,
        .options_set_vulkan_rules_relaxed = dlsymT(
            *const fn (?*anyopaque, bool) callconv(.c) void, handle, "shaderc_compile_options_set_vulkan_rules_relaxed",
        ) orelse return false,
        .compile_into_spv = dlsymT(
            *const fn (?*anyopaque, [*]const u8, usize, c_int, [*:0]const u8, [*:0]const u8, ?*anyopaque) callconv(.c) ?*anyopaque,
            handle, "shaderc_compile_into_spv",
        ) orelse return false,
        .result_release = dlsymT(*const fn (?*anyopaque) callconv(.c) void, handle, "shaderc_result_release") orelse return false,
        .result_get_compilation_status = dlsymT(
            *const fn (?*anyopaque) callconv(.c) c_int, handle, "shaderc_result_get_compilation_status",
        ) orelse return false,
        .result_get_bytes = dlsymT(
            *const fn (?*anyopaque) callconv(.c) ?[*]const u8, handle, "shaderc_result_get_bytes",
        ) orelse return false,
        .result_get_length = dlsymT(
            *const fn (?*anyopaque) callconv(.c) usize, handle, "shaderc_result_get_length",
        ) orelse return false,
        .result_get_error_message = dlsymT(
            *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8, handle, "shaderc_result_get_error_message",
        ) orelse return false,
    };

    const compiler = fns.compiler_init() orelse return false;
    // Warm up shaderc's C++ allocator while single-threaded — glibc's malloc
    // crashes in __aarch64_cas4_acq after Vulkan threads are created
    if (fns.options_init()) |opts| {
        fns.options_release(opts);
    }
    shaderc = fns;
    shaderc_compiler = compiler;
    shaderc_dl_handle = handle;
    return true;
}

fn loadShadercViaDlopen() bool {
    // With per-call TLS switching, zig_dlopen/zig_dlsym work anytime.
    const handle = zig_dl.zig_dlopen("libshaderc_shared.so.1", 1) orelse {
        std.debug.print("[vk_shdrmgmt] failed to zig_dlopen libshaderc_shared.so.1\n", .{});
        return false;
    };
    return resolveShadercSymbols(handle);
}

fn loadShadercViaStd() bool {
    var lib = std.DynLib.open("libshaderc_shared.so.1") catch {
        std.debug.print("[vk_shdrmgmt] failed to dlopen libshaderc_shared.so.1\n", .{});
        return false;
    };

    const fns = ShadercFns{
        .compiler_init = lib.lookup(*const fn () callconv(.c) ?*anyopaque, "shaderc_compiler_initialize") orelse { lib.close(); return false; },
        .compiler_release = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "shaderc_compiler_release") orelse { lib.close(); return false; },
        .options_init = lib.lookup(*const fn () callconv(.c) ?*anyopaque, "shaderc_compile_options_initialize") orelse { lib.close(); return false; },
        .options_release = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "shaderc_compile_options_release") orelse { lib.close(); return false; },
        .options_set_forced_version_profile = lib.lookup(
            *const fn (?*anyopaque, c_int, c_int) callconv(.c) void, "shaderc_compile_options_set_forced_version_profile",
        ) orelse { lib.close(); return false; },
        .options_set_target_env = lib.lookup(
            *const fn (?*anyopaque, c_int, u32) callconv(.c) void, "shaderc_compile_options_set_target_env",
        ) orelse { lib.close(); return false; },
        .options_set_auto_bind_uniforms = lib.lookup(
            *const fn (?*anyopaque, bool) callconv(.c) void, "shaderc_compile_options_set_auto_bind_uniforms",
        ) orelse { lib.close(); return false; },
        .options_set_auto_map_locations = lib.lookup(
            *const fn (?*anyopaque, bool) callconv(.c) void, "shaderc_compile_options_set_auto_map_locations",
        ) orelse { lib.close(); return false; },
        .options_set_auto_combined_image_sampler = lib.lookup(
            *const fn (?*anyopaque, bool) callconv(.c) void, "shaderc_compile_options_set_auto_combined_image_sampler",
        ) orelse { lib.close(); return false; },
        .options_set_vulkan_rules_relaxed = lib.lookup(
            *const fn (?*anyopaque, bool) callconv(.c) void, "shaderc_compile_options_set_vulkan_rules_relaxed",
        ) orelse { lib.close(); return false; },
        .compile_into_spv = lib.lookup(
            *const fn (?*anyopaque, [*]const u8, usize, c_int, [*:0]const u8, [*:0]const u8, ?*anyopaque) callconv(.c) ?*anyopaque,
            "shaderc_compile_into_spv",
        ) orelse { lib.close(); return false; },
        .result_release = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "shaderc_result_release") orelse { lib.close(); return false; },
        .result_get_compilation_status = lib.lookup(
            *const fn (?*anyopaque) callconv(.c) c_int, "shaderc_result_get_compilation_status",
        ) orelse { lib.close(); return false; },
        .result_get_bytes = lib.lookup(
            *const fn (?*anyopaque) callconv(.c) ?[*]const u8, "shaderc_result_get_bytes",
        ) orelse { lib.close(); return false; },
        .result_get_length = lib.lookup(
            *const fn (?*anyopaque) callconv(.c) usize, "shaderc_result_get_length",
        ) orelse { lib.close(); return false; },
        .result_get_error_message = lib.lookup(
            *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8, "shaderc_result_get_error_message",
        ) orelse { lib.close(); return false; },
    };

    const compiler = fns.compiler_init() orelse { lib.close(); return false; };
    shaderc = fns;
    shaderc_compiler = compiler;
    shaderc_lib = lib;
    return true;
}

// GLSL Compilation

const default_vert_src: [*:0]const u8 =
    "#version 120\n" ++
    "uniform mat4 modelview;\n" ++
    "uniform mat4 projection;\n" ++
    "attribute vec2 texcoord;\n" ++
    "varying vec2 texco;\n" ++
    "attribute vec4 vertex;\n" ++
    "void main(){\n" ++
    "   gl_Position = (projection * modelview) * vertex;\n" ++
    "   texco = texcoord;\n" ++
    "}";

const default_frag_src: [*:0]const u8 =
    "#version 120\n" ++
    "uniform sampler2D map_diffuse;\n" ++
    "varying vec2 texco;\n" ++
    "uniform float obj_opacity;\n" ++
    "void main(){\n" ++
    "   vec4 col = texture2D(map_diffuse, texco);\n" ++
    "   col.a = col.a * obj_opacity;\n" ++
    "   gl_FragColor = col;\n" ++
    "}";

// shaderc shader kind constants
const SHADERC_VERTEX_SHADER: c_int = 0;
const SHADERC_FRAGMENT_SHADER: c_int = 1;
// shaderc profile constants
const SHADERC_PROFILE_NONE: c_int = 0;
// shaderc target env
const SHADERC_TARGET_ENV_VULKAN: c_int = 0;
// shaderc env version
const SHADERC_ENV_VERSION_VULKAN_1_0: u32 = (1 << 22);
const SHADERC_ENV_VERSION_VULKAN_1_3: u32 = (1 << 22) | (3 << 12);

const GlslDeclKind = enum { attribute, varying, uniform_sampler, uniform_scalar };

/// Two-pass GLSL 1.20 → 4.50 preprocessor for Vulkan.
/// Pass 1: Parse declarations (uniforms, attributes, varyings).
/// Pass 2: Emit proper #version 450 with layout qualifiers, UBO blocks, and body replacements.
/// Returns allocated null-terminated buffer (caller must free) or null.
fn preprocessGlsl(source: [*:0]const u8, is_vertex: bool) ?[:0]u8 {
    const src = std.mem.span(source);

    // Pass 1: Collect declarations
    const max_decls = 32;

    const Decl = struct {
        kind: GlslDeclKind,
        type_str: []const u8, // e.g. "vec3", "sampler2D", "mat4"
        name_str: []const u8, // e.g. "color", "map_tu0"
        line_start: usize, // offset in src
        line_end: usize, // offset past '\n' or end
    };

    var decls: [max_decls]Decl = undefined;
    var n_decls: usize = 0;

    // Scan lines
    var line_start: usize = 0;
    while (line_start < src.len) {
        // Find end of line
        var line_end = line_start;
        while (line_end < src.len and src[line_end] != '\n') : (line_end += 1) {}
        const line_end_full = if (line_end < src.len) line_end + 1 else line_end;

        // Skip leading whitespace
        var p = line_start;
        while (p < line_end and (src[p] == ' ' or src[p] == '\t')) : (p += 1) {}

        if (n_decls < max_decls) {
            if (parseDecl(src, p, line_end)) |decl_info| {
                decls[n_decls] = .{
                    .kind = decl_info.kind,
                    .type_str = decl_info.type_str,
                    .name_str = decl_info.name_str,
                    .line_start = line_start,
                    .line_end = line_end_full,
                };
                n_decls += 1;
            }
        }

        line_start = line_end_full;
    }

    // Pass 2: Emit GLSL 4.50
    const alloc_size = src.len + 2048;
    var buf = std.heap.c_allocator.allocSentinel(u8, alloc_size, 0) catch return null;
    var pos: usize = 0;

    // Helper to append string
    const append = struct {
        fn f(b: []u8, p: *usize, s: []const u8) void {
            @memcpy(b[p.* .. p.* + s.len], s);
            p.* += s.len;
        }
    }.f;

    // #version 450
    append(buf, &pos, "#version 450\n");

    // Fragment output
    if (!is_vertex) {
        append(buf, &pos, "layout(location=0) out vec4 _fragColor;\n");
    }

    // Emit attributes with semantic location mapping:
    // "vertex" → location 0 (position), "texcoord" → location 1 (uv)
    // This matches the pipeline vertex input layout in createGraphicsPipeline().
    // Declaration order in the GLSL source must NOT determine location — the
    // default vertex shader declares texcoord before vertex, which would swap them.
    var next_attr_loc: u32 = 2; // for any attribute that isn't vertex or texcoord
    for (decls[0..n_decls]) |d| {
        if (d.kind == .attribute and is_vertex) {
            const loc: u32 = if (std.mem.eql(u8, d.name_str, "vertex"))
                0
            else if (std.mem.eql(u8, d.name_str, "texcoord"))
                1
            else blk: {
                const l = next_attr_loc;
                next_attr_loc += 1;
                break :blk l;
            };
            const written = std.fmt.bufPrint(buf[pos..], "layout(location={d}) in {s} {s};\n", .{
                loc, d.type_str, d.name_str,
            }) catch "";
            pos += written.len;
        }
    }
    // Varyings (separate loop — emitted after attributes)
    var varying_loc: u32 = 0;
    for (decls[0..n_decls]) |d| {
        if (d.kind == .varying) {
            const dir: []const u8 = if (is_vertex) "out" else "in";
            const written = std.fmt.bufPrint(buf[pos..], "layout(location={d}) {s} {s} {s};\n", .{
                varying_loc, dir, d.type_str, d.name_str,
            }) catch "";
            pos += written.len;
            varying_loc += 1;
        }
    }

    // Collect non-opaque uniforms into push_constant (vertex) or UBO (fragment).
    //
    // The vertex shader's engine matrices (modelview, projection, texturem) go into
    // layout(push_constant) matching the PushCache layout in vk.zig. This avoids a
    // UBO binding conflict: vertex and fragment would generate incompatible UBO blocks
    // at the same binding, causing the vertex shader to read garbage matrices.
    //
    // Fragment shaders keep ALL uniforms in UBO — the SPIR-V reflection + syncEnvvToUbo
    // handles engine uniforms (obj_opacity etc.) correctly.
    var binding: u32 = 0;

    // Samplers first
    for (decls[0..n_decls]) |d| {
        if (d.kind == .uniform_sampler) {
            const written = std.fmt.bufPrint(buf[pos..], "layout(set=0, binding={d}) uniform {s} {s};\n", .{
                binding, d.type_str, d.name_str,
            }) catch "";
            pos += written.len;
            binding += 1;
        }
    }

    // Ensure UBO binding matches descriptor set layout (always binding 1).
    // Descriptor set: binding 0 = sampler, binding 1 = UBO, binding 2 = sampler.
    // Without this, no-sampler shaders (e.g. ui_statusbar) put UBO at binding 0,
    // reading the image descriptor as uniform data → garbage → invisible output.
    if (binding < 1) binding = 1;

    // Vertex shader: engine matrices → push_constant, rest → UBO
    // Fragment shader: everything → UBO
    const PcEntry = struct { name: []const u8, offset: u32 };
    // Only mat4 matrices for vertex push_constant (offsets are std430-aligned)
    const vert_pc_entries = [_]PcEntry{
        .{ .name = "modelview", .offset = 0 },
        .{ .name = "projection", .offset = 64 },
        .{ .name = "texturem", .offset = 128 },
    };

    var has_pc = false;
    var has_ubo = false;

    if (is_vertex) {
        // Vertex: push_constant block for engine matrices
        for (decls[0..n_decls]) |d| {
            if (d.kind != .uniform_scalar) continue;
            const pc_off = blk: {
                for (vert_pc_entries) |e| {
                    if (std.mem.eql(u8, d.name_str, e.name)) break :blk @as(?u32, e.offset);
                }
                break :blk @as(?u32, null);
            };
            if (pc_off) |off| {
                if (!has_pc) {
                    append(buf, &pos, "layout(push_constant) uniform _PC {\n");
                    has_pc = true;
                }
                const w2 = std.fmt.bufPrint(buf[pos..], "    layout(offset={d}) {s} {s};\n", .{ off, d.type_str, d.name_str }) catch "";
                pos += w2.len;
            }
        }
        if (has_pc) {
            append(buf, &pos, "};\n");
        }
        // Vertex: remaining non-engine uniforms → UBO (rare but possible)
        for (decls[0..n_decls]) |d| {
            if (d.kind != .uniform_scalar) continue;
            const is_pc = blk: {
                for (vert_pc_entries) |e| {
                    if (std.mem.eql(u8, d.name_str, e.name)) break :blk true;
                }
                break :blk false;
            };
            if (!is_pc) {
                if (!has_ubo) {
                    const w1 = std.fmt.bufPrint(buf[pos..], "layout(set=0, binding={d}) uniform _UBO {{\n", .{binding}) catch "";
                    pos += w1.len;
                    has_ubo = true;
                }
                const w2 = std.fmt.bufPrint(buf[pos..], "    {s} {s};\n", .{ d.type_str, d.name_str }) catch "";
                pos += w2.len;
            }
        }
        if (has_ubo) {
            append(buf, &pos, "};\n");
        }
    } else {
        // Fragment: ALL non-opaque uniforms → UBO (no push_constant)
        for (decls[0..n_decls]) |d| {
            if (d.kind == .uniform_scalar) {
                if (!has_ubo) {
                    const w1 = std.fmt.bufPrint(buf[pos..], "layout(set=0, binding={d}) uniform _UBO {{\n", .{binding}) catch "";
                    pos += w1.len;
                    has_ubo = true;
                }
                const w2 = std.fmt.bufPrint(buf[pos..], "    {s} {s};\n", .{ d.type_str, d.name_str }) catch "";
                pos += w2.len;
            }
        }
        if (has_ubo) {
            append(buf, &pos, "};\n");
        }
    }

    // Emit body lines (skip declaration lines and #version, replace texture2D/gl_FragColor)
    line_start = 0;
    while (line_start < src.len) {
        var line_end = line_start;
        while (line_end < src.len and src[line_end] != '\n') : (line_end += 1) {}
        const line_end_full = if (line_end < src.len) line_end + 1 else line_end;

        // Check if this line is a declaration we already emitted or a #version line
        var skip = false;

        // Skip #version
        var lp = line_start;
        while (lp < line_end and (src[lp] == ' ' or src[lp] == '\t')) : (lp += 1) {}
        if (std.mem.startsWith(u8, src[lp..], "#version ")) {
            skip = true;
        }

        // Skip parsed declarations
        if (!skip) {
            for (decls[0..n_decls]) |d| {
                if (d.line_start == line_start) {
                    skip = true;
                    break;
                }
            }
        }

        if (!skip) {
            // Copy line with texture2D/gl_FragColor replacements
            var j = line_start;
            while (j < line_end) {
                if (std.mem.startsWith(u8, src[j..], "texture2D(")) {
                    append(buf, &pos, "texture(");
                    j += "texture2D(".len;
                } else if (!is_vertex and std.mem.startsWith(u8, src[j..], "gl_FragColor")) {
                    append(buf, &pos, "_fragColor");
                    j += "gl_FragColor".len;
                } else {
                    buf[pos] = src[j];
                    pos += 1;
                    j += 1;
                }
            }
            // Newline
            if (line_end < src.len) {
                buf[pos] = '\n';
                pos += 1;
            }
        }

        line_start = line_end_full;
    }

    buf[pos] = 0;
    return buf[0..pos :0];
}

/// Parse a single line for a GLSL declaration.
fn parseDecl(src: []const u8, start: usize, end: usize) ?struct {
    kind: GlslDeclKind,
    type_str: []const u8,
    name_str: []const u8,
} {
    var p = start;

    var base_kind: enum { attribute, varying, uniform } = undefined;

    if (std.mem.startsWith(u8, src[p..end], "attribute ")) {
        base_kind = .attribute;
        p += "attribute ".len;
    } else if (std.mem.startsWith(u8, src[p..end], "varying ")) {
        base_kind = .varying;
        p += "varying ".len;
    } else if (std.mem.startsWith(u8, src[p..end], "uniform ")) {
        base_kind = .uniform;
        p += "uniform ".len;
    } else {
        return null;
    }

    // Skip whitespace
    while (p < end and (src[p] == ' ' or src[p] == '\t')) : (p += 1) {}

    // Read type
    const type_start = p;
    while (p < end and src[p] != ' ' and src[p] != '\t' and src[p] != ';') : (p += 1) {}
    if (p == type_start) return null;
    const type_str = src[type_start..p];

    // Skip whitespace
    while (p < end and (src[p] == ' ' or src[p] == '\t')) : (p += 1) {}

    // Read name (stop at ; or whitespace or end)
    const name_start = p;
    while (p < end and src[p] != ' ' and src[p] != '\t' and src[p] != ';' and src[p] != '=') : (p += 1) {}
    if (p == name_start) return null;
    const name_str = src[name_start..p];

    // Determine kind
    const kind: GlslDeclKind = switch (base_kind) {
        .attribute => .attribute,
        .varying => .varying,
        .uniform => if (isSamplerType(type_str)) .uniform_sampler else .uniform_scalar,
    };

    return .{ .kind = kind, .type_str = type_str, .name_str = name_str };
}

fn isSamplerType(t: []const u8) bool {
    return std.mem.startsWith(u8, t, "sampler") or
        std.mem.startsWith(u8, t, "isampler") or
        std.mem.startsWith(u8, t, "usampler") or
        std.mem.eql(u8, t, "image2D") or
        std.mem.eql(u8, t, "samplerCube");
}

/// Compile a GLSL source string to SPIR-V. Returns allocated u8 slice (caller must free) or null.
fn compileGlslToSpirv(source: [*:0]const u8, is_vertex: bool) ?struct { data: []u8, len: usize } {
    const sc = shaderc orelse return null;
    const compiler = shaderc_compiler orelse return null;

    // Preprocess GL 1.20 → GLSL 4.50 (attribute/varying/texture2D/gl_FragColor)
    const preprocessed = preprocessGlsl(source, is_vertex) orelse return null;
    defer std.heap.c_allocator.free(preprocessed[0 .. preprocessed.len + 1]);

    // Diagnostic: dump first few preprocessed shaders to catch location/layout issues
    {
    }

    // Create options
    const opts = sc.options_init() orelse return null;
    defer sc.options_release(opts);

    // Preprocessor emits proper #version 450 with layout qualifiers and UBO blocks,
    // so no relaxed rules needed — just target Vulkan 1.3 SPIR-V.
    sc.options_set_target_env(opts, SHADERC_TARGET_ENV_VULKAN, SHADERC_ENV_VERSION_VULKAN_1_3);

    const kind: c_int = if (is_vertex) SHADERC_VERTEX_SHADER else SHADERC_FRAGMENT_SHADER;
    const fname: [*:0]const u8 = if (is_vertex) "vert.glsl" else "frag.glsl";

    const result = sc.compile_into_spv(compiler, preprocessed.ptr, preprocessed.len, kind, fname, "main", opts) orelse return null;
    defer sc.result_release(result);

    const status = sc.result_get_compilation_status(result);
    if (status != 0) {
        // Compilation failed
        if (sc.result_get_error_message(result)) |msg| {
            std.debug.print("[vk_shdrmgmt] shaderc error: {s}\n", .{std.mem.span(msg)});
        }
        return null;
    }

    const spv_bytes = sc.result_get_bytes(result) orelse return null;
    const spv_len = sc.result_get_length(result);
    if (spv_len == 0) return null;

    // Copy to our own buffer (result is freed on return)
    // Ensure u32 alignment for SPIR-V
    const aligned_len = (spv_len + 3) & ~@as(usize, 3);
    const buf = std.heap.c_allocator.alignedAlloc(u8, .@"4", aligned_len) catch return null;
    @memcpy(buf[0..spv_len], spv_bytes[0..spv_len]);
    // Zero-pad alignment bytes
    if (aligned_len > spv_len) {
        @memset(buf[spv_len..aligned_len], 0);
    }

    return .{ .data = buf, .len = spv_len };
}

// SPIR-V Reflection
// Parse SPIR-V binary to extract UBO member names and std140 offsets.

const ReflectedUniform = struct {
    name: [64]u8 = .{0} ** 64,
    name_len: u8 = 0,
    offset: u32 = 0,
    size: u32 = 0,
};

const ReflectResult = struct {
    uniforms: [MAX_UNIFORMS]ReflectedUniform = [_]ReflectedUniform{.{}} ** MAX_UNIFORMS,
    n_uniforms: u32 = 0,
    ubo_size: u32 = 0, // total size of the UBO struct
    ubo_binding: u32 = 0,
};

fn reflectSpirv(spv: []const u8) ReflectResult {
    var result = ReflectResult{};
    if (spv.len < 20) return result; // too small for SPIR-V header

    const words: []const u32 = @alignCast(std.mem.bytesAsSlice(u32, spv));
    if (words.len < 5) return result;

    // SPIR-V magic
    if (words[0] != 0x07230203) return result;

    const bound = words[3]; // ID upper bound
    _ = bound;

    // We need to find:
    // 1. OpVariable with StorageClass Uniform → the UBO variable
    // 2. OpTypeStruct that the UBO variable points to
    // 3. OpMemberDecorate with Offset decoration for that struct
    // 4. OpMemberName for that struct's members
    // 5. OpDecorate with Binding for the UBO variable
    // 6. OpDecorate with Block for the struct type (confirms it's a UBO)

    // First pass: collect struct type IDs decorated with Block
    var block_type_id: u32 = 0;
    var ubo_var_type_id: u32 = 0;

    // Member offsets and names indexed by member index
    var member_offsets: [MAX_UNIFORMS]u32 = .{0} ** MAX_UNIFORMS;
    var member_names: [MAX_UNIFORMS][64]u8 = .{.{0} ** 64} ** MAX_UNIFORMS;
    var member_name_lens: [MAX_UNIFORMS]u8 = .{0} ** MAX_UNIFORMS;
    var max_member: u32 = 0;

    // Member type IDs for size estimation
    var member_type_ids: [MAX_UNIFORMS]u32 = .{0} ** MAX_UNIFORMS;

    // Type sizes (OpTypeFloat, OpTypeVector, OpTypeMatrix, OpTypeInt)
    // We'll collect these in a sparse map
    const MaxTypeIds = 512;
    var type_sizes: [MaxTypeIds]u32 = .{0} ** MaxTypeIds;

    // Two-pass: first find Block-decorated struct, then gather member info
    var i: usize = 5; // skip header
    while (i < words.len) {
        const word0 = words[i];
        const opcode = word0 & 0xFFFF;
        const wcount = word0 >> 16;
        if (wcount == 0) break;
        if (i + wcount > words.len) break;

        switch (opcode) {
            // OpTypeFloat = 22: result_id, width
            22 => {
                if (wcount >= 3) {
                    const id = words[i + 1];
                    const width = words[i + 2];
                    if (id < MaxTypeIds) type_sizes[id] = width / 8;
                }
            },
            // OpTypeInt = 21: result_id, width, signedness
            21 => {
                if (wcount >= 3) {
                    const id = words[i + 1];
                    const width = words[i + 2];
                    if (id < MaxTypeIds) type_sizes[id] = width / 8;
                }
            },
            // OpTypeVector = 23: result_id, component_type, count
            23 => {
                if (wcount >= 4) {
                    const id = words[i + 1];
                    const comp_type = words[i + 2];
                    const count = words[i + 3];
                    if (id < MaxTypeIds and comp_type < MaxTypeIds) {
                        type_sizes[id] = type_sizes[comp_type] * count;
                    }
                }
            },
            // OpTypeMatrix = 24: result_id, column_type, column_count
            24 => {
                if (wcount >= 4) {
                    const id = words[i + 1];
                    const col_type = words[i + 2];
                    const col_count = words[i + 3];
                    if (id < MaxTypeIds and col_type < MaxTypeIds) {
                        type_sizes[id] = type_sizes[col_type] * col_count;
                    }
                }
            },
            // OpTypeStruct = 30: result_id, member_type_ids...
            30 => {
                // Store member type IDs if this turns out to be the Block struct
                const struct_id = words[i + 1];
                // We'll check later if this is the block struct
                _ = struct_id;
                // Store all struct type IDs → member types for later
                // We'll re-parse on second pass after knowing block_type_id
            },
            // OpDecorate = 71: target_id, decoration, [extra]
            71 => {
                if (wcount >= 3) {
                    const target = words[i + 1];
                    const decoration = words[i + 2];
                    if (decoration == 2) { // Block
                        block_type_id = target;
                    }
                    if (decoration == 33 and wcount >= 4) { // Binding
                        result.ubo_binding = words[i + 3];
                    }
                }
            },
            // OpMemberDecorate = 72: struct_type, member, decoration, [extra]
            72 => {
                if (wcount >= 4) {
                    const struct_type = words[i + 1];
                    _ = struct_type; // will match against block_type_id
                    const member = words[i + 2];
                    const decoration = words[i + 3];
                    if (decoration == 35 and wcount >= 5) { // Offset
                        if (member < MAX_UNIFORMS) {
                            member_offsets[member] = words[i + 4];
                            if (member + 1 > max_member) max_member = member + 1;
                        }
                    }
                }
            },
            // OpMemberName = 6: type, member, "name"
            6 => {
                if (wcount >= 4) {
                    const member = words[i + 2];
                    if (member < MAX_UNIFORMS) {
                        // Name is null-terminated string starting at word i+3
                        const name_words = wcount - 3;
                        const name_bytes: [*]const u8 = @ptrCast(&words[i + 3]);
                        const max_len = name_words * 4;
                        var len: u8 = 0;
                        while (len < max_len and len < 63) : (len += 1) {
                            if (name_bytes[len] == 0) break;
                            member_names[member][len] = name_bytes[len];
                        }
                        member_names[member][len] = 0;
                        member_name_lens[member] = len;
                    }
                }
            },
            // OpTypePointer = 32: result_id, storage_class, type
            32 => {
                if (wcount >= 4) {
                    const storage_class = words[i + 2];
                    if (storage_class == 2) { // Uniform
                        ubo_var_type_id = words[i + 3];
                    }
                }
            },
            else => {},
        }
        i += wcount;
    }

    // Second pass: get member type IDs from the Block struct
    if (block_type_id != 0) {
        i = 5;
        while (i < words.len) {
            const word0 = words[i];
            const opcode = word0 & 0xFFFF;
            const wcount = word0 >> 16;
            if (wcount == 0) break;
            if (i + wcount > words.len) break;

            if (opcode == 30 and words[i + 1] == block_type_id) { // OpTypeStruct
                var m: u32 = 0;
                var wi: usize = i + 2;
                while (wi < i + wcount and m < MAX_UNIFORMS) : ({
                    wi += 1;
                    m += 1;
                }) {
                    member_type_ids[m] = words[wi];
                }
                break;
            }
            i += wcount;
        }
    }

    // Build result
    var n: u32 = 0;
    for (0..max_member) |mi| {
        if (member_name_lens[mi] == 0) continue;
        if (n >= MAX_UNIFORMS) break;

        result.uniforms[n].name = member_names[mi];
        result.uniforms[n].name_len = member_name_lens[mi];
        result.uniforms[n].offset = member_offsets[mi];

        // Estimate size from type
        const tid = member_type_ids[mi];
        if (tid < MaxTypeIds and type_sizes[tid] > 0) {
            result.uniforms[n].size = type_sizes[tid];
        } else {
            result.uniforms[n].size = 4; // fallback to float
        }
        n += 1;
    }
    result.n_uniforms = n;

    // Estimate total UBO size from last member offset + size
    if (n > 0) {
        var max_end: u32 = 0;
        for (0..n) |ui| {
            const end = result.uniforms[ui].offset + result.uniforms[ui].size;
            if (end > max_end) max_end = end;
        }
        // Round up to 16-byte alignment (std140 rule)
        result.ubo_size = (max_end + 15) & ~@as(u32, 15);
    }

    return result;
}

// Engine Uniform Name Matching
const envv_names = [NUM_ENVV][]const u8{
    "modelview",
    "projection",
    "texturem",
    "obj_opacity",
    "trans_blend",
    "trans_move",
    "trans_rotate",
    "trans_scale",
    "obj_input_sz",
    "obj_output_sz",
    "obj_storage_sz",
    "rtgt_id",
    "fract_timestamp",
    "timestamp",
};

fn mapEnvvOffsets(slot: *ShaderSlot, reflect: *const ReflectResult) void {
    for (0..NUM_ENVV) |ei| {
        slot.envv_offsets[ei] = -1;
        slot.envv_sizes[ei] = 0;
    }
    for (0..reflect.n_uniforms) |ui| {
        const name = reflect.uniforms[ui].name[0..reflect.uniforms[ui].name_len];
        for (0..NUM_ENVV) |ei| {
            if (std.mem.eql(u8, name, envv_names[ei])) {
                slot.envv_offsets[ei] = @intCast(reflect.uniforms[ui].offset);
                slot.envv_sizes[ei] = reflect.uniforms[ui].size;
                break;
            }
        }
    }
}

// Write engine uniforms to UBO
fn syncEnvvToUbo(slot: *ShaderSlot, group_idx: u32) void {
    const mapped = slot.ubo_mapped orelse return;
    const base: u32 = group_idx * slot.ubo_stride;
    const push_bytes: [*]const u8 = @ptrCast(&push_cache);

    for (0..NUM_ENVV) |ei| {
        const off = slot.envv_offsets[ei];
        if (off < 0) continue;
        const ubo_off = base + @as(u32, @intCast(off));
        const info = envv_table[ei];
        const sz = @min(info.size, slot.envv_sizes[ei]);
        if (sz == 0) continue;
        @memcpy(mapped[ubo_off .. ubo_off + sz], push_bytes[info.offset .. info.offset + sz]);
    }
}

// Shader ID encoding (matches GL backend agp_platform.h:36-38)
// lower 16 bits: shader slot index, upper 16 bits: group index
inline fn SHADER_INDEX(shid: u32) u32 {
    return shid & 0xFFFF;
}

inline fn GROUP_INDEX(shid: u32) u32 {
    return shid >> 16;
}

inline fn SHADER_ID(slot_idx: u32, group_idx: u32) u32 {
    return (group_idx << 16) | (slot_idx & 0xFFFF);
}

// Helper: duplicate a C string using c_allocator
fn cstrdup(src: [*:0]const u8) ?[*]u8 {
    const span = std.mem.span(src);
    const buf = std.heap.c_allocator.alloc(u8, span.len + 1) catch return null;
    @memcpy(buf[0..span.len], span);
    buf[span.len] = 0;
    return buf.ptr;
}

fn cstrfree(ptr: ?[*]u8) void {
    if (ptr) |p| {
        // Find length by scanning for NUL
        var len: usize = 0;
        while (p[len] != 0) : (len += 1) {}
        std.heap.c_allocator.free(p[0 .. len + 1]);
    }
}

// Exported AGP Functions

export fn agp_default_shader(shader_type: c_uint) u32 {
    return switch (shader_type) {
        0, 2 => 0, // BASIC_2D, BASIC_3D -> pipeline 0
        1 => 1, // COLOR_2D -> pipeline 1
        else => 0,
    };
}

export fn agp_shader_source(
    shader_type: c_uint,
    vert: ?*[*:0]const u8,
    frag: ?*[*:0]const u8,
) void {
    _ = shader_type;
    if (vert) |v| v.* = default_vert_src;
    if (frag) |f| f.* = default_frag_src;
}

export fn agp_shader_activate(shid: u32) c_int {
    // Returns 0 (ARCAN_OK) on success, -1 on failure
    if (shid == BROKEN_SHADER) return -1;

    const sid = SHADER_INDEX(shid);
    const gid = GROUP_INDEX(shid);

    if (sid >= MAX_SLOTS) return -1;

    active_shader = shid;

    if (sid < 2) {
        // Built-in shader: use push constants path
        vk_env_bind_pipeline(sid);
        if (vk_env_is_rendering()) {
            pushAll();
        }
        return 0; // ARCAN_OK
    }

    // Custom shader
    const slot = &slots[sid];
    if (!slot.in_use) return -1;

    const pipeline = slotPipeline(slot);
    if (pipeline == 0) return -1;

    // Tell vk.zig we're using a custom pipeline (>= 2)
    vk_env_bind_pipeline(sid);

    // Sync all engine uniforms to UBO for this group
    syncEnvvToUbo(slot, gid);

    // Bind pipeline + UBO descriptor
    if (vk_env_is_rendering()) {
        // Sync push_cache → env.push_constants so the vertex shader gets
        // correct modelview/projection via layout(push_constant).
        // Without this, env.push_constants retains stale matrices from
        // the last built-in shader activation → wrong vertex positions.
        pushAll();
        const dynamic_offset = gid * slot.ubo_stride;
        vk_env_bind_custom_shader(pipeline, slot.ubo_buffer, slot.ubo_stride, dynamic_offset);

        // DEBUG: dump UBO contents for first custom shader activations
    }

    return 0; // ARCAN_OK
}

export fn agp_shader_envv(slot_idx: c_uint, value: ?*anyopaque, size: usize) c_int {
    if (slot_idx >= envv_table.len) return 0;
    const v = value orelse return 0;

    const info = envv_table[slot_idx];
    const dst: [*]u8 = @ptrCast(&push_cache);
    const src: [*]const u8 = @ptrCast(v);
    const copy_size = @min(size, info.size);
    @memcpy(dst[info.offset .. info.offset + copy_size], src[0..copy_size]);



    // If active shader is custom, also update its UBO
    const sid = SHADER_INDEX(active_shader);
    const gid = GROUP_INDEX(active_shader);
    if (sid >= 2 and sid < MAX_SLOTS) {
        const s = &slots[sid];
        if (s.in_use) {
            const off = s.envv_offsets[slot_idx];
            if (off >= 0) {
                if (s.ubo_mapped) |mapped| {
                    const base = gid * s.ubo_stride;
                    const ubo_off = base + @as(u32, @intCast(off));
                    const sz = @min(info.size, s.envv_sizes[slot_idx]);
                    if (sz > 0) {
                        @memcpy(mapped[ubo_off .. ubo_off + sz], src[0..sz]);
                    }
                }
            }
        }
    }

    // If rendering is active, push updated constants.
    // UBO data is already written via memcpy (host-coherent memory).
    if (vk_env_is_rendering()) {
        if (sid < 2) {
            pushAll();
        } else if (sid < MAX_SLOTS and slots[sid].in_use) {
            // Custom shader: sync push_cache → env.push_constants only.
            // The descriptor set from agp_shader_activate is still bound
            // with the correct UBO buffer, texture, and dynamic offset.
            // No need to allocate a new descriptor set (wastes pool entries).
            pushAll();
        }
    }

    return 1;
}

export fn agp_shader_build(
    tag: ?[*:0]const u8,
    geom: ?[*:0]const u8,
    vert: ?[*:0]const u8,
    frag: ?[*:0]const u8,
) u32 {
    _ = geom;
    const label = tag orelse return BROKEN_SHADER;
    const label_span = std.mem.span(label);
    if (label_span.len == 0) return BROKEN_SHADER;

    // Switch to glibc TLS for shaderc calls (loaded via zig_dlopen)
    if (use_zig_dlopen) zig_dl.zig_foreign_begin();
    defer if (use_zig_dlopen) zig_dl.zig_foreign_end();

    // Load shaderc on first call
    if (!loadShaderc()) {
        std.debug.print("[vk_shdrmgmt] shaderc unavailable, shader '{s}' fails\n", .{label_span});
        return BROKEN_SHADER;
    }

    // Supply defaults if NULL
    var shmask: u8 = 0;
    const vert_src: [*:0]const u8 = vert orelse blk: {
        shmask |= 1;
        break :blk default_vert_src;
    };
    const frag_src: [*:0]const u8 = frag orelse blk: {
        shmask |= 2;
        break :blk default_frag_src;
    };

    // Check for existing slot with same label (overwrite)
    var dstind: ?usize = null;
    var overwrite = false;
    for (0..MAX_SLOTS) |i| {
        if (slots[i].in_use and slots[i].label_len > 0) {
            if (std.mem.eql(u8, slots[i].label[0..slots[i].label_len], label_span)) {
                dstind = i;
                overwrite = true;
                break;
            }
        }
    }

    // Find free slot if no overwrite
    if (dstind == null) {
        // Start scanning from alloc_ofs
        alloc_ofs = (alloc_ofs + 1) % MAX_SLOTS;
        if (alloc_ofs < 2) alloc_ofs = 2; // skip built-in
        if (!slots[alloc_ofs].in_use) {
            dstind = alloc_ofs;
        } else {
            for (2..MAX_SLOTS) |i| {
                if (!slots[i].in_use) {
                    dstind = i;
                    break;
                }
            }
        }
    }

    const idx = dstind orelse {
        std.debug.print("[vk_shdrmgmt] no free shader slot for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    };

    // Destroy old slot if overwriting
    if (overwrite) {
        destroySlot(idx);
    }

    // Compile vertex shader
    const vert_spv = compileGlslToSpirv(vert_src, true) orelse {
        std.debug.print("[vk_shdrmgmt] vertex compile failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    };
    defer std.heap.c_allocator.free(vert_spv.data);

    // Compile fragment shader
    const frag_spv = compileGlslToSpirv(frag_src, false) orelse {
        std.debug.print("[vk_shdrmgmt] fragment compile failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    };
    defer std.heap.c_allocator.free(frag_spv.data);

    // Create shader modules
    const vert_mod = vk_env_create_shader_module(vert_spv.data.ptr, @intCast(vert_spv.len));
    if (vert_mod == 0) {
        std.debug.print("[vk_shdrmgmt] vert module creation failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    }

    const frag_mod = vk_env_create_shader_module(frag_spv.data.ptr, @intCast(frag_spv.len));
    if (frag_mod == 0) {
        vk_env_destroy_shader_module(vert_mod);
        std.debug.print("[vk_shdrmgmt] frag module creation failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    }

    // Create pipelines (SRGB + UNORM)
    const srgb_format = vk_env_get_swapchain_format();
    const pipeline_srgb = vk_env_create_custom_pipeline(vert_mod, frag_mod, srgb_format);
    if (pipeline_srgb == 0) {
        vk_env_destroy_shader_module(vert_mod);
        vk_env_destroy_shader_module(frag_mod);
        std.debug.print("[vk_shdrmgmt] SRGB pipeline creation failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    }

    // UNORM variant for offscreen RT — R8G8B8A8; pixel upload swizzles BGRA→RGBA
    const UNORM_FORMAT: u32 = 37; // VK_FORMAT_R8G8B8A8_UNORM
    const pipeline_unorm = vk_env_create_custom_pipeline(vert_mod, frag_mod, UNORM_FORMAT);
    if (pipeline_unorm == 0) {
        _ = c.printf("[vk_shdrmgmt] UNORM pipeline FAILED for '%.*s'\n", @as(c_int, @intCast(label_span.len)), label_span.ptr);
    }

    // Reflect fragment SPIR-V for UBO layout (fragment has most uniforms)
    var reflect = reflectSpirv(frag_spv.data[0..frag_spv.len]);

    // NOTE: Do NOT merge vertex SPIR-V reflection here. The vertex shader uses
    // layout(push_constant) for engine matrices (modelview, projection, texturem).
    // SPIR-V reflection can't distinguish push_constant Block from UBO Block, so
    // merging would put engine matrices at offsets 0/64/128 in the UBO, overlapping
    // with fragment custom uniforms (col, obj_opacity, etc.) and corrupting them
    // when syncEnvvToUbo writes matrix data.

    // Create UBO — size = MAX_GROUPS * aligned_stride
    const alignment = vk_env_get_ubo_alignment();
    const raw_size = if (reflect.ubo_size > 0) reflect.ubo_size else 256;
    const ubo_stride = ((raw_size + alignment - 1) / alignment) * alignment;
    const total_ubo_size = ubo_stride * MAX_GROUPS;

    var ubo_mapped: ?[*]u8 = null;
    var ubo_desc: u64 = 0;
    const ubo_buffer = vk_env_create_ubo(@intCast(total_ubo_size), @intCast(ubo_stride), &ubo_mapped, &ubo_desc);
    if (ubo_buffer == 0) {
        vk_env_destroy_pipeline(pipeline_srgb);
        if (pipeline_unorm != 0) vk_env_destroy_pipeline(pipeline_unorm);
        vk_env_destroy_shader_module(vert_mod);
        vk_env_destroy_shader_module(frag_mod);
        std.debug.print("[vk_shdrmgmt] UBO creation failed for '{s}'\n", .{label_span});
        return BROKEN_SHADER;
    }
    const ubo_memory = vk_env_get_last_ubo_memory();

    // Zero-init UBO
    if (ubo_mapped) |m| {
        @memset(m[0..total_ubo_size], 0);
    }

    // Fill slot
    const slot = &slots[idx];
    slot.* = .{};
    slot.in_use = true;
    slot.shmask = shmask;

    // Store label
    const copy_len = @min(label_span.len, slot.label.len - 1);
    @memcpy(slot.label[0..copy_len], label_span[0..copy_len]);
    slot.label[copy_len] = 0;
    slot.label_len = @intCast(copy_len);

    // Store source strings
    slot.vert_src = cstrdup(vert_src);
    slot.frag_src = cstrdup(frag_src);

    // Vulkan handles
    slot.vert_module = vert_mod;
    slot.frag_module = frag_mod;
    slot.pipeline_srgb = pipeline_srgb;
    slot.pipeline_unorm = pipeline_unorm;

    // UBO
    slot.ubo_buffer = ubo_buffer;
    slot.ubo_memory = ubo_memory;
    slot.ubo_descriptor = ubo_desc;
    slot.ubo_mapped = ubo_mapped;
    slot.ubo_stride = @intCast(ubo_stride);
    slot.ubo_raw_size = raw_size;

    // Copy uniform metadata
    slot.n_uniforms = reflect.n_uniforms;
    for (0..reflect.n_uniforms) |ui| {
        slot.uniforms[ui].name = reflect.uniforms[ui].name;
        slot.uniforms[ui].name_len = reflect.uniforms[ui].name_len;
        slot.uniforms[ui].ubo_offset = reflect.uniforms[ui].offset;
        slot.uniforms[ui].size = reflect.uniforms[ui].size;
    }

    // Map engine uniforms
    mapEnvvOffsets(slot, &reflect);

    // Create initial group (group 0)
    slot.groups[0] = .{ .in_use = true };
    slot.group_count = 1;

    // Sync current engine uniform values to group 0
    syncEnvvToUbo(slot, 0);

    return @intCast(idx);
}

fn destroySlot(idx: usize) void {
    const slot = &slots[idx];
    if (!slot.in_use) return;

    // Destroy Vulkan resources
    if (slot.pipeline_srgb != 0) vk_env_destroy_pipeline(slot.pipeline_srgb);
    if (slot.pipeline_unorm != 0) vk_env_destroy_pipeline(slot.pipeline_unorm);
    if (slot.vert_module != 0) vk_env_destroy_shader_module(slot.vert_module);
    if (slot.frag_module != 0) vk_env_destroy_shader_module(slot.frag_module);
    if (slot.ubo_buffer != 0) vk_env_destroy_ubo(slot.ubo_buffer, slot.ubo_memory, slot.ubo_descriptor);

    // Free source strings
    cstrfree(slot.vert_src);
    cstrfree(slot.frag_src);

    slot.* = .{};
}

export fn agp_shader_destroy(shid: u32) bool {
    if (shid == BROKEN_SHADER) return false;
    const sid = SHADER_INDEX(shid);
    const gid = GROUP_INDEX(shid);

    if (sid < 2 or sid >= MAX_SLOTS) return false;
    if (!slots[sid].in_use) return false;

    if (gid == 0) {
        // Destroy entire shader
        destroySlot(sid);
        return true;
    }

    // Just destroy a uniform group
    if (gid < MAX_GROUPS and slots[sid].groups[gid].in_use) {
        slots[sid].groups[gid].in_use = false;
        if (slots[sid].group_count > 0) slots[sid].group_count -= 1;
        return true;
    }
    return false;
}

export fn agp_shader_lookup(tag: ?[*:0]const u8) u32 {
    const t = tag orelse return BROKEN_SHADER;
    const name = std.mem.span(t);

    // Check built-in names first
    if (std.mem.eql(u8, name, "DEFAULT")) return 0;
    if (std.mem.eql(u8, name, "DEFAULT_COLOR")) return 1;

    // Search custom slots
    for (2..MAX_SLOTS) |i| {
        if (slots[i].in_use and slots[i].label_len > 0) {
            if (std.mem.eql(u8, slots[i].label[0..slots[i].label_len], name)) {
                return @intCast(i);
            }
        }
    }
    return BROKEN_SHADER;
}

export fn agp_shader_lookuptag(id: u32) ?[*:0]const u8 {
    const sid = SHADER_INDEX(id);
    if (sid == 0) return "DEFAULT";
    if (sid == 1) return "DEFAULT_COLOR";
    if (sid >= MAX_SLOTS or !slots[sid].in_use) return null;
    return @ptrCast(&slots[sid].label);
}

export fn agp_shader_lookupprgs(
    id: u32,
    vert: ?*[*:0]const u8,
    frag: ?*[*:0]const u8,
) bool {
    const sid = SHADER_INDEX(id);
    if (sid < 2) {
        if (vert) |v| v.* = default_vert_src;
        if (frag) |f| f.* = default_frag_src;
        return true;
    }
    if (sid >= MAX_SLOTS or !slots[sid].in_use) return false;

    if (vert) |v| {
        if (slots[sid].vert_src) |s| {
            v.* = @ptrCast(s);
        } else {
            v.* = "";
        }
    }
    if (frag) |f| {
        if (slots[sid].frag_src) |s| {
            f.* = @ptrCast(s);
        } else {
            f.* = "";
        }
    }
    return true;
}

export fn agp_shader_valid(shid: u32) bool {
    if (shid == BROKEN_SHADER) return false;
    const sid = SHADER_INDEX(shid);
    if (sid < 2) return true;
    if (sid >= MAX_SLOTS) return false;
    return slots[sid].in_use;
}

export fn agp_shader_vattribute_loc(attr: c_uint) c_int {
    return switch (attr) {
        0 => 0, // ATTRIBUTE_VERTEX -> location 0
        1 => 1, // ATTRIBUTE_TEXCORD0 -> location 1
        else => -1,
    };
}

export fn agp_shader_addgroup(shid: u32) u32 {
    if (shid == BROKEN_SHADER) return BROKEN_SHADER;
    const sid = SHADER_INDEX(shid);
    const src_gid = GROUP_INDEX(shid);

    if (sid < 2) return BROKEN_SHADER; // built-in shaders don't support groups
    if (sid >= MAX_SLOTS or !slots[sid].in_use) return BROKEN_SHADER;

    const slot = &slots[sid];

    // Find a free group slot
    var new_gid: ?u32 = null;
    for (0..MAX_GROUPS) |gi| {
        if (!slot.groups[gi].in_use) {
            new_gid = @intCast(gi);
            break;
        }
    }
    const gid = new_gid orelse return BROKEN_SHADER;

    slot.groups[gid].in_use = true;
    slot.group_count += 1;

    // Copy source group's UBO data to new group
    if (slot.ubo_mapped) |mapped| {
        const src_off = src_gid * slot.ubo_stride;
        const dst_off = gid * slot.ubo_stride;
        const stride = slot.ubo_stride;
        @memcpy(mapped[dst_off .. dst_off + stride], mapped[src_off .. src_off + stride]);
    }

    return SHADER_ID(sid, gid);
}

const symtbl = [_][*:0]const u8{
    "modelview",
    "projection",
    "texturem",
    "obj_opacity",
    "trans_blend",
    "trans_move",
    "trans_rotate",
    "trans_scale",
    "obj_input_sz",
    "obj_output_sz",
    "obj_storage_sz",
    "rtgt_id",
    "fract_timestamp",
    "timestamp",
};

export fn agp_shader_symtype(env_slot: c_uint) [*:0]const u8 {
    if (env_slot < symtbl.len) return symtbl[env_slot];
    return "unknown";
}

// shdrutype enum values from arcan_videoint.h
const SHDRBOOL: u32 = 0;
const SHDRINT: u32 = 1;
const SHDRFLOAT: u32 = 2;
const SHDRVEC2: u32 = 3;
const SHDRVEC3: u32 = 4;
const SHDRVEC4: u32 = 5;
const SHDRMAT4X4: u32 = 6;

fn shdrutype_size(utype: u32) u32 {
    return switch (utype) {
        SHDRBOOL, SHDRINT => 4,
        SHDRFLOAT => 4,
        SHDRVEC2 => 8,
        SHDRVEC3 => 12,
        SHDRVEC4 => 16,
        SHDRMAT4X4 => 64,
        else => 4,
    };
}

export fn agp_shader_forceunif(
    label: ?[*:0]const u8,
    utype: c_uint,
    value: ?*anyopaque,
) void {
    const lbl = label orelse return;
    const v = value orelse return;
    const name = std.mem.span(lbl);

    const sid = SHADER_INDEX(active_shader);
    const gid = GROUP_INDEX(active_shader);

    // For built-in shaders, handle special cases via push constants
    if (sid < 2) {
        if (std.mem.eql(u8, name, "obj_col")) {
            const src: [*]const f32 = @ptrCast(@alignCast(v));
            push_cache.texturem[0] = src[0];
            push_cache.texturem[1] = src[1];
            push_cache.texturem[2] = src[2];
            if (vk_env_is_rendering()) {
                pushAll();
            }
        }
        return;
    }

    // Custom shader: find uniform in metadata and write to UBO
    if (sid >= MAX_SLOTS or !slots[sid].in_use) return;
    const slot = &slots[sid];
    const mapped = slot.ubo_mapped orelse return;
    const base = gid * slot.ubo_stride;

    // Search for uniform by name
    for (0..slot.n_uniforms) |ui| {
        const uname = slot.uniforms[ui].name[0..slot.uniforms[ui].name_len];
        if (std.mem.eql(u8, uname, name)) {
            const off = base + slot.uniforms[ui].ubo_offset;
            const sz = @min(shdrutype_size(utype), slot.uniforms[ui].size);
            const src: [*]const u8 = @ptrCast(v);
            @memcpy(mapped[off .. off + sz], src[0..sz]);
            // UBO is host-coherent — write is immediately visible to GPU.
            // No descriptor rebind needed; the set from agp_shader_activate
            // already points to this buffer with the correct dynamic offset.
            return;
        }
    }

    // Not found — that's ok, GL backend silently ignores too
}

export fn agp_shader_flush() void {
    for (2..MAX_SLOTS) |i| {
        destroySlot(i);
    }
    alloc_ofs = 2;
    active_shader = 0;
}

export fn agp_shader_unload_all() void {
    agp_shader_flush();
}

export fn agp_shader_rebuild_all() void {
    // For custom shaders, we'd need to recompile from stored source.
    // This is rarely called (only on context loss). For now, no-op.
}
