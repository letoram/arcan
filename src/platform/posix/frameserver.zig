// Pure Zig port of posix/frameserver.c — platform frameserver management.
// Exports all platform_fsrv_* functions: alloc, destroy, destroy_local,
// dropshared, pushevent, pushfd, validchild, lastwords, wrapcl,
// spawn_subsegment, listen_external, preset_server, spawn_server,
// resynch, socketpoll, socketauth, default_abufsize, display_limit.
//
// Uses shmif_offsets.Fsrv / .Page / .Evctx byte-offset accessors for
// arcan_frameserver, arcan_shmif_page, arcan_evctx (all opaque in Zig
// due to bitfields / _Atomic fields).

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const shmif_monitor = @import("shmif_monitor");

// ABI constants and struct sizes come from the pure-Zig shmif_types module
// rather than @cImport — the aarch64 SH backend can't run @cImport (requires
// LLVM), and the constants / extern struct layouts in shmif_types.zig are
// authoritative. Kept as `cabi` to minimise the diff in the references below.
const cabi = if (is_freestanding) struct {} else @import("shmif_types");

// Opaque engine types
const ArcanFrameserver = anyopaque;
const ArcanShmifPage = anyopaque;
const ArcanEvctx = anyopaque;

// C library / POSIX externs
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn strerror(errnum: c_int) [*c]const u8;
extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn readlink(noalias path: [*c]const u8, noalias buf: [*c]u8, bufsiz: usize) isize;
extern fn unlink(path: [*c]const u8) c_int;
extern fn close(fd: c_int) c_int;
extern fn getpid() c_int;
extern fn getenv(name: [*c]const u8) [*c]const u8;
extern fn unsetenv(name: [*c]const u8) c_int;
extern fn ftruncate(fd: c_int, length: isize) c_int;
extern fn fchmod(fd: c_int, mode: u32) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) callconv(.c) c_int;
extern fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, offset: isize) ?*anyopaque;
extern fn munmap(addr: ?*anyopaque, len: usize) c_int;
extern fn mremap(old_addr: ?*anyopaque, old_size: usize, new_size: usize, flags: c_int, ...) callconv(.c) ?*anyopaque;
extern fn poll(fds: [*]PollFd, nfds: usize, timeout: c_int) c_int;
extern fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
extern fn socketpair(domain: c_int, sock_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern fn bind(sockfd: c_int, addr: *const anyopaque, addrlen: u32) c_int;
extern fn listen(sockfd: c_int, backlog: c_int) c_int;
extern fn accept(sockfd: c_int, addr: ?*anyopaque, addrlen: ?*u32) c_int;
extern fn shutdown(sockfd: c_int, how: c_int) c_int;
extern fn ioctl(fd: c_int, request: c_ulong, ...) callconv(.c) c_int;
extern fn stat(path: [*c]const u8, buf: *StatBuf) c_int;
extern fn kill(pid: c_int, sig: c_int) c_int;
extern fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
extern fn sleep(seconds: c_uint) c_uint;
extern fn setjmp(env: *anyopaque) c_int;
extern fn longjmp(env: *anyopaque, val: c_int) noreturn;

extern fn pthread_create(thread: *usize, attr: ?*anyopaque, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern fn pthread_attr_init(attr: *PthreadAttr) c_int;
extern fn pthread_attr_setdetachstate(attr: *PthreadAttr, detachstate: c_int) c_int;
extern fn pthread_attr_destroy(attr: *PthreadAttr) c_int;

// Engine / platform externs
extern fn arcan_warning(fmt: [*c]const u8, ...) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_random(dst: [*]u8, sz: usize) void;
extern fn arcan_timemillis() c_ulonglong;
extern fn arcan_shmif_cookie() u64;
extern fn arcan_shmif_resolve_connpath(key: [*c]const u8, dst: [*c]u8, lim: usize) c_int;
extern fn arcan_shmif_mapav(
    page: ?*anyopaque,
    vbufs: [*]?*anyopaque,
    vbufc: usize,
    vbuf_sz: usize,
    abufs: [*]?*anyopaque,
    abufc: usize,
    abuf_sz: usize,
) usize;
extern fn arcan_shmif_vbufsz(
    meta: c_int,
    hints: u8,
    w: usize,
    h: usize,
    rows: usize,
    cols: usize,
) usize;
extern fn arcan_pushhandle(fd: c_int, channel: c_int) bool;
extern fn arcan_send_fds(channel: c_int, fds: [*]c_int, nfd: usize) bool;
extern fn platform_fsrv_enter(fsrv: *ArcanFrameserver, tramp: *anyopaque) void;
extern fn platform_fsrv_leave() void;
extern fn platform_fsrv_shmmem() c_int;
// Weak: compositor provides the real implementation; frameservers get the fallback.
fn platform_video_auth(cardn: c_int, token: c_uint) bool {
    const real = @as(?*const fn (c_int, c_uint) callconv(.c) bool, @extern(
        *const fn (c_int, c_uint) callconv(.c) bool,
        .{ .name = "platform_video_auth", .linkage = .weak },
    ));
    if (real) |f| return f(cardn, token);
    return false;
}

// Constants

const BADFD: c_int = -1;
const BROKEN_PROCESS_HANDLE: c_int = -1;
const ARCAN_EID: i64 = 0;
const ARCAN_OK: c_int = 0;
const ARCAN_ERRC_BAD_ARGUMENT: c_int = -5;
const ARCAN_ERRC_NO_SUCH_OBJECT: c_int = -7;
const ARCAN_ERRC_UNACCEPTED_STATE: c_int = -4;
const ARCAN_ERRC_OUT_OF_SPACE: c_int = -6;
const EVENT_EXTERNAL: c_int = if (is_freestanding) 0 else cabi.EVENT_EXTERNAL;
const EVENT_TARGET: c_int = if (is_freestanding) 0 else cabi.EVENT_TARGET;

extern fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*anyopaque;
extern fn fprintf(f: ?*anyopaque, fmt: [*c]const u8, ...) c_int;
extern fn fclose(f: ?*anyopaque) c_int;
extern fn pread(fd: c_int, buf: [*]u8, count: usize, offset: i64) isize;
const pread_extern = pread;
const EVENT_IO: c_int = if (is_freestanding) 0 else cabi.EVENT_IO;
const TARGET_COMMAND_EXIT: c_int = if (is_freestanding) 0 else cabi.TARGET_COMMAND_EXIT;
const TARGET_COMMAND_NEWSEGMENT: c_int = if (is_freestanding) 0 else cabi.TARGET_COMMAND_NEWSEGMENT;
const SEGID_ENCODER: c_int = if (is_freestanding) 0 else cabi.SEGID_ENCODER;
const SEGID_UNKNOWN: c_int = if (is_freestanding) 0 else cabi.SEGID_UNKNOWN;
const SEGID_HANDOVER: c_int = if (is_freestanding) 0 else cabi.SEGID_HANDOVER;
const ARCAN_SHMIF_SAMPLERATE: c_uint = if (is_freestanding) 48000 else cabi.ARCAN_SHMIF_SAMPLERATE;
const ARCAN_SHMIF_ACHANNELS: u8 = if (is_freestanding) 2 else cabi.ARCAN_SHMIF_ACHANNELS;
const ARCAN_PLAYING: c_int = 2;
const ASHMIF_VERSION_MAJOR: u8 = if (is_freestanding) 0 else cabi.ASHMIF_VERSION_MAJOR;
const ASHMIF_VERSION_MINOR: u8 = if (is_freestanding) 18 else cabi.ASHMIF_VERSION_MINOR;
const SHMIF_META_CM: c_uint = if (is_freestanding) 0 else cabi.SHMIF_META_CM;
const SHMIF_META_HDR: c_uint = if (is_freestanding) 0 else cabi.SHMIF_META_HDR;
const SHMIF_META_VR: c_uint = if (is_freestanding) 0 else cabi.SHMIF_META_VR;
const SHMIF_META_VENC: c_uint = if (is_freestanding) 0 else cabi.SHMIF_META_VENC;
const SHMIF_RHINT_AUTH_TOK: c_int = if (is_freestanding) 0 else cabi.SHMIF_RHINT_AUTH_TOK;
const ARCAN_SHMIF_RAMPMAGIC: u32 = if (is_freestanding) 0 else cabi.ARCAN_SHMIF_RAMPMAGIC;
const VR_VERSION: u8 = if (is_freestanding) 0 else cabi.VR_VERSION;
const LIMB_LIM: usize = if (is_freestanding) 8 else @intCast(cabi.LIMB_LIM);
const FSRV_MAX_VBUFC: usize = 3;
const FSRV_MAX_ABUFC: usize = 12;

// Memory allocation types
const ARCAN_MEM_VTAG: c_int = 7;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// POSIX constants
const AF_UNIX: c_int = 1;
const PF_UNIX: c_int = 1;
const SOCK_STREAM: c_int = 1;
const SOCK_SEQPACKET: c_int = 5;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const F_GETFD: c_int = 1;
const F_SETFD: c_int = 2;
const O_NONBLOCK: c_int = if (@import("builtin").os.tag.isDarwin()) 0x4 else 0o4000;
const FD_CLOEXEC: c_int = 1;
const PROT_READ: c_int = 0x1;
const PROT_WRITE: c_int = 0x2;
const MAP_SHARED: c_int = 0x01;
const MAP_FAILED: usize = @as(usize, @bitCast(@as(isize, -1)));
const MREMAP_MAYMOVE: c_int = 1;
const POLLIN: c_short = 0x001;
const POLLERR: c_short = 0x008;
const POLLHUP: c_short = 0x010;
const POLLNVAL: c_short = 0x020;
const SHUT_RDWR: c_int = 2;
const EINTR: c_int = 4;
const ENOENT: c_int = 2;
const ECHILD: c_int = 10;
const EINVAL: c_int = 22;
const EAGAIN: c_int = 11;
const EWOULDBLOCK: c_int = EAGAIN;
const EACCES: c_int = 13;
const POLLOUT: c_short = 0x04;
const SOL_SOCKET: c_int = if (@import("builtin").os.tag.isDarwin()) 0xFFFF else 1;
const SO_SNDBUF: c_int = if (builtin.os.tag.isDarwin()) 0x1001 else 7;
const SO_RCVBUF: c_int = if (builtin.os.tag.isDarwin()) 0x1002 else 8;
extern fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: ?*const anyopaque, optlen: c_uint) c_int;
extern fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: ?*anyopaque, optlen: *c_uint) c_int;

// ArcanFrameserver.activated offset (fl_activated in engine/arcan_frameserver_helpers.zig:164).
// Read directly via byte arithmetic because the engine's accessor lives in
// the main arcan binary; linking from afsrv_* builds would fail.
const FSRV_OFF_ACTIVATED: usize = 760;
fn fsrv_read_activated(f: *anyopaque) c_int {
    const base: [*]u8 = @ptrCast(f);
    return @as(*align(1) c_int, @ptrCast(base + FSRV_OFF_ACTIVATED)).*;
}

// Piece 4 instrumentation: process-wide counter of platform_fsrv_pushfd
// entries. Paired with `activated` flag lets post-hoc log analysis tell
// preroll bursts apart from runtime fd-sends.
var total_pushfd_calls: u64 = 0;
const EBADF: c_int = 9;
const SIGKILL: c_int = 9;
const WNOHANG: c_int = 1;
const S_IRWXU: u32 = 0o700;
const S_IFSOCK: u32 = 0o140000;
const PTHREAD_CREATE_DETACHED: c_int = 1;

// Struct sizes from @cImport (architecture-independent)
const SIZEOF_SHMIF_OFSTBL: usize = if (is_freestanding) 128 else @sizeOf(cabi.struct_arcan_shmif_ofstbl);
const SIZEOF_SHMIF_RAMP: usize = if (is_freestanding) 256 else @sizeOf(cabi.struct_arcan_shmif_ramp);
const SIZEOF_RAMP_BLOCK: usize = if (is_freestanding) 256 else @sizeOf(cabi.struct_ramp_block);
const SIZEOF_SHMIF_VR: usize = if (is_freestanding) 256 else @sizeOf(cabi.struct_arcan_shmif_vr);
const SIZEOF_VR_LIMB: usize = if (is_freestanding) 64 else @sizeOf(cabi.struct_vr_limb);
const SIZEOF_SHMIF_VENC: usize = if (is_freestanding) 64 else @sizeOf(cabi.struct_arcan_shmif_venc);
const SIZEOF_SHMIF_PIXEL: usize = if (is_freestanding) 4 else @sizeOf(cabi.shmif_pixel);
const SIZEOF_AV_PIXEL: usize = @sizeOf(u32); // av_pixel = shmif_pixel = uint32_t
const SIZEOF_MAX_ALIGN_T: usize = 16; // max_align_t is 16 bytes on aarch64/x86_64

