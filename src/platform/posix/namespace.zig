// Pure Zig port of posix/namespace.c — zero C helpers.
// Namespace management: resource lookup, expansion, override.

const std = @import("std");

const c = struct {
    extern fn open(path: [*c]const u8, flags: c_int, ...) callconv(.c) c_int;
    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn strlen(s: [*c]const u8) usize;
    extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    extern fn strcat(dst: [*c]u8, src: [*c]const u8) [*c]u8;
    extern fn strchr(s: [*c]const u8, ch: c_int) [*c]const u8;
    extern fn strsep(stringp: *[*c]u8, delim: [*c]const u8) [*c]u8;
    extern fn strtok_r(s: [*c]u8, delim: [*c]const u8, saveptr: *[*c]u8) [*c]u8;
    extern fn getenv(name: [*c]const u8) [*c]const u8;
    extern fn malloc(size: usize) ?[*]u8;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
    extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
    extern fn isalnum(ch: c_int) c_int;

    const O_CLOEXEC: c_int = 0o2000000;
    const O_DIRECTORY: c_int = 0o200000;
    const O_CREAT: c_int = 0o100;
    const O_RDWR: c_int = 0o2;
    const O_EXCL: c_int = 0o200;
    const O_RDONLY: c_int = 0;
    const S_IRWXU: c_int = 0o700;
};

// Engine API
extern fn verify_traverse(path: [*c]const u8) [*c]const u8;
extern fn arcan_isfile(path: [*c]const u8) bool;
extern fn arcan_isdir(path: [*c]const u8) bool;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_mem_freearr(arr: *arcan_strarr) void;
extern fn arcan_mem_growarr(arr: *arcan_strarr) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

const arcan_dbh = anyopaque;
extern fn arcan_db_get_shared(appl: ?*[*c]const u8) ?*arcan_dbh;
extern fn arcan_db_applkeys(dbh: ?*arcan_dbh, appl: [*c]const u8, pattern: [*c]const u8) arcan_strarr;

const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    data: [*c][*c]u8,
};

const arcan_userns = extern struct {
    read: bool,
    write: bool,
    ipc: bool,
    dirfd: c_int,
    label: [64]u8,
    name: [32]u8,
    path: [256]u8,
};

// Memory type / hint constants
const ARCAN_MEM_EXTSTRUCT: c_int = 3;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// Resource namespace constants
const RESOURCE_SYS_ENDM: c_int = 2048;
const RESOURCE_SYS_LIBS: c_int = 512;
const RESOURCE_SYS_BINS: c_int = 256;
const RESOURCE_NS_USER: c_int = 4096;

// Resource type flags
const ARES_FILE: c_int = 1;
const ARES_FOLDER: c_int = 2;
const ARES_CREATE: c_int = 256;
const ARES_RDONLY: c_int = 512;

const FRAMESERVER_MODESTRING = "terminal game net decode encode remoting avfeed";
const NUM_NS = 12;

// Module state
var namespaces: struct {
    paths: [NUM_NS][*c]u8 = [_][*c]u8{null} ** NUM_NS,
    flags: [NUM_NS]c_int = [_]c_int{0} ** NUM_NS,
    lenv: [NUM_NS]c_int = [_]c_int{0} ** NUM_NS,
} = .{};

const lbls = [NUM_NS][*c]const u8{
    "application-temporary",
    "application",
    "application-shared",
    "application-state",
    "system-applbase",
    "system-applstore",
    "system-statebase",
    "system-font",
    "system-binaries",
    "system-libraries",
    "system-debugoutput",
    "system-scripts",
};

var atypestr: [*c]u8 = null;

fn ns_debug_enabled() bool {
    const State = struct {
        var checked: bool = false;
        var enabled: bool = false;
    };
    if (!State.checked) {
        State.checked = true;
        State.enabled = c.getenv("ARCAN_NS_DEBUG") != null;
    }
    return State.enabled;
}

fn i_log2(n_arg: u32) u32 {
    var n = n_arg;
    var res: u32 = 0;
    n >>= 1;
    while (n > 0) : (n >>= 1) {
        res += 1;
    }
    return res;
}

