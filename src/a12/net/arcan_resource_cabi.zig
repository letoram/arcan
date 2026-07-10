// Pure-Zig C-ABI surface for the arcan resource I/O helpers. Upstream lives
// in engine/alt (data_source) + platform/posix/resource_io.c +
// platform/posix/map_resource.c + platform/posix/namespace.c. Our Zig
// ports in map_resource.zig / resource_io.zig have Zig-native APIs
// (allocator-based, named-return structs); this file exposes the C-ABI
// functions the existing callers in dir_lua_appl.zig, dir_lua_support.zig,
// and nbio.zig declare `extern "c"`.
//
// The `data_source` / `map_region` layouts mirror what the callers already
// declare (dir_lua_appl.zig:53-62, dir_lua_support.zig:50-55).

const std = @import("std");
const posix = std.posix;

pub const data_source = extern struct {
    fd: c_int,
    source: ?[*:0]const u8,
};

pub const map_region = extern struct {
    ptr: ?[*]u8,
    sz: usize,
    fd: c_int,
    rst: bool,
};

const MAX_RESMAP_SIZE: usize = 1024 * 1024 * 40;

// C stdlib free — ownership of `data_source.source` when populated via strdup.
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*:0]const u8) ?[*:0]u8;

/// Open a file for read access, setting CLOEXEC. On error fd == -1.
pub export fn arcan_open_resource(arg: [*:0]const u8) callconv(.c) data_source {
    var rv = data_source{ .fd = -1, .source = null };
    const fd = posix.open(
        std.mem.sliceTo(arg, 0),
        .{ .ACCMODE = .RDONLY, .CLOEXEC = true },
        0,
    ) catch return rv;
    rv.fd = @intCast(fd);
    rv.source = strdup(arg);
    return rv;
}

/// Close fd + free source string. Safe to call on an already-released source.
pub export fn arcan_release_resource(src: *data_source) callconv(.c) void {
    if (src.fd >= 0) posix.close(src.fd);
    if (src.source) |s| free(@ptrCast(@constCast(s)));
    src.* = data_source{ .fd = -1, .source = null };
}

