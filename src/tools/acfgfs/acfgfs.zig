// ACFGFS — pure-Zig FUSE client for the Durian control-socket tree.
//
// Speaks the kernel /dev/fuse wire protocol directly (no libfuse3 link).
// The /dev/fuse fd is obtained by forking and execing the setuid
// `fusermount3` helper, then reading an SCM_RIGHTS cmsg from the
// child's socketpair side.
//
// The durian IPC plumbing (control-socket line protocol, menu cache)
// is kept intact. Only the FUSE layer changed — we used to dlopen
// libfuse3 and proxy ops through its event loop, which segfaulted on
// musl↔glibc ABI mismatches (libfuse3's sscanf from a musl-built
// process). Pure syscall path sidesteps that.

const std = @import("std");
const libc = @import("posix");

// ══════════════════════════════════════════════════════════════════════
// linux/fuse.h — hand-translated subset in fuse_types.zig. No C object
// gets linked; the resulting types/consts are plain Zig.
// ══════════════════════════════════════════════════════════════════════

const fuse = @import("fuse_types");

// Keep the `cfuse.X` spelling used throughout as a dispatch struct that
// forwards to the hand-translated module — trivial to audit, no surprise
// hidden in `@cImport`.
const cfuse = struct {
    pub const FUSE_KERNEL_VERSION = fuse.FUSE_KERNEL_VERSION;
    pub const FUSE_ACCESS = fuse.FUSE_ACCESS;
    pub const FUSE_BATCH_FORGET = fuse.FUSE_BATCH_FORGET;
    pub const FUSE_DESTROY = fuse.FUSE_DESTROY;
    pub const FUSE_FLUSH = fuse.FUSE_FLUSH;
    pub const FUSE_FORGET = fuse.FUSE_FORGET;
    pub const FUSE_GETATTR = fuse.FUSE_GETATTR;
    pub const FUSE_INIT = fuse.FUSE_INIT;
    pub const FUSE_LOOKUP = fuse.FUSE_LOOKUP;
    pub const FUSE_OPEN = fuse.FUSE_OPEN;
    pub const FUSE_OPENDIR = fuse.FUSE_OPENDIR;
    pub const FUSE_READ = fuse.FUSE_READ;
    pub const FUSE_READDIR = fuse.FUSE_READDIR;
    pub const FUSE_RELEASE = fuse.FUSE_RELEASE;
    pub const FUSE_RELEASEDIR = fuse.FUSE_RELEASEDIR;
    pub const FUSE_SETATTR = fuse.FUSE_SETATTR;
    pub const FUSE_STATFS = fuse.FUSE_STATFS;
    pub const FUSE_WRITE = fuse.FUSE_WRITE;
    pub const fuse_attr = fuse.fuse_attr;
    pub const fuse_attr_out = fuse.fuse_attr_out;
    pub const fuse_dirent = fuse.fuse_dirent;
    pub const fuse_entry_out = fuse.fuse_entry_out;
    pub const fuse_in_header = fuse.fuse_in_header;
    pub const fuse_init_in = fuse.fuse_init_in;
    pub const fuse_init_out = fuse.fuse_init_out;
    pub const fuse_open_out = fuse.fuse_open_out;
    pub const fuse_out_header = fuse.fuse_out_header;
    pub const fuse_read_in = fuse.fuse_read_in;
    pub const fuse_release_in = fuse.fuse_release_in;
    pub const fuse_statfs_out = fuse.fuse_statfs_out;
    pub const fuse_write_in = fuse.fuse_write_in;
    pub const fuse_write_out = fuse.fuse_write_out;
};

// ══════════════════════════════════════════════════════════════════════
// Extra libc decls not in posix_libc. Candidates for later promotion
// are flagged with `// PROMOTE:`.
// ══════════════════════════════════════════════════════════════════════

