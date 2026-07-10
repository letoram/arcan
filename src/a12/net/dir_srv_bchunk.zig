// Zig port of a12/net/dir_srv_bchunk.c — binary chunk handling for the
// directory server: file uploads/downloads, state store/restore, and binary
// stream management for worker <-> parent privilege-boundary requests.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    pub const FILE = libc.FILE;
    pub const exit = libc.exit;
    pub const EXIT_SUCCESS = libc.EXIT_SUCCESS;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
    pub const close = libc.close;
    pub const fclose = libc.fclose;
    pub const fcntl = libc.fcntl;
    pub const fdopen = libc.fdopen;
    pub const fork = libc.fork;
    pub const free = libc.free;
    pub const fwrite = libc.fwrite;
    pub const lseek = libc.lseek;
    pub const malloc = libc.malloc;
    pub const openat = libc.openat;
    pub const pipe = libc.pipe;
    pub const renameat = libc.renameat;
    pub const snprintf = libc.snprintf;
    pub const strcmp = libc.strcmp;
    pub const execv = libc.execv;

    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;

    pub const struct_a12_state = a12.struct_a12_state;
    // appl_meta + shmifsrv_client live in both a12_types and anet_types; this
    // consumer accesses `dirsrv_config().dir` (anet-origin), so it must use the
    // anet_types definitions so pointer types line up through the helper struct.
    pub const struct_appl_meta = anet.struct_appl_meta;
    pub const struct_shmifsrv_client = anet.struct_shmifsrv_client;

    pub const struct_anet_dirsrv_opts = anet.struct_anet_dirsrv_opts;
    pub const struct_dircl = anet.struct_dircl;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const SERVER_APPL_TEMP = a12.SERVER_APPL_TEMP;
    pub const SERVER_APPL_PRIMARY = a12.SERVER_APPL_PRIMARY;
};

// C extern functions called by this module

extern "c" fn a12helper_keystore_accepted(pubk: [*]const u8, tag: ?[*]const u8) bool;
extern "c" fn a12helper_keystore_statestore(
    pubk: [*]const u8,
    name: [*]const u8,
    flags: c_int,
    mode: [*]const u8,
) c_int;
extern "c" fn buf_memfd(buf: ?[*]const u8, buf_sz: usize) c_int;
extern "c" fn file_to_membuf(applin: *c.FILE, out: *?[*]u8, out_sz: *usize) ?*c.FILE;
extern "c" fn verify_appl_pkg(
    buf: [*]u8,
    buf_sz: usize,
    insig_pk: [*]u8,
    outsig_pk: [*]u8,
    errmsg: *?[*]const u8,
) ?[*:0]u8;
extern "c" fn shmifsrv_enqueue_event(
    cl: ?*c.struct_shmifsrv_client,
    ev: *const c.struct_arcan_event,
    fd: c_int,
) bool;
extern "c" fn dirsrv_global_lock(file: [*:0]const u8, line: c_int) void;
extern "c" fn dirsrv_global_unlock(file: [*:0]const u8, line: c_int) void;
extern "c" fn dirsrv_config() *c.struct_anet_dirsrv_opts;
extern "c" fn dirsrv_opts() ?*c.struct_global_cfg;
extern "c" fn build_appl_pkg(
    name: ?[*:0]u8,
    dst: *c.struct_appl_meta,
    dirfd: c_int,
    signtag: ?[*:0]const u8,
) bool;
extern "c" fn dirsrv_trace_state() *c.struct_a12_state;
extern "c" fn dirsrv_locked_numid_appl(id: u16) ?*c.struct_appl_meta;
extern "c" fn anet_directory_lua_spawn_runner(appl: *c.struct_appl_meta, external: bool) bool;
extern "c" fn anet_directory_lua_monitor(C: *c.struct_dircl, appl: *c.struct_appl_meta) bool;
extern "c" fn anet_directory_lua_update(appl: *c.struct_appl_meta, newappl: c_int) void;
extern "c" fn anet_directory_shmifsrv_set(opts: *c.struct_anet_dirsrv_opts) void;
extern "c" fn dirsrv_build_report(appl: [*c]const u8) c_int;
extern "c" fn dirsrv_flush_report(appl: [*c]const u8) void;
extern "c" fn a12int_trace(target: c_int, fmt: [*:0]const u8, ...) void;
extern "c" var a12_trace_targets: c_int;

