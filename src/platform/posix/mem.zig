// Zig port of posix/mem.c
// Type/use-hinted memory (de-)allocation routines.
// Currently a stub implementation — serious hardening slated for 0.8-0.9.

const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const c = @import("shmif_types");

// MADV_DONTDUMP / MADV_NOCORE for excluding pages from core dumps.
// Linux defines MADV_DONTDUMP, BSDs use MADV_NOCORE.
const NO_DUMPFLAG: c_int = if (is_freestanding) 0 else c.MADV_DONTDUMP;

const REALLOC_STEP: usize = 16;

extern fn arcan_fatal(fmt: [*c]const u8, ...) callconv(.c) void;

// MAY-258: freestanding (EL2 bare-metal) engine heap, backed by the seL4
// BootInfo-sourced free-list allocator in src/sel4-zig/sel4_heap.zig. Reached by
// C-ABI extern symbol (these live in the root module of the boot payload, this
// file is compiled into the engine module). On hosted/posix builds these
// symbols are never referenced (the is_freestanding branches are dead).
extern fn el2_heap_alloc(size: usize, alignment: usize) ?*anyopaque;
extern fn el2_heap_free(ptr: ?*anyopaque) void;

// m1n1 uses a 16K page (Apple Silicon). NATURAL/SIMD map to the heap's 16-byte
// minimum; PAGE maps to the 16K page so PAGE-aligned engine allocs are honored.
const FS_ALIGN_NATURAL: usize = 16;
const FS_ALIGN_SIMD: usize = 16;
const FS_ALIGN_PAGE: usize = 16384;

export var system_page_size: c_int = 4096;

/// Initialize memory pools. Currently a stub.
export fn arcan_mem_init() void {}

/// Tick-based memory housekeeping. Currently a stub.
export fn arcan_mem_tick() void {}

const enum_arcan_memtypes = c.enum_arcan_memtypes;
const enum_arcan_memhint = c.enum_arcan_memhint;
const enum_arcan_memalign = c.enum_arcan_memalign;

export fn arcan_alloc_mem(
    nb: usize,
    mem_type: enum_arcan_memtypes,
    hint: enum_arcan_memhint,
    alignment: enum_arcan_memalign,
) ?*anyopaque {
    if (is_freestanding) {
        // EL2 bare-metal: route every type through the seL4-sourced engine heap.
        // ENDMARKER / unknown types still fatal (matches the posix path's else).
        switch (mem_type) {
            c.ARCAN_MEM_SHARED,
            c.ARCAN_MEM_BINDING,
            c.ARCAN_MEM_THREADCTX,
            c.ARCAN_MEM_VBUFFER,
            c.ARCAN_MEM_ABUFFER,
            c.ARCAN_MEM_MODELDATA,
            c.ARCAN_MEM_VSTRUCT,
            c.ARCAN_MEM_EXTSTRUCT,
            c.ARCAN_MEM_STRINGBUF,
            c.ARCAN_MEM_VTAG,
            c.ARCAN_MEM_ATAG,
            => {},
            else => arcan_fatal("arcan_alloc_mem(): invalid memtype (freestanding)\n"),
        }

        const al: usize = switch (alignment) {
            c.ARCAN_MEMALIGN_PAGE => FS_ALIGN_PAGE,
            c.ARCAN_MEMALIGN_SIMD => FS_ALIGN_SIMD,
            else => FS_ALIGN_NATURAL, // NATURAL + any unknown
        };

        // el2_heap_alloc zeroes the block, satisfying ARCAN_MEM_BZERO for every
        // type. (The posix path fills VBUFFER with opaque-black RGBA(0,0,0,255)
        // rather than raw zero; we keep raw-zero here — the engine's first allocs
        // on the bringup path are VSTRUCT, not VBUFFER, and zeroed VBUFFER is a
        // transparent-black rather than opaque-black canvas, a display nicety not
        // needed for correctness. RGBA() isn't exposed by shmif_types anyway.)
        const rptr = el2_heap_alloc(nb, al);
        if (rptr == null) {
            // Honor ARCAN_MEM_NONFATAL: callers like populate_vstore handle null.
            if ((@as(c_uint, @bitCast(hint)) & @as(c_uint, @bitCast(c.ARCAN_MEM_NONFATAL))) == 0) {
                arcan_fatal("arcan_alloc_mem(), out of memory (freestanding heap).\n");
            }
            return null;
        }
        return rptr;
    }
    var rptr: ?*anyopaque = null;
    const header_sz: usize = 0;
    const footer_sz: usize = 0;
    const padding_sz: usize = 0;
    var total: usize = 0;

    switch (mem_type) {
        // SHARED: mmap an anonymous shared page (not safe to _free yet)
        c.ARCAN_MEM_SHARED => {
            const page_sz: usize = @intCast(system_page_size);
            const ptr = c.mmap(
                null,
                page_sz,
                c.PROT_READ | c.PROT_WRITE,
                c.MAP_SHARED | c.MAP_ANONYMOUS,
                -1,
                0,
            );
            if (ptr != c.MAP_FAILED) {
                rptr = ptr;
            }
            total = page_sz;
        },

        // All other valid types: heap allocation with alignment
        c.ARCAN_MEM_BINDING,
        c.ARCAN_MEM_THREADCTX,
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_ABUFFER,
        c.ARCAN_MEM_MODELDATA,
        c.ARCAN_MEM_VSTRUCT,
        c.ARCAN_MEM_EXTSTRUCT,
        c.ARCAN_MEM_STRINGBUF,
        c.ARCAN_MEM_VTAG,
        c.ARCAN_MEM_ATAG,
        => {
            total = header_sz + footer_sz + padding_sz + nb;

            switch (alignment) {
                c.ARCAN_MEMALIGN_NATURAL => {
                    rptr = c.malloc(total);
                },
                c.ARCAN_MEMALIGN_PAGE => {
                    var aligned: ?*anyopaque = null;
                    if (c.posix_memalign(&aligned, @intCast(system_page_size), total) == 0) {
                        rptr = aligned;
                    }
                },
                c.ARCAN_MEMALIGN_SIMD => {
                    var aligned: ?*anyopaque = null;
                    if (c.posix_memalign(&aligned, 16, total) == 0) {
                        rptr = aligned;
                    }
                },
                else => {},
            }
        },

        // ENDMARKER or unknown: fatal
        else => {
            c.abort();
        },
    }

    if (rptr == null) {
        if ((@as(c_uint, @bitCast(hint)) & @as(c_uint, @bitCast(c.ARCAN_MEM_NONFATAL))) == 0) {
            arcan_fatal("arcan_alloc_mem(), out of memory.\n");
        }
        return null;
    }

    // Post-alloc hooks: madvise for buffer types and sensitive data
    var madvflag: c_int = 0;

    switch (mem_type) {
        c.ARCAN_MEM_VBUFFER,
        c.ARCAN_MEM_ABUFFER,
        c.ARCAN_MEM_MODELDATA,
        => {
            madvflag |= NO_DUMPFLAG;
        },
        else => {},
    }

    if ((@as(c_uint, @bitCast(hint)) & @as(c_uint, @bitCast(c.ARCAN_MEM_SENSITIVE))) != 0) {
        madvflag |= NO_DUMPFLAG;
    }

    if (madvflag != 0) {
        _ = c.madvise(rptr, total, madvflag);
    }

    if ((@as(c_uint, @bitCast(hint)) & @as(c_uint, @bitCast(c.ARCAN_MEM_BZERO))) != 0) {
        if (mem_type == c.ARCAN_MEM_VBUFFER) {
            // VBUFFER zero: fill with RGBA(0,0,0,255) — opaque black pixels
            const buf_ptr: [*]c.av_pixel = @ptrCast(@alignCast(rptr));
            const pixel_count = nb / @sizeOf(c.av_pixel);
            const opaque_black = c.RGBA(0, 0, 0, 255);
            for (0..pixel_count) |i| {
                buf_ptr[i] = opaque_black;
            }
        } else {
            _ = c.memset(rptr, 0, total);
        }
    }

    return rptr;
}