fn find_ns_user(str: [*c]const u8, dns: ?*arcan_userns) [*c]u8 {
    var i: usize = 0;
    while (str[i] != 0 and c.isalnum(@intCast(str[i])) != 0) : (i += 1) {}

    if (str[i] != ':' or str[i + 1] != '/')
        return null;

    var ns = std.mem.zeroes(arcan_userns);
    if (i > ns.name.len - 1)
        return null;

    for (0..i) |k| ns.name[k] = str[k];

    if (!arcan_lookup_namespace(&ns.name, &ns, false))
        return null;

    const str_rest_len = c.strlen(str + i + 2);
    const ns_path_len = cstrlen_arr(&ns.path);
    const path_sz = str_rest_len + 1 + ns_path_len + 1;
    const res = c.malloc(path_sz) orelse return null;
    _ = c.snprintf(res, path_sz, "%s/%s", @as([*c]const u8, &ns.path), str + i + 2);

    if (dns) |d| d.* = ns;
    return res;
}

fn handle_dynfile(base: [*c]u8, ares: c_int, dfd: ?*c_int) [*c]u8 {
    const d = dfd orelse return base;

    var fl: c_int = c.O_CLOEXEC;
    if ((ares & ARES_FOLDER) != 0)
        fl |= c.O_DIRECTORY;

    if ((ares & ARES_CREATE) != 0) {
        d.* = c.open(base, fl | c.O_CREAT | c.O_RDWR | c.O_EXCL, c.S_IRWXU);
    } else {
        const ofl: c_int = if ((ares & ARES_RDONLY) != 0) c.O_RDONLY else c.O_RDWR;
        d.* = c.open(base, ofl);
    }

    if (d.* == -1) {
        if (ns_debug_enabled())
            arcan_warning("[ns] handle_dynfile: open(%s, ares=0x%x) failed errno=%d\n",
                base, ares, if (comptime @import("builtin").os.tag == .freestanding) @as(c_int, 0) else std.c._errno().*);
        c.free(base);
        return null;
    }
    return base;
}

fn cstrlen_arr(s: []const u8) usize {
    for (0..s.len) |i| {
        if (s[i] == 0) return i;
    }
    return s.len;
}

export fn arcan_find_resource(
    label: [*c]const u8,
    space_arg: c_int,
    ares: c_int,
    dfd: ?*c_int,
) [*c]u8 {
    if (dfd) |d| d.* = -1;

    const dbg = ns_debug_enabled();

    if (label == null or verify_traverse(label) == null) {
        if (dbg)
            arcan_warning("[ns] find_resource: label=%s rejected by verify_traverse\n",
                if (label == null) @as([*c]const u8, "<null>") else label);
        return null;
    }

    if (dbg)
        arcan_warning("[ns] find_resource(label=%s, space=0x%x, ares=0x%x)\n",
            label, space_arg, ares);

    if ((space_arg & RESOURCE_NS_USER) != 0) {
        var ns: arcan_userns = undefined;
        const res = find_ns_user(label, &ns);
        if (res != null) {
            if ((ares & ARES_FILE) != 0) {
                const read = (ares & ARES_RDONLY) != 0;
                if ((ns.read and read) or ns.write)
                    return handle_dynfile(res, ares, dfd);
            }
            if ((ares & ARES_FOLDER) != 0 and arcan_isdir(res))
                return handle_dynfile(res, ares, dfd);
            c.free(res);
            if (dbg)
                arcan_warning("[ns]   user-ns matched but ares mismatch -> NULL\n");
            return null;
        }
    }

    const space = space_arg & ~RESOURCE_NS_USER;

    var i: c_int = 1;
    var j: u32 = 0;
    while (i <= RESOURCE_SYS_ENDM) : ({
        i <<= 1;
        j += 1;
    }) {
        if ((space & i) == 0) continue;
        if (namespaces.paths[j] == null) {
            if (dbg)
                arcan_warning("[ns]   bit=0x%x ns[%d/%s] path=NULL\n",
                    i, j, lbls[j]);
            continue;
        }

        var scratch: [2048]u8 = undefined;
        const fmt: [*c]const u8 = if (label[0] == '/') "%s%s" else "%s/%s";
        _ = c.snprintf(&scratch, scratch.len, fmt, namespaces.paths[j], label);

        const isf = arcan_isfile(&scratch);
        const isd = arcan_isdir(&scratch);
        if (dbg)
            arcan_warning("[ns]   bit=0x%x ns[%d/%s]=%s -> %s (isfile=%d isdir=%d)\n",
                i, j, lbls[j], namespaces.paths[j],
                @as([*c]const u8, &scratch), @as(c_int, if (isf) 1 else 0),
                @as(c_int, if (isd) 1 else 0));

        if (((ares & ARES_FILE) != 0 and isf) or
            ((ares & ARES_FOLDER) != 0 and isd))
        {
            return handle_dynfile(c.strdup(&scratch), ares, dfd);
        } else if ((ares & ARES_CREATE) != 0) {
            return handle_dynfile(c.strdup(&scratch), ares, dfd);
        }
    }

    if (dbg)
        arcan_warning("[ns] find_resource(%s) -> NULL\n", label);
    return null;
}