// POSIX types

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

// Use Zig's platform-correct Stat struct
const StatBuf = if (@import("builtin").os.tag.isDarwin()) std.c.Stat else std.os.linux.Stat;

// sockaddr_un — Darwin leads with a length byte and uses a 104-byte path
const SockaddrUn = if (@import("builtin").os.tag.isDarwin()) extern struct {
    sun_len: u8 = 0,
    sun_family: u8 = 0,
    sun_path: [104]u8,
} else extern struct {
    sun_family: u16,
    sun_path: [108]u8,
};

// Minimal pthread_attr_t placeholder (Linux aarch64: 64 bytes)
const PthreadAttr = extern struct {
    data: [64]u8,
};

// jmp_buf
// Linux aarch64 jmp_buf: 312 bytes (from setjmpimpl.h / glibc)
const JMPBUF_SIZE: usize = 312;

// Build option: DRM auth
// In C, PLATFORM_VIDEO_DRMAUTH is a compile-time define. In Zig, the
// build system should set this via an @import("config") or root module
// option. For now, default to true (the code is harmless on non-DRM
// platforms since flags.gpu_auth will be false).
const drmauth_enabled: bool = true;

// Static state

var default_abuf_sz: usize = 512;
var default_disp_lim: usize = 8;

// Compositor DMA-BUF vidp allocation
// Allocates a CPU-mappable DMA-BUF via GBM (in vk.zig) and sends
// the fd + metadata to the client via DEVICE_NODE event. The client
// mmaps it as vidp. On push_buffer, the compositor imports the DMA-BUF
// directly as a Vulkan texture (STREAM_HANDLE path).

const GbmAllocResult = extern struct {
    fd: c_int,
    map_ptr: ?*anyopaque,
    map_data: ?*anyopaque,
    bo: ?*anyopaque,
    stride: u32,
    modifier_lo: u32,
    modifier_hi: u32,
};

// Weak externs: only available when Vulkan compositor is linked.
const vk_gbm_alloc_fn = @as(?*const fn (u32, u32, *GbmAllocResult) callconv(.c) bool, @extern(
    *const fn (u32, u32, *GbmAllocResult) callconv(.c) bool,
    .{ .name = "vk_gbm_alloc", .linkage = .weak },
));
const vk_gbm_free_fn = @as(?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void, @extern(
    *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    .{ .name = "vk_gbm_free", .linkage = .weak },
));

const TARGET_COMMAND_DEVICE_NODE: c_int = if (is_freestanding) 0 else cabi.TARGET_COMMAND_DEVICE_NODE;
const DRM_FORMAT_ARGB8888: u32 = 0x34325241;

fn dmabuf_vidp_free(s: *anyopaque) void {
    const old_bo = off.Fsrv.getDmabufVidpBo(s);
    const old_map_data = off.Fsrv.getDmabufVidpMapData(s);
    const old_fd = off.Fsrv.getDmabufVidpFd(s);

    if (old_fd >= 0) {
        // Free GBM BO (also unmaps).  Same weak-extern null-check trap as
        // dmabuf_vidp_realloc — the `if (vk_gbm_free_fn) |..|` capture
        // bypasses the runtime null check when the compiler thinks the
        // optional is provably-non-null.  Explicit numeric guard.
        if (vk_gbm_free_fn != null and @intFromPtr(vk_gbm_free_fn) != 0) {
            vk_gbm_free_fn.?(old_bo, old_map_data);
        }
        _ = close(old_fd);
        off.Fsrv.setDmabufVidpGlid(s, 0);
        off.Fsrv.setDmabufVidpFd(s, -1);
        off.Fsrv.setDmabufVidpBo(s, null);
        off.Fsrv.setDmabufVidpMapData(s, null);
        off.Fsrv.setDmabufVidpMapPtr(s, null);
    }
}

fn dmabuf_vidp_realloc(s: *anyopaque, w: u32, h: u32) void {
    // The compiler treats `@as(?*const fn..., @extern(*const fn..., .{ .linkage = .weak }))`
    // as guaranteed-non-null and elides the orelse null check, so the
    // unresolved-weak NULL flies straight into a call. Explicit numeric
    // test via @intFromPtr forces the compare. Same applies to
    // dmabuf_vidp_free's vk_gbm_free_fn check (line 291) — see below.
    if (vk_gbm_alloc_fn == null or @intFromPtr(vk_gbm_alloc_fn) == 0) {
        _ = std.c.write(2, "[dmabuf_vidp] weak extern vk_gbm_alloc not resolved\n", 52);
        return;
    }
    const alloc_fn = vk_gbm_alloc_fn.?;

    // Free old allocation if dimensions changed
    const old_w = off.Fsrv.getDmabufVidpW(s);
    const old_h = off.Fsrv.getDmabufVidpH(s);
    if (off.Fsrv.getDmabufVidpFd(s) >= 0 and old_w == w and old_h == h)
        return; // Same size, keep existing DMA-BUF

    dmabuf_vidp_free(s);

    var result: GbmAllocResult = undefined;
    if (!alloc_fn(w, h, &result)) {
        _ = std.c.write(2, "[dmabuf_vidp] vk_gbm_alloc failed\n", 34);
        return; // GBM not available or alloc failed — client stays on shmif path
    }
    // Store in frameserver struct
    off.Fsrv.setDmabufVidpFd(s, result.fd);
    off.Fsrv.setDmabufVidpBo(s, result.bo);
    off.Fsrv.setDmabufVidpMapData(s, result.map_data);
    off.Fsrv.setDmabufVidpMapPtr(s, result.map_ptr);
    off.Fsrv.setDmabufVidpStride(s, result.stride);
    off.Fsrv.setDmabufVidpModLo(s, result.modifier_lo);
    off.Fsrv.setDmabufVidpModHi(s, result.modifier_hi);
    off.Fsrv.setDmabufVidpW(s, w);
    off.Fsrv.setDmabufVidpH(s, h);

    // Send DMA-BUF fd to client via DEVICE_NODE event (subtype 6 = dmabuf vidp).
    // The client mmaps it and replaces vidp.
    // ioevs layout: [0].iv = render_node_fd (paired fd), [1].iv = 6 (subtype),
    //               [2].iv = stride, [3].iv = format (DRM fourcc)
    var ev: cabi.arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
    ev.unnamed_0.unnamed_0.category = @intCast(EVENT_TARGET);
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_uint, @intCast(TARGET_COMMAND_DEVICE_NODE)));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = 6; // subtype: dmabuf vidp
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = @intCast(result.stride);
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @bitCast(DRM_FORMAT_ARGB8888);

    // Dup the fd for sending (compositor keeps original)
    const send_fd = std.c.dup(result.fd);
    if (send_fd >= 0) {
        const pfd_rc = platform_fsrv_pushfd(@ptrCast(s), &ev, send_fd);
        // SCM_RIGHTS duplicates on receive; sender always closes its dup.
        _ = close(send_fd);
        // fossil 7c2828e9bd: arcan-net bridge clients can't import DMA-BUF
        // via SCM_RIGHTS — kernel rejects with EACCES because the receiver
        // (helper_cl grandchild) lives in a different graphics domain and
        // has no GPU access.  When the push fails, the compositor still
        // has the DMA-BUF marked as the client's vidp but the client never
        // got it; every subsequent frame the compositor writes to a
        // DMA-BUF the client can't read, frames don't deliver, and the
        // bridge hangs / tears down.
        // Recovery: free the DMA-BUF and let the client stay on the
        // standard shm-backed vidp path.
        if (pfd_rc != ARCAN_OK) {
            _ = std.c.write(2,
                "[dmabuf_vidp] pushfd rejected — reverting to shm vidp\n", 54);
            dmabuf_vidp_free(s);
        }
    }
}

// Helper: get errno

fn get_errno() c_int {
    if (is_freestanding) return 0;
    return get_errno_posix();
}
fn get_errno_posix() c_int {
    return std.c._errno().*;
}

fn set_errno(val: c_int) void {
    if (is_freestanding) return;
    set_errno_posix(val);
}
fn set_errno_posix(val: c_int) void {
    std.c._errno().* = val;
}

// Helper: FORCE_SYNCH

var force_synch_dummy: u32 = 0;
inline fn FORCE_SYNCH() void {
    @atomicStore(u32, &force_synch_dummy, @atomicLoad(u32, &force_synch_dummy, .seq_cst), .seq_cst);
    _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);
}

// Helper: TRAMP_GUARD
// Returns true if the trampoline fired (i.e., should return error).
// On success (setjmp returns 0), calls platform_fsrv_enter and returns false.
fn tramp_guard(fsrv: *ArcanFrameserver, tramp: *align(16) [JMPBUF_SIZE]u8) bool {
    if (setjmp(@ptrCast(tramp)) != 0)
        return true;
    platform_fsrv_enter(fsrv, @ptrCast(tramp));
    return false;
}

// Helper: S_ISSOCK

fn stat_is_sock(buf: *const StatBuf) bool {
    return (buf.mode & 0o170000) == S_IFSOCK;
}

fn stat_get_mode(buf: *const StatBuf) u32 {
    return buf.mode;
}

// Helper: PP_QUEUE_SZ

const PP_QUEUE_SZ: u8 = off.Page.pp_queue_sz;

// shmpage_size

fn shmpage_size(w: usize, h: usize, vbufc: usize, abufc: usize, abufsz: usize, apad: usize) usize {
    return off.Page.sizeof_page + apad + 64 +
        abufc * abufsz + (abufc * 64) +
        vbufc * w * h * SIZEOF_SHMIF_PIXEL + (vbufc * 64);
}

// fsrv_setevqs

fn fsrv_setevqs(dst: *anyopaque, inq: *anyopaque, outq: *anyopaque) void {
    {
        const f = fopen("/tmp/arcan_shm_trace.log", "a");
        if (f != null) {
            _ = fprintf(f, "fsrv_setevqs: shm=%p inq=%p outq=%p childevq_front=%p\n",
                dst, inq, outq, off.Page.childevqFrontPtr(dst));
            _ = fclose(f);
        }
    }
    // Note: the C code swaps inq/outq immediately, so the "inqueue" from the
    // frameserver's perspective maps to the child evq on the shared page,
    // and "outqueue" maps to the parent evq. We replicate the swap.
    const real_inq = outq;
    const real_outq = inq;

    // killswitch = NULL
    off.Evctx.setSynchKillswitch(real_inq, null);
    off.Evctx.setSynchKillswitch(real_outq, null);

    // inq (was outq param) -> childevq
    off.Evctx.setLocal(real_inq, false);
    off.Evctx.setEventbuf(real_inq, @ptrCast(off.Page.childevqEventbuf(dst)));
    off.Evctx.setFront(real_inq, off.Page.childevqFrontPtr(dst));
    off.Evctx.setBack(real_inq, off.Page.childevqBackPtr(dst));
    off.Evctx.setEventbufSz(real_inq, PP_QUEUE_SZ);

    // outq (was inq param) -> parentevq
    off.Evctx.setLocal(real_outq, false);
    off.Evctx.setEventbuf(real_outq, @ptrCast(off.Page.parentevqEventbuf(dst)));
    off.Evctx.setFront(real_outq, off.Page.parentevqFrontPtr(dst));
    off.Evctx.setBack(real_outq, off.Page.parentevqBackPtr(dst));
    off.Evctx.setEventbufSz(real_outq, PP_QUEUE_SZ);
}

// nanny_thread

fn nanny_thread(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const pidptr: *c_int = @ptrCast(@alignCast(arg));
    const pid = pidptr.*;
    var counter: c_int = 10;

    while (counter > 0) {
        counter -= 1;
        var statusfl: c_int = 0;
        const rv = waitpid(pid, &statusfl, WNOHANG);
        if (rv > 0)
            break;

        if (counter == 0) {
            _ = kill(pid, SIGKILL);
            _ = waitpid(pid, &statusfl, 0);
            break;
        }

        _ = sleep(1);
    }

    free(@as(?*anyopaque, @ptrCast(pidptr)));
    return null;
}

// fsrv_killchild

var env_checked: bool = false;
var no_nanny: bool = false;

