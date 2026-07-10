// Zig port of posix/map_resource.c
// Map/unmap resource files: mmap for aligned reads, fallback to read() for others.

const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const shmif = if (is_freestanding) struct {} else @import("shmif_types");
const libc = if (is_freestanding) struct {} else @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module. Freestanding builds stub
/// out the map/read code paths entirely (see is_freestanding guards), so
/// we only populate the struct in posix builds.
const c = if (is_freestanding) struct {} else struct {
    pub const off_t = libc.off_t;
    pub const struct_stat = shmif.struct_stat;
    pub const fstat = shmif.fstat;
    pub const lseek = shmif.lseek;
    pub const mmap = libc.mmap;
    pub const munmap = libc.munmap;
    pub const MAP_FAILED = libc.MAP_FAILED;
    pub const MAP_PRIVATE = libc.MAP_PRIVATE;
    pub const PROT_READ = libc.PROT_READ;
    pub const malloc = libc.malloc;
    pub const free = libc.free;
    pub const realloc = shmif.realloc;
    pub const read = libc.read;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const EINTR = libc.EINTR;
    pub const __errno_location = libc.__errno_location;
    pub const sysconf = libc.sysconf;
    pub const _SC_PAGE_SIZE = libc._SC_PAGE_SIZE;
    pub const S_IFMT = libc.S_IFMT;
    pub const S_IFIFO = libc.S_IFIFO;
    pub const S_IFSOCK = libc.S_IFSOCK;
};

const MAX_RESMAP_SIZE: usize = 1024 * 1024 * 40;

const off_t = if (is_freestanding) i64 else c.off_t;

const data_source = extern struct {
    fd: c_int,
    start: off_t,
    len: off_t,
    source: [*c]u8,
};

const map_region = extern struct {
    ptr: [*c]u8,
    zbyte: u8,
    sz: usize,
    mmap_flag: bool,
};

// Direct varargs call to arcan_warning (no C shim needed)
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn strerror(errnum: c_int) [*c]const u8;

fn read_safe(fd: c_int, ntr_arg: usize, bs: usize, dofs: ?[*]u8, outsz: ?*off_t) bool {
    if (is_freestanding) return false;
    var ntr = ntr_arg;
    var emptyb: [8192]u8 = undefined;
    var dbuf: [*]u8 = dofs orelse &emptyb;

    while (ntr > 0) {
        const to_read = if (bs > ntr) ntr else bs;
        const nr = c.read(fd, dbuf, to_read);

        if (nr > 0) {
            const n: usize = @intCast(nr);
            ntr -= n;
            if (outsz) |p| {
                p.* += @intCast(nr);
            }
            if (dofs != null) {
                dbuf += n;
            }
        } else if (nr == 0) {
            break;
        } else {
            if (c.__errno_location().* == c.EINTR) {
                continue;
            }
            break;
        }
    }

    return ntr == 0;
}

export fn arcan_map_resource(source: *data_source, allowwrite: bool) map_region {
    if (is_freestanding)
        return map_region{ .ptr = null, .zbyte = 0, .sz = 0, .mmap_flag = false };
    var rv = map_region{
        .ptr = null,
        .zbyte = 0,
        .sz = 0,
        .mmap_flag = false,
    };
    var sbuf: c.struct_stat = undefined;
    var allow_trunc: bool = false;
    var force_read: bool = false;

    // resolve size if not yet known
    if (source.len == 0 and c.fstat(source.fd, &sbuf) != -1) {
        source.len = sbuf.st_size;
        source.start = 0;
        const mode = sbuf.st_mode & c.S_IFMT;
        // overalloc for pipes/sockets
        if (mode == c.S_IFIFO or mode == c.S_IFSOCK) {
            source.len = MAX_RESMAP_SIZE;
            allow_trunc = true;
            force_read = true;
        }
    }

    // bad resource
    if (source.len == 0)
        return rv;

    const src_len: usize = @intCast(source.len);

    // for unaligned reads (or writable/forced) — fall through to read path
    const page_size = c.sysconf(c._SC_PAGE_SIZE);
    if (page_size > 0 and @rem(source.start, page_size) != 0 or allowwrite or force_read) {
        return do_memread(source, &rv, allow_trunc, src_len);
    }

    // try mmap for reasonably-sized resources
    if (source.len > 0 and src_len < MAX_RESMAP_SIZE) {
        rv.sz = src_len;
        const ptr = c.mmap(null, rv.sz, c.PROT_READ, c.MAP_PRIVATE, source.fd, source.start);

        if (ptr == c.MAP_FAILED) {
            const errbuf = strerror(c.__errno_location().*);
            arcan_warning("arcan_map_resource() failed, reason(%d): %s\n\t(length)%d, (fd)%d, (offset)%ld\n", c.__errno_location().*, errbuf, @as(c_int, @intCast(rv.sz)), source.fd, @as(c_long, @intCast(source.start)));
            rv.ptr = null;
            rv.sz = 0;
        } else {
            rv.ptr = @ptrCast(ptr);
            rv.mmap_flag = true;
        }
    }
    return rv;
}

fn do_memread(source: *data_source, rv: *map_region, allow_trunc: bool, src_len: usize) map_region {
    rv.ptr = @ptrCast(c.malloc(src_len));
    rv.sz = src_len;
    rv.mmap_flag = false;

    if (rv.ptr == null) {
        rv.sz = 0;
        return rv.*;
    }

    // if seeking is not possible, skip by reading
    var rstatus: bool = true;
    if (source.start > 0) {
        if (c.lseek(source.fd, source.start, c.SEEK_SET) == -1) {
            rstatus = read_safe(source.fd, @intCast(source.start), 8192, null, null);
        }
    }

    if (rstatus) {
        const reqlen = source.len;
        source.len = 0;
        rstatus = read_safe(source.fd, @intCast(reqlen), 8192, rv.ptr, &source.len);
    }

    if (!rstatus) {
        if (allow_trunc and source.len > 0) {
            const new_len: usize = @intCast(source.len);
            const ptr: ?*anyopaque = c.realloc(rv.ptr, new_len);
            if (ptr) |p| {
                rv.ptr = @ptrCast(p);
                rv.sz = new_len;
                return rv.*;
            }
        }

        c.free(rv.ptr);
        rv.ptr = null;
        rv.sz = 0;
    }

    return rv.*;
}

export fn arcan_release_map(region: map_region) bool {
    if (is_freestanding) return false;
    if (region.sz > 0 and region.ptr != null) {
        if (region.mmap_flag) {
            return c.munmap(region.ptr, region.sz) != -1;
        } else {
            c.free(region.ptr);
            return true;
        }
    }
    return false;
}