// dir_lua.h — resource hook lookup (config.lua hook_resource(...) registry).
extern "c" fn anet_directory_lua_resource_hooked(
    ext: [*:0]const u8,
    ns: usize,
    argv_reserve: usize,
    tag: *?[*c]u8,
    bin: *?[*c]u8,
    argv: *[*c][*c]u8,
    argv_used: *usize,
) bool;

// a12_helper.h — base64 encoder (used for --ident arg when spawning hook).
extern "c" fn a12helper_tob64(data: [*]const u8, inl: usize, outl: *usize) ?[*:0]u8;

// BLAKE3
// blake3_hasher may come through opaque via cImport; use explicit externs.
const Blake3Hasher = opaque {};
extern "c" fn blake3_hasher_init(hasher: *Blake3Hasher) void;
extern "c" fn blake3_hasher_update(hasher: *Blake3Hasher, input: *const anyopaque, input_len: usize) void;
extern "c" fn blake3_hasher_finalize(hasher: *Blake3Hasher, out: [*]u8, out_len: usize) void;

// errno
// errno is a macro in glibc and cannot be accessed as c.errno; use a thin
// C-linkage helper instead.
extern "c" fn __errno_location() *c_int;
inline fn getErrno() c_int {
    return __errno_location().*;
}

// Constants

// A12_TRACE_DIRECTORY value from a12_int.h
const A12_TRACE_DIRECTORY: c_int = 16;

const SIG_PUBK_SZ: usize = 32;

// Open flags — POSIX values for Linux/aarch64
const O_RDONLY: c_int = 0;
const O_WRONLY: c_int = 1;
const O_RDWR: c_int = 2;
const O_CREAT: c_int = 0o100;
const O_TRUNC: c_int = 0o1000;
const O_CLOEXEC: c_int = 0o2000000;
const O_DIRECTORY: c_int = 0o200000;
const FD_CLOEXEC: c_int = 1;
const F_SETFD: c_int = 2;
const SEEK_SET: c_int = 0;

// Identifier type enum
// Maps the extension suffix of a resource request to a handling mode.

const IdType = enum(c_int) {
    appl   = 0,
    state  = 1,
    debug  = 2,
    raw    = 3,
    actrl  = 4,
    mon    = 5,
    report = 6,
};

// Trace macro equivalents
// A12INT_DIRTRACE: lock, trace, unlock.
// A12INT_DIRTRACE_LOCKED: trace only (lock already held by caller).
//
// Both are expressed as comptime-inlined macros via inline fn + comptime fmt.
// The file/line arguments to the lock/unlock are cosmetic; pass a literal.

const TRACE_FILE: [*:0]const u8 = "dir_srv_bchunk.zig";

inline fn dirtrace(comptime fmt: [*:0]const u8, args: anytype) void {
    if (a12_trace_targets & A12_TRACE_DIRECTORY == 0) return;
    _ = dirsrv_trace_state();
    dirsrv_global_lock(TRACE_FILE, 0);
    @call(.auto, a12int_trace, .{ A12_TRACE_DIRECTORY, fmt } ++ args);
    dirsrv_global_unlock(TRACE_FILE, 0);
}

inline fn dirtraceLocked(comptime fmt: [*:0]const u8, args: anytype) void {
    if (a12_trace_targets & A12_TRACE_DIRECTORY == 0) return;
    _ = dirsrv_trace_state();
    @call(.auto, a12int_trace, .{ A12_TRACE_DIRECTORY, fmt } ++ args);
}

// identifierToAppl
// Parse the resource identifier extension string into an IdType.

fn identifierToAppl(sep: [*:0]const u8) IdType {
    const s = std.mem.span(sep);
    if (std.mem.eql(u8, s, ".state"))   return .state;
    if (std.mem.eql(u8, s, ".debug"))   return .debug;
    if (std.mem.eql(u8, s, ".report"))  return .report;
    if (std.mem.eql(u8, s, ".appl"))    return .appl;
    if (std.mem.eql(u8, s, ".ctrl"))    return .actrl;
    if (std.mem.eql(u8, s, ".monitor")) return .mon;
    // Non-empty unknown suffix → raw; empty → raw too (length check collapsed).
    return .raw;
}

