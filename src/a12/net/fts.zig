// Zig port of a12/external/fts.c (BSD fts(3))
// Original: Copyright (c) 1990, 1993, 1994 The Regents of the University of
// California — 3-Clause BSD.  See COPYING file in arcan source repository.
//
// This reimplementation replaces the BSD fts(3) C library with a Zig-native
// file-tree traversal built on std.fs.Dir.walk().  The public API mirrors the
// C API used throughout a12/net/ (afts_open / afts_read / afts_close) so that
// the rest of the Zig port can call it without changes.
//
// Scope of the port
// -----------------
// The a12 callers (dir_supp.c, fap_impl.c) use only:
//   afts_open  — start a traversal of a single root directory
//   afts_read  — yield the next FTSENT (regular files + pre-order dirs)
//   afts_close — release all resources
//   FTS_F      — info value for regular files
//   FTS_D      — info value for directories (pre-order)
//   FTS_DP     — info value for directories (post-order, ignored by callers)
//   fts_name   — filename component
//   fts_path   — full path from the traversal root
//   fts_info   — one of the FTS_* constants above
//
// Options: only FTS_PHYSICAL is supported (lstat, no symlink following).
// Sort:    an optional comparator is accepted for API compatibility; entries
//          within each directory are sorted before being yielded.

const std = @import("std");
const posix = std.posix;

// ---------------------------------------------------------------------------
// Public constants — mirrors fts.h
// ---------------------------------------------------------------------------

pub const FTS_D: u16 = 1; // preorder directory
pub const FTS_DC: u16 = 2; // directory that causes a cycle
pub const FTS_DEFAULT: u16 = 3; // none of the above
pub const FTS_DNR: u16 = 4; // unreadable directory
pub const FTS_DOT: u16 = 5; // dot or dot-dot
pub const FTS_DP: u16 = 6; // postorder directory
pub const FTS_ERR: u16 = 7; // error; errno is set
pub const FTS_F: u16 = 8; // regular file
pub const FTS_INIT: u16 = 9; // initialised only
pub const FTS_NS: u16 = 10; // stat(2) failed
pub const FTS_NSOK: u16 = 11; // no stat(2) requested
pub const FTS_SL: u16 = 12; // symbolic link
pub const FTS_SLNONE: u16 = 13; // symlink without target

pub const FTS_PHYSICAL: c_int = 0x010;
pub const FTS_LOGICAL: c_int = 0x002;
pub const FTS_NOCHDIR: c_int = 0x004;
pub const FTS_NOSTAT: c_int = 0x008;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single entry yielded by afts_read.
/// The backing memory is owned by the Fts handle; do not free individually.
pub const Ftsent = struct {
    /// File name component (last segment of the path).
    fts_name: [:0]const u8,
    /// Full path relative to the traversal root (or absolute if root was absolute).
    fts_path: [:0]const u8,
    /// Entry classification: FTS_F, FTS_D, FTS_DP, FTS_SL, …
    fts_info: u16,
    /// Depth: 0 = root entries, 1 = one level below, …
    fts_level: i32,
    /// errno captured when fts_info == FTS_ERR / FTS_NS.
    fts_errno: c_int,
};

/// Opaque traversal handle returned by afts_open.
pub const Fts = struct {
    allocator: std.mem.Allocator,
    /// Per-entry string storage (name + path are slices into this arena).
    arena: std.heap.ArenaAllocator,
    /// Pending entries in the current traversal, sorted if a comparator was given.
    queue: std.ArrayListUnmanaged(Ftsent),
    /// Stack of open directory iterators, one per level of depth.
    stack: std.ArrayListUnmanaged(DirLevel),
    /// Optional comparator for sorting within each directory.
    compar: ?ComparFn,
    /// Root path string (owned by arena).
    root_path: []const u8,

    const ComparFn = *const fn (*const Ftsent, *const Ftsent) bool;
};

// ---------------------------------------------------------------------------
// Internal bookkeeping
// ---------------------------------------------------------------------------

const DirLevel = struct {
    dir: std.fs.Dir,
    path: []const u8, // owned by arena
    level: i32,
    /// Buffered children collected so we can sort them before yielding.
    children: std.ArrayListUnmanaged(RawEntry),

    const RawEntry = struct {
        name: [:0]const u8,
        kind: std.fs.File.Kind,
    };
};

