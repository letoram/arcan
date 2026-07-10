// Pure Zig port of posix/paths.c — zero C helpers.
// Path utilities: isdir, isfile, namespace defaults, namespace expansion.

const std = @import("std");
const arcan = @import("arcan");

const posix = std.posix;

const is_darwin = @import("builtin").os.tag.isDarwin();

const c = struct {
    // POSIX
    const stat_t = extern struct {
        // aarch64-linux (glibc): struct stat is 128 bytes.
        // darwin arm64 (__DARWIN_STRUCT_STAT64): 144 bytes.
        _pad: [if (is_darwin) 144 else 128]u8,
    };
    extern fn __xstat(ver: c_int, path: [*c]const u8, buf: *stat_t) c_int;
    // stat() on modern glibc is a wrapper, but we can call the libc stat directly
    extern fn stat(path: [*c]const u8, buf: *stat_t) c_int;
    extern fn getenv(name: [*c]const u8) [*c]const u8;
    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn strlen(s: [*c]const u8) usize;
    extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    extern fn strchr(s: [*c]const u8, ch: c_int) [*c]const u8;
    extern fn malloc(size: usize) ?[*]u8;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
    extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
    extern fn readlink(path: [*c]const u8, buf: [*c]u8, bufsiz: usize) isize;
    extern fn strrchr(s: [*c]const u8, ch: c_int) [*c]u8;
    extern fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) callconv(.c) c_int;
    extern var stderr: *anyopaque;

    // S_IFMT and mode bit masks for aarch64-linux
    const S_IFMT: u32 = 0o170000;
    const S_IFDIR: u32 = 0o040000;
    const S_IFREG: u32 = 0o100000;
    const S_IFIFO: u32 = 0o010000;
    const S_IFSOCK: u32 = 0o140000;

    // stat.st_mode offset: aarch64-linux glibc has a u32 at 16; darwin
    // arm64 a u16 at 4.
    const STAT_MODE_OFFSET: usize = if (is_darwin) 4 else 16;

    fn getStatMode(buf: *stat_t) u32 {
        if (is_darwin) {
            const ptr: *align(2) const u16 = @ptrCast(@alignCast(&buf._pad[STAT_MODE_OFFSET]));
            return ptr.*;
        }
        const ptr: *const u32 = @ptrCast(@alignCast(&buf._pad[STAT_MODE_OFFSET]));
        return ptr.*;
    }
};

export fn arcan_isdir(fn_ptr: [*c]const u8) bool {
    if (fn_ptr == null) return false;
    var buf: c.stat_t = undefined;
    if (c.stat(fn_ptr, &buf) == 0) {
        return (c.getStatMode(&buf) & c.S_IFMT) == c.S_IFDIR;
    }
    return false;
}

export fn arcan_isfile(fn_ptr: [*c]const u8) bool {
    if (fn_ptr == null) return false;
    var buf: c.stat_t = undefined;
    if (c.stat(fn_ptr, &buf) == 0) {
        const mode = c.getStatMode(&buf) & c.S_IFMT;
        return mode == c.S_IFREG or mode == c.S_IFIFO or mode == c.S_IFSOCK;
    }
    return false;
}

const pathks = [_][*c]const u8{
    "path_appltemp",  "path_appl",      "path_resource",  "path_state",
    "path_applbase",  "path_applstore",  "path_statebase", "path_font",
    "path_bin",       "path_lib",        "path_log",       "path_script",
};

const pinks = [_][*c]const u8{
    "pin_appltemp",  "pin_appl",      "pin_resource",  "pin_state",
    "pin_applbase",  "pin_applstore",  "pin_statebase", "pin_font",
    "pin_bin",       "pin_lib",        "pin_log",       "pin_script",
};

const envvs = [_][*c]const u8{
    "ARCAN_APPLPATH",      "ARCAN_RESOURCEPATH",  "ARCAN_APPLTEMPPATH",
    "ARCAN_STATEPATH",     "ARCAN_APPLBASEPATH",  "ARCAN_APPLSTOREPATH",
    "ARCAN_STATEBASEPATH", "ARCAN_FONTPATH",      "ARCAN_BINPATH",
    "ARCAN_LIBPATH",       "ARCAN_LOGPATH",       "ARCAN_SCRIPTPATH",
};

const pinvs = [_][*c]const u8{
    "ARCAN_APPLPIN",      "ARCAN_RESOURCEPIN",  "ARCAN_APPLTEMPPIN",
    "ARCAN_STATEPIN",     "ARCAN_APPLBASEPIN",  "ARCAN_APPLSTOREPIN",
    "ARCAN_STATEBASEPIN", "ARCAN_FONTPIN",      "ARCAN_BINPIN",
    "ARCAN_LIBPIN",       "ARCAN_LOGPIN",       "ARCAN_SCRIPTPIN",
};