// getStateRes
// Open the keystore-backed state file "<appl><name>" for reading or writing.
// fl == O_RDONLY (0) → read mode, anything else → write mode.

fn getStateRes(
    C: *c.struct_dircl,
    appl: [*:0]const u8,
    name: [*:0]const u8,
    fl: c_int,
) c_int {
    var fnbuf: [64]u8 = undefined;
    dirsrv_global_lock(TRACE_FILE, 0);
    const n = std.fmt.bufPrintZ(
        &fnbuf, "{s}{s}",
        .{ std.mem.span(appl), std.mem.span(name) },
    ) catch {
        dirsrv_global_unlock(TRACE_FILE, 0);
        return -1;
    };
    // O_RDONLY == 0, so test with == rather than &
    const mode: [*:0]const u8 = if (fl == O_RDONLY) "r" else "w+";
    const resfd = a12helper_keystore_statestore(&C.pubk, n.ptr, 0, mode);
    dirsrv_global_unlock(TRACE_FILE, 0);
    return resfd;
}

// buildDirPkg
// Admin --get-file .ctrl: package the appl directory into a memfd snapshot.
// The C upstream only supports the partial (controller-only) path; the full
// (data-included) form is asserted off because build_appl_pkg uses an internal
// memstream that's unsuited for arbitrarily large data dirs.

fn buildDirPkg(M: *c.struct_appl_meta, full: bool) c_int {
    std.debug.assert(!full);

    if (M.server_appl != c.SERVER_APPL_TEMP and M.server_appl != c.SERVER_APPL_PRIMARY)
        return -1;

    const opts = dirsrv_opts() orelse return -1;
    const dfd: c_int = if (M.server_appl == c.SERVER_APPL_TEMP)
        opts.dirsrv.appl_server_temp_dfd
    else
        opts.dirsrv.appl_server_dfd;

    var temp: c.struct_appl_meta = std.mem.zeroes(c.struct_appl_meta);
    var ret: c_int = -1;
    if (build_appl_pkg(@ptrCast(&M.appl.name), &temp, dfd, null)) {
        ret = buf_memfd(M.buf, M.buf_sz);
    }
    if (temp.buf) |b| c.free(b);
    if (temp.next) |n| c.free(n);

    return ret;
}

// accessPrivateStore
// ns == 0 path: open a private keystore entry by raw name.  Names with a '.'
// prefix are reserved — consult the resource-hook table first; only fall back
// to the keystore when no hook claims the name.

fn accessPrivateStore(
    C: *c.struct_dircl,
    name: [*:0]const u8,
    input: bool,
) c_int {
    var fnbuf: [64]u8 = undefined;

    // '.' files are always reserved; check if there is a hook resource handler
    // — other specials like admin/monitor etc. have already been routed.
    if (name[0] == '.') {
        var outfd: c_int = -1;
        if (checkHookedResource(name, 0, &C.pubk, &outfd, !input)) {
            return outfd;
        }
        return -1;
    }

    const n = std.fmt.bufPrintZ(&fnbuf, "{s}", .{std.mem.span(name)}) catch return -1;
    const mode: [*:0]const u8 = if (input) "r" else "w+";
    return a12helper_keystore_statestore(&C.pubk, n.ptr, 0, mode);
}

// allocateNewApplSlot
// Walk the global directory list and, if [id] is not already present and there
// is room, convert the empty-item terminator into a new appl entry, appending
// a fresh zero terminator after it.  Returns the newly filled slot on success.
//
// The C malloc-backed terminator allocation uses the global C heap so that the
// list outlives any Zig stack frame and is freed by the normal C cleanup path.

fn allocateNewApplSlot(id: u16, mid: *u16) ?*c.struct_appl_meta {
    dirsrv_global_lock(TRACE_FILE, 0);
    var cur: *c.struct_appl_meta = &dirsrv_config().dir;

    var last_id: u16 = 1;
    const result = blk: {
        while (true) {
            // Collision: id already present — return null.
            if (cur.identifier == id) break :blk null;

            if (cur.identifier == 0) {
                // cur is the terminator; promote it to the new appl entry.
                if (last_id >= 65534) break :blk null;

                const terminator = @as(
                    ?*c.struct_appl_meta,
                    @ptrCast(@alignCast(c.malloc(@sizeOf(c.struct_appl_meta)))),
                ) orelse break :blk null;
                terminator.* = std.mem.zeroes(c.struct_appl_meta);

                cur.* = std.mem.zeroes(c.struct_appl_meta);
                cur.identifier = last_id + 1;
                cur.next = terminator;
                mid.* = last_id + 1;
                break :blk cur;
            }

            last_id = cur.identifier;
            cur = cur.next orelse break :blk null;
        }
    };

    dirsrv_global_unlock(TRACE_FILE, 0);
    return result;
}