// ---------------------------------------------------------------------------
// afts_open — begin a traversal
// ---------------------------------------------------------------------------

/// Begin a file-system traversal rooted at `root`.
///
/// `options`  — only FTS_PHYSICAL is meaningful; other flags are accepted for
///              compatibility but ignored.
/// `compar`   — optional comparator; when non-null entries within each
///              directory are sorted using it.  The C signature is
///              `int (*)(const FTSENT**, const FTSENT**)` — map to the
///              Zig ComparFn which takes `*const Ftsent` pointers directly.
/// Returns null on allocation failure or when `root` cannot be opened.
pub fn afts_open(
    allocator: std.mem.Allocator,
    root: []const u8,
    options: c_int,
    compar: ?*const fn (*const *const Ftsent, *const *const Ftsent) callconv(.c) c_int,
) ?*Fts {
    _ = options; // FTS_PHYSICAL assumed; other flags not needed

    var handle = allocator.create(Fts) catch return null;
    handle.* = Fts{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .queue = .{},
        .stack = .{},
        .compar = if (compar != null) wrapCompar(compar.?) else null,
        .root_path = "",
    };

    // Open the root directory.
    const dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch {
        allocator.destroy(handle);
        return null;
    };

    const root_copy = handle.arena.allocator().dupe(u8, root) catch {
        dir.close();
        handle.arena.deinit();
        allocator.destroy(handle);
        return null;
    };
    handle.root_path = root_copy;

    // Push the root level onto the stack.
    var root_level = DirLevel{
        .dir = dir,
        .path = root_copy,
        .level = 0,
        .children = .{},
    };
    collectChildren(&root_level, handle.arena.allocator()) catch {
        dir.close();
        handle.arena.deinit();
        allocator.destroy(handle);
        return null;
    };
    if (handle.compar) |cmp| sortChildren(&root_level.children, cmp, handle.arena.allocator());

    handle.stack.append(allocator, root_level) catch {
        dir.close();
        handle.arena.deinit();
        allocator.destroy(handle);
        return null;
    };

    return handle;
}

// ---------------------------------------------------------------------------
// afts_read — yield the next entry
// ---------------------------------------------------------------------------