// PROMOTE: realpath shows up in any tool that takes a filesystem path.
extern "c" fn realpath(path: [*:0]const u8, resolved: ?[*:0]u8) ?[*:0]u8;
// PROMOTE: snprintf/strlen/strcmp/strncmp/memcpy are ubiquitous.
extern "c" fn snprintf(buf: [*]u8, sz: usize, fmt: [*:0]const u8, ...) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
// Socket + fd I/O.
extern "c" fn socket(domain: c_int, type_: c_int, protocol: c_int) c_int;
extern "c" fn socketpair(domain: c_int, type_: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn connect(sockfd: c_int, addr: *const anyopaque, addrlen: c_uint) c_int;
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn execvp(file: [*:0]const u8, argv: [*c]const ?[*:0]const u8) c_int;
extern "c" fn _exit(status: c_int) noreturn;
extern "c" fn waitpid(pid: c_int, wstatus: ?*c_int, options: c_int) c_int;
extern "c" fn sendmsg(fd: c_int, msg: *const Msghdr, flags: c_int) isize;
extern "c" fn recvmsg(fd: c_int, msg: *Msghdr, flags: c_int) isize;
extern "c" fn __errno_location() *c_int;
extern "c" fn getuid() c_uint;
extern "c" fn getgid() c_uint;

fn errno() c_int {
    return __errno_location().*;
}

// ══════════════════════════════════════════════════════════════════════
// Socket / cmsg layout for recvmsg-SCM_RIGHTS fd pickup.
// ══════════════════════════════════════════════════════════════════════

const AF_UNIX: c_int = 1;
const SOCK_STREAM: c_int = 1;
const SOL_SOCKET: c_int = 1;
const SCM_RIGHTS: c_int = 1;
const EAGAIN: c_int = 11;
const EINTR: c_int = 4;
const EINVAL: c_int = 22;
const ENOENT: c_int = 2;
const EIO: c_int = 5;
const EACCES: c_int = 13;
const EEXIST: c_int = 17;
const ENOSYS: c_int = 38;

const UNIX_PATH_MAX: usize = 108;
const SockaddrUn = extern struct {
    sun_family: c_ushort,
    sun_path: [UNIX_PATH_MAX]u8,
};

const Iovec = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

const Msghdr = extern struct {
    msg_name: ?*anyopaque,
    msg_namelen: c_uint,
    msg_iov: ?*Iovec,
    msg_iovlen: usize,
    msg_control: ?*anyopaque,
    msg_controllen: usize,
    msg_flags: c_int,
};

const Cmsghdr = extern struct {
    cmsg_len: usize,
    cmsg_level: c_int,
    cmsg_type: c_int,
};

// S_IFDIR / S_IFREG for the mode word.
const S_IFDIR: u32 = 0o040000;
const S_IFREG: u32 = 0o100000;

// ══════════════════════════════════════════════════════════════════════
// Durian control-socket layer (unchanged in behavior).
// ══════════════════════════════════════════════════════════════════════

const Options = extern struct {
    control: ?[*:0]const u8,
    con: c_int,
    show_help: c_int,
};

var g_options: Options = .{ .control = null, .con = -1, .show_help = 0 };

// uid/gid presented to the kernel for every inode. Set once in main()
// from getuid/getgid so default_permissions grants access to the user
// that launched us. Without this we'd stamp everything with uid=0 and
// lock ourselves out when running unprivileged.
var g_uid: u32 = 0;
var g_gid: u32 = 0;

fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    _ = @call(.auto, libc.fprintf, .{ libc.stderr, (fmt ++ "\n").ptr } ++ args);
}

const LineCb = ?*const fn (str: [*:0]u8, tag: ?*anyopaque) void;

fn waitForCommand(
    cmd: [*:0]const u8,
    path: ?[*:0]const u8,
    arg: ?[*:0]const u8,
    line_cb: LineCb,
    tag: ?*anyopaque,
) c_int {
    var buf: [4096]u8 = undefined;

    if (g_options.con == -1) {
        var addr = SockaddrUn{ .sun_family = AF_UNIX, .sun_path = std.mem.zeroes([UNIX_PATH_MAX]u8) };
        _ = snprintf(&addr.sun_path, UNIX_PATH_MAX, "%s", g_options.control.?);
        g_options.con = socket(AF_UNIX, SOCK_STREAM, 0);
        if (connect(g_options.con, @ptrCast(&addr), @sizeOf(SockaddrUn)) == -1) {
            debugPrint("can't connect to socket (%s)", .{g_options.control.?});
            _ = libc.close(g_options.con);
            g_options.con = -1;
            return -EEXIST;
        }
    }

    const ntw_i = snprintf(
        &buf,
        buf.len,
        "%s %s%s%s\n",
        cmd,
        if (path) |p| p else @as([*:0]const u8, ""),
        if (arg != null) @as([*:0]const u8, "=") else @as([*:0]const u8, ""),
        if (arg) |a| a else @as([*:0]const u8, ""),
    );
    if (ntw_i < 0 or @as(usize, @intCast(ntw_i)) >= buf.len) {
        debugPrint("command overflow protection", .{});
        return -EINVAL;
    }
    var ntw: usize = @intCast(ntw_i);

    var ofs: usize = 0;
    while (ntw > 0) {
        const nw = write(g_options.con, @as([*]const u8, @ptrCast(&buf)) + ofs, ntw);
        if (nw == -1) {
            const e = errno();
            if (e != EAGAIN and e != EINTR) {
                debugPrint("write to parent failed, connection broken", .{});
                _ = libc.close(g_options.con);
                g_options.con = -1;
                return -e;
            }
            continue;
        }
        const nw_u: usize = @intCast(nw);
        ofs += nw_u;
        ntw -= nw_u;
    }

    ofs = 0;
    while (true) {
        const nr = read(g_options.con, @as([*]u8, @ptrCast(&buf)) + ofs, 1);
        if (nr == -1) {
            const e = errno();
            if (e != EAGAIN and e != EINTR) {
                _ = libc.close(g_options.con);
                g_options.con = -1;
                return -e;
            }
            continue;
        }

        if (buf[ofs] == '\n') {
            buf[ofs] = 0;
            ofs = 0;
            const line: [*:0]u8 = @ptrCast(&buf);
            if (strcmp(line, "OK") == 0) return 0;
            if (strncmp(line, "EINVAL", 6) == 0) return -ENOENT;
            if (line_cb) |cb| cb(line, tag);
            continue;
        }

        ofs += 1;
        if (ofs == buf.len) return -EINVAL;
    }
}