// checkHookedResource
// The config.lua script is allowed to hook any '.' prefixed file that isn't in
// the IDTYPE_mapping.  If so it'll launch a single-use process to handle the
// request.  The Lua-side registration stores {tag, bin, argv}; here we look it
// up, reserve 7 extra argv slots for appended launch args, then double-fork
// exec and wire the appropriate end of a pipe into *fd.

fn checkHookedResource(
    ext: [*:0]const u8,
    ns: usize,
    pubk: *const [SIG_PUBK_SZ]u8,
    fd: *c_int,
    upload: bool,
) bool {
    var tag: ?[*c]u8 = null;
    var bin: ?[*c]u8 = null;
    var argv: [*c][*c]u8 = null;
    var rv: bool = false;
    var argc: usize = 0;
    var nsname: [18]u8 = undefined;

    dirsrv_global_lock(TRACE_FILE, 0);
    if (!anet_directory_lua_resource_hooked(ext, ns, 7, &tag, &bin, &argv, &argc)) {
        dirsrv_global_unlock(TRACE_FILE, 0);
        return false;
    }
    const meta = dirsrv_locked_numid_appl(@intCast(ns));
    if (meta) |m| {
        @memcpy(&nsname, &m.appl.name);
    } else {
        nsname[0] = 0;
    }
    dirsrv_global_unlock(TRACE_FILE, 0);

    // Prepare the exec- environment — this is not using shmifsrv_spawn_client
    // as it is meant to be simple one-off bridges to environments like ticket/RCS.
    var ppair: [2]c_int = .{ -1, -1 };
    if (c.pipe(&ppair) == -1) {
        dirtrace("launch_hook:pipe.2 failed", .{});
        // Fall through to cleanup.
    } else {
        // Append our arguments:
        //   --ns <applname> --ident str --fd-in,out n  (NULL is guaranteed by _lua call)
        // these are not covered by free(argv[i]) loop in cleanup.
        const a = argv;
        a[argc + 0] = @ptrCast(@constCast(@as([*:0]const u8, "--ns")));
        a[argc + 1] = @ptrCast(&nsname);
        a[argc + 2] = @ptrCast(@constCast(@as([*:0]const u8, "--ident")));
        var b64_outl: usize = 0;
        const b64: ?[*:0]u8 = a12helper_tob64(pubk, 32, &b64_outl);
        a[argc + 3] = @ptrCast(b64);
        a[argc + 4] = if (upload)
            @ptrCast(@constCast(@as([*:0]const u8, "--fd-in")))
        else
            @ptrCast(@constCast(@as([*:0]const u8, "--fd-out")));
        var fd_str: [8]u8 = undefined;
        _ = c.snprintf(&fd_str, 8, "%d", if (upload) ppair[0] else ppair[1]);
        a[argc + 5] = @ptrCast(&fd_str);
        // argc+6 is left NULL by the zeroed malloc.

        // SIGCHLD is ignored; double-fork and only keep the relevant end.
        if (c.fork() == 0) {
            _ = c.close(if (upload) ppair[1] else ppair[0]);

            if (c.fork() == 0) {
                if (bin) |b| _ = c.execv(@ptrCast(b), @ptrCast(a));
                c.exit(c.EXIT_FAILURE);
            }
            c.exit(c.EXIT_SUCCESS);
        }

        // Keep the other end.
        if (upload) {
            _ = c.close(ppair[0]);
            fd.* = ppair[1];
        } else {
            _ = c.close(ppair[1]);
            fd.* = ppair[0];
        }
        rv = true;
    }

    // cleanup
    if (tag) |t| c.free(t);
    if (bin) |b| c.free(b);
    var i: usize = 0;
    while (i < argc) : (i += 1) {
        c.free(argv[i]);
    }
    c.free(@ptrCast(argv));

    return rv;
}

