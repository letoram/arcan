// fuse_types — hand-translated subset of linux/fuse.h used by acfgfs.
//
// Only the opcodes / structs consumed by the Zig FUSE loop are exposed.
// Mirrors shmif_types.zig style: plain `extern struct`s + constants, no
// `@cImport`. The kernel UAPI is ABI-frozen for these fields so a
// hand copy is safe.

// Protocol version.
pub const FUSE_KERNEL_VERSION: u32 = 7;

// Opcodes — `enum fuse_opcode` (uint32_t on the wire).
pub const FUSE_LOOKUP: u32 = 1;
pub const FUSE_FORGET: u32 = 2;
pub const FUSE_GETATTR: u32 = 3;
pub const FUSE_SETATTR: u32 = 4;
pub const FUSE_OPEN: u32 = 14;
pub const FUSE_READ: u32 = 15;
pub const FUSE_WRITE: u32 = 16;
pub const FUSE_STATFS: u32 = 17;
pub const FUSE_RELEASE: u32 = 18;
pub const FUSE_FLUSH: u32 = 25;
pub const FUSE_INIT: u32 = 26;
pub const FUSE_OPENDIR: u32 = 27;
pub const FUSE_READDIR: u32 = 28;
pub const FUSE_RELEASEDIR: u32 = 29;
pub const FUSE_ACCESS: u32 = 34;
pub const FUSE_DESTROY: u32 = 38;
pub const FUSE_BATCH_FORGET: u32 = 42;

// struct fuse_attr — per-inode metadata. 88 bytes, all little-endian.
pub const fuse_attr = extern struct {
    ino: u64 = 0,
    size: u64 = 0,
    blocks: u64 = 0,
    atime: u64 = 0,
    mtime: u64 = 0,
    ctime: u64 = 0,
    atimensec: u32 = 0,
    mtimensec: u32 = 0,
    ctimensec: u32 = 0,
    mode: u32 = 0,
    nlink: u32 = 0,
    uid: u32 = 0,
    gid: u32 = 0,
    rdev: u32 = 0,
    blksize: u32 = 0,
    flags: u32 = 0,
};

// struct fuse_kstatfs — mirrors statfs(2).
pub const fuse_kstatfs = extern struct {
    blocks: u64 = 0,
    bfree: u64 = 0,
    bavail: u64 = 0,
    files: u64 = 0,
    ffree: u64 = 0,
    bsize: u32 = 0,
    namelen: u32 = 0,
    frsize: u32 = 0,
    padding: u32 = 0,
    spare: [6]u32 = .{ 0, 0, 0, 0, 0, 0 },
};

// struct fuse_entry_out — LOOKUP reply.
pub const fuse_entry_out = extern struct {
    nodeid: u64 = 0,
    generation: u64 = 0,
    entry_valid: u64 = 0,
    attr_valid: u64 = 0,
    entry_valid_nsec: u32 = 0,
    attr_valid_nsec: u32 = 0,
    attr: fuse_attr = .{},
};

// struct fuse_attr_out — GETATTR reply.
pub const fuse_attr_out = extern struct {
    attr_valid: u64 = 0,
    attr_valid_nsec: u32 = 0,
    dummy: u32 = 0,
    attr: fuse_attr = .{},
};

// struct fuse_open_out — OPEN/OPENDIR reply.
pub const fuse_open_out = extern struct {
    fh: u64 = 0,
    open_flags: u32 = 0,
    backing_id: i32 = 0,
};

// struct fuse_release_in — RELEASE/RELEASEDIR request.
pub const fuse_release_in = extern struct {
    fh: u64 = 0,
    flags: u32 = 0,
    release_flags: u32 = 0,
    lock_owner: u64 = 0,
};

// struct fuse_read_in — READ/READDIR request.
pub const fuse_read_in = extern struct {
    fh: u64 = 0,
    offset: u64 = 0,
    size: u32 = 0,
    read_flags: u32 = 0,
    lock_owner: u64 = 0,
    flags: u32 = 0,
    padding: u32 = 0,
};

// struct fuse_write_in — WRITE request.
pub const fuse_write_in = extern struct {
    fh: u64 = 0,
    offset: u64 = 0,
    size: u32 = 0,
    write_flags: u32 = 0,
    lock_owner: u64 = 0,
    flags: u32 = 0,
    padding: u32 = 0,
};

// struct fuse_write_out — WRITE reply.
pub const fuse_write_out = extern struct {
    size: u32 = 0,
    padding: u32 = 0,
};

// struct fuse_statfs_out — STATFS reply.
pub const fuse_statfs_out = extern struct {
    st: fuse_kstatfs = .{},
};

// struct fuse_init_in — INIT request.
pub const fuse_init_in = extern struct {
    major: u32 = 0,
    minor: u32 = 0,
    max_readahead: u32 = 0,
    flags: u32 = 0,
    flags2: u32 = 0,
    unused: [11]u32 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

// struct fuse_init_out — INIT reply.
pub const fuse_init_out = extern struct {
    major: u32 = 0,
    minor: u32 = 0,
    max_readahead: u32 = 0,
    flags: u32 = 0,
    max_background: u16 = 0,
    congestion_threshold: u16 = 0,
    max_write: u32 = 0,
    time_gran: u32 = 0,
    max_pages: u16 = 0,
    map_alignment: u16 = 0,
    flags2: u32 = 0,
    max_stack_depth: u32 = 0,
    request_timeout: u16 = 0,
    unused: [11]u16 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

// struct fuse_in_header — every request prefix.
pub const fuse_in_header = extern struct {
    len: u32 = 0,
    opcode: u32 = 0,
    unique: u64 = 0,
    nodeid: u64 = 0,
    uid: u32 = 0,
    gid: u32 = 0,
    pid: u32 = 0,
    total_extlen: u16 = 0,
    padding: u16 = 0,
};

// struct fuse_out_header — every reply prefix.
pub const fuse_out_header = extern struct {
    len: u32 = 0,
    @"error": i32 = 0,
    unique: u64 = 0,
};

// struct fuse_dirent — variable-length directory entry (name[] tail).
pub const fuse_dirent = extern struct {
    ino: u64 = 0,
    off: u64 = 0,
    namelen: u32 = 0,
    type: u32 = 0,
    // `char name[]` flexible array — callers append past the struct.
};