// ══════════════════════════════════════════════════════════════════════
// Inode table: every inode we've handed out is backed by a full durian
// path. Inode 1 is the root ("/"). We append; we only remove on
// FUSE_FORGET (which we ignore — cost of keeping them around is trivial
// for the menu sizes in play).
// ══════════════════════════════════════════════════════════════════════

const NodeKind = enum(u8) { unknown, directory, file };

const Node = struct {
    path: []u8, // heap, owned, NUL-terminated (len excludes the NUL)
    kind: NodeKind = .unknown,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var inode_table = std.ArrayList(Node){};
var path_to_ino = std.StringHashMap(u64).init(std.heap.page_allocator);

fn nodeInit() !void {
    // Inode 0 is the placeholder, inode 1 is the root.
    try inode_table.append(gpa, .{ .path = try gpa.dupe(u8, ""), .kind = .directory });
    try inode_table.append(gpa, .{ .path = try gpa.dupe(u8, "/"), .kind = .directory });
    try path_to_ino.put("/", 1);
}

fn nodeLookup(parent_ino: u64, name: []const u8) !u64 {
    if (parent_ino == 0 or parent_ino >= inode_table.items.len) return error.NoEntry;
    const parent = inode_table.items[@intCast(parent_ino)];
    // Durian paths look like "/global/settings/..." — join with '/'
    // unless parent is root (which already is "/").
    var joined = std.ArrayList(u8){};
    defer joined.deinit(gpa);
    try joined.appendSlice(gpa, parent.path);
    if (parent.path.len == 0 or parent.path[parent.path.len - 1] != '/') try joined.append(gpa, '/');
    try joined.appendSlice(gpa, name);

    if (path_to_ino.get(joined.items)) |ino| return ino;

    const owned = try gpa.dupe(u8, joined.items);
    try inode_table.append(gpa, .{ .path = owned, .kind = .unknown });
    const ino: u64 = @intCast(inode_table.items.len - 1);
    try path_to_ino.put(owned, ino);
    return ino;
}

fn nodePath(ino: u64) ?[]const u8 {
    if (ino == 0 or ino >= inode_table.items.len) return null;
    return inode_table.items[@intCast(ino)].path;
}

// Return a zero-terminated version of the durian path for this inode.
// Uses a thread-local-ish scratch buffer; caller must consume before
// another call.
var path_scratch: [4096]u8 = undefined;
fn nodePathZ(ino: u64) ?[*:0]const u8 {
    const p = nodePath(ino) orelse return null;
    if (p.len >= path_scratch.len) return null;
    @memcpy(path_scratch[0..p.len], p);
    path_scratch[p.len] = 0;
    return @ptrCast(&path_scratch);
}

// ══════════════════════════════════════════════════════════════════════
// FUSE wire helpers
// ══════════════════════════════════════════════════════════════════════

var fuse_fd: c_int = -1;

fn replyError(unique: u64, err_code: i32) void {
    var out = cfuse.fuse_out_header{
        .len = @sizeOf(cfuse.fuse_out_header),
        .@"error" = err_code,
        .unique = unique,
    };
    _ = write(fuse_fd, @ptrCast(&out), @sizeOf(cfuse.fuse_out_header));
}

fn replyOk(unique: u64, body: []const u8) void {
    var hdr = cfuse.fuse_out_header{
        .len = @intCast(@sizeOf(cfuse.fuse_out_header) + body.len),
        .@"error" = 0,
        .unique = unique,
    };
    // writev would be nicer; concatenate into a single buffer to keep
    // this single-syscall-per-reply.
    var scratch: [1 << 17]u8 = undefined;
    if (hdr.len > scratch.len) {
        replyError(unique, -EIO);
        return;
    }
    @memcpy(scratch[0..@sizeOf(cfuse.fuse_out_header)], std.mem.asBytes(&hdr));
    if (body.len > 0)
        @memcpy(
            scratch[@sizeOf(cfuse.fuse_out_header) .. @sizeOf(cfuse.fuse_out_header) + body.len],
            body,
        );
    _ = write(fuse_fd, @ptrCast(&scratch), hdr.len);
}

fn fillAttr(ino: u64, kind: NodeKind, out: *cfuse.fuse_attr) void {
    out.* = std.mem.zeroes(cfuse.fuse_attr);
    out.ino = ino;
    out.uid = g_uid;
    out.gid = g_gid;
    switch (kind) {
        .directory => {
            out.mode = S_IFDIR | 0o700;
            out.nlink = 2;
            out.size = 4096;
        },
        .file => {
            out.mode = S_IFREG | 0o600;
            out.nlink = 1;
            out.size = 4096;
        },
        .unknown => {
            out.mode = S_IFREG | 0o600;
            out.nlink = 1;
            out.size = 0;
        },
    }
    out.blksize = 4096;
}

// Ask durian what this inode's kind is by running `read <path>` and
// inspecting the response lines. Caches the resolved kind on the
// inode so repeated getattrs don't re-hit the socket.
fn nodeClassify(ino: u64) NodeKind {
    if (ino == 0 or ino >= inode_table.items.len) return .unknown;
    var node = &inode_table.items[@intCast(ino)];
    if (node.kind != .unknown) return node.kind;
    if (ino == 1) {
        node.kind = .directory;
        return .directory;
    }

    var result_kind: NodeKind = .unknown;
    const Ctx = struct { kind: *NodeKind };
    var ctx = Ctx{ .kind = &result_kind };
    const cb = struct {
        fn cb(str: [*:0]u8, tag: ?*anyopaque) void {
            const c: *Ctx = @ptrCast(@alignCast(tag));
            if (strcmp(str, "kind: directory") == 0) c.kind.* = .directory;
            if (strcmp(str, "kind: action") == 0) c.kind.* = .file;
            if (strcmp(str, "kind: value") == 0) c.kind.* = .file;
        }
    }.cb;
    const pathz = nodePathZ(ino) orelse return .unknown;
    _ = waitForCommand("read", pathz, null, cb, &ctx);
    node.kind = result_kind;
    return result_kind;
}

// ══════════════════════════════════════════════════════════════════════
// Open-file state: we cache the full payload at open-time so read()
// can service arbitrary offsets. Matches what the libfuse3 version did.
// ══════════════════════════════════════════════════════════════════════

const OpenFile = struct {
    buffer: std.ArrayList(u8),
    value: bool,
};

var open_handles = std.AutoHashMap(u64, *OpenFile).init(std.heap.page_allocator);
var next_fh: u64 = 1;

fn readIntoBuffer(ino: u64, out_value: *bool) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(gpa);
    const Ctx = struct {
        buf: *std.ArrayList(u8),
        value: *bool,
    };
    var ctx = Ctx{ .buf = &buf, .value = out_value };
    const cb = struct {
        fn cb(str: [*:0]u8, tag: ?*anyopaque) void {
            const c: *Ctx = @ptrCast(@alignCast(tag));
            const slen = strlen(str);
            c.buf.appendSlice(gpa, str[0..slen]) catch return;
            c.buf.append(gpa, '\n') catch return;
            if (strcmp(str, "kind: value") == 0) c.value.* = true;
        }
    }.cb;
    const pathz = nodePathZ(ino) orelse return error.NoEntry;
    const r = waitForCommand("read", pathz, null, cb, &ctx);
    if (r != 0) return error.NoEntry;
    return buf;
}