// handleBchunkUpload
// Open a backing fd for an inbound binary stream (worker uploading to server).
// Returns -1 on permission failure, the fd on success.

fn handleBchunkUpload(
    C: *c.struct_dircl,
    M: *c.struct_appl_meta,
    ns: usize,
    mtype: IdType,
    ext: [*:0]const u8,
    closefd: *bool,
) c_int {
    const mid: c_int = M.identifier;
    var resfd: c_int = -1;

    switch (mtype) {
        .appl, .actrl => {
            const tag: ?[*]const u8 = if (mtype == .appl)
                @ptrCast(dirsrv_config().allow_appl)
            else
                @ptrCast(dirsrv_config().allow_ctrl);

            if (C.dir_link or a12helper_keystore_accepted(&C.pubk, tag)) {
                dirtrace("accept_update=%d", .{mid});
                resfd = buf_memfd(null, 0);
                if (resfd != -1) {
                    C.type = @intFromEnum(mtype);
                    C.pending_fd = resfd;
                    C.pending_stream = true;
                    C.pending_id = @intCast(M.identifier);
                    // Do not close; the fd must remain open for the completion path.
                    closefd.* = false;
                }
            } else {
                dirtrace("reject_update=%d:reason=keystore_deny", .{mid});
                return -1;
            }
        },

        .state => {
            resfd = getStateRes(C, @ptrCast(&M.appl.name), ".state", O_WRONLY);
        },

        .debug => {
            resfd = getStateRes(C, @ptrCast(&M.appl.name), ".debug", O_WRONLY);
        },

        .raw => {
            if (checkHookedResource(ext, ns, &C.pubk, &resfd, true)) {
                return resfd;
            }
            if (a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_ctrl))) {
                const dfd = c.openat(
                    dirsrv_config().appl_server_datadfd,
                    &M.appl.name,
                    O_RDONLY | O_DIRECTORY,
                );
                if (dfd != -1) {
                    resfd = c.openat(dfd, ext, O_RDWR | O_CREAT | O_CLOEXEC, @as(c_uint, 0o700));
                    _ = c.close(dfd);
                }
            }
        },

        // No upload path for mon/report/state(dup).
        else => {},
    }

    return resfd;
}

// handleBchunkDownload
// Open a backing fd for an outbound binary stream (server delivering to worker).
// Returns 0 when the reply has already been sent internally (monitor path),
// -1 on error or permission denial, otherwise the fd to send.

fn handleBchunkDownload(
    C: *c.struct_dircl,
    M: *c.struct_appl_meta,
    ns: usize,
    mtype: IdType,
    ext: [*:0]const u8,
    ressz: *usize,
) c_int {
    var resfd: c_int = -1;

    switch (mtype) {
        // Make a locked copy of the cached appl data; the copy prevents a
        // compromised worker from mutating the underlying mapping.
        .appl => {
            dirsrv_global_lock(TRACE_FILE, 0);
            resfd = buf_memfd(M.buf, M.buf_sz);
            ressz.* = M.buf_sz;
            dirsrv_global_unlock(TRACE_FILE, 0);
        },

        .state => {
            resfd = getStateRes(C, @ptrCast(&M.appl.name), ".state", O_RDONLY);
        },

        .debug => {
            resfd = getStateRes(C, @ptrCast(&M.appl.name), ".debug", O_RDONLY);
        },

        // Downloading the controller is admin-only.
        .actrl => {
            if (a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_admin))) {
                resfd = buildDirPkg(M, false);
            }
        },

        // Monitor mode: join the appl runner and route bstream as debug channel.
        // If anet_directory_lua_monitor returns true the bchunk response was already
        // sent inside the function; signal no-reply with 0.
        .mon => {
            if (a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_appl))) {
                if (M.server_tag == null) {
                    _ = anet_directory_lua_spawn_runner(M, true);
                }
                if (anet_directory_lua_monitor(C, M)) {
                    return 0;
                }
            }
        },

        // Report: collect and optionally flush debug dumps.
        .report => {
            if (a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_appl))) {
                if (M.server_tag != null) return -1;
                resfd = dirsrv_build_report(&M.appl.name);
                if (dirsrv_config().flush_on_report) {
                    dirsrv_flush_report(&M.appl.name);
                }
            }
        },

        // Raw file in the server-side appl store.  Public if no controller is
        // active; otherwise requires allow_ctrl permission.
        .raw => {
            if (checkHookedResource(ext, ns, &C.pubk, &resfd, false)) {
                return resfd;
            }
            if (M.server_tag == null or
                a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_ctrl)))
            {
                const dfd = c.openat(
                    dirsrv_config().appl_server_datadfd,
                    &M.appl.name,
                    O_RDONLY | O_DIRECTORY,
                );
                if (dfd != -1) {
                    resfd = c.openat(dfd, ext, O_RDONLY);
                    if (resfd != -1) {
                        // Avoid c.struct_stat — musl timespec is opaque.
                        if (std.posix.fstat(resfd)) |sb| {
                            ressz.* = @intCast(sb.size);
                        } else |_| {}
                    }
                    _ = c.close(dfd);
                }
            }
        },
    }

    return resfd;
}