fn alloc_cat(a: [*c]const u8, b_arg: [*c]const u8) [*c]u8 {
    const a_sz = c.strlen(a);
    const b_sz = c.strlen(b_arg);
    const newstr = c.malloc(a_sz + b_sz + 1) orelse return null;
    _ = c.memcpy(newstr, a, a_sz);
    _ = c.memcpy(newstr + a_sz, b_arg, b_sz);
    newstr[a_sz + b_sz] = 0;
    return newstr;
}

fn rep_str(instr_arg: [*c]u8) [*c]u8 {
    var instr = instr_arg;
    var pos: [*c]u8 = instr;

    while (true) {
        var beg = c.strchr(pos, '[');
        if (beg == null) return instr;

        const end_ptr = c.strchr(@ptrCast(@constCast(beg) + 1), ']');
        if (end_ptr == null) return instr;
        var end: [*c]u8 = @ptrCast(@constCast(end_ptr));

        // counter abc [ [ARCAN_APPLPATH]
        var step = c.strchr(@ptrCast(@constCast(beg) + 1), '[');
        while (step != null and @intFromPtr(step) < @intFromPtr(end)) {
            beg = step;
            step = c.strchr(@ptrCast(@constCast(beg) + 1), '[');
        }

        var beg_mut: [*c]u8 = @ptrCast(@constCast(beg));
        end[0] = 0;

        var found = false;
        for (0..envvs.len) |i| {
            if (c.strcmp(beg_mut + 1, envvs[i]) == 0) {
                const ns: c_int = @as(c_int, 1) << @intCast(i);
                const exp = arcan.arcan_expand_resource("", ns);
                if (exp != null) {
                    beg_mut[0] = 0;
                    const newstr = alloc_cat(instr, exp);
                    const resstr = alloc_cat(newstr, end + 1);
                    c.free(instr);
                    c.free(newstr);
                    pos = resstr;
                    instr = resstr;
                }
                arcan.arcan_mem_free(exp);
                found = true;
                break;
            }
        }

        if (!found) {
            end[0] = ']';
            pos = end;
        }
    }
}

export fn arcan_expand_namespaces(inargs: [*c][*c]u8) [*c][*c]u8 {
    if (inargs == null) return inargs;
    var work = inargs;
    while (work[0] != null) {
        work[0] = rep_str(work[0]);
        work += 1;
    }
    return inargs;
}

fn exe_dir() ?[*:0]const u8 {
    const State = struct {
        var dir: [4096]u8 = undefined;
        var result: ?[*:0]const u8 = null;
        var cached: bool = false;
    };
    if (State.cached) return State.result;
    State.cached = true;
    if (comptime @import("builtin").os.tag.isDarwin()) {
        // no /proc on darwin; dyld tracks the executable path
        var sz: u32 = State.dir.len - 1;
        if (_NSGetExecutablePath(&State.dir, &sz) != 0) return null;
    } else {
        const len = c.readlink("/proc/self/exe", &State.dir, State.dir.len - 1);
        if (len <= 0) return null;
        const ulen: usize = @intCast(len);
        State.dir[ulen] = 0;
    }
    const slash = c.strrchr(&State.dir, '/');
    if (slash != null) slash[0] = 0;
    State.result = @ptrCast(&State.dir);
    return State.result;
}

extern "c" fn _NSGetExecutablePath(buf: [*c]u8, bufsize: *u32) c_int;

fn binpath_unix() [*c]u8 {
    if (exe_dir()) |edir| {
        var buf: [4096]u8 = undefined;
        _ = c.snprintf(&buf, buf.len, "%s/arcan_frameserver", edir);
        if (arcan_isfile(&buf))
            return c.strdup(&buf);
    }
    if (arcan_isfile("./arcan_frameserver"))
        return c.strdup("./arcan_frameserver");
    if (arcan_isfile("/usr/local/bin/arcan_frameserver"))
        return c.strdup("/usr/local/bin/arcan_frameserver");
    if (arcan_isfile("/usr/bin/arcan_frameserver"))
        return c.strdup("/usr/bin/arcan_frameserver");
    return null;
}

fn scriptpath_unix() [*c]u8 {
    if (exe_dir()) |edir| {
        var buf: [4096]u8 = undefined;
        _ = c.snprintf(&buf, buf.len, "%s/../share/arcan/scripts", edir);
        if (arcan_isdir(&buf))
            return c.strdup(&buf);
    }
    if (arcan_isdir("/usr/local/share/arcan/scripts"))
        return c.strdup("/usr/local/share/arcan/scripts");
    if (arcan_isdir("/usr/share/arcan/scripts"))
        return c.strdup("/usr/share/arcan/scripts");
    return null;
}