// ══════════════════════════════════════════════════════════════════════
// Opcode handlers
// ══════════════════════════════════════════════════════════════════════

fn handleInit(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    if (body.len < @sizeOf(cfuse.fuse_init_in)) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    const in: *const cfuse.fuse_init_in = @ptrCast(@alignCast(body.ptr));
    var out = std.mem.zeroes(cfuse.fuse_init_out);
    out.major = cfuse.FUSE_KERNEL_VERSION;
    // Pin to 7.31 — post-that libfuse/kernel added required features we
    // don't implement (idmapping, statx). 7.31 is 5.11-era, ancient by
    // now; every kernel we target supports it.
    const wire_minor: u32 = if (in.minor < 31) in.minor else 31;
    out.minor = wire_minor;
    out.max_readahead = in.max_readahead;
    out.flags = 0;
    out.max_background = 16;
    out.congestion_threshold = 12;
    out.max_write = 128 * 1024;
    out.time_gran = 1;
    out.max_pages = 32;
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleGetattr(hdr: *const cfuse.fuse_in_header) void {
    const kind = nodeClassify(hdr.nodeid);
    var out = std.mem.zeroes(cfuse.fuse_attr_out);
    out.attr_valid = 1;
    fillAttr(hdr.nodeid, kind, &out.attr);
    if (kind == .unknown and hdr.nodeid != 1) {
        replyError(hdr.unique, -ENOENT);
        return;
    }
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

// Kernel issues this on truncate-on-open / chmod / chown. We don't back
// anything persistently — just echo attrs so shell redirection (which
// truncates before writing) succeeds.
fn handleSetattr(hdr: *const cfuse.fuse_in_header) void {
    const kind = nodeClassify(hdr.nodeid);
    var out = std.mem.zeroes(cfuse.fuse_attr_out);
    out.attr_valid = 1;
    fillAttr(hdr.nodeid, kind, &out.attr);
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleLookup(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    // Body is a NUL-terminated name.
    if (body.len == 0) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    var name = body;
    if (name[name.len - 1] == 0) name = name[0 .. name.len - 1];
    if (name.len == 0) {
        replyError(hdr.unique, -EINVAL);
        return;
    }

    const ino = nodeLookup(hdr.nodeid, name) catch {
        replyError(hdr.unique, -EIO);
        return;
    };
    const kind = nodeClassify(ino);
    if (kind == .unknown) {
        replyError(hdr.unique, -ENOENT);
        return;
    }
    var out = std.mem.zeroes(cfuse.fuse_entry_out);
    out.nodeid = ino;
    out.generation = 0;
    out.entry_valid = 1;
    out.attr_valid = 1;
    fillAttr(ino, kind, &out.attr);
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleOpendir(hdr: *const cfuse.fuse_in_header) void {
    var out = std.mem.zeroes(cfuse.fuse_open_out);
    out.fh = 0;
    out.open_flags = 0;
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

// Build a fuse_dirent into `scratch` at `ofs`, return new ofs.
fn appendDirent(scratch: []u8, ofs: usize, ino: u64, off: u64, mode_type: u32, name: []const u8) ?usize {
    const header_size = @sizeOf(cfuse.fuse_dirent);
    const name_off = header_size; // name[] starts right after
    const rec_len = (name_off + name.len + 7) & ~@as(usize, 7);
    if (ofs + rec_len > scratch.len) return null;

    // Zero the record (pads the trailing alignment).
    @memset(scratch[ofs .. ofs + rec_len], 0);
    const dirent: *cfuse.fuse_dirent = @ptrCast(@alignCast(scratch.ptr + ofs));
    dirent.ino = ino;
    dirent.off = off;
    dirent.namelen = @intCast(name.len);
    dirent.type = mode_type >> 12; // dirent type is IFTODT(mode) == mode >> 12
    @memcpy(scratch[ofs + name_off .. ofs + name_off + name.len], name);
    return ofs + rec_len;
}

const ReaddirCtx = struct {
    scratch: []u8,
    ofs: usize,
    off_counter: u64,
    parent_ino: u64,
    parent_path: []const u8,
    limit: usize,
};

fn readdirLineCb(str: [*:0]u8, tag: ?*anyopaque) void {
    const ctx: *ReaddirCtx = @ptrCast(@alignCast(tag));
    var len = strlen(str);
    if (len == 0) return;

    var is_dir = false;
    if (str[len - 1] == '/') {
        is_dir = true;
        str[len - 1] = 0;
        len -= 1;
    }
    if (len == 0) return;

    const name = str[0..len];
    // Register the child inode so future lookup/getattr resolves.
    const child_ino = nodeLookup(ctx.parent_ino, name) catch return;
    if (child_ino < inode_table.items.len) {
        inode_table.items[@intCast(child_ino)].kind = if (is_dir) .directory else .file;
    }

    ctx.off_counter += 1;
    const mode: u32 = if (is_dir) S_IFDIR | 0o700 else S_IFREG | 0o600;
    if (appendDirent(ctx.scratch, ctx.ofs, child_ino, ctx.off_counter, mode, name)) |new_ofs| {
        ctx.ofs = new_ofs;
    }
}

fn handleReaddir(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    if (body.len < @sizeOf(cfuse.fuse_read_in)) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    const in: *const cfuse.fuse_read_in = @ptrCast(@alignCast(body.ptr));
    // offset != 0 means kernel is asking for the next page. We emit
    // everything in one go; pagination => empty reply.
    if (in.offset != 0) {
        replyOk(hdr.unique, &[_]u8{});
        return;
    }

    var scratch: [32 * 1024]u8 = undefined;
    const parent_path = nodePath(hdr.nodeid) orelse {
        replyError(hdr.unique, -ENOENT);
        return;
    };

    var ctx = ReaddirCtx{
        .scratch = scratch[0..@min(in.size, scratch.len)],
        .ofs = 0,
        .off_counter = 0,
        .parent_ino = hdr.nodeid,
        .parent_path = parent_path,
        .limit = @min(in.size, scratch.len),
    };

    // "." and ".."
    ctx.off_counter += 1;
    ctx.ofs = appendDirent(ctx.scratch, ctx.ofs, hdr.nodeid, ctx.off_counter, S_IFDIR, ".") orelse ctx.ofs;
    ctx.off_counter += 1;
    ctx.ofs = appendDirent(ctx.scratch, ctx.ofs, hdr.nodeid, ctx.off_counter, S_IFDIR, "..") orelse ctx.ofs;

    const pathz = nodePathZ(hdr.nodeid) orelse {
        replyError(hdr.unique, -ENOENT);
        return;
    };
    _ = waitForCommand("ls", pathz, null, readdirLineCb, &ctx);

    replyOk(hdr.unique, scratch[0..ctx.ofs]);
}

fn handleReleasedir(hdr: *const cfuse.fuse_in_header) void {
    replyOk(hdr.unique, &[_]u8{});
}

fn handleOpen(hdr: *const cfuse.fuse_in_header) void {
    var is_value = false;
    var buffer = readIntoBuffer(hdr.nodeid, &is_value) catch {
        replyError(hdr.unique, -ENOENT);
        return;
    };
    const fh_ptr = gpa.create(OpenFile) catch {
        buffer.deinit(gpa);
        replyError(hdr.unique, -EIO);
        return;
    };
    fh_ptr.* = .{ .buffer = buffer, .value = is_value };

    const fh = next_fh;
    next_fh += 1;
    open_handles.put(fh, fh_ptr) catch {
        fh_ptr.buffer.deinit(gpa);
        gpa.destroy(fh_ptr);
        replyError(hdr.unique, -EIO);
        return;
    };

    var out = std.mem.zeroes(cfuse.fuse_open_out);
    out.fh = fh;
    out.open_flags = 1 << 2; // FOPEN_NONSEEKABLE — closest to libfuse3 version
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleRead(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    if (body.len < @sizeOf(cfuse.fuse_read_in)) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    const in: *const cfuse.fuse_read_in = @ptrCast(@alignCast(body.ptr));
    const handle = open_handles.get(in.fh) orelse {
        replyError(hdr.unique, -EINVAL);
        return;
    };
    const off: usize = @intCast(in.offset);
    if (off >= handle.buffer.items.len) {
        replyOk(hdr.unique, &[_]u8{});
        return;
    }
    const left = handle.buffer.items.len - off;
    const n = @min(@as(usize, in.size), left);
    replyOk(hdr.unique, handle.buffer.items[off .. off + n]);
}

fn handleRelease(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    if (body.len < @sizeOf(cfuse.fuse_release_in)) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    const in: *const cfuse.fuse_release_in = @ptrCast(@alignCast(body.ptr));
    if (open_handles.fetchRemove(in.fh)) |kv| {
        kv.value.buffer.deinit(gpa);
        gpa.destroy(kv.value);
    }
    replyOk(hdr.unique, &[_]u8{});
}

fn handleWrite(hdr: *const cfuse.fuse_in_header, body: []const u8) void {
    if (body.len < @sizeOf(cfuse.fuse_write_in)) {
        replyError(hdr.unique, -EINVAL);
        return;
    }
    const in: *const cfuse.fuse_write_in = @ptrCast(@alignCast(body.ptr));
    const data_body = body[@sizeOf(cfuse.fuse_write_in)..];
    const sz: usize = @min(@as(usize, in.size), data_body.len);
    const data = data_body[0..sz];

    const handle = open_handles.get(in.fh) orelse {
        replyError(hdr.unique, -EINVAL);
        return;
    };
    const pathz = nodePathZ(hdr.nodeid) orelse {
        replyError(hdr.unique, -EIO);
        return;
    };

    if (handle.value) {
        // Strip trailing newline before shipping, it's just shell noise.
        var effective_len = sz;
        while (effective_len > 0 and (data[effective_len - 1] == '\n' or data[effective_len - 1] == '\r')) {
            effective_len -= 1;
        }
        var argbuf: [1024]u8 = undefined;
        if (effective_len + 1 > argbuf.len) {
            replyError(hdr.unique, -EINVAL);
            return;
        }
        @memcpy(argbuf[0..effective_len], data[0..effective_len]);
        argbuf[effective_len] = 0;
        const r = waitForCommand("write", pathz, @ptrCast(&argbuf), null, null);
        if (r != 0) {
            replyError(hdr.unique, -EINVAL);
            return;
        }
    } else {
        const r = waitForCommand("exec", pathz, null, null, null);
        if (r != 0) {
            replyError(hdr.unique, -EINVAL);
            return;
        }
    }

    var out = std.mem.zeroes(cfuse.fuse_write_out);
    out.size = @intCast(sz);
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleFlush(hdr: *const cfuse.fuse_in_header) void {
    replyOk(hdr.unique, &[_]u8{});
}

fn handleStatfs(hdr: *const cfuse.fuse_in_header) void {
    var out = std.mem.zeroes(cfuse.fuse_statfs_out);
    out.st.bsize = 4096;
    out.st.namelen = 255;
    out.st.frsize = 4096;
    replyOk(hdr.unique, std.mem.asBytes(&out));
}

fn handleAccess(hdr: *const cfuse.fuse_in_header) void {
    replyOk(hdr.unique, &[_]u8{});
}

fn handleForget(_: *const cfuse.fuse_in_header) void {
    // no reply
}

// ══════════════════════════════════════════════════════════════════════
// Main /dev/fuse loop
// ══════════════════════════════════════════════════════════════════════

fn runLoop() void {
    const FUSE_MAX_REQ = 1 << 20; // 1 MiB, same as our max_write
    var req_buf: [FUSE_MAX_REQ + 4096]u8 align(8) = undefined;

    while (true) {
        const n = read(fuse_fd, &req_buf, req_buf.len);
        if (n < 0) {
            const e = errno();
            if (e == EINTR or e == EAGAIN) continue;
            // ENODEV = kernel unmounted us.
            return;
        }
        if (n == 0) return; // EOF → unmounted

        const nu: usize = @intCast(n);
        if (nu < @sizeOf(cfuse.fuse_in_header)) continue;

        const hdr: *const cfuse.fuse_in_header = @ptrCast(@alignCast(&req_buf));
        if (hdr.len > nu) continue; // short read, shouldn't happen
        const body = req_buf[@sizeOf(cfuse.fuse_in_header)..hdr.len];

        switch (hdr.opcode) {
            cfuse.FUSE_INIT => handleInit(hdr, body),
            cfuse.FUSE_GETATTR => handleGetattr(hdr),
            cfuse.FUSE_SETATTR => handleSetattr(hdr),
            cfuse.FUSE_LOOKUP => handleLookup(hdr, body),
            cfuse.FUSE_OPENDIR => handleOpendir(hdr),
            cfuse.FUSE_READDIR => handleReaddir(hdr, body),
            cfuse.FUSE_RELEASEDIR => handleReleasedir(hdr),
            cfuse.FUSE_OPEN => handleOpen(hdr),
            cfuse.FUSE_READ => handleRead(hdr, body),
            cfuse.FUSE_RELEASE => handleRelease(hdr, body),
            cfuse.FUSE_WRITE => handleWrite(hdr, body),
            cfuse.FUSE_FLUSH => handleFlush(hdr),
            cfuse.FUSE_STATFS => handleStatfs(hdr),
            cfuse.FUSE_ACCESS => handleAccess(hdr),
            cfuse.FUSE_FORGET => handleForget(hdr),
            cfuse.FUSE_BATCH_FORGET => handleForget(hdr),
            cfuse.FUSE_DESTROY => {
                replyOk(hdr.unique, &[_]u8{});
                return;
            },
            else => replyError(hdr.unique, -ENOSYS),
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// fusermount3 handshake
// ══════════════════════════════════════════════════════════════════════

// Exchange a /dev/fuse fd with `fusermount3` via SCM_RIGHTS.
// Returns the negotiated fd (owned) on success, -1 on failure.
fn mountViaFusermount(mountpoint: [*:0]const u8) c_int {
    var sv: [2]c_int = .{ -1, -1 };
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, &sv) == -1) {
        debugPrint("socketpair failed", .{});
        return -1;
    }

    const pid = std.c.fork();
    if (pid < 0) {
        debugPrint("fork failed", .{});
        _ = libc.close(sv[0]);
        _ = libc.close(sv[1]);
        return -1;
    }

    if (pid == 0) {
        // Child — hand fd sv[1] to fusermount3 via env var _FUSE_COMMFD.
        _ = libc.close(sv[0]);
        // Put the socket on a known descriptor; fusermount3 reads the
        // number from _FUSE_COMMFD.
        if (dup2(sv[1], 3) == -1) _exit(1);
        if (sv[1] != 3) _ = libc.close(sv[1]);
        _ = libc.setenv("_FUSE_COMMFD", "3", 1);

        const opts: [*:0]const u8 = "rw,nosuid,nodev,default_permissions,fsname=arcan_cfgfs";
        var argv = [_]?[*:0]const u8{
            "fusermount3",
            "-o",
            opts,
            "--",
            mountpoint,
            null,
        };
        _ = execvp("fusermount3", @ptrCast(&argv));
        // If execvp returned, it failed.
        _exit(1);
    }

    // Parent — receive the fd.
    _ = libc.close(sv[1]);

    var dummy: [1]u8 = .{0};
    var iov = Iovec{ .iov_base = &dummy, .iov_len = 1 };

    // Control buffer sized generously.
    var ctrl_buf: [64]u8 align(@alignOf(Cmsghdr)) = undefined;

    var mh = Msghdr{
        .msg_name = null,
        .msg_namelen = 0,
        .msg_iov = @ptrCast(&iov),
        .msg_iovlen = 1,
        .msg_control = &ctrl_buf,
        .msg_controllen = ctrl_buf.len,
        .msg_flags = 0,
    };

    // fusermount3 can send two bytes before the fd; loop a few times.
    var got_fd: c_int = -1;
    var attempts: usize = 0;
    while (attempts < 4) : (attempts += 1) {
        mh.msg_control = &ctrl_buf;
        mh.msg_controllen = ctrl_buf.len;
        iov.iov_base = &dummy;
        iov.iov_len = 1;
        const n = recvmsg(sv[0], &mh, 0);
        if (n < 0) {
            if (errno() == EINTR) continue;
            break;
        }
        // Find SCM_RIGHTS cmsg.
        if (mh.msg_controllen >= @sizeOf(Cmsghdr)) {
            const cmsg: *Cmsghdr = @ptrCast(@alignCast(mh.msg_control.?));
            if (cmsg.cmsg_level == SOL_SOCKET and cmsg.cmsg_type == SCM_RIGHTS) {
                const data_ptr: *c_int = @ptrCast(@alignCast(@as([*]u8, @ptrCast(mh.msg_control.?)) + @sizeOf(Cmsghdr)));
                got_fd = data_ptr.*;
                break;
            }
        }
        if (n == 0) break;
    }

    _ = libc.close(sv[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);

    if (got_fd < 0) {
        debugPrint("didn't receive /dev/fuse fd from fusermount3", .{});
        return -1;
    }
    return got_fd;
}

fn unmount(mountpoint: [*:0]const u8) void {
    const pid = std.c.fork();
    if (pid == 0) {
        var argv = [_]?[*:0]const u8{ "fusermount3", "-u", "-z", mountpoint, null };
        _ = execvp("fusermount3", @ptrCast(&argv));
        _exit(1);
    } else if (pid > 0) {
        var status: c_int = 0;
        _ = waitpid(pid, &status, 0);
    }
}

// ══════════════════════════════════════════════════════════════════════
// CLI
// ══════════════════════════════════════════════════════════════════════

fn showHelp(progname: [*:0]const u8) void {
    _ = libc.printf("usage: %s --control=<socket> <mountpoint>\n", progname);
    _ = libc.printf("  --control=<path>   durian control socket (required)\n");
    _ = libc.printf("  -h, --help         show this help\n");
}

pub export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    var mountpoint: ?[*:0]const u8 = null;
    var show_help = false;

    var i: c_int = 1;
    while (i < argc) : (i += 1) {
        const a: [*:0]const u8 = @ptrCast(argv[@intCast(i)]);
        const alen = strlen(a);
        const slc = a[0..alen];
        if (std.mem.startsWith(u8, slc, "--control=")) {
            g_options.control = @ptrCast(a + "--control=".len);
        } else if (std.mem.eql(u8, slc, "-h") or std.mem.eql(u8, slc, "--help")) {
            show_help = true;
        } else if (mountpoint == null) {
            mountpoint = a;
        } else {
            _ = libc.fprintf(libc.stderr, "acfgfs: unexpected argument: %s\n", a);
            return 1;
        }
    }

    if (show_help) {
        showHelp(@ptrCast(argv[0]));
        return 0;
    }
    if (g_options.control == null) {
        _ = libc.fprintf(libc.stderr, "control socket missing, use --control=/path/to/control\n");
        return 1;
    }
    if (mountpoint == null) {
        _ = libc.fprintf(libc.stderr, "mountpoint required\n");
        return 1;
    }

    // realpath; lifetime ≡ process so no free.
    const resolved = realpath(g_options.control.?, null);
    if (resolved == null) {
        _ = libc.fprintf(libc.stderr, "control socket missing or unreadable\n");
        return 1;
    }
    g_options.control = resolved;

    g_uid = getuid();
    g_gid = getgid();

    nodeInit() catch {
        _ = libc.fprintf(libc.stderr, "acfgfs: inode table init failed\n");
        return 1;
    };

    const mp = mountpoint.?;
    fuse_fd = mountViaFusermount(mp);
    if (fuse_fd < 0) {
        _ = libc.fprintf(libc.stderr, "acfgfs: mount failed\n");
        return 1;
    }

    runLoop();

    _ = libc.close(fuse_fd);
    unmount(mp);
    return 0;
}