// handleBchunkAdmin
// Set up the admin control pipe.  The write-end is stored on [C]; the read-end
// is returned as the bchunk fd so the worker gets a readable stream.  Any
// MESSAGE received from the worker is routed via the Lua admin_command handler.

fn handleBchunkAdmin(C: *c.struct_dircl) c_int {
    if (!a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_admin)))
        return -1;

    // Terminate any pre-existing admin channel (irreversible by design).
    if (C.admin_fdout > 0) {
        _ = c.close(C.admin_fdout);
        C.admin_fdout = -1;
    }

    var pair: [2]c_int = .{ -1, -1 };
    if (c.pipe(&pair) != -1) {
        C.admin_fdout = pair[1];
        C.in_admin = true;
        _ = c.fcntl(C.admin_fdout, F_SETFD, @as(c_int, FD_CLOEXEC));
    }

    return pair[0]; // read-end delivered to worker
}

// bchunkNsidApplAlloc
// Resolve a namespace id to an appl_meta, allocating a fresh slot when the
// request is a new APPL upload and the caller has install permission.

fn bchunkNsidApplAlloc(
    C: *c.struct_dircl,
    ns: usize,
    input: bool,
    mtype: IdType,
    ext: [*:0]const u8,
    mid: *u16,
) ?*c.struct_appl_meta {
    dirsrv_global_lock(TRACE_FILE, 0);
    const meta = dirsrv_locked_numid_appl(@intCast(ns));
    dirsrv_global_unlock(TRACE_FILE, 0);

    if (meta == null and mtype == .appl and !input) {
        if (C.dir_link or
            a12helper_keystore_accepted(&C.pubk, @ptrCast(dirsrv_config().allow_install)))
        {
            dirtrace("dirsv:accepted_new=%s", .{ext});
            return allocateNewApplSlot(@intCast(ns), mid);
        } else {
            dirtrace("dirsv:rejected_new=%s:permission", .{ext});
            return null;
        }
    } else if (meta) |m| {
        mid.* = m.identifier;
    }

    return meta;
}

// dirsrv_bchunk_req
// Public entry point (matches declaration in directory.h).
//
// Called by the directory server when a worker sends a BCHUNKSTATE event.
// Parses the resource identifier, enforces permissions, and delivers either
// a BCHUNK_IN/OUT event (with fd) or a REQFAIL event back to the worker.