/// mmap the resource's fd into memory. Returns .ptr = null on failure.
/// `writable` forces the read-into-heap fallback for a mutable copy.
pub export fn arcan_map_resource(src: *data_source, writable: bool) callconv(.c) map_region {
    var rv = map_region{ .ptr = null, .sz = 0, .fd = -1, .rst = false };
    if (src.fd < 0) return rv;

    const stat = posix.fstat(src.fd) catch return rv;
    const size: usize = if (stat.size > 0) @intCast(stat.size) else 0;
    if (size == 0 or size > MAX_RESMAP_SIZE) return rv;

    const mode = stat.mode & posix.S.IFMT;
    const is_regular = (mode == posix.S.IFREG);

    if (!writable and is_regular) {
        const ptr = posix.mmap(
            null,
            size,
            posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            src.fd,
            0,
        ) catch return rv;
        rv.ptr = ptr.ptr;
        rv.sz = size;
        rv.fd = src.fd;
        rv.rst = false;
        return rv;
    }

    // Heap-read fallback (writable or non-regular).
    const buf = std.heap.c_allocator.alloc(u8, size) catch return rv;
    errdefer std.heap.c_allocator.free(buf);
    var total: usize = 0;
    while (total < size) {
        const n = posix.read(src.fd, buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    if (total == 0) {
        std.heap.c_allocator.free(buf);
        return rv;
    }
    rv.ptr = buf.ptr;
    rv.sz = total;
    rv.fd = src.fd;
    rv.rst = true; // caller frees via c_allocator
    return rv;
}

/// Release a map_region. Uses rst=true to distinguish heap from mmap.
pub export fn arcan_release_map(reg: map_region) callconv(.c) void {
    const p = reg.ptr orelse return;
    if (reg.rst) {
        std.heap.c_allocator.free(p[0..reg.sz]);
    } else {
        posix.munmap(@alignCast(p[0..reg.sz]));
    }
}

// Namespace resolution
//
// Upstream's arcan_find_resource / arcan_expand_resource consult a global
// table of namespace paths populated from ARCAN_* environment variables.
// For a stand-alone arcan-net build — which only hits these helpers from
// directory-server paths that aren't exercised by the interop tests — we
// provide an ENV-driven simple resolver: look up ARCAN_<NAME>PATH for the
// known namespace flags, fall back to null if unset.
//
// This matches the observable behaviour of upstream for end-users who
// export ARCAN_RESOURCEPATH / ARCAN_APPLBASEPATH / etc.

const RESOURCE_NS_USER: c_int = 1 << 30;

// enum arcan_namespaces bit flags from resource_type.h
const RESOURCE_APPL: c_int = 1;
const RESOURCE_APPL_TEMP: c_int = 2;
const RESOURCE_APPL_SHARED: c_int = 4;
const RESOURCE_APPL_STATE: c_int = 8;
const RESOURCE_SYS_APPLBASE: c_int = 16;
const RESOURCE_SYS_APPLSTORE: c_int = 32;
const RESOURCE_SYS_APPLSTATE: c_int = 64;
const RESOURCE_SYS_FONT: c_int = 128;
const RESOURCE_SYS_BINS: c_int = 256;
const RESOURCE_SYS_LIBS: c_int = 512;
const RESOURCE_SYS_DEBUG: c_int = 1024;
const RESOURCE_SYS_SCRIPTS: c_int = 4096;

const ARES_FILE: c_int = 1;
const ARES_FOLDER: c_int = 2;
const ARES_RDONLY: c_int = 4;
const ARES_CREATE: c_int = 8;

fn nsEnvName(ns: c_int) ?[*:0]const u8 {
    return switch (ns) {
        RESOURCE_APPL => "ARCAN_APPLPATH",
        RESOURCE_APPL_TEMP => "ARCAN_APPLTEMPPATH",
        RESOURCE_APPL_SHARED => "ARCAN_RESOURCEPATH",
        RESOURCE_APPL_STATE => "ARCAN_STATEPATH",
        RESOURCE_SYS_APPLBASE => "ARCAN_APPLBASEPATH",
        RESOURCE_SYS_APPLSTORE => "ARCAN_APPLSTOREPATH",
        RESOURCE_SYS_APPLSTATE => "ARCAN_STATEBASEPATH",
        RESOURCE_SYS_FONT => "ARCAN_FONTPATH",
        RESOURCE_SYS_BINS => "ARCAN_BINPATH",
        RESOURCE_SYS_LIBS => "ARCAN_LIBPATH",
        RESOURCE_SYS_DEBUG => "ARCAN_LOGPATH",
        RESOURCE_SYS_SCRIPTS => "ARCAN_SCRIPTPATH",
        else => null,
    };
}

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;

fn joinPath(base: [*:0]const u8, label: [*:0]const u8) ?[*:0]u8 {
    const base_len = std.mem.len(base);
    const label_len = std.mem.len(label);
    const sep: usize = if (label[0] == '/' or base_len == 0) 0 else 1;
    const total = base_len + sep + label_len + 1;
    const buf = std.heap.c_allocator.alloc(u8, total) catch return null;
    @memcpy(buf[0..base_len], base[0..base_len]);
    if (sep == 1) buf[base_len] = '/';
    @memcpy(buf[base_len + sep ..][0..label_len], label[0..label_len]);
    buf[total - 1] = 0;
    return @ptrCast(buf.ptr);
}

fn firstNs(space: c_int) c_int {
    const s = space & ~RESOURCE_NS_USER;
    if (s == 0) return 0;
    return s & -s; // lowest set bit
}

pub export fn arcan_find_resource(
    label: ?[*:0]const u8,
    space: c_int,
    ares: c_int,
    dfd: ?*c_int,
) callconv(.c) ?[*:0]u8 {
    if (dfd) |p| p.* = -1;
    const lbl = label orelse return null;
    if (lbl[0] == 0) return null;

    // Walk the namespace bitmask low-bit-first, same as upstream.
    var s = space & ~RESOURCE_NS_USER;
    while (s != 0) {
        const bit = s & -s;
        s &= ~bit;
        const env = nsEnvName(bit) orelse continue;
        const base = getenv(env) orelse continue;
        const joined = joinPath(base, lbl) orelse continue;

        const st = posix.fstatatZ(posix.AT.FDCWD, joined, 0) catch {
            if ((ares & ARES_CREATE) != 0) return joined;
            std.heap.c_allocator.free(std.mem.span(joined));
            continue;
        };
        const mode = st.mode & posix.S.IFMT;
        const is_file = mode == posix.S.IFREG;
        const is_dir = mode == posix.S.IFDIR;
        if (((ares & ARES_FILE) != 0 and is_file) or
            ((ares & ARES_FOLDER) != 0 and is_dir))
        {
            return joined;
        }
        std.heap.c_allocator.free(std.mem.span(joined));
    }
    return null;
}

pub export fn arcan_expand_resource(
    label: ?[*:0]const u8,
    space: c_int,
) callconv(.c) ?[*:0]u8 {
    const lbl = label orelse return null;
    const bit = firstNs(space);
    if (bit == 0) return null;
    const env = nsEnvName(bit) orelse return null;
    const base = getenv(env) orelse return null;
    if (lbl[0] == 0) return strdup(base);
    return joinPath(base, lbl);
}