fn fsrv_killchild(src: *anyopaque) void {
    // only "kill" main-segments and non-authoritative connections
    if (off.Fsrv.getParentVid(src) != ARCAN_EID or off.Fsrv.getChild(src) <= 1)
        return;

    // drop env so we don't propagate to sub- arcan_lwa processes
    if (!env_checked) {
        env_checked = true;
        if (getenv("ARCAN_DEBUG_NONANNY") != null) {
            _ = unsetenv("ARCAN_DEBUG_NONANNY");
            no_nanny = true;
        }
    }

    if (no_nanny)
        return;

    // nanny thread: fire once then forget
    const pidptr_raw = malloc(@sizeOf(c_int)) orelse {
        _ = kill(off.Fsrv.getChild(src), SIGKILL);
        return;
    };
    const pidptr: *c_int = @ptrCast(@alignCast(pidptr_raw));
    pidptr.* = off.Fsrv.getChild(src);

    var nanny_attr: PthreadAttr = undefined;
    _ = pthread_attr_init(&nanny_attr);
    _ = pthread_attr_setdetachstate(&nanny_attr, PTHREAD_CREATE_DETACHED);

    var nanny: usize = 0;
    if (0 != pthread_create(&nanny, @ptrCast(&nanny_attr), &nanny_thread, pidptr_raw))
        _ = kill(off.Fsrv.getChild(src), SIGKILL);
    _ = pthread_attr_destroy(&nanny_attr);
}

// fd_avail

fn fd_avail(fd: c_int, term: *bool) bool {
    var fds = [1]PollFd{.{
        .fd = fd,
        .events = POLLIN | POLLERR | POLLHUP | POLLNVAL,
        .revents = 0,
    }};

    const sv = poll(&fds, 1, 0);
    term.* = false;

    if (sv == -1) {
        if (get_errno() != EINTR)
            term.* = true;
        return false;
    }

    if (sv == 0)
        return false;

    if ((fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
        term.* = true;
    } else {
        return true;
    }

    return false;
}

// sockpair_alloc

fn sockpair_alloc(dst: []c_int, n: usize, cloexec: bool) bool {
    var result = false;
    const total = n * 2;

    var i: usize = 0;
    while (i < total) : (i += 2) {
        var pair: [2]c_int = .{ -1, -1 };
        if (socketpair(PF_UNIX, SOCK_STREAM, 0, &pair) != -1) {
            dst[i] = pair[0];
            dst[i + 1] = pair[1];
            result = true;
        }
    }

    if (!result) {
        for (dst[0..total]) |*d| {
            if (d.* != -1) {
                _ = close(d.*);
                d.* = -1;
            }
        }
    } else {
        for (dst[0..total]) |d| {
            var flags = fcntl(d, F_GETFL);
            if (flags != -1)
                _ = fcntl(d, F_SETFL, flags | O_NONBLOCK);

            if (cloexec) {
                flags = fcntl(d, F_GETFD);
                if (flags != -1)
                    _ = fcntl(d, F_SETFD, flags | FD_CLOEXEC);
            }

            // Bump send/recv buffer to 4 MiB. Default ~200 KiB and tiny SCM_RIGHTS
            // messages each take a non-trivial chunk of kernel memory, so we
            // hit EAGAIN on rapid multi-fd-pass even though logical data is
            // tiny. We have plenty of RAM; trade memory for reliability.
            //
            // The kernel silently caps SO_SNDBUF to 2 * net.core.wmem_max for
            // unprivileged processes — typically 208 KiB, not our requested
            // 4 MiB. setsockopt returns success in either case. Verify with
            // getsockopt so the "we have 4 MiB headroom" premise that all the
            // downstream retry loops rely on is either confirmed or loudly
            // shown to be fiction.
            const big_buf: c_int = 4 * 1024 * 1024;
            _ = setsockopt(d, SOL_SOCKET, SO_RCVBUF, @ptrCast(&big_buf), @sizeOf(c_int));
            _ = setsockopt(d, SOL_SOCKET, SO_SNDBUF, @ptrCast(&big_buf), @sizeOf(c_int));

            var got_snd: c_int = 0;
            var got_rcv: c_int = 0;
            var optlen: c_uint = @sizeOf(c_int);
            _ = getsockopt(d, SOL_SOCKET, SO_SNDBUF, @ptrCast(&got_snd), &optlen);
            optlen = @sizeOf(c_int);
            _ = getsockopt(d, SOL_SOCKET, SO_RCVBUF, @ptrCast(&got_rcv), &optlen);
            arcan_warning(
                "sockpair_alloc: fd=%d requested=%d got_snd=%d got_rcv=%d\n",
                @as(c_int, d),
                @as(c_int, big_buf),
                @as(c_int, got_snd),
                @as(c_int, got_rcv),
            );
            if (builtin.mode == .Debug and comptime !builtin.os.tag.isDarwin()) {
                // Loud failure if the kernel clamped us below 1 MiB — the
                // whole premise of the downstream workarounds is wrong when
                // this fires. Darwin caps AF_UNIX buffers far lower and the
                // Linux-specific retry premise doesn't apply; keep whatever
                // the kernel grants there.
                std.debug.assert(got_snd >= 1_000_000);
            }
        }
    }

    return result;
}

// setup_socket

fn setup_socket(ctx: *anyopaque, shmfd: c_int, optkey: [*c]const u8, optdesc: c_int) bool {
    _ = shmfd;
    var addr: SockaddrUn = std.mem.zeroes(SockaddrUn);
    addr.sun_family = AF_UNIX;
    const lim = addr.sun_path.len;

    if (optkey == null) {
        arcan_warning("posix/frameserver.c:shmalloc(), named socket " ++
            "connected requested but with empty key. cannot " ++
            "setup frameserver connectionpoint.\n");
        return false;
    }

    var fd = optdesc;
    if (optdesc == -1) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd == -1) {
            arcan_warning("posix/frameserver.c:shmalloc(), could allocate socket " ++
                "for listening, check permissions and descriptor ulimit.\n");
            return false;
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC);
    }

    const len = arcan_shmif_resolve_connpath(optkey, &addr.sun_path, lim);
    if (len < 0) {
        arcan_warning("posix/frameserver.c:setup_socket(), couldn't resolve path");
        return false;
    } else if (@as(usize, @intCast(len)) > lim) {
        arcan_warning("posix/frameserver.c:setup_socket(), expanded path " ++
            "exceed build-time length");
        return false;
    }

    if (optdesc == -1) {
        // Check for stale listener
        var sbuf: StatBuf = undefined;
        const rv = stat(&addr.sun_path, &sbuf);
        if ((rv == -1 and get_errno() != ENOENT) or (rv == 0 and !stat_is_sock(&sbuf))) {
            _ = close(fd);
            return false;
        } else if (rv == 0) {
            _ = unlink(&addr.sun_path);
        }

        if (bind(fd, @ptrCast(&addr), @sizeOf(SockaddrUn)) != 0) {
            arcan_warning("posix/frameserver.c:shmalloc(), couldn't setup " ++
                "domain socket for frameserver connectionpoint, check " ++
                "path permissions.\n");
            _ = close(fd);
            return false;
        }

        _ = fchmod(fd, off.Fsrv.getSockmode(ctx));
        _ = listen(fd, 5);
    }

    off.Fsrv.setDpipe(ctx, fd);
    // Track output socket path separately for unlink on exit
    off.Fsrv.setSockaddr(ctx, strdup(&addr.sun_path));
    if (optkey != null) {
        off.Fsrv.setSockkey(ctx, strdup(optkey));
    } else {
        off.Fsrv.setSockkey(ctx, null);
    }
    return true;
}

// fill_shmpage

fn fill_shmpage(ctx: *anyopaque, shmfd: c_int) bool {
    off.Fsrv.setShmHandle(ctx, shmfd);

    const shmsize = off.Fsrv.getShmShmsize(ctx);
    const raw = mmap(null, shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, shmfd, 0);
    {
        var sb: StatBuf = undefined;
        const stat_rc = fstat(shmfd, &sb);
        const f = fopen("/tmp/arcan_shm_trace.log", "a");
        if (f != null) {
            _ = fprintf(f, "fill_shmpage: ctx=%p shmfd=%d ino=%llu sz=%zu mmap=%p\n",
                ctx, shmfd,
                @as(c_ulonglong, @intCast(if (stat_rc == 0) sb.ino else 0)),
                shmsize, raw);
            _ = fclose(f);
        }
    }
    if (@intFromPtr(raw) == MAP_FAILED or raw == null) {
        arcan_warning("platform_fsrv_spawn_server(unix) -- couldn't " ++
            "allocate shmpage\n");
        _ = close(shmfd);
        return false;
    }
    const shmpage: *anyopaque = raw.?;

    // setjmp for SIGBUS protection
    var out_buf: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&out_buf)) != 0) {
        _ = munmap(shmpage, shmsize);
        off.Fsrv.setShmPtr(ctx, null);
        _ = close(shmfd);
        return false;
    }

    // tiny race condition SIGBUS window here
    platform_fsrv_enter(ctx, @ptrCast(&out_buf));
    _ = memset(shmpage, 0, shmsize);
    off.Page.setDms(shmpage, 1);
    off.Page.setParent(shmpage, getpid());
    off.Page.setMajor(shmpage, ASHMIF_VERSION_MAJOR);
    off.Page.setMinor(shmpage, ASHMIF_VERSION_MINOR);
    off.Page.setSegmentSize(shmpage, @intCast(shmsize));
    off.Page.setSegmentToken(shmpage, off.Fsrv.getCookie(ctx));
    off.Page.setCookie(shmpage, arcan_shmif_cookie());

    off.Page.setVpending(shmpage, 1);
    off.Page.setApending(shmpage, 1);
    off.Fsrv.setShmPtr(ctx, shmpage);
    platform_fsrv_leave();

    // BUG-10: log page creation — confirm dms=1 was written

    // should already be set but make sure
    _ = fcntl(shmfd, F_SETFD, FD_CLOEXEC);
    return true;
}

// shmalloc

fn shmalloc(ctx: *anyopaque, namedsocket: bool, optkey: [*c]const u8, optdesc: c_int) bool {
    if (off.Fsrv.getShmShmsize(ctx) == 0) {
        off.Fsrv.setShmShmsize(ctx, @intCast(cabi.ARCAN_SHMPAGE_START_SZ));
    }

    const shmfd = platform_fsrv_shmmem();
    if (shmfd == -1)
        return false;

    if (namedsocket) {
        if (!setup_socket(ctx, shmfd, optkey, optdesc)) {
            _ = close(shmfd);
            return false;
        }
    }

    // max videoframesize + DTS + structure + maxaudioframesize
    const rc = ftruncate(shmfd, @intCast(off.Fsrv.getShmShmsize(ctx)));
    if (rc == -1) {
        arcan_warning("platform_fsrv_spawn_server(unix) -- allocating" ++
            " shared memory failed.\n");
        _ = close(shmfd);
        return false;
    }

    return fill_shmpage(ctx, shmfd);
}

// fsrv_protosize

fn fsrv_protosize(ctx: *anyopaque, proto: c_uint, dofs_opt: ?[*]u8) usize {
    _ = ctx;
    var tot: usize = 0;
    const dofs = dofs_opt orelse return 0;
    if (proto == 0) {
        @memset(dofs[0..SIZEOF_SHMIF_OFSTBL], 0);
        return 0;
    }

    tot += SIZEOF_SHMIF_OFSTBL;
    if (tot % SIZEOF_MAX_ALIGN_T != 0)
        tot += tot - (tot % SIZEOF_MAX_ALIGN_T);

    // Offsets within arcan_shmif_ofstbl (each field is u32):
    // ofs_ramp=0, sz_ramp=4, ofs_vr=8, sz_vr=12, ofs_hdr=16, sz_hdr=20,
    // ofs_vector=24, sz_vector=28, ofs_venc=32, sz_venc=36
    const ofs_ramp_off: usize = 0;
    const sz_ramp_off: usize = 4;
    const ofs_vr_off: usize = 8;
    const sz_vr_off: usize = 12;
    const ofs_hdr_off: usize = 16;
    const sz_hdr_off: usize = 20;
    const ofs_venc_off: usize = 32;
    const sz_venc_off: usize = 36;

    if ((proto & SHMIF_META_CM) != 0) {
        var lim = default_disp_lim;
        writeU32(dofs, ofs_ramp_off, @intCast(tot));
        writeU32(dofs, sz_ramp_off, @intCast(tot));
        lim *= 2; // both in and out
        tot += SIZEOF_SHMIF_RAMP + SIZEOF_RAMP_BLOCK * lim;
        const cur_ofs = readU32(dofs, sz_ramp_off);
        writeU32(dofs, sz_ramp_off, @intCast(tot - cur_ofs));
    } else {
        writeU32(dofs, ofs_ramp_off, 0);
        writeU32(dofs, sz_ramp_off, 0);
    }

    if (tot % SIZEOF_MAX_ALIGN_T != 0)
        tot += tot - (tot % SIZEOF_MAX_ALIGN_T);

    // HDR: nothing now
    writeU32(dofs, ofs_hdr_off, 0);
    writeU32(dofs, sz_hdr_off, 0);

    if ((proto & SHMIF_META_VENC) != 0) {
        writeU32(dofs, ofs_venc_off, @intCast(tot));
        writeU32(dofs, sz_venc_off, @intCast(tot));
        tot += SIZEOF_SHMIF_VENC;
        const cur_ofs = readU32(dofs, sz_venc_off);
        writeU32(dofs, sz_venc_off, @intCast(tot - cur_ofs));
    }

    if (tot % SIZEOF_MAX_ALIGN_T != 0)
        tot += tot - (tot % SIZEOF_MAX_ALIGN_T);

    if ((proto & SHMIF_META_VR) != 0) {
        writeU32(dofs, ofs_vr_off, @intCast(tot));
        writeU32(dofs, sz_vr_off, @intCast(tot));
        tot += SIZEOF_SHMIF_VR;
        tot += SIZEOF_VR_LIMB * LIMB_LIM;
        const cur_ofs = readU32(dofs, sz_vr_off);
        writeU32(dofs, sz_vr_off, @intCast(tot - cur_ofs));
    } else {
        writeU32(dofs, ofs_vr_off, 0);
        writeU32(dofs, sz_vr_off, 0);
    }

    if (tot % SIZEOF_MAX_ALIGN_T != 0)
        tot += tot - (tot % SIZEOF_MAX_ALIGN_T);

    return tot;
}