export fn arcan_fetch_namespace(space_arg: c_int) [*c]u8 {
    const space = space_arg & ~RESOURCE_NS_USER;
    const space_ind = i_log2(@intCast(space));
    if (space_ind >= NUM_NS) return null;
    return namespaces.paths[space_ind];
}

export fn arcan_expand_resource(label: [*c]const u8, space_arg: c_int) [*c]u8 {
    if ((space_arg & RESOURCE_NS_USER) != 0) {
        return find_ns_user(label, null);
    }

    const space = space_arg & ~RESOURCE_NS_USER;
    const space_ind = i_log2(@intCast(space));

    if (space_ind >= NUM_NS or
        label == null or verify_traverse(label) == null or
        namespaces.paths[space_ind] == null)
        return null;

    const len_1 = c.strlen(label);
    const len_2: usize = @intCast(namespaces.lenv[space_ind]);

    if (len_1 == 0) {
        return if (namespaces.paths[space_ind] != null)
            c.strdup(namespaces.paths[space_ind])
        else
            null;
    }

    var cbuf: [2048]u8 = undefined;
    const total = len_2 + 1 + len_1 + 1;
    if (total > cbuf.len) return null;

    _ = c.memcpy(&cbuf, namespaces.paths[space_ind], len_2);
    cbuf[len_2] = '/';
    const dst_off = len_2 + (if (label[0] == '/') @as(usize, 0) else @as(usize, 1));
    _ = c.memcpy(@as([*]u8, &cbuf) + dst_off, label, len_1 + 1);

    return c.strdup(&cbuf);
}

export fn arcan_frameserver_atypes() [*c]const u8 {
    return if (atypestr != null) atypestr else "";
}

export fn arcan_verify_namespaces(report_arg: bool) bool {
    var working = true;
    const report = report_arg or ns_debug_enabled();

    if (report)
        arcan_warning("--- Verifying Namespaces: ---\n");

    const libs_ind = i_log2(@intCast(RESOURCE_SYS_LIBS));
    for (0..NUM_NS) |i| {
        if (namespaces.paths[i] == null) {
            if (i != libs_ind) {
                working = false;
                if (report)
                    arcan_warning("%s -- broken\n", lbls[i]);
                continue;
            }
        }
        if (report)
            arcan_warning("%s -- OK (%s)\n", lbls[i], namespaces.paths[i]);
    }

    if (report)
        arcan_warning("--- Namespace Verification Completed ---\n");

    if (working) {
        if (atypestr == null)
            atypestr = c.strdup(FRAMESERVER_MODESTRING);

        // In-process dispatch: every mode in FRAMESERVER_MODESTRING is linked
        // into `may` and dispatched by frameserver_main (src/frameserver/
        // frameserver.zig). The legacy "scan SYS_BINS / self-exe-dir for
        // afsrv_<mode> binaries" verification is gone — `AFSRV_BLOCK_<mode>`
        // is still honoured to disable individual modes at runtime.
        if (atypestr != null) {
            var toktmp_buf: [256]u8 = undefined;
            const ms = FRAMESERVER_MODESTRING;
            for (0..ms.len) |i| toktmp_buf[i] = ms[i];
            toktmp_buf[ms.len] = 0;

            atypestr[0] = 0;
            var tokctx: [*c]u8 = undefined;
            var tok = c.strtok_r(&toktmp_buf, " ", &tokctx);
            var first = true;
            while (tok != null) {
                var exp: [256]u8 = undefined;
                _ = c.snprintf(&exp, exp.len, "AFSRV_BLOCK_%s", tok);
                if (c.getenv(&exp) == null) {
                    if (!first) _ = c.strcat(atypestr, " ");
                    _ = c.strcat(atypestr, tok);
                    first = false;
                }
                tok = c.strtok_r(null, " ", &tokctx);
            }
        }
    }

    return working;
}

export fn arcan_softoverride_namespace(new: [*c]const u8, space: c_int) void {
    const sp = space & ~RESOURCE_NS_USER;
    const tmp = arcan_expand_resource("", sp);
    if (tmp == null)
        arcan_override_namespace(new, sp)
    else
        c.free(tmp);
}

export fn arcan_pin_namespace(space: c_int) void {
    const sp = space & ~RESOURCE_NS_USER;
    const ind = i_log2(@intCast(sp));
    if (ind < NUM_NS)
        namespaces.flags[ind] = 1;
}

