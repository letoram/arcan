// SHL - Ring buffer
//
// Copyright (c) 2011-2014 David Herrmann <dh.herrmann@gmail.com>
// Dedicated to the Public Domain
//
// Zig port of shl-ring.c

const std = @import("std");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const free = libc.free;
    pub const malloc = libc.malloc;
    pub const memcpy = libc.memcpy;
    pub const memset = libc.memset;
    pub const ENOMEM = libc.ENOMEM;
    pub const struct_iovec = libc.struct_iovec;
};

const shl_ring = extern struct {
    buf: ?[*]u8,
    size: usize,
    start: usize,
    used: usize,
};

inline fn RING_MASK(r: *shl_ring, v: usize) usize {
    return v & (r.size - 1);
}

export fn shl_ring_flush(r: *shl_ring) void {
    r.start = 0;
    r.used = 0;
}

export fn shl_ring_clear(r: *shl_ring) void {
    if (r.buf) |buf| {
        c.free(buf);
    }
    const ptr: [*]u8 = @ptrCast(@alignCast(r));
    _ = c.memset(ptr, 0, @sizeOf(shl_ring));
}

// Get data pointers for current ring-buffer data. @vec must be an array of 2
// iovec objects. They are filled according to the data available in the
// ring-buffer. 0, 1 or 2 is returned according to the number of iovec objects
// that were filled (0 meaning buffer is empty).
export fn shl_ring_peek(r: *shl_ring, vec: ?[*]c.struct_iovec) usize {
    if (r.used == 0) {
        return 0;
    } else if (r.start + r.used <= r.size) {
        if (vec) |v| {
            v[0].iov_base = @ptrCast(r.buf.? + r.start);
            v[0].iov_len = r.used;
        }
        return 1;
    } else {
        if (vec) |v| {
            v[0].iov_base = @ptrCast(r.buf.? + r.start);
            v[0].iov_len = r.size - r.start;
            v[1].iov_base = @ptrCast(r.buf.?);
            v[1].iov_len = r.used - (r.size - r.start);
        }
        return 2;
    }
}

// Copy data from the ring buffer into the linear external buffer @buf. Copy
// at most @size bytes. If the ring buffer size is smaller, copy less bytes and
// return the number of bytes copied.
export fn shl_ring_copy(r: *shl_ring, buf: ?*anyopaque, size_arg: usize) usize {
    var size = size_arg;

    if (size > r.used)
        size = r.used;

    if (size > 0) {
        const l = r.size - r.start;
        const dst: [*]u8 = @ptrCast(@alignCast(buf.?));
        if (size <= l) {
            _ = c.memcpy(dst, r.buf.? + r.start, size);
        } else {
            _ = c.memcpy(dst, r.buf.? + r.start, l);
            _ = c.memcpy(dst + l, r.buf.?, size - l);
        }
    }

    return size;
}

// Resize ring-buffer to size @nsize. @nsize must be a power-of-2, otherwise
// ring operations will behave incorrectly.
fn ring_resize(r: *shl_ring, nsize: usize) c_int {
    const alloc = c.malloc(nsize);
    if (alloc == null)
        return -@as(c_int, c.ENOMEM);
    const buf: [*]u8 = @ptrCast(alloc.?);

    if (r.used > 0) {
        const l = r.size - r.start;
        if (r.used <= l) {
            _ = c.memcpy(buf, r.buf.? + r.start, r.used);
        } else {
            _ = c.memcpy(buf, r.buf.? + r.start, l);
            _ = c.memcpy(buf + l, r.buf.?, r.used - l);
        }
    }

    if (r.buf) |old_buf| {
        c.free(old_buf);
    }
    r.buf = buf;
    r.size = nsize;
    r.start = 0;

    return 0;
}

// Resize ring-buffer to provide enough room for @add bytes of new data. This
// resizes the buffer if it is too small. It returns -ENOMEM on OOM and 0 on
// success.
fn ring_grow(r: *shl_ring, add: usize) c_int {
    if (r.size - r.used >= add)
        return 0;

    var need = r.used +% add;
    if (need <= r.used)
        return -@as(c_int, c.ENOMEM);

    if (need < 4096)
        need = 4096;

    need = std.math.ceilPowerOfTwo(usize, need) catch return -@as(c_int, c.ENOMEM);

    return ring_resize(r, need);
}

// Push @len bytes from @u8 into the ring buffer. The buffer is resized if it
// is too small. -ENOMEM is returned on OOM, 0 on success.
export fn shl_ring_push(r: *shl_ring, u8_ptr: ?*const anyopaque, size: usize) c_int {
    if (size == 0)
        return 0;

    const err = ring_grow(r, size);
    if (err < 0)
        return err;

    const pos = RING_MASK(r, r.start + r.used);
    const l = r.size - pos;
    const src: [*]const u8 = @ptrCast(@alignCast(u8_ptr.?));
    if (l >= size) {
        _ = c.memcpy(r.buf.? + pos, src, size);
    } else {
        _ = c.memcpy(r.buf.? + pos, src, l);
        _ = c.memcpy(r.buf.?, src + l, size - l);
    }

    r.used += size;

    return 0;
}

// Remove @len bytes from the start of the ring-buffer. Note that we protect
// against overflows so removing more bytes than available is safe.
export fn shl_ring_pull(r: *shl_ring, size_arg: usize) void {
    var size = size_arg;
    if (size > r.used)
        size = r.used;

    r.start = RING_MASK(r, r.start + size);
    r.used -= size;
}

// Return size of occupied buffer in bytes.
export fn shl_ring_get_size(r: *shl_ring) usize {
    return r.used;
}