fn readU32(buf: [*]u8, byte_off: usize) u32 {
    const p: *align(1) const u32 = @ptrCast(buf + byte_off);
    return p.*;
}

fn writeU32(buf: [*]u8, byte_off: usize, val: u32) void {
    const p: *align(1) u32 = @ptrCast(buf + byte_off);
    p.* = val;
}

// fsrv_setproto

fn fsrv_setproto(ctx: *anyopaque, proto: c_uint, aofs: [*]const u8) void {
    // Zero desc.aext
    off.Fsrv.zeroDescAext(ctx);
    // Copy ofstbl into desc.aofs
    _ = memcpy(@ptrCast(off.Fsrv.getDescAofsPtr(ctx)), @ptrCast(aofs), SIZEOF_SHMIF_OFSTBL);

    if (proto == 0)
        return;

    // base = address of shmpage->adata
    const shmpage = off.Fsrv.getShmPtr(ctx) orelse return;
    const base: usize = off.Page.getAdataAddr(shmpage);

    // Copy ofstbl to the beginning of adata
    _ = memcpy(@ptrFromInt(base), @ptrCast(aofs), SIZEOF_SHMIF_OFSTBL);

    if ((proto & SHMIF_META_CM) != 0) {
        const ofs_ramp = readU32Const(aofs, 0);
        const sz_ramp = readU32Const(aofs, 4);
        var lim = default_disp_lim;
        const gamma_addr = base + ofs_ramp;
        off.Fsrv.setDescAextGamma(ctx, @ptrFromInt(gamma_addr));
        _ = memset(@ptrFromInt(gamma_addr), 0, sz_ramp);
        lim = if (lim != 0) lim else 4;
        lim *= 2; // both in and out
        // Set magic and n_blocks via typed pointer
        const gamma_ptr: *cabi.struct_arcan_shmif_ramp = @ptrFromInt(gamma_addr);
        gamma_ptr.magic = ARCAN_SHMIF_RAMPMAGIC;
        gamma_ptr.n_blocks = @intCast(lim);
    } else {
        off.Fsrv.setDescAextGamma(ctx, null);
    }

    if ((proto & SHMIF_META_HDR) != 0) {
        const ofs_hdr = readU32Const(aofs, 16);
        const sz_hdr = readU32Const(aofs, 20);
        const hdr_addr = base + ofs_hdr;
        off.Fsrv.setDescAextHdr(ctx, @ptrFromInt(hdr_addr));
        _ = memset(@ptrFromInt(hdr_addr), 0, sz_hdr);
    } else {
        off.Fsrv.setDescAextHdr(ctx, null);
    }

    if ((proto & SHMIF_META_VR) != 0) {
        const ofs_vr = readU32Const(aofs, 8);
        const sz_vr = readU32Const(aofs, 12);
        const vr_addr = base + ofs_vr;
        off.Fsrv.setDescAextVr(ctx, @ptrFromInt(vr_addr));
        _ = memset(@ptrFromInt(vr_addr), 0, sz_vr);
        // vr->version at @offsetOf(0), vr->limb_lim at @offsetOf(1)
        const vr_ptr: *cabi.struct_arcan_shmif_vr = @ptrFromInt(vr_addr);
        vr_ptr.version = VR_VERSION;
        vr_ptr.limb_lim = @intCast(LIMB_LIM);
    } else {
        off.Fsrv.setDescAextVr(ctx, null);
    }

    if ((proto & SHMIF_META_VENC) != 0) {
        const ofs_venc = readU32Const(aofs, 32);
        const sz_venc = readU32Const(aofs, 36);
        const venc_addr = base + ofs_venc;
        off.Fsrv.setDescAextVenc(ctx, @ptrFromInt(venc_addr));
        _ = memset(@ptrFromInt(venc_addr), 0, sz_venc);
    } else {
        off.Fsrv.setDescAextVenc(ctx, null);
    }

    off.Fsrv.setDescAproto(ctx, proto);
}

fn readU32Const(buf: [*]const u8, byte_off: usize) u32 {
    const p: *align(1) const u32 = @ptrCast(buf + byte_off);
    return p.*;
}

// prepare_segment

fn prepare_segment(
    ctx: *anyopaque,
    segid: c_int,
    hints: c_int,
    hintw: usize,
    hinth: usize,
    named: bool,
    optkey: [*c]const u8,
    optdesc: c_int,
    tag: usize,
) bool {
    var abufc: usize = 0;
    var abufsz: usize = 0;

    // Encoder gets audio buffers
    if (segid == SEGID_ENCODER) {
        abufc = 1;
        abufsz = 65535;
    }

    off.Fsrv.setShmShmsize(ctx, shmpage_size(hintw, hinth, 1, abufc, abufsz, 0));

    if (!shmalloc(ctx, named, optkey, optdesc))
        return false;

    const shmpage = off.Fsrv.getShmPtr(ctx) orelse return false;

    var out_buf: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&out_buf)) != 0) {
        _ = platform_fsrv_destroy(ctx);
        return false;
    }

    // Write new settings to shm page
    platform_fsrv_enter(ctx, @ptrCast(&out_buf));
    off.Page.setW(shmpage, @intCast(hintw));
    off.Page.setH(shmpage, @intCast(hinth));
    off.Page.setHints(shmpage, @intCast(hints));
    off.Page.setVpending(shmpage, 1);
    off.Page.setAbufsize(shmpage, @intCast(abufsz));
    off.Page.setApending(shmpage, @intCast(abufc));

    const vbufs = off.Fsrv.getVbufsPtr(ctx);
    const abufs = off.Fsrv.getAbufsPtr(ctx);
    const new_seg_size = arcan_shmif_mapav(
        shmpage,
        vbufs,
        1,
        hintw * hinth * SIZEOF_SHMIF_PIXEL,
        abufs,
        abufc,
        abufsz,
    );
    off.Page.setSegmentSize(shmpage, @intCast(new_seg_size));

    platform_fsrv_leave();

    // Set desc fields
    off.Fsrv.setDescWidth(ctx, @intCast(hintw));
    off.Fsrv.setDescHeight(ctx, @intCast(hinth));
    off.Fsrv.setDescSamplerate(ctx, ARCAN_SHMIF_SAMPLERATE);
    off.Fsrv.setDescChannels(ctx, ARCAN_SHMIF_ACHANNELS);
    off.Fsrv.setDescBpp(ctx, SIZEOF_AV_PIXEL);

    off.Fsrv.setLaunchedtime(ctx, @intCast(arcan_timemillis()));
    off.Fsrv.setFlagsAlive(ctx, true);
    off.Fsrv.setSegid(ctx, segid);

    off.Fsrv.setVbufCnt(ctx, 1);
    off.Fsrv.setAbufCnt(ctx, abufc);
    off.Fsrv.setAbufSz(ctx, abufsz);
    off.Fsrv.setTag(ctx, @intCast(tag));

    const inqueue = off.Fsrv.getInqueuePtr(ctx);
    const outqueue = off.Fsrv.getOutqueuePtr(ctx);
    fsrv_setevqs(shmpage, inqueue, outqueue);

    // Set killswitches to point back to ctx
    off.Evctx.setSynchKillswitch(inqueue, ctx);
    off.Evctx.setSynchKillswitch(outqueue, ctx);

    return true;
}

// ══════════════════════════════════════════════════════════════════════
// Exported functions
// ══════════════════════════════════════════════════════════════════════

// platform_fsrv_alloc

export fn platform_fsrv_alloc() callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    const raw = arcan_alloc_mem(
        2280, // sizeof(arcan_frameserver) on aarch64 — includes dmabuf_vidp
        ARCAN_MEM_VTAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return null;
    const res: *anyopaque = raw;

    off.Fsrv.setWatchConst(res, 0xfeed);
    off.Fsrv.setDpipe(res, BADFD);
    // Initialize dmabuf_vidp.fd to -1 (inactive)
    off.Fsrv.setDmabufVidpFd(res, -1);
    off.Fsrv.setQueueMask(res, EVENT_EXTERNAL);
    off.Fsrv.setPlaystate(res, ARCAN_PLAYING);
    off.Fsrv.setFlagsAlive(res, true);
    off.Fsrv.setFlagsAutoclock(res, true);
    off.Fsrv.setXferSat(res, 0.5);
    off.Fsrv.setParentVid(res, ARCAN_EID);
    off.Fsrv.setDescSamplerate(res, ARCAN_SHMIF_SAMPLERATE);
    off.Fsrv.setSockmode(res, S_IRWXU);
    off.Fsrv.setChild(res, BROKEN_PROCESS_HANDLE);
    off.Fsrv.setDescChannels(res, ARCAN_SHMIF_ACHANNELS);

    // Generate random cookie
    var cookie_bytes: [4]u8 = undefined;
    arcan_random(&cookie_bytes, 4);
    const cookie_val: u32 = @as(*align(1) const u32, @ptrCast(&cookie_bytes)).*;
    off.Fsrv.setCookie(res, cookie_val);

    return @ptrCast(res);
}

// platform_fsrv_wrapcl

export fn platform_fsrv_wrapcl(in: ?*anyopaque, tag: usize) callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    const res = platform_fsrv_alloc() orelse return null;
    const f: *anyopaque = @ptrCast(res);

    // desc fields from in->w, in->h
    // arcan_shmif_cont is opaque in Zig, use Cont byte-offset accessors
    if (in) |cont| {
        off.Fsrv.setDescWidth(f, @intCast(off.Cont.getW(cont)));
        off.Fsrv.setDescHeight(f, @intCast(off.Cont.getH(cont)));
    }
    off.Fsrv.setDescSamplerate(f, ARCAN_SHMIF_SAMPLERATE);
    off.Fsrv.setDescChannels(f, ARCAN_SHMIF_ACHANNELS);
    off.Fsrv.setDescBpp(f, SIZEOF_AV_PIXEL);

    off.Fsrv.setFlagsWrapped(f, true);
    off.Fsrv.setFlagsAlive(f, true);
    off.Fsrv.setVid(f, @intCast(tag));
    off.Fsrv.setShmExternal(f, in);

    return res;
}

// platform_fsrv_lastwords

export fn platform_fsrv_lastwords(src: ?*ArcanFrameserver, dst: [*c]u8, n: usize) callconv(.c) bool {
    if (is_freestanding) return false;
    const s: *anyopaque = @ptrCast(src orelse {
        if (n > 0) dst[0] = 0;
        return false;
    });

    const shmptr = off.Fsrv.getShmPtr(s) orelse {
        if (n > 0) dst[0] = 0;
        return false;
    };

    var tramp: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&tramp)) != 0) {
        if (n > 0) dst[0] = 0;
        return false;
    }

    platform_fsrv_enter(s, @ptrCast(&tramp));
    const lw_sz = off.Page.sizeof_last_words;
    const copy_n = if (n > lw_sz) lw_sz else n;

    // Copy last_words from shared page to dst
    var i: usize = 0;
    while (i < copy_n) : (i += 1) {
        const ch = off.Page.getLastWordsChar(shmptr, i);
        dst[i] = ch;
        if (ch == 0) break;
    }
    if (i < n) dst[i] = 0;

    platform_fsrv_leave();
    return true;
}

// platform_fsrv_destroy_local