pub export fn dirsrv_bchunk_req(
    C: *c.struct_dircl,
    ns: usize,
    ext: [*:0]u8,
    input: bool,
) void {
    const mtype = identifierToAppl(ext);
    const evkind: c_int = if (input)
        c.TARGET_COMMAND_BCHUNK_IN
    else
        c.TARGET_COMMAND_BCHUNK_OUT;

    var mid: u16 = 0;
    var closefd: bool = true;
    var resfd: c_int = -1;
    var ressz: usize = 0;

    if (ns == 0) {
        // Private store shortpath — no appl-meta needed.
        if (c.strcmp(ext, ".admin") == 0) {
            resfd = handleBchunkAdmin(C);
        } else {
            resfd = accessPrivateStore(C, ext, input);
        }
    } else {
        const M = bchunkNsidApplAlloc(C, ns, input, mtype, ext, &mid);
        if (M) |meta| {
            if (input) {
                // input == true → server downloads to worker
                resfd = handleBchunkDownload(C, meta, ns, mtype, ext, &ressz);
            } else {
                // input == false → worker uploads to server
                resfd = handleBchunkUpload(C, meta, ns, mtype, ext, &closefd);
            }
        }
    }

    // 0 is the "reply already sent" sentinel from the monitor path.
    if (resfd == 0) return;

    if (resfd != -1) {
        var ev = c.struct_arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @intCast(evkind);
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = @intCast(ressz);
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @as(c_int, mid);

        // Format mid as decimal into tgt.message (mirrors C snprintf).
        var msgbuf: [16]u8 = undefined;
        const msg = std.fmt.bufPrint(&msgbuf, "{d}\x00", .{mid}) catch msgbuf[0..2];
        const dst: []u8 = @as([*]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))[0..@sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))];
        const copy_len = @min(msg.len, dst.len);
        @memcpy(dst[0..copy_len], msg[0..copy_len]);

        if (!shmifsrv_enqueue_event(C.C, &ev, resfd)) {
            dirtrace("bchunk_req:fail=send_to_worker:code=%d", .{getErrno()});
        }

        if (closefd) _ = c.close(resfd);
        return;
    }

    // Send REQFAIL — worker maps the id back to its pending stream.
    var fail_ev = c.struct_arcan_event.zeroes();
    fail_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_REQFAIL;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].uiv = @as(c_uint, mid);
    _ = shmifsrv_enqueue_event(C.C, &fail_ev, -1);
}

// dirsrv_bchunk_completion
// Public entry point (matches declaration in directory.h).
//
// Called when a STREAMSTATUS event signals completion of an upload initiated
// by dirsrv_bchunk_req.  Validates, hashes, and installs the new appl; persists
// a .fap file to disk and notifies directory listeners.