const struct_arcan_strarr = if (is_freestanding) anyopaque else c.struct_arcan_strarr;

export fn arcan_mem_growarr(res: *struct_arcan_strarr) void {
    if (is_freestanding) return;
    const new_limit = res.limit + REALLOC_STEP;
    const newbuf: [*c][*c]u8 = @ptrCast(@alignCast(arcan_alloc_mem(
        new_limit * @sizeOf([*c]u8),
        c.ARCAN_MEM_STRINGBUF,
        c.ARCAN_MEM_BZERO,
        c.ARCAN_MEMALIGN_NATURAL,
    )));

    if (res.unnamed_0.data != null) {
        _ = c.memcpy(
            @as(?*anyopaque, @ptrCast(newbuf)),
            @as(?*const anyopaque, @ptrCast(res.unnamed_0.data)),
            res.limit * @sizeOf([*c]u8),
        );
    }
    arcan_mem_free(@as(?*anyopaque, @ptrCast(res.unnamed_0.data)));
    res.unnamed_0.data = newbuf;
    res.limit = new_limit;
}

export fn arcan_mem_freearr(res: ?*struct_arcan_strarr) void {
    if (is_freestanding) return;
    const r = res orelse return;
    if (r.unnamed_0.data == null) return;

    var cptr: [*c][*c]u8 = r.unnamed_0.data;
    while (cptr[0] != null) {
        arcan_mem_free(@as(?*anyopaque, @ptrCast(cptr[0])));
        cptr += 1;
    }

    arcan_mem_free(@as(?*anyopaque, @ptrCast(r.unnamed_0.data)));

    _ = c.memset(
        @as(?*anyopaque, @ptrCast(r)),
        0,
        @sizeOf(c.struct_arcan_strarr),
    );
}

/// Allocate and fill memory from a source buffer.
export fn arcan_alloc_fillmem(
    data: ?*const anyopaque,
    ds: usize,
    mem_type: enum_arcan_memtypes,
    hint: enum_arcan_memhint,
    alignment: enum_arcan_memalign,
) ?*anyopaque {
    if (is_freestanding) {
        const buf = arcan_alloc_mem(ds, mem_type, hint, alignment) orelse return null;
        if (data) |src| {
            const dst: [*]u8 = @ptrCast(buf);
            const src_b: [*]const u8 = @ptrCast(src);
            @memcpy(dst[0..ds], src_b[0..ds]);
        }
        return buf;
    }
    const buf = arcan_alloc_mem(ds, mem_type, hint, alignment) orelse return null;
    _ = c.memcpy(buf, data, ds);
    return buf;
}

export fn arcan_mem_free(inptr: ?*anyopaque) void {
    if (is_freestanding) {
        // free + coalesce in the seL4-sourced heap; no-op on null / out-of-arena.
        el2_heap_free(inptr);
        return;
    }
    c.free(inptr);
}