export fn platform_fsrv_destroy_local(src: ?*ArcanFrameserver) callconv(.c) bool {
    if (is_freestanding) return false;
    const s: *anyopaque = @ptrCast(src orelse return false);

    if (!off.Fsrv.getFlagsAlive(s))
        return false;

    // Free compositor-allocated DMA-BUF vidp
    dmabuf_vidp_free(s);

    off.Fsrv.setFlagsAlive(s, false);
    arcan_mem_free(@ptrCast(off.Fsrv.getAudb(s)));
    off.Fsrv.setAudb(s, null);

    if (off.Fsrv.getFlagsWrapped(s)) {
        off.Fsrv.setShmPtr(s, null);
    }

    // Close dpipe if valid
    const dpipe = off.Fsrv.getDpipe(s);
    if (dpipe != BADFD) {
        _ = close(dpipe);
        off.Fsrv.setDpipe(s, BADFD);
    }

    const shmpage = off.Fsrv.getShmPtr(s);
    const shmsize = off.Fsrv.getShmShmsize(s);

    if (shmpage) |p| {
        if (munmap(p, shmsize) == -1)
            arcan_warning("BUG -- frameserver_dropshared(), munmap failed\n");
    }

    if (off.Fsrv.getShmHandle(s) != -1)
        _ = close(off.Fsrv.getShmHandle(s));

    off.Fsrv.setShmPtr(s, null);
    return true;
}

// platform_fsrv_destroy

export fn platform_fsrv_destroy(src: ?*ArcanFrameserver) callconv(.c) bool {
    if (is_freestanding) return false;
    const s: *anyopaque = @ptrCast(src orelse return false);

    if (!off.Fsrv.getFlagsAlive(s))
        return false;

    shmif_monitor.emit("fsrv-destroy", @intCast(off.Fsrv.getVid(s)), -1, -1);

    const shmpage = off.Fsrv.getShmPtr(s);

    var tramp: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&tramp)) != 0) {
        // Jump target: fall through to out
    } else {
        platform_fsrv_enter(s, @ptrCast(&tramp));

        if (shmpage) |page| {
            if (!off.Fsrv.getFlagsNoDmsFree(s)) {
                // Push TARGET_COMMAND_EXIT event
                var ev: cabi.arcan_event = undefined; @memset(std.mem.asBytes(&ev), 0);
                ev.unnamed_0.unnamed_0.category = @intCast(EVENT_TARGET);
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_uint, @intCast(TARGET_COMMAND_EXIT)));
                _ = platform_fsrv_pushevent(src, @ptrCast(&ev));
                // Set dms=0 to signal child to exit
                off.Page.setDms(page, 0);
            } else {
                // Reset event queues
                const front = off.Page.childevqFrontPtr(page);
                const back = off.Page.childevqBackPtr(page);
                front.* = back.*;
                const pfront = off.Page.parentevqFrontPtr(page);
                const pback = off.Page.parentevqBackPtr(page);
                pfront.* = pback.*;
                off.Page.setEsync(page, 0xffffffff);
            }

            off.Page.setVready(page, 0);
            off.Page.setAready(page, 0);
            off.Page.setVsync(page, 0xffffffff);
            off.Page.setAsync(page, 0xffffffff);
        }

        platform_fsrv_dropshared(src);
        platform_fsrv_leave();
    }

    // out:
    fsrv_killchild(s);
    off.Fsrv.setChild(s, BROKEN_PROCESS_HANDLE);
    off.Fsrv.setFlagsAlive(s, false);

    // Free possible mixing audio buffer
    arcan_mem_free(@ptrCast(off.Fsrv.getAudb(s)));

    // Mark for debugging
    off.Fsrv.setWatchConst(s, 0xdead);

    // Close dpipe
    const dpipe = off.Fsrv.getDpipe(s);
    if (dpipe != BADFD) {
        _ = shutdown(dpipe, SHUT_RDWR);
        _ = close(dpipe);
        off.Fsrv.setDpipe(s, BADFD);
    }

    arcan_mem_free(@ptrCast(src));
    return true;
}

// platform_fsrv_dropshared

export fn platform_fsrv_dropshared(src: ?*ArcanFrameserver) callconv(.c) void {
    if (is_freestanding) return;
    const s: *anyopaque = @ptrCast(src orelse return);

    const dpipe = off.Fsrv.getDpipe(s);
    if (dpipe != BADFD) {
        _ = shutdown(dpipe, SHUT_RDWR);
        _ = close(dpipe);
        off.Fsrv.setDpipe(s, BADFD);
    }

    const sockaddr = off.Fsrv.getSockaddr(s);
    if (sockaddr != null) {
        _ = unlink(sockaddr);
        arcan_mem_free(@ptrCast(sockaddr));
        off.Fsrv.setSockaddr(s, null);
    }

    const shmpage = off.Fsrv.getShmPtr(s);
    const shmsize = off.Fsrv.getShmShmsize(s);

    if (shmpage) |p| {
        if (munmap(p, shmsize) == -1)
            arcan_warning("BUG -- frameserver_dropshared(), munmap failed\n");
    }

    if (off.Fsrv.getShmHandle(s) != -1)
        _ = close(off.Fsrv.getShmHandle(s));

    off.Fsrv.setShmPtr(s, null);
}

// platform_fsrv_validchild

export fn platform_fsrv_validchild(src: ?*ArcanFrameserver) callconv(.c) bool {
    if (is_freestanding) return false;
    const s: *anyopaque = @ptrCast(src orelse return false);

    if (!off.Fsrv.getFlagsAlive(s))
        return false;

    if (off.Fsrv.getChild(s) == BROKEN_PROCESS_HANDLE) {
        const dp = off.Fsrv.getDpipe(s);
        if (dp > 0) {
            const mask: c_short = POLLERR | POLLHUP | POLLNVAL;
            var fds = [1]PollFd{.{
                .fd = dp,
                .events = mask,
                .revents = 0,
            }};

            if ((poll(&fds, 1, 0) == -1 and get_errno() != EINTR) or
                (fds[0].revents & mask) > 0)
                return false;
        }
        return true;
    }

    set_errno(0);
    var status: c_int = 0;
    const child_pid = off.Fsrv.getChild(s);
    const ec = waitpid(child_pid, &status, WNOHANG);
    const errno_after = get_errno();

    if (ec == child_pid or errno_after == ECHILD) {
        // Pin which way waitpid failed: reaped-child (ec == pid) means
        // someone somewhere thinks the child exited, and status tells us
        // *how* (exited / signalled / stopped / continued). ECHILD means
        // another SIGCHLD handler already reaped it out from under us.
        // Piece 7 of the fd-pass instrumentation: log the triple so we can
        // tell those two very different bugs apart when the "terminals
        // disappear on font-size change" path fires.
        const log_f = fopen("/tmp/arcan_fsrv_free.log", "a");
        if (log_f != null) {
            _ = fprintf(
                log_f,
                "validchild_waitpid_fail: pid=%d ec=%d errno=%d status=0x%x WIFEXITED=%d WIFSIGNALED=%d WIFSTOPPED=%d\n",
                @as(c_int, child_pid),
                @as(c_int, ec),
                @as(c_int, errno_after),
                @as(c_uint, @bitCast(status)),
                @as(c_int, if ((status & 0x7f) == 0) 1 else 0),
                @as(c_int, if (((status & 0x7f) != 0) and ((status & 0x7f) != 0x7f)) 1 else 0),
                @as(c_int, if ((status & 0xff) == 0x7f) 1 else 0),
            );
            _ = fclose(log_f);
        }
        set_errno(EINVAL);
        return false;
    }
    return true;
}

// platform_fsrv_pushfd

export fn platform_fsrv_pushfd(
    fsrv: ?*ArcanFrameserver,
    ev: ?*anyopaque,
    fd: c_int,
) callconv(.c) c_int {
    if (is_freestanding) return 0;
    const f: *anyopaque = @ptrCast(fsrv orelse return ARCAN_ERRC_BAD_ARGUMENT);
    if (fd == BADFD)
        return ARCAN_ERRC_BAD_ARGUMENT;

    // H24 fix: retry on EAGAIN with a short poll-for-writable. Upstream
    // silently drops events on EAGAIN (losing the fd payload); under rapid
    // multi-fsrv fd-passing the send buffer fills and the drop rate is
    // visible both during preroll and during delete. A brief poll-based
    // retry recovers without changing steady-state behaviour.
    const dpipe = off.Fsrv.getDpipe(f);
    // Piece 4 instrumentation: we want to know whether each pushfd is
    // happening during preroll (fsrv not yet activated) or after. Trace one
    // line per call; post-hoc analysis of the log reveals how many fd-sends
    // a single preroll really does.
    {
        const activated: c_int = fsrv_read_activated(f);
        const fd_sends_seen = @atomicRmw(u64, &total_pushfd_calls, .Add, 1, .seq_cst) + 1;
        const log_f = fopen("/tmp/arcan_fsrv_debug.log", "a");
        if (log_f != null) {
            _ = fprintf(
                log_f,
                "pushfd_enter: activated=%d dpipe=%d fd=%d fd_sends_seen=%llu\n",
                activated,
                dpipe,
                fd,
                fd_sends_seen,
            );
            _ = fclose(log_f);
        }
    }
    // Bounded retry on EAGAIN/EWOULDBLOCK only — these are transient
    // SCM_RIGHTS queue-drain pressure and clear within a poll-wait.
    // EACCES is NOT retried: the kernel rejects SCM_RIGHTS for DMA-BUF
    // descriptors deterministically when the receiver lives in a
    // different graphics domain (fossil 7c2828e9bd: the arcan-net
    // helper_cl grandchild has no GPU access, so DMA-BUFs can't be
    // imported).  Retrying just adds ~40 ms of stall before the same
    // EACCES; the real fix lives at the caller — arcan_frameserver_helpers
    // checks the return and toggles rt_hwreadback=false to fall back to
    // SHM transfer for the rendertarget.
    var attempts: u32 = 0;
    var last_errno: c_int = 0;
    while (attempts < 5) : (attempts += 1) {
        if (arcan_pushhandle(fd, dpipe)) {
            _ = platform_fsrv_pushevent(fsrv, ev);
            return ARCAN_OK;
        }
        last_errno = get_errno();
        if (last_errno != EAGAIN and last_errno != EWOULDBLOCK) break;
        var pfd = [_]PollFd{.{
            .fd = dpipe,
            .events = POLLOUT,
            .revents = 0,
        }};
        _ = poll(&pfd, 1, 1);
    }

    // Diagnostic — capture fd identity (the type of fd that failed to
    // pass), helpful for narrowing the EACCES root cause (font fd /
    // memfd / socket / dirfd).  Fires on every non-success exit.
    {
        const log_f = fopen("/tmp/arcan_fsrv_pushfd.log", "a");
        if (log_f != null) {
            var st: StatBuf = undefined;
            const stat_rc = fstat(fd, &st);
            var lname: [128]u8 = undefined;
            var lpath: [64]u8 = undefined;
            _ = snprintf(@ptrCast(&lpath), lpath.len, "/proc/self/fd/%d", fd);
            const lr = readlink(@ptrCast(&lpath), @ptrCast(&lname), lname.len - 1);
            if (lr > 0) lname[@intCast(lr)] = 0 else lname[0] = 0;
            _ = fprintf(log_f,
                "pushhandle_fail: errno=%d fd=%d dpipe=%d attempts=%u stat_rc=%d mode=0%o link=%s\n",
                last_errno, fd, dpipe, attempts, stat_rc,
                if (stat_rc == 0) @as(c_uint, @intCast(st.mode)) else 0,
                @as([*c]const u8, @ptrCast(&lname)));
            _ = fclose(log_f);
        }
    }

    arcan_warning("frameserver_pushfd(%d->%d) failed, reason(%d) : %s\n",
        fd, dpipe, last_errno, strerror(last_errno));

    return ARCAN_ERRC_BAD_ARGUMENT;
}

// platform_fsrv_pushevent