pub export fn dirsrv_bchunk_completion(C: *c.struct_dircl, ok_in: bool) void {
    if (C.pending_fd == -1) {
        dirtrace("dirsv:bchunk_state:complete_unknown_fd", .{});
        return;
    }

    if (!ok_in) {
        dirtrace("dirsv:bchunk_state:cancelled", .{});
        _ = c.close(C.pending_fd);
        return;
    }

    // Find the appl slot for the pending transfer, under the global lock.
    dirsrv_global_lock(TRACE_FILE, 0);

    var found_meta: ?*c.struct_appl_meta = null;
    var cur_opt: ?*c.struct_appl_meta = &dirsrv_config().dir;
    while (cur_opt) |cur| {
        if (cur.identifier == C.pending_id) {
            found_meta = cur;
            break;
        }
        cur_opt = cur.next;
    }

    if (found_meta == null) {
        dirtraceLocked("dirsv:bchunk_state:complete_unknown", .{});
        dirsrv_global_unlock(TRACE_FILE, 0);
        _ = c.close(C.pending_fd);
        C.pending_fd = -1;
        return;
    }

    const cur = found_meta.?;

    _ = c.lseek(C.pending_fd, 0, SEEK_SET);

    // ACTRL updates are handled by the Lua runner which takes ownership of fd.
    if (C.type == @intFromEnum(IdType.actrl)) {
        anet_directory_lua_update(cur, C.pending_fd);
        C.pending_fd = -1;
        dirsrv_global_unlock(TRACE_FILE, 0);
        return;
    }

    // Read the entire memfd into memory via file_to_membuf.
    const fpek = c.fdopen(C.pending_fd, "r");
    if (fpek == null) {
        _ = c.close(C.pending_fd);
        C.pending_fd = -1;
        dirsrv_global_unlock(TRACE_FILE, 0);
        return;
    }

    var dst_ptr: ?[*]u8 = null;
    var dst_sz: usize = 0;
    const handle = file_to_membuf(fpek.?, &dst_ptr, &dst_sz);
    C.pending_fd = -1; // fdopen takes ownership; do not close separately

    if (handle == null) {
        dirsrv_global_unlock(TRACE_FILE, 0);
        _ = c.fclose(fpek);
        return;
    }

    // Install the new buffer into the index slot.
    cur.buf_sz = dst_sz;
    cur.buf = @ptrCast(dst_ptr);
    cur.handle = handle;

    // Hash the transfer for cache-invalidation (not content signature).
    // blake3_hasher is sizeable; put it on the stack.
    var hasher_storage: [512]u8 align(16) = undefined;
    const hasher: *Blake3Hasher = @ptrCast(@alignCast(&hasher_storage));
    blake3_hasher_init(hasher);
    if (dst_ptr) |d| blake3_hasher_update(hasher, d, dst_sz);
    blake3_hasher_finalize(hasher, @ptrCast(&cur.hash), 4);

    // Signature check: if the appl slot carries a signing public key, the
    // uploading client's signing key must match it.
    const nullk = [_]u8{0} ** SIG_PUBK_SZ;
    if (!std.mem.eql(u8, &cur.sig_pubk, &nullk)) {
        if (!std.mem.eql(u8, &C.pubk_sign, &cur.sig_pubk)) {
            dirtraceLocked(
                "dirsv:bchunk_state:update_fail:reason=client signature - appl mismatch",
                .{},
            );
            dirsrv_global_unlock(TRACE_FILE, 0);
            return;
        }
    }

    // Validate the package manifest and extract the canonical appl name.
    var errmsg: ?[*]const u8 = null;
    const name_ptr = verify_appl_pkg(
        @ptrCast(dst_ptr.?),
        dst_sz,
        &C.pubk_sign,
        &cur.sig_pubk,
        &errmsg,
    );

    if (name_ptr == null) {
        dirtraceLocked(
            "dirsv:bchunk_state:appl_verify_fail:reason=%s",
            .{errmsg orelse "(unknown)"},
        );
        _ = c.fclose(handle);
        dirsrv_global_unlock(TRACE_FILE, 0);
        return;
    }
    const name: [*:0]const u8 = name_ptr.?;
    const name_slice = std.mem.span(name);

    // New install vs. update.
    if (cur.appl.name[0] == 0) {
        const copy_len = @min(name_slice.len, cur.appl.name.len - 1);
        @memcpy(cur.appl.name[0..copy_len], name_slice[0..copy_len]);
        cur.appl.name[copy_len] = 0;
        dirtraceLocked(
            "dirsv:bchunk_state:new_appl=%d:name=%s",
            .{ @as(c_int, cur.identifier), name },
        );
    } else {
        dirtraceLocked(
            "dirsv:bchunk_state:appl_update=%d",
            .{@as(c_int, cur.identifier)},
        );
    }

    // Persist to disk: rotate any existing .fap → .fap.old, then write new .fap.
    const basedir_fd = dirsrv_config().basedir;
    var fn_buf: [256]u8 = undefined;

    const fn_slice = std.fmt.bufPrintZ(&fn_buf, "{s}.fap", .{name_slice}) catch {
        // Name too long for buffer — skip persistence but continue.
        dirsrv_global_unlock(TRACE_FILE, 0);
        anet_directory_shmifsrv_set(dirsrv_config());
        c.free(@as(?*anyopaque, @ptrCast(@constCast(name))));
        _ = c.fclose(fpek);
        return;
    };

    // Rotate existing .fap → .fap.old (best-effort).  Avoid c.struct_stat —
    // musl timespec is opaque in translate-c.
    if (std.posix.fstatat(basedir_fd, std.mem.sliceTo(fn_slice, 0), 0)) |_| {
        var ofn_buf: [280]u8 = undefined;
        if (std.fmt.bufPrintZ(&ofn_buf, "{s}.fap.old", .{name_slice})) |ofn| {
            _ = c.renameat(basedir_fd, fn_slice.ptr, basedir_fd, ofn.ptr);
        } else |_| {}
    } else |_| {}

    // Write the new .fap.
    const fapfd = c.openat(
        basedir_fd,
        fn_slice.ptr,
        O_RDWR | O_CREAT | O_TRUNC,
        @as(c_uint, 0o600),
    );
    if (fapfd != -1) {
        const fout = c.fdopen(fapfd, "w");
        if (fout != null) {
            _ = c.fwrite(cur.buf, cur.buf_sz, 1, fout);
            _ = c.fclose(fout);
        }
    } else {
        dirtraceLocked("dirsv:bchunk_state:appl_sync:fail_open=%s", .{fn_slice.ptr});
    }

    // Unlock before shmifsrv_set, which acquires the lock internally, rebuilds
    // the index, and notifies all listeners.
    dirsrv_global_unlock(TRACE_FILE, 0);
    anet_directory_shmifsrv_set(dirsrv_config());
    c.free(@as(?*anyopaque, @ptrCast(@constCast(name))));

    _ = c.fclose(fpek);
}
