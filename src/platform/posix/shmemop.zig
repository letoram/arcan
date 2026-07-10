// Zig port of posix/shmemop.c
// Shared memory operations: memfd creation, video buffer size calculation, and
// audio/video buffer mapping within an arcan_shmif_page.

const std = @import("std");
const builtin = @import("builtin");
const off = @import("shmif_offsets");

// POSIX shared-memory entry points (used on non-Linux, which lacks memfd_create).
extern "c" fn shm_open(name: [*:0]const u8, oflag: c_int, mode: c_uint) c_int;
extern "c" fn shm_unlink(name: [*:0]const u8) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn getpid() c_int;
var shm_seq: u32 = 0;

// raster constants (from src/shmif/tui/raster/raster_const.h)
const raster_cell_sz: usize = 12;
const raster_hdr_sz: usize = 16;
const raster_line_sz: usize = 9;
const raster_hdr_pad: usize = 32;

// shmif constants
const SHMIF_RHINT_TPACK: u8 = 128;
const ARCAN_SHMPAGE_ALIGN: usize = 64;

// types
const shmif_pixel = u32;
const shmif_asample = i16;

/// Align a byte pointer up to the given alignment boundary.
inline fn alignv(inptr: [*]u8, align_sz: usize) [*]u8 {
    const addr = @intFromPtr(inptr);
    if (addr % align_sz != 0) {
        return inptr + align_sz - (addr % align_sz);
    }
    return inptr;
}

/// Create an anonymous shared memory file descriptor. Linux uses
/// memfd_create; other OSes (macOS/BSD) have no such syscall, so create a
/// uniquely-named POSIX shm object and shm_unlink it immediately — the fd
/// stays valid and inherits across fork, exactly like a memfd. CLOEXEC is
/// set to match memfd's MFD_CLOEXEC (the frameserver spawn dups it without
/// CLOEXEC to hand to the child).
export fn platform_fsrv_shmmem() callconv(.c) c_int {
    if (comptime builtin.os.tag == .linux) {
        const MFD_CLOEXEC: u32 = 1;
        const rc = std.os.linux.memfd_create("arcan_shmif", MFD_CLOEXEC);
        // memfd_create syscall returns usize; convert error to -1 for C ABI
        if (@as(isize, @bitCast(rc)) < 0) {
            return -1;
        }
        return @intCast(rc);
    }
    if (comptime builtin.os.tag == .windows) {
        // TODO(windows substrate): CreateFileMapping-backed anonymous shm.
        // Stub for now so the windows build links; frameserver shm alloc
        // fails gracefully (-1) until the win32 substrate lands.
        return -1;
    }
    // macOS/BSD POSIX-shm path. O_RDWR|O_CREAT|O_EXCL with BSD-family flag
    // values (this branch never compiles on Linux/Windows).
    const O_RDWR: c_int = 2;
    const O_CREAT: c_int = 0x200;
    const O_EXCL: c_int = 0x800;
    const F_SETFD: c_int = 2;
    const FD_CLOEXEC: c_int = 1;
    var attempt: u32 = 0;
    while (attempt < 64) : (attempt += 1) {
        shm_seq +%= 1;
        var namebuf: [64]u8 = undefined;
        // shm names are short (< ~31 on darwin) and must start with '/'.
        const name = std.fmt.bufPrintZ(&namebuf, "/arcan_shmif_{d}_{d}", .{ getpid(), shm_seq }) catch return -1;
        const fd = shm_open(name.ptr, O_RDWR | O_CREAT | O_EXCL, @as(c_uint, 0o600));
        if (fd >= 0) {
            _ = shm_unlink(name.ptr);
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC);
            return fd;
        }
    }
    return -1;
}

/// Compute the video buffer size for a given resolution / tpack layout.
export fn arcan_shmif_vbufsz(
    meta: c_int,
    hints: u8,
    w: usize,
    h: usize,
    rows: usize,
    cols: usize,
) callconv(.c) usize {
    _ = meta;
    if ((hints & SHMIF_RHINT_TPACK) != 0 and rows != 0 and cols != 0) {
        return raster_hdr_sz + (rows * cols + 2) * raster_cell_sz +
            (rows + 2) * raster_line_sz + raster_hdr_pad;
    }
    return w * h * @sizeOf(shmif_pixel);
}

/// Map audio and video buffers within the shared memory page.
/// Returns the total byte offset from `addr` to the end of the last mapped buffer.
export fn arcan_shmif_mapav(
    addr: ?*anyopaque,
    vbuf: ?[*]?[*]shmif_pixel,
    vbufc: usize,
    vbuf_sz: usize,
    abuf: ?[*]?[*]shmif_asample,
    abufc: usize,
    abuf_sz: usize,
) callconv(.c) usize {
    const base: [*]u8 = @ptrCast(addr orelse return 0);
    var wbuf: [*]u8 = base + off.Page.sizeof_page;

    if (addr != null and vbuf != null) {
        wbuf += off.Page.getApad(@ptrCast(addr.?));
    }

    // Map audio buffers
    for (0..abufc) |i| {
        wbuf = alignv(wbuf, ARCAN_SHMPAGE_ALIGN);
        if (abuf) |ab| {
            ab[i] = if (abuf_sz != 0) @ptrCast(@alignCast(wbuf)) else null;
        }
        wbuf += abuf_sz;
    }

    // Map video buffers
    for (0..vbufc) |i| {
        wbuf = alignv(wbuf, ARCAN_SHMPAGE_ALIGN);
        if (vbuf) |vb| {
            vb[i] = if (vbuf_sz != 0)
                @ptrCast(@alignCast(alignv(wbuf, ARCAN_SHMPAGE_ALIGN)))
            else
                null;
        }
        wbuf += vbuf_sz;
    }

    return @intFromPtr(wbuf) - @intFromPtr(addr);
}