export fn platform_fsrv_pushevent(dst: ?*ArcanFrameserver, ev: ?*anyopaque) callconv(.c) c_int {
    if (is_freestanding) return 0;
    const d: *anyopaque = @ptrCast(dst orelse return ARCAN_ERRC_NO_SUCH_OBJECT);
    const event: *anyopaque = ev orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    // Early-side monitor emit so we see the call even when the event is
    // later filtered (IO mask, OUT_OF_SPACE, etc.).
    {
        const ev_probe: *const cabi.arcan_event = @ptrCast(@alignCast(event));
        const cat_probe: u8 = ev_probe.unnamed_0.unnamed_0.category;
        const kind_probe: c_int = blk: {
            if (cat_probe == @as(u8, @intCast(EVENT_TARGET)))
                break :blk @intCast(ev_probe.unnamed_0.unnamed_0.unnamed_0.tgt.kind);
            if (cat_probe == @as(u8, @intCast(EVENT_EXTERNAL)))
                break :blk @intCast(ev_probe.unnamed_0.unnamed_0.unnamed_0.ext.kind);
            break :blk -1;
        };
        shmif_monitor.emit("out-entry", @intCast(off.Fsrv.getVid(d)), @intCast(cat_probe), kind_probe);
    }

    const outqueue = off.Fsrv.getOutqueuePtr(d);
    const back_ptr = off.Evctx.getBack(outqueue) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    var tramp: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (tramp_guard(d, &tramp))
        return ARCAN_ERRC_UNACCEPTED_STATE;

    if (!off.Fsrv.getFlagsAlive(d) or off.Fsrv.getShmPtr(d) == null) {
        shmif_monitor.emit("out-reject-dead", @intCast(off.Fsrv.getVid(d)), -1, -1);
        platform_fsrv_leave();
        return ARCAN_ERRC_UNACCEPTED_STATE;
    }

    // Check DMS
    const shmptr = off.Fsrv.getShmPtr(d).?;
    if (off.Page.getDms(shmptr) == 0) {
        shmif_monitor.emit("out-reject-dms", @intCast(off.Fsrv.getVid(d)), -1, -1);
        platform_fsrv_leave();
        return ARCAN_ERRC_UNACCEPTED_STATE;
    }

    // Check IO masking
    const ev_ptr: *const cabi.arcan_event = @ptrCast(@alignCast(event));
    const category: u8 = ev_ptr.unnamed_0.unnamed_0.category;
    if (category == @as(u8, @intCast(EVENT_IO))) {
        const devkind: c_uint = @bitCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.io.devkind);
        const datatype: c_uint = @bitCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.io.datatype);
        if ((off.Fsrv.getDevicemask(d) & devkind) != 0 or (off.Fsrv.getDatamask(d) & datatype) != 0) {
            platform_fsrv_leave();
            return ARCAN_OK;
        }
    }

    const evbuf_sz = off.Evctx.getEventbufSz(outqueue);
    const front_ptr = off.Evctx.getFront(outqueue) orelse {
        platform_fsrv_leave();
        return ARCAN_ERRC_NO_SUCH_OBJECT;
    };

    // Outqueue full: match upstream (arcan-upstream/src/platform/posix/frameserver.c:1026-1029)
    // — return OUT_OF_SPACE immediately. The prior 5×1ms retry loop was a
    // bandaid for X autorepeat flood that overloaded the queue; the real
    // fix landed at the XKB layer (DETECTABLE_AUTO_REPEAT in vk_xcb) so
    // the flood never reaches this code path. Retaining the retry hid a
    // legitimate error signal (caller should handle OUT_OF_SPACE) and
    // under extreme pressure tripped our debug assert in the ping path.
    if (((back_ptr.* +% 1) % evbuf_sz) == front_ptr.*) {
        shmif_monitor.emit("out-reject-full", @intCast(off.Fsrv.getVid(d)), -1, -1);
        platform_fsrv_leave();
        return ARCAN_ERRC_OUT_OF_SPACE;
    }

    // Copy event to eventbuf[back]
    const evbuf_base = off.Evctx.getEventbuf(outqueue) orelse {
        platform_fsrv_leave();
        return ARCAN_ERRC_NO_SUCH_OBJECT;
    };
    const event_size = off.Fsrv.sizeof_event;
    const dest: [*]u8 = @as([*]u8, @ptrCast(evbuf_base)) + @as(usize, back_ptr.*) * event_size;
    const back_before: u32 = back_ptr.*;
    _ = memcpy(@ptrCast(dest), event, event_size);

    // === DIAG: dump everything about this push ===
    if (category == @as(u8, @intCast(EVENT_TARGET))) {
        const kind_dump: c_int = @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.tgt.kind);
        const iev0: c_int = @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
        const iev1: c_int = @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv);
        const f_dump = fopen("/tmp/arcan_pushevent_trace.log", "a");
        if (f_dump != null) {
            _ = fprintf(f_dump,
                "PUSH vid=%d kind=%d back=%u iev0=%d iev1=%d\n",
                @as(c_int, @intCast(off.Fsrv.getVid(d))),
                kind_dump, back_before, iev0, iev1);
            _ = fclose(f_dump);
        }
    }

    FORCE_SYNCH();
    const new_back = (back_ptr.* +% 1) % evbuf_sz;
    back_ptr.* = new_back;

    // Plan asserts (eager-noodling-waffle): if the SH backend has
    // miscompiled the *volatile u8 store of back_ptr, the read-back below
    // will not match new_back. This is the cheapest place to catch a
    // store-not-observable miscompile — it doesn't even need the kid to
    // be involved.
    if (builtin.mode == .Debug) {
        // Volatile-store paranoia: check the LOW BYTE of back_ptr's u32
        // matches the LOW BYTE of new_back.  Use @truncate, not @intCast,
        // since new_back routinely exceeds 255 (default evbuf_sz is
        // 1024) — @intCast in Debug panics on out-of-range, which the
        // simple_panic handler renders as a bare "reached unreachable
        // code" with no source line.  Dropped frameserver-destroy events
        // (post-256 events) hit this path and crash the compositor.
        const back_after: u8 = @as(*volatile u8, @ptrCast(back_ptr)).*;
        const expected_low: u8 = @truncate(new_back);
        if (back_after != expected_low) {
            const f_assert = fopen("/tmp/arcan_pushevent_trace.log", "a");
            if (f_assert != null) {
                _ = fprintf(f_assert,
                    "ASSERT-STORE-DROP vid=%d back_ptr=%p wrote=%u read=%u\n",
                    @as(c_int, @intCast(off.Fsrv.getVid(d))),
                    back_ptr,
                    @as(c_uint, new_back),
                    @as(c_uint, back_after));
                _ = fclose(f_assert);
            }
            // [bug 0125] breadcrumb to stderr — when this assert produces a
            // coredump, journalctl _PID=<pid> shows this line and identifies
            // the panic as bug 0125 (volatile-store-readback variant).
            var bcbuf: [256]u8 = undefined;
            const bcmsg = std.fmt.bufPrint(&bcbuf,
                "[bug 0125] pushevent: about to assert(false) — volatile-store readback mismatch vid={d} wrote={d} read={d}. Do NOT soften. Walk back to find who's racing the back_ptr store.\n",
                .{ @as(i32, @intCast(off.Fsrv.getVid(d))), new_back, back_after }) catch "[bug 0125] pushevent: about to assert(false) — volatile-store-drop\n";
            _ = std.posix.write(2, bcmsg) catch {};
            std.debug.assert(false);
        }
    }

    // Env-gated shmif-monitor: record one line per outbound event when
    // ARCAN_SHMIF_MONITOR is set. Single null check in the hot path when
    // the env var isn't set.
    {
        const kind_byte: c_int = blk: {
            if (category == @as(u8, @intCast(EVENT_TARGET)))
                break :blk @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.tgt.kind);
            if (category == @as(u8, @intCast(EVENT_EXTERNAL)))
                break :blk @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.ext.kind);
            break :blk -1;
        };
        shmif_monitor.emit("out", @intCast(off.Fsrv.getVid(d)), @intCast(category), kind_byte);
    }

    // Wake the child via a fire-and-forget SCM_RIGHTS ping on the dpipe.
    // Matches upstream (arcan-upstream/src/platform/posix/frameserver.c:1048).
    // The prior 5×1ms retry loop was a bandaid for the autorepeat-driven
    // kernel send buffer pressure that Layer A (XKB DETECTABLE_AUTO_REPEAT)
    // now eliminates at the source; SO_SNDBUF=4MiB on both sockpair_alloc
    // and the accept()'d connpath socket covers the residual burst. If the
    // ping drops under truly pathological load, the child wakes at the
    // next event-loop tick instead — visible delay is one frame, not a
    // child wedge.
    const dpipe_for_ping = off.Fsrv.getDpipe(d);
    const ping_ok = arcan_pushhandle(-1, dpipe_for_ping);
    shmif_monitor.emit(if (ping_ok) "ping-ok" else "ping-fail",
        @intCast(off.Fsrv.getVid(d)), dpipe_for_ping, -1);

    // Plan asserts (eager-noodling-waffle): if the wake byte didn't
    // actually fire, the kid will never wake from recvmsg. Capture the
    // failure mode (errno + dpipe sndq depth) here. SO_SNDBUF is
    // already 4 MiB via socketpoll, so a sndq-full report would mean
    // the kernel never drained earlier wakes — distinct signal from
    // the SH-store-miscompile case caught above.
    if (builtin.mode == .Debug and !ping_ok) {
        const errno_now: c_int = std.c._errno().*;
        var sndq: c_int = 0;
        // TIOCOUTQ = 0x5411 on Linux; harmless on other platforms (returns -1)
        _ = ioctl(dpipe_for_ping, 0x5411, &sndq);
        const f_assert = fopen("/tmp/arcan_pushevent_trace.log", "a");
        if (f_assert != null) {
            _ = fprintf(f_assert,
                "ASSERT-PING-FAIL vid=%d kid_pid=%d dpipe=%d errno=%d sndq=%d\n",
                @as(c_int, @intCast(off.Fsrv.getVid(d))),
                off.Fsrv.getChild(d),
                dpipe_for_ping, errno_now, sndq);
            _ = fclose(f_assert);
        }
        // bug 0019: EPIPE (errno 32) is the normal kid-already-exited
        // signal — don't kill the compositor for it. ENOTCONN (107) and
        // ECONNRESET (104) are the same semantic for unix sockets where
        // the peer dropped the connection abnormally — observed via
        // arcan-net bridges on 2026-05-02 when the bridge child died
        // (SIGSEGV from bug 0130 / clean exit from bug 0131) and arcan
        // tried to push an event to the orphaned shmif segment. All
        // three are "peer's gone" and the right behaviour is to let the
        // fsrv-lifecycle teardown handle it on the next tick, not to
        // SIGABRT the compositor and lose the user's session.
        //
        // Other errnos (EAGAIN, EINVAL, EBADF, ...) stay assert-fatal —
        // the SH-miscompile wake-byte-drop diagnostic still needs to
        // catch a genuine drop, and EBADF specifically indicates the
        // dpipe was closed while the fsrv slot is still considered
        // alive (a real fsrv-lifecycle invariant violation upstream
        // that the assert is supposed to surface).
        const peer_gone = errno_now == 32 // EPIPE (same on Darwin)
            or (if (comptime @import("builtin").os.tag.isDarwin())
                (errno_now == 54 or errno_now == 57) // Darwin ECONNRESET/ENOTCONN
            else
                (errno_now == 104 or errno_now == 107)) // Linux ECONNRESET/ENOTCONN
            or errno_now == 13; // EACCES — observed 2026-05-03 in bridge
        // failure path: a remote afsrv that connected over arcan-net then
        // had its TCP torn down asymmetrically left the local dpipe in a
        // state where the next pushevent ping returned EACCES instead of
        // EPIPE. Same semantic ("peer is gone, this fd is not usable")
        // and SIGABRT'ing the compositor over it loses the entire
        // session for what is just a stale bridge segment.
        if (!peer_gone) {
            // [bug 0125] breadcrumb to stderr — journal alongside the
            // coredump shows this line and identifies the panic as bug
            // 0125 (ping-fail variant). Do NOT soften beyond peer_gone —
            // find the upstream fsrv-lifecycle bug that closed dpipe early.
            var bcbuf: [256]u8 = undefined;
            const bcmsg = std.fmt.bufPrint(&bcbuf,
                "[bug 0125] pushevent: about to assert(false) — ping failed vid={d} dpipe={d} errno={d} sndq={d}. Do NOT soften.\n",
                .{ @as(i32, @intCast(off.Fsrv.getVid(d))), dpipe_for_ping, errno_now, sndq }) catch "[bug 0125] pushevent: about to assert(false) — ping-fail\n";
            _ = std.posix.write(2, bcmsg) catch {};
            std.debug.assert(false);
        }
    }

    if (category == @as(u8, @intCast(EVENT_TARGET))) {
        const kind_val: c_uint = @intCast(ev_ptr.unnamed_0.unnamed_0.unnamed_0.tgt.kind);
        if (kind_val == 2 or kind_val == 11 or kind_val == 24) {
            const f = fopen("/tmp/arcan_pushevent_trace.log", "a");
            if (f != null) {
                // Plan: include kid_pid + ping_ok so we can grep the kid
                // log by pid and confirm the wake hit the right socket.
                _ = fprintf(f,
                    "pushevent: ping fired for kind=%u dpipe=%d kid_pid=%d ping_ok=%d\n",
                    kind_val, off.Fsrv.getDpipe(d),
                    off.Fsrv.getChild(d),
                    @as(c_int, @intFromBool(ping_ok)));
                _ = fclose(f);
            }
        }
    }
    platform_fsrv_leave();
    return ARCAN_OK;
}