/// Return a pointer to the next Ftsent, or null when traversal is complete.
/// The returned pointer is valid until the next call to afts_read or afts_close.
pub fn afts_read(handle: *Fts) ?*Ftsent {
    while (handle.stack.items.len > 0) {
        const top = &handle.stack.items[handle.stack.items.len - 1];

        if (top.children.items.len == 0) {
            // Pop this level — we have exhausted it.
            var popped = handle.stack.pop().?;
            popped.dir.close();
            // Yield the post-order directory entry for this level.
            if (popped.level > 0) {
                const name = std.fs.path.basename(popped.path);
                const ent = makeEntry(handle, popped.path, name, FTS_DP, popped.level) catch continue;
                return ent;
            }
            continue;
        }

        // Take the first child (children are ordered, so pop front by index 0).
        const child = top.children.orderedRemove(0);

        switch (child.kind) {
            .file => {
                const full_path = joinPath(handle.arena.allocator(), top.path, child.name) catch continue;
                const ent = makeEntry(handle, full_path, child.name, FTS_F, top.level + 1) catch continue;
                return ent;
            },
            .sym_link => {
                const full_path = joinPath(handle.arena.allocator(), top.path, child.name) catch continue;
                const ent = makeEntry(handle, full_path, child.name, FTS_SL, top.level + 1) catch continue;
                return ent;
            },
            .directory => {
                const full_path = joinPath(handle.arena.allocator(), top.path, child.name) catch continue;
                // Yield pre-order directory entry immediately.
                const ent = makeEntry(handle, full_path, child.name, FTS_D, top.level + 1) catch continue;

                // Push a new level for this subdirectory.
                const sub_dir = top.dir.openDir(child.name, .{ .iterate = true }) catch {
                    // Mark as unreadable but still yield the FTS_D entry.
                    ent.fts_info = FTS_DNR;
                    return ent;
                };
                var sub_level = DirLevel{
                    .dir = sub_dir,
                    .path = full_path,
                    .level = top.level + 1,
                    .children = .{},
                };
                collectChildren(&sub_level, handle.arena.allocator()) catch {};
                if (handle.compar) |cmp| sortChildren(&sub_level.children, cmp, handle.arena.allocator());
                handle.stack.append(handle.allocator, sub_level) catch {
                    sub_dir.close();
                };
                return ent;
            },
            else => {
                const full_path = joinPath(handle.arena.allocator(), top.path, child.name) catch continue;
                const ent = makeEntry(handle, full_path, child.name, FTS_DEFAULT, top.level + 1) catch continue;
                return ent;
            },
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// afts_close — release all resources
// ---------------------------------------------------------------------------

/// Release the traversal handle and all associated memory.
pub fn afts_close(handle: *Fts) void {
    // Close all open directory handles on the stack.
    for (handle.stack.items) |*level| {
        level.dir.close();
        level.children.deinit(handle.allocator);
    }
    handle.stack.deinit(handle.allocator);
    handle.queue.deinit(handle.allocator);
    handle.arena.deinit();
    handle.allocator.destroy(handle);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Collect all immediate children of `level` into level.children.
fn collectChildren(level: *DirLevel, arena: std.mem.Allocator) !void {
    var it = level.dir.iterate();
    while (try it.next()) |entry| {
        // Skip dot and dot-dot.
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        const name_z: [:0]const u8 = try arena.dupeZ(u8, entry.name);
        try level.children.append(arena, .{
            .name = name_z,
            .kind = entry.kind,
        });
    }
}

fn sortChildren(
    children: *std.ArrayListUnmanaged(DirLevel.RawEntry),
    cmp: Fts.ComparFn,
    arena: std.mem.Allocator,
) void {
    _ = arena;
    std.sort.pdq(DirLevel.RawEntry, children.items, cmp, rawEntryCmp);
}

fn rawEntryCmp(
    user_cmp: Fts.ComparFn,
    a: DirLevel.RawEntry,
    b: DirLevel.RawEntry,
) bool {
    // Build temporary Ftsent values on the stack for the comparator.
    const fa = Ftsent{ .fts_name = a.name, .fts_path = a.name, .fts_info = 0, .fts_level = 0, .fts_errno = 0 };
    const fb = Ftsent{ .fts_name = b.name, .fts_path = b.name, .fts_info = 0, .fts_level = 0, .fts_errno = 0 };
    return user_cmp(&fa, &fb);
}

/// Build a sentinel Ftsent stored in the arena and return a pointer to it.
fn makeEntry(
    handle: *Fts,
    full_path: []const u8,
    name: []const u8,
    info: u16,
    level: i32,
) !*Ftsent {
    const arena = handle.arena.allocator();
    const ent = try arena.create(Ftsent);
    const path_z: [:0]const u8 = try arena.dupeZ(u8, full_path);
    const name_z: [:0]const u8 = try arena.dupeZ(u8, name);
    ent.* = Ftsent{
        .fts_name = name_z,
        .fts_path = path_z,
        .fts_info = info,
        .fts_level = level,
        .fts_errno = 0,
    };
    return ent;
}

fn joinPath(arena: std.mem.Allocator, parent: []const u8, name: []const u8) ![:0]const u8 {
    const full = try std.fs.path.joinZ(arena, &.{ parent, name });
    return full;
}

/// Wrap the C-ABI comparator (which takes **FTSENT) into a Zig bool comparator.
fn wrapCompar(
    c_cmp: *const fn (*const *const Ftsent, *const *const Ftsent) callconv(.c) c_int,
) Fts.ComparFn {
    // We cannot capture c_cmp in a Zig function pointer without a closure, so
    // store it in a file-scoped var (single-threaded use is assumed for fts).
    stored_compar = c_cmp;
    return wrappedCmp;
}

var stored_compar: ?*const fn (*const *const Ftsent, *const *const Ftsent) callconv(.c) c_int = null;

fn wrappedCmp(a: *const Ftsent, b: *const Ftsent) bool {
    const cmp = stored_compar orelse return std.mem.order(u8, a.fts_name, b.fts_name) == .lt;
    return cmp(&a, &b) < 0;
}