fn unix_find(fname: [*c]const u8) [*c]u8 {
    // Match upstream priority order: cwd first, then $HOME/.arcan,
    // then system install dirs. Our bundled zig-out/share/arcan must
    // rank BELOW $HOME/.arcan, otherwise APPLSTORE (which backs
    // RESOURCE_APPL_TEMP for each appl) resolves to a read-only
    // install path and e.g. durian's control socket ends up there
    // instead of in ~/.arcan/appl/durian/.
    const home = c.getenv("HOME");
    var homebuf: [512]u8 = undefined;
    if (home != null) {
        _ = c.snprintf(&homebuf, homebuf.len, "%s/.arcan", home);
    } else {
        homebuf[0] = 0;
    }

    var exepath: [4096]u8 = undefined;
    exepath[0] = 0;
    if (exe_dir()) |edir| {
        _ = c.snprintf(&exepath, exepath.len, "%s/../share/arcan", edir);
    }

    // exepath (`<bindir>/../share/arcan`) is tried BEFORE the system
    // prefixes so a self-contained tree (e.g. built into ./zig-out and run
    // as ./zig-out/bin/arcan) wins over a stale `/usr/local/share/arcan`
    // left by an older install. For a real system install
    // (/usr/local/bin/arcan) exepath resolves to /usr/local/share/arcan
    // anyway, so system deployments are unaffected.
    const pathtbl = [_][*c]const u8{
        ".",
        &homebuf,
        if (exepath[0] != 0) @as([*c]const u8, &exepath) else null,
        "/usr/local/share/arcan",
        "/usr/share/arcan",
    };

    for (pathtbl) |base| {
        if (base == null) continue;
        var buf: [4096]u8 = undefined;
        _ = c.snprintf(&buf, buf.len, "%s/%s", base, fname);
        if (arcan_isdir(&buf))
            return c.strdup(&buf);
    }

    return null;
}

export fn arcan_set_namespace_defaults() void {
    var tag: usize = 0;
    const get_config = arcan.platform_config_lookup(&tag);

    // use environment variables / config as hard overrides
    for (0..envvs.len) |i| {
        const ns: c_int = @as(c_int, 1) << @intCast(i);
        var tmp: [*c]u8 = null;
        if (get_config) |cfg_fn| {
            if (cfg_fn(pathks[i], 0, &tmp, tag) and tmp != null) {
                arcan.arcan_override_namespace(tmp, ns);
                c.free(tmp);
            }
        }

        const env = c.getenv(envvs[i]);
        if (env != null)
            arcan.arcan_override_namespace(env, ns);

        if (get_config) |cfg_fn| {
            if (c.getenv(pinvs[i]) != null or cfg_fn(pinks[i], 0, &tmp, tag))
                arcan.arcan_pin_namespace(ns);
        } else {
            if (c.getenv(pinvs[i]) != null)
                arcan.arcan_pin_namespace(ns);
        }
    }

    const scrp = scriptpath_unix();
    arcan.arcan_softoverride_namespace(scrp, arcan.RESOURCE_SYS_SCRIPTS);
    c.free(scrp);

    const binpath = binpath_unix();
    arcan.arcan_softoverride_namespace(binpath, arcan.RESOURCE_SYS_BINS);
    c.free(binpath);

    var respath = unix_find("resources");
    if (respath == null)
        respath = arcan.arcan_expand_resource("", arcan.RESOURCE_APPL_SHARED);

    if (respath != null) {
        const len = c.strlen(respath);
        var debug_dir: [1024]u8 = undefined;
        var font_dir: [1024]u8 = undefined;
        _ = c.snprintf(&debug_dir, debug_dir.len, "%s/logs", respath);
        _ = c.snprintf(&font_dir, font_dir.len, "%s/fonts", respath);

        arcan.arcan_softoverride_namespace(respath, arcan.RESOURCE_APPL_SHARED);
        arcan.arcan_softoverride_namespace(&debug_dir, arcan.RESOURCE_SYS_DEBUG);
        arcan.arcan_softoverride_namespace(respath, arcan.RESOURCE_APPL_STATE);
        arcan.arcan_softoverride_namespace(&font_dir, arcan.RESOURCE_SYS_FONT);
        arcan.arcan_mem_free(respath);
        _ = len;
    }

    const scrpath = unix_find("appl");
    if (scrpath != null) {
        arcan.arcan_softoverride_namespace(scrpath, arcan.RESOURCE_SYS_APPLBASE);
        arcan.arcan_softoverride_namespace(scrpath, arcan.RESOURCE_SYS_APPLSTORE);
        arcan.arcan_mem_free(scrpath);
    }

    var tmp2 = arcan.arcan_expand_resource("", arcan.RESOURCE_SYS_APPLSTATE);
    if (tmp2 == null) {
        tmp2 = arcan.arcan_expand_resource("savestates", arcan.RESOURCE_APPL_SHARED);
        if (tmp2 != null)
            arcan.arcan_override_namespace(tmp2, arcan.RESOURCE_SYS_APPLSTATE);
    }
    arcan.arcan_mem_free(tmp2);
}