// platform_fsrv_socketauth

export fn platform_fsrv_socketauth(tgt: ?*ArcanFrameserver) callconv(.c) c_int {
    if (is_freestanding) return 0;
    const t: *anyopaque = @ptrCast(tgt orelse return -1);

    if (!arcan_pushhandle(off.Fsrv.getShmHandle(t), off.Fsrv.getDpipe(t))) {
        arcan_warning("couldn't send shared memory handle over socket");
        set_errno(EBADF);
        return -1;
    }

    return 0;
}

// platform_fsrv_socketpoll

export fn platform_fsrv_socketpoll(tgt: ?*ArcanFrameserver) callconv(.c) c_int {
    if (is_freestanding) return 0;
    const t: *anyopaque = @ptrCast(tgt orelse return -1);

    var term: bool = false;
    if (!fd_avail(off.Fsrv.getDpipe(t), &term)) {
        if (term) {
            set_errno(EBADF);
            return -1;
        }
        set_errno(EAGAIN);
        return -1;
    }

    const dpipe = off.Fsrv.getDpipe(t);
    const newfd = accept(dpipe, null, null);
    if (newfd == -1) {
        set_errno(EAGAIN);
        return -1;
    }

    const flags = fcntl(dpipe, F_GETFL);
    _ = fcntl(newfd, F_SETFL, flags | O_NONBLOCK);

    // The accept()'d fd does NOT inherit SO_SNDBUF/SO_RCVBUF from the
    // listening socket — it comes back with the kernel-default ~208 KiB.
    // Every subsequent pushfd/ping on this channel was fighting a quarter-
    // megabyte queue instead of the 4 MiB sockpair_alloc already sizes.
    // Without this the downstream EAGAIN retry loops were the only thing
    // keeping ARCAN_CONNPATH clients alive during multi-fsrv bursts, and
    // the 5×1ms budget exhausted on real workloads (see wake-ping assert).
    const big_buf: c_int = 4 * 1024 * 1024;
    _ = setsockopt(newfd, SOL_SOCKET, SO_RCVBUF, @ptrCast(&big_buf), @sizeOf(c_int));
    _ = setsockopt(newfd, SOL_SOCKET, SO_SNDBUF, @ptrCast(&big_buf), @sizeOf(c_int));
    var got_snd: c_int = 0;
    var optlen: c_uint = @sizeOf(c_int);
    _ = getsockopt(newfd, SOL_SOCKET, SO_SNDBUF, @ptrCast(&got_snd), &optlen);
    arcan_warning(
        "socketpoll accept: fd=%d requested=%d got_snd=%d\n",
        @as(c_int, newfd),
        @as(c_int, big_buf),
        @as(c_int, got_snd),
    );
    if (builtin.mode == .Debug) {
        std.debug.assert(got_snd >= 1_000_000);
    }

    const sockaddr = off.Fsrv.getSockaddr(t);
    free(@ptrCast(sockaddr));
    off.Fsrv.setSockaddr(t, null);
    off.Fsrv.setDpipe(t, newfd);
    return dpipe; // return old fd
}

// platform_fsrv_spawn_subsegment

export fn platform_fsrv_spawn_subsegment(
    ctx: ?*ArcanFrameserver,
    segid_in: c_int,
    hints: c_int,
    hintw_in: usize,
    hinth_in: usize,
    tag: usize,
    reqid: u32,
) callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    const c: *anyopaque = @ptrCast(ctx orelse return null);

    if (!off.Fsrv.getFlagsAlive(c))
        return null;

    const hintw = if (hintw_in == 0 or hintw_in > @as(usize, @intCast(cabi.ARCAN_SHMPAGE_MAXW))) @as(usize, 32) else hintw_in;
    const hinth = if (hinth_in == 0 or hinth_in > @as(usize, @intCast(cabi.ARCAN_SHMPAGE_MAXH))) @as(usize, 32) else hinth_in;

    const forced_bit: bool = (segid_in & @as(c_int, @bitCast(@as(u32, 1) << 31))) != 0;
    const segid: c_int = segid_in & ~@as(c_int, @bitCast(@as(u32, 1) << 31));

    const newseg = platform_fsrv_alloc() orelse return null;
    const ns: *anyopaque = @ptrCast(newseg);

    if (!prepare_segment(ns, segid, hints, hintw, hinth, false, null, -1, tag)) {
        arcan_mem_free(@ptrCast(newseg));
        return null;
    }

    // Minor parent relationship tracking
    const source = off.Fsrv.getSource(c);
    if (source != null) {
        off.Fsrv.setSource(ns, strdup(source));
    }

    off.Fsrv.setParentVid(ns, off.Fsrv.getVid(c));
    off.Fsrv.setParentPtr(ns, c);
    off.Fsrv.setVid(ns, @intCast(tag));

    // Monitor same PID as parent
    off.Fsrv.setChild(ns, off.Fsrv.getChild(c));

    // Set rz_flag so 'resized' event goes through
    off.Fsrv.setDescRzFlag(ns, true);

    // Socket pair for descriptor transfer
    var sockp = [2]c_int{ -1, -1 };
    if (!sockpair_alloc(&sockp, 1, true)) {
        _ = platform_fsrv_destroy(newseg);
        return null;
    }

    off.Fsrv.setDpipe(ns, sockp[0]);

    // Send fds to parent context
    var fds_to_send = [2]c_int{ sockp[1], off.Fsrv.getShmHandle(ns) };
    _ = arcan_send_fds(off.Fsrv.getDpipe(c), &fds_to_send, 2);
    _ = close(sockp[1]);

    // Build NEWSEGMENT event
    var keyev: cabi.arcan_event = undefined; @memset(std.mem.asBytes(&keyev), 0);
    keyev.unnamed_0.unnamed_0.category = @intCast(EVENT_TARGET);
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @bitCast(@as(c_uint, @intCast(TARGET_COMMAND_NEWSEGMENT)));
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[1].iv = if (segid == SEGID_ENCODER) @as(i32, 1) else @as(i32, 0);
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = segid;
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @bitCast(reqid);
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].uiv = off.Fsrv.getCookie(ns);
    keyev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].iv = if (forced_bit) @as(i32, 1) else @as(i32, 0);

    // Manually queue into ctx's outqueue (TRAMP_GUARD)
    var tramp: [JMPBUF_SIZE]u8 align(16) = undefined;
    if (tramp_guard(c, &tramp))
        return null;

    const evctx = off.Fsrv.getOutqueuePtr(c);
    const back_ptr = off.Evctx.getBack(evctx) orelse {
        platform_fsrv_leave();
        return null;
    };
    const front_ptr = off.Evctx.getFront(evctx) orelse {
        platform_fsrv_leave();
        return null;
    };
    const evbuf_sz = off.Evctx.getEventbufSz(evctx);

    if (((back_ptr.* +% 1) % evbuf_sz) == front_ptr.*) {
        platform_fsrv_leave();
        return null;
    }

    const evbuf_base = off.Evctx.getEventbuf(evctx) orelse {
        platform_fsrv_leave();
        return null;
    };
    const event_size = off.Fsrv.sizeof_event;
    const dest: [*]u8 = @as([*]u8, @ptrCast(evbuf_base)) + @as(usize, back_ptr.*) * event_size;
    _ = memcpy(@ptrCast(dest), @ptrCast(&keyev), event_size);

    FORCE_SYNCH();
    back_ptr.* = (back_ptr.* +% 1) % evbuf_sz;
    platform_fsrv_leave();

    // HANDOVER: detach parent
    if (segid == SEGID_HANDOVER) {
        off.Fsrv.setSegid(ns, SEGID_UNKNOWN);
        off.Fsrv.setParentPtr(ns, null);
        off.Fsrv.setParentVid(ns, ARCAN_EID);
    }

    return newseg;
}

// platform_fsrv_default_abufsize

export fn platform_fsrv_default_abufsize(new_sz: usize) callconv(.c) usize {
    if (is_freestanding) return 0;
    const res = default_abuf_sz;
    if (new_sz > 0)
        default_abuf_sz = new_sz;
    return res;
}

// platform_fsrv_display_limit

export fn platform_fsrv_display_limit(new_sz: usize) callconv(.c) usize {
    if (is_freestanding) return 0;
    const res = default_disp_lim;
    if (new_sz > 0)
        default_disp_lim = new_sz;
    return res;
}

// platform_fsrv_resynch