export fn arcan_override_namespace(path: [*c]const u8, space: c_int) void {
    if (path == null) return;

    const sp = space & ~RESOURCE_NS_USER;
    const space_ind = i_log2(@intCast(sp));
    if (space_ind >= NUM_NS) return;

    if (namespaces.paths[space_ind] != null) {
        if (namespaces.flags[space_ind] != 0) return;
        arcan_mem_free(namespaces.paths[space_ind]);
    }

    namespaces.paths[space_ind] = c.strdup(path);
    namespaces.lenv[space_ind] = @intCast(c.strlen(namespaces.paths[space_ind]));
}

fn decompose(ns_arg: [*c]u8, dst: *arcan_userns) bool {
    dst.* = std.mem.zeroes(arcan_userns);
    var tmp: [*c]u8 = ns_arg;

    // Find '=' separator (ns_key=...)
    while (tmp[0] != '=' and tmp[0] != 0) : (tmp += 1) {}
    if (tmp[0] == 0) return false;
    tmp[0] = 0;
    tmp += 1;

    // Name is after "ns_" prefix (3 chars)
    const name_src = ns_arg + 3;
    const name_len = c.strlen(name_src);
    const copy_len = if (name_len >= dst.name.len) dst.name.len - 1 else name_len;
    for (0..copy_len) |i| dst.name[i] = name_src[i];

    var pos: usize = 0;
    while (tmp != null and tmp[0] != 0) {
        const cur = c.strsep(&tmp, ":");
        switch (pos) {
            0 => {
                const l = c.strlen(cur);
                const cl = if (l >= 64) @as(usize, 63) else l;
                for (0..cl) |i| dst.label[i] = cur[i];
            },
            1 => {
                if (c.strchr(cur, 'r') != null) dst.read = true;
                if (c.strchr(cur, 'w') != null) dst.write = true;
                if (c.strchr(cur, 'p') != null) dst.ipc = true;
            },
            2 => {
                const l = c.strlen(cur);
                const cl = if (l >= dst.path.len) dst.path.len - 1 else l;
                for (0..cl) |i| dst.path[i] = cur[i];
                return true;
            },
            else => {},
        }
        pos += 1;
    }

    return false;
}

export fn arcan_user_namespaces() arcan_strarr {
    var res = std.mem.zeroes(arcan_strarr);
    var ids = arcan_db_applkeys(arcan_db_get_shared(null), "arcan", "ns_%");

    if (ids.count == 0) {
        arcan_mem_freearr(&ids);
        return res;
    }

    var iind: usize = 0;
    while (ids.data[iind] != null) {
        if (res.count == res.limit) {
            arcan_mem_growarr(&res);
            if (res.count == res.limit) break;
        }

        var tmp: arcan_userns = undefined;
        if (decompose(ids.data[iind], &tmp)) {
            const cdata: [*c]?*anyopaque = @ptrCast(res.data);
            cdata[res.count] = arcan_alloc_mem(
                @sizeOf(arcan_userns),
                ARCAN_MEM_EXTSTRUCT,
                ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL,
                ARCAN_MEMALIGN_NATURAL,
            );
            if (cdata[res.count] == null) break;
            const dst: *arcan_userns = @ptrCast(@alignCast(cdata[res.count].?));
            dst.* = tmp;
            res.count += 1;
        } else {
            arcan_warning("bad user-namespace format: %s (label:perm:path)", ids.data[iind]);
        }
        iind += 1;
    }

    arcan_mem_freearr(&ids);
    return res;
}

export fn arcan_lookup_namespace(
    id: [*c]const u8,
    dst: *arcan_userns,
    dfd: bool,
) bool {
    const id_len = c.strlen(id);
    const len = id_len + 4; // "ns_" + id + null
    const buf = c.malloc(len) orelse return false;
    _ = c.snprintf(buf, len, "ns_%s", id);

    var tbl = arcan_db_applkeys(arcan_db_get_shared(null), "arcan", buf);
    c.free(buf);
    var res = false;

    if (tbl.count == 1) {
        res = decompose(tbl.data[0], dst);
    }

    if (dfd and dst.path[0] != 0) {
        const dirfd = c.open(&dst.path, c.O_RDWR, c.O_DIRECTORY);
        if (dirfd == -1) {
            arcan_mem_freearr(&tbl);
            dst.* = std.mem.zeroes(arcan_userns);
        }
    }

    arcan_mem_freearr(&tbl);
    return res;
}