export fn platform_fsrv_resynch(s_in: ?*ArcanFrameserver) callconv(.c) c_int {
    if (is_freestanding) return 0;
    const s: *anyopaque = @ptrCast(s_in orelse return -1);
    var state: c_int = 0;
    const shmpage = off.Fsrv.getShmPtr(s) orelse return -1;

    // Local copy (avoid TOCTOU)
    const w: usize = off.Page.getW(shmpage);
    const h: usize = off.Page.getH(shmpage);
    var abufsz: usize = off.Page.getAbufsize(shmpage);
    var vbufc: usize = off.Page.getVpending(shmpage);
    var abufc: usize = off.Page.getApending(shmpage);
    const samplerate: usize = off.Page.getAudiorate(shmpage);
    const rows: usize = off.Page.getRows(shmpage);
    const cols: usize = off.Page.getCols(shmpage);
    const aproto: c_uint = off.Page.getApadType(shmpage) & off.Fsrv.getMetamask(s);

    if (vbufc > FSRV_MAX_VBUFC) vbufc = FSRV_MAX_VBUFC;
    if (abufc > FSRV_MAX_ABUFC) abufc = FSRV_MAX_ABUFC;
    if (vbufc == 0) vbufc = 1;

    // Determine sub-protocol size
    var apend: [SIZEOF_SHMIF_OFSTBL]u8 = [_]u8{0} ** SIZEOF_SHMIF_OFSTBL;
    const apad_sz = fsrv_protosize(s, aproto, &apend);
    const reset_proto = (off.Fsrv.getDescAproto(s) != aproto);

    if (abufsz < default_abuf_sz)
        abufsz = default_abuf_sz;

    if (samplerate != 0)
        off.Fsrv.setDescSamplerate(s, @intCast(samplerate));

    // Shrink vbufc if needed
    var shmsz: usize = undefined;
    while (true) {
        shmsz = shmpage_size(w, h, vbufc, abufc, abufsz, apad_sz);
        if (shmsz <= @as(usize, @intCast(cabi.ARCAN_SHMPAGE_MAX_SZ)) or vbufc <= 1) break;
        vbufc -= 1;
    }

    // Sanity check
    if (shmsz > @as(usize, @intCast(cabi.ARCAN_SHMPAGE_MAX_SZ)) or
        (off.Fsrv.getMaxW(s) != 0 and w > off.Fsrv.getMaxW(s)) or
        (off.Fsrv.getMaxH(s) != 0 and h > off.Fsrv.getMaxH(s)))
    {
        // fail path
        off.Page.setAbufsize(shmpage, @intCast(abufsz));
        off.Page.setApending(shmpage, @intCast(off.Fsrv.getAbufCnt(s)));
        off.Page.setVpending(shmpage, @intCast(off.Fsrv.getVbufCnt(s)));
        off.Page.setW(shmpage, @intCast(off.Fsrv.getDescWidth(s)));
        off.Page.setH(shmpage, @intCast(off.Fsrv.getDescHeight(s)));
        off.Page.setCols(shmpage, @intCast(off.Fsrv.getDescCols(s)));
        off.Page.setRows(shmpage, @intCast(off.Fsrv.getDescRows(s)));
        off.Page.setResized(shmpage, @as(i8, -1));
        FORCE_SYNCH();
        off.Page.setVsync(shmpage, 0);
        off.Page.setAsync(shmpage, 0);
        return -1;
    }

    const src_shmsize = off.Fsrv.getShmShmsize(s);

    // Check if remap needed
    const rmap = (shmsz > src_shmsize or @as(f64, @floatFromInt(shmsz)) < @as(f64, @floatFromInt(src_shmsize)) * 0.8);

    if (rmap) {
        {
            var sb: StatBuf = undefined;
            const fd = off.Fsrv.getShmHandle(s);
            const stat_rc = fstat(fd, &sb);
            const f = fopen("/tmp/arcan_shm_trace.log", "a");
            if (f != null) {
                _ = fprintf(f, "pre-mremap fstat: fd=%d rc=%d ino=%llu size=%llu old_addr=%p\n",
                    fd, stat_rc,
                    @as(c_ulonglong, @intCast(if (stat_rc == 0) sb.ino else 0)),
                    @as(c_ulonglong, @intCast(if (stat_rc == 0) sb.size else 0)),
                    off.Fsrv.getShmPtr(s));
                _ = fclose(f);
            }
        }
        if (ftruncate(off.Fsrv.getShmHandle(s), @intCast(shmsz)) == -1) {
            arcan_warning("truncate failed during resize operation\n");
            // fail path
            off.Page.setAbufsize(shmpage, @intCast(abufsz));
            off.Page.setApending(shmpage, @intCast(off.Fsrv.getAbufCnt(s)));
            off.Page.setVpending(shmpage, @intCast(off.Fsrv.getVbufCnt(s)));
            off.Page.setW(shmpage, @intCast(off.Fsrv.getDescWidth(s)));
            off.Page.setH(shmpage, @intCast(off.Fsrv.getDescHeight(s)));
            off.Page.setCols(shmpage, @intCast(off.Fsrv.getDescCols(s)));
            off.Page.setRows(shmpage, @intCast(off.Fsrv.getDescRows(s)));
            off.Page.setResized(shmpage, @as(i8, -1));
            FORCE_SYNCH();
            off.Page.setVsync(shmpage, 0);
            off.Page.setAsync(shmpage, 0);
            return -1;
        }

        // Use mremap on Linux (_GNU_SOURCE); Darwin has no mremap — map the
        // resized fd at a fresh address first, then drop the old mapping
        // (order matters: the -1/fail path below still writes via shmpage).
        const newp = blk: {
            if (comptime builtin.os.tag.isDarwin()) {
                const np = mmap(null, shmsz, PROT_READ | PROT_WRITE, MAP_SHARED,
                    off.Fsrv.getShmHandle(s), 0);
                if (@intFromPtr(np) != MAP_FAILED and np != null)
                    _ = munmap(shmpage, src_shmsize);
                break :blk np;
            }
            break :blk mremap(shmpage, src_shmsize, shmsz, MREMAP_MAYMOVE);
        };
        if (@intFromPtr(newp) == MAP_FAILED or newp == null) {
            if (ftruncate(off.Fsrv.getShmHandle(s), @intCast(src_shmsize)) == -1)
                arcan_warning("_resize, truncate reset on resize fail fail\n");
            // fail path
            off.Page.setAbufsize(shmpage, @intCast(abufsz));
            off.Page.setApending(shmpage, @intCast(off.Fsrv.getAbufCnt(s)));
            off.Page.setVpending(shmpage, @intCast(off.Fsrv.getVbufCnt(s)));
            off.Page.setW(shmpage, @intCast(off.Fsrv.getDescWidth(s)));
            off.Page.setH(shmpage, @intCast(off.Fsrv.getDescHeight(s)));
            off.Page.setCols(shmpage, @intCast(off.Fsrv.getDescCols(s)));
            off.Page.setRows(shmpage, @intCast(off.Fsrv.getDescRows(s)));
            off.Page.setResized(shmpage, @as(i8, -1));
            FORCE_SYNCH();
            off.Page.setVsync(shmpage, 0);
            off.Page.setAsync(shmpage, 0);
            return -1;
        }
        off.Fsrv.setShmPtr(s, newp);
        {
            var sb: StatBuf = undefined;
            const fd = off.Fsrv.getShmHandle(s);
            const stat_rc = fstat(fd, &sb);
            // Read a few bytes from the new mapping to verify it's readable
            const cookie_ptr = @as(*volatile u32, @ptrCast(@alignCast(@as([*]u8, @ptrCast(newp.?)) + 64)));
            const read_via_mmap = cookie_ptr.*;
            const f = fopen("/tmp/arcan_shm_trace.log", "a");
            if (f != null) {
                _ = fprintf(f, "post-mremap: new_addr=%p shmfd=%d ino=%llu size=%llu cookie_via_mmap=0x%x\n",
                    newp, fd,
                    @as(c_ulonglong, @intCast(if (stat_rc == 0) sb.ino else 0)),
                    @as(c_ulonglong, @intCast(if (stat_rc == 0) sb.size else 0)),
                    read_via_mmap);
                _ = fclose(f);
            }
        }
    }

    const new_shmpage = off.Fsrv.getShmPtr(s).?;
    off.Fsrv.setShmShmsize(s, shmsz);

    // Commit to local tracking
    off.Page.setW(new_shmpage, @intCast(w));
    off.Page.setH(new_shmpage, @intCast(h));
    off.Page.setRows(new_shmpage, @intCast(rows));
    off.Page.setCols(new_shmpage, @intCast(cols));

    off.Fsrv.setDescWidth(s, @intCast(w));
    off.Fsrv.setDescHeight(s, @intCast(h));
    off.Fsrv.setDescRows(s, rows);
    off.Fsrv.setDescCols(s, cols);
    off.Fsrv.setDescPendingHints(s, @intCast(off.Page.getHints(new_shmpage)));
    off.Fsrv.setVbufCnt(s, vbufc);
    off.Fsrv.setAbufCnt(s, abufc);

    // DRM auth: authenticate GPU token if SHMIF_RHINT_AUTH_TOK is set.
    // In C this was behind #ifdef PLATFORM_VIDEO_DRMAUTH; we include it
    // unconditionally since platform_video_auth is always linked.
    if (drmauth_enabled) {
        var hints_val: c_uint = @intCast(off.Fsrv.getDescPendingHints(s));
        if ((hints_val & @as(c_uint, @intCast(SHMIF_RHINT_AUTH_TOK))) != 0) {
            const token: c_uint = @intCast(off.Page.getVpts(new_shmpage));
            hints_val &= ~@as(c_uint, @intCast(SHMIF_RHINT_AUTH_TOK));
            off.Fsrv.setDescPendingHints(s, @intCast(hints_val));
            off.Page.setHints(new_shmpage, @intCast(hints_val));

            if (!off.Fsrv.getFlagsGpuAuth(s) or !platform_video_auth(0, token)) {
                // fail path (use new_shmpage since remap may have occurred)
                off.Page.setAbufsize(new_shmpage, @intCast(abufsz));
                off.Page.setApending(new_shmpage, @intCast(off.Fsrv.getAbufCnt(s)));
                off.Page.setVpending(new_shmpage, @intCast(off.Fsrv.getVbufCnt(s)));
                off.Page.setW(new_shmpage, @intCast(off.Fsrv.getDescWidth(s)));
                off.Page.setH(new_shmpage, @intCast(off.Fsrv.getDescHeight(s)));
                off.Page.setCols(new_shmpage, @intCast(off.Fsrv.getDescCols(s)));
                off.Page.setRows(new_shmpage, @intCast(off.Fsrv.getDescRows(s)));
                off.Page.setResized(new_shmpage, @as(i8, -1));
                FORCE_SYNCH();
                off.Page.setVsync(new_shmpage, 0);
                off.Page.setAsync(new_shmpage, 0);
                return -1;
            }
        }
    }

    // Compute vbufsz
    const vbufsz = arcan_shmif_vbufsz(
        @intCast(aproto),
        @intCast(off.Fsrv.getDescPendingHints(s)),
        w,
        h,
        off.Fsrv.getDescRows(s),
        off.Fsrv.getDescCols(s),
    );

    // Update apad on shared page, then remap pointers
    off.Page.setApad(new_shmpage, @intCast(apad_sz));

    const vbufs = off.Fsrv.getVbufsPtr(s);
    const abufs = off.Fsrv.getAbufsPtr(s);
    const new_seg_size = arcan_shmif_mapav(
        new_shmpage,
        vbufs,
        vbufc,
        vbufsz,
        abufs,
        abufc,
        abufsz,
    );
    off.Page.setSegmentSize(new_shmpage, @intCast(new_seg_size));

    off.Fsrv.setAbufSz(s, abufsz);

    const inqueue = off.Fsrv.getInqueuePtr(s);
    const outqueue = off.Fsrv.getOutqueuePtr(s);
    {
        const f = fopen("/tmp/arcan_shm_trace.log", "a");
        if (f != null) {
            _ = fprintf(f, "platform_fsrv_resize: about to setevqs new_shmpage=%p fsrv=%p shmhandle=%d shmsize=%zu rmap=%d\n",
                new_shmpage, s, off.Fsrv.getShmHandle(s), shmsz, @as(c_int, if (rmap) 1 else 0));
            _ = fclose(f);
        }
    }
    fsrv_setevqs(new_shmpage, inqueue, outqueue);

    // Commit to shared page
    off.Page.setResized(new_shmpage, 0);
    off.Page.setAbufsize(new_shmpage, @intCast(abufsz));
    off.Page.setApending(new_shmpage, @intCast(abufc));
    off.Page.setVpending(new_shmpage, @intCast(vbufc));

    // Realize sub-protocol
    if (reset_proto) {
        fsrv_setproto(s, aproto, &apend);
        off.Page.setApadType(new_shmpage, aproto);
        state = 2;
    } else {
        state = 1;
    }

    // Allocate compositor-side DMA-BUF for zero-copy vidp.
    // The client will receive the fd via DEVICE_NODE event and mmap it as vidp.
    //
    // MAY-110 crash hardening (st 2026-05-15): the dmabuf path crashes
    // inside vk_gbm_alloc → gbmInitDevice → zig_foreign_begin (the
    // cosmopolitan-style host-libgbm shim). Root cause likely a stale
    // ld-linux foreign-call state or libgbm dlopen state that isn't
    // surviving the engine's frameserver-spawn path. Until that's
    // diagnosed, force the shmif-pixel fallback: it's slower (CPU
    // copies the frame from the client shmpage into the compositor
    // surface) but doesn't hit the broken path. Tracked separately
    // from MAY-110 closure as a follow-up.
    //
    // To re-enable once the dlopen issue is fixed, restore the call:
    //     const W_MAX: usize = std.math.maxInt(u32);
    //     if (w > 0 and h > 0 and w <= W_MAX and h <= W_MAX) {
    //         dmabuf_vidp_realloc(s, @intCast(w), @intCast(h));
    //     }

    // done:
    FORCE_SYNCH();
    off.Page.setVsync(new_shmpage, 0);
    off.Page.setAsync(new_shmpage, 0);
    return state;
}

// platform_fsrv_listen_external

export fn platform_fsrv_listen_external(
    key: [*c]const u8,
    auth: [*c]const u8,
    fd: c_int,
    mode: u32,
    w: usize,
    h: usize,
    tag: usize,
) callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    _ = auth;
    const newseg = platform_fsrv_alloc() orelse return null;
    const ns: *anyopaque = @ptrCast(newseg);
    off.Fsrv.setSockmode(ns, mode);
    if (!prepare_segment(ns, SEGID_UNKNOWN, 0, w, h, true, key, fd, tag)) {
        arcan_mem_free(@ptrCast(newseg));
        return null;
    }
    return newseg;
}

// platform_fsrv_preset_server

export fn platform_fsrv_preset_server(
    sockin: c_int,
    memin: c_int,
    segid: c_int,
    w: usize,
    h: usize,
    tag: usize,
) callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    const newseg = platform_fsrv_alloc() orelse return null;
    const ns: *anyopaque = @ptrCast(newseg);

    if (memin == -1) {
        if (!prepare_segment(ns, segid, 0, w, h, false, null, -1, tag)) {
            arcan_mem_free(@ptrCast(newseg));
            return null;
        }
    } else {
        // Pre-allocated segment: trust contents
        // fstat to get size -- use the segid fd (matches the C code: fstat(segid, &inf))
        var sbuf: StatBuf = undefined;
        if (stat_fstat(segid, &sbuf) == 0) {
            off.Fsrv.setShmShmsize(ns, stat_get_size(&sbuf));
        }

        if (!fill_shmpage(ns, memin)) {
            arcan_mem_free(@ptrCast(newseg));
            return null;
        }
    }

    off.Fsrv.setDpipe(ns, sockin);
    return newseg;
}

// fstat wrapper
extern fn fstat(fd: c_int, buf: *StatBuf) c_int;

fn stat_fstat(fd: c_int, buf: *StatBuf) c_int {
    return fstat(fd, buf);
}

fn stat_get_size(buf: *const StatBuf) usize {
    return @intCast(buf.size);
}

// platform_fsrv_spawn_server

export fn platform_fsrv_spawn_server(
    segid: c_int,
    w: usize,
    h: usize,
    tag: usize,
    childfd: *c_int,
) callconv(.c) ?*ArcanFrameserver {
    if (is_freestanding) return null;
    const newseg = platform_fsrv_alloc() orelse return null;
    const ns: *anyopaque = @ptrCast(newseg);

    if (!prepare_segment(ns, segid, 0, w, h, false, null, -1, tag)) {
        arcan_mem_free(@ptrCast(newseg));
        return null;
    }

    var sockp = [2]c_int{ -1, -1 };
    if (!sockpair_alloc(&sockp, 1, true)) {
        _ = platform_fsrv_destroy(newseg);
        return null;
    }

    off.Fsrv.setDpipe(ns, sockp[0]);
    childfd.* = sockp[1];

    return newseg;
}

