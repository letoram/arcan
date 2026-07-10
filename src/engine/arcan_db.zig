// Pure Zig port of engine/arcan_db.c — xitdb database backend.
// Manages target/config/appl key-value storage for arcan.
// Replaces the SQLite3 implementation with xitdb embedded immutable database.

const std = @import("std");
const builtin = @import("builtin");
const xitdb = @import("xitdb");

const is_freestanding = builtin.os.tag == .freestanding;

// xitdb type aliases
// Use u160 hash — matches xitdb test suite. xitdb's shift logic needs
// std.math.Log2Int(HashInt) >= u8 (i.e. HashInt > 128 bits).
const HashInt = u160;
const DB = if (is_freestanding)
    xitdb.Database(.memory, HashInt)
else
    xitdb.Database(.file, HashInt);

// C library
extern fn strdup(s: [*c]const u8) [*c]u8;

// Arcan memory management
const ARCAN_MEM_EXTSTRUCT: c_uint = 3;
const ARCAN_MEM_STRINGBUF: c_uint = 5;
const ARCAN_MEM_BZERO: c_uint = 1;
const ARCAN_MEM_SENSITIVE: c_uint = 32;
const ARCAN_MEMALIGN_NATURAL: c_uint = 0;
const ARCAN_MEMALIGN_PAGE: c_uint = 1;

extern fn arcan_alloc_mem(sz: usize, memtype: c_uint, hint: c_uint, alignment: c_uint) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_mem_growarr(arr: *arcan_strarr) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_fatal(fmt: [*c]const u8, ...) callconv(.c) void;

// Types
pub const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    // C union { char** data; void** cdata; } — only need data access
    data: [*c][*c]u8,
};

const arcan_targetid = c_long;
const arcan_configid = c_long;

const BAD_TARGET: arcan_targetid = -1;
const BAD_CONFIG: arcan_configid = -1;

const DVT_APPL: c_int = 0;
const DVT_TARGET: c_int = 1;
const DVT_TARGET_ENV: c_int = 2;
const DVT_TARGET_LIBV: c_int = 3;
const DVT_CONFIG: c_int = 10;
const DVT_CONFIG_ENV: c_int = 11;
const DVT_ENDM: c_int = 5;

const arcan_dbtrans_id = extern union {
    cid: arcan_configid,
    tid: arcan_targetid,
    applname: [*c]const u8,
};

// arcan_dbh now holds xitdb state instead of sqlite3
const arcan_dbh = extern struct {
    // Pointer to heap-allocated DbState (opaque to C callers)
    state: ?*anyopaque,
    applname: [*c]u8,
    // Transaction buffering
    ttype: c_int,
    trid: arcan_dbtrans_id,
    trclean: bool,
    in_transaction: bool,
};

// Internal state holding the xitdb database — heap-allocated via Zig allocator
const DbState = struct {
    db: DB,
    // For freestanding: the backing buffer for xitdb memory mode
    mem_buffer: if (is_freestanding) std.Io.Writer.Allocating else void,
    // For POSIX: the backing file
    file: if (is_freestanding) void else std.fs.File,
    // Allocator: GPA on POSIX, FixedBufferAllocator on freestanding
    // (GPA requires page_size which isn't available on freestanding)
    gpa: if (is_freestanding) void else std.heap.GeneralPurposeAllocator(.{}),
    fba: if (is_freestanding) std.heap.FixedBufferAllocator else void,
    // Static backing store for the freestanding FixedBufferAllocator
    fba_buf: if (is_freestanding) [64 * 1024]u8 else void,
};

// Constants
const DB_VERSION_NUM = "4";
const ARCAN_TBL = "arcan";

// State
var db_init: bool = false;
var shared_handle: ?*arcan_dbh = null;

// Helper: C string → Zig slice
fn cstr(s: [*c]const u8) []const u8 {
    if (s == null) return "";
    return std.mem.sliceTo(s, 0);
}

// Hash helper
fn hashKey(key: []const u8) HashInt {
    // Produce 160-bit hash using SHA1 (same as xitdb test suite)
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(key, &hash, .{});
    return std.mem.readInt(HashInt, &hash, .big);
}

// xitdb helpers

fn getDbState(dbh: *arcan_dbh) ?*DbState {
    const s = dbh.state orelse return null;
    return @as(*DbState, @ptrCast(@alignCast(s)));
}

/// Allocate a C string from a Zig slice using arcan_alloc_mem
fn allocCStr(slice: []const u8) [*c]u8 {
    const ptr = arcan_alloc_mem(
        slice.len + 1,
        ARCAN_MEM_STRINGBUF,
        0,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return null;
    const dest: [*]u8 = @ptrCast(ptr);
    @memcpy(dest[0..slice.len], slice);
    dest[slice.len] = 0;
    return @ptrCast(dest);
}

/// Read bytes from a cursor into an arcan_alloc_mem'd C string
fn cursorToCStr(cursor: anytype) [*c]u8 {
    var buf: [4096]u8 = undefined;
    const bytes = cursor.readBytes(&buf) catch return null;
    return allocCStr(bytes);
}

/// Initialize root HashMap if not already done
fn ensureRootMap(state: *DbState) !DB.HashMap(.read_write) {
    return DB.HashMap(.read_write).init(state.db.rootCursor());
}

/// Get or create a sub-HashMap under a parent map at the given key
fn ensureSubMap(parent: DB.HashMap(.read_write), key: []const u8) !DB.HashMap(.read_write) {
    const h = hashKey(key);
    const sub_cursor = try parent.putCursor(h);
    const sub = try DB.HashMap(.read_write).init(sub_cursor);
    try parent.putKey(h, .{ .bytes = key });
    return sub;
}

/// Read a string value from a HashMap by key, returns null if not found
fn mapGetStr(map: anytype, key: []const u8) [*c]u8 {
    const cursor = (map.getCursor(hashKey(key)) catch return null) orelse return null;
    return cursorToCStr(cursor);
}

/// Get a read-only sub-HashMap under a parent map at the given key
fn getSubMapRO(parent: anytype, key: []const u8) ?DB.HashMap(.read_only) {
    const cursor = (parent.getCursor(hashKey(key)) catch return null) orelse return null;
    return DB.HashMap(.read_only).init(cursor) catch null;
}

/// Get a read-write sub-HashMap under a parent map at the given key
fn getSubMapRW(parent: DB.HashMap(.read_write), key: []const u8) ?DB.HashMap(.read_write) {
    const cursor = (parent.putCursor(hashKey(key)) catch return null);
    return DB.HashMap(.read_write).init(cursor) catch null;
}

/// Read a uint from a HashMap by key, returns null if not found
fn mapGetUint(map: anytype, key: []const u8) ?u64 {
    const cursor = (map.getCursor(hashKey(key)) catch return null) orelse return null;
    return cursor.readUint() catch return null;
}

/// Write a string value into a HashMap
fn mapPutStr(map: DB.HashMap(.read_write), key: []const u8, value: []const u8) void {
    const h = hashKey(key);
    map.put(h, .{ .bytes = value }) catch return;
    map.putKey(h, .{ .bytes = key }) catch return;
}

/// Write a uint value into a HashMap
fn mapPutUint(map: DB.HashMap(.read_write), key: []const u8, value: u64) void {
    const h = hashKey(key);
    map.put(h, .{ .uint = value }) catch return;
    map.putKey(h, .{ .bytes = key }) catch return;
}

/// Get the targets HashMap from root
fn getTargetsMap(state: *DbState, comptime rw: bool) if (rw) ?DB.HashMap(.read_write) else ?DB.HashMap(.read_only) {
    if (rw) {
        const root = ensureRootMap(state) catch return null;
        return ensureSubMap(root, "targets") catch return null;
    } else {
        const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return null) orelse return null;
        const root = DB.HashMap(.read_only).init(root_cursor) catch return null;
        return getSubMapRO(root, "targets");
    }
}

/// Get a target's sub-map by name
fn getTargetByName(state: *DbState, name: []const u8) ?DB.HashMap(.read_only) {
    const targets = getTargetsMap(state, false) orelse return null;
    return getSubMapRO(targets, name);
}

/// Get target name from its ID (stored as "name" field in the target sub-map)
/// Targets are keyed by name in the HashMap. We store a mapping from ID→name
/// under root/"target_ids"/id_str → name.
fn getTargetNameById(state: *DbState, id: arcan_targetid) ?[]const u8 {
    const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return null) orelse return null;
    const root = DB.HashMap(.read_only).init(root_cursor) catch return null;
    const ids_map = getSubMapRO(root, "target_ids") orelse return null;
    var buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&buf, "{d}", .{id}) catch return null;
    const cursor = (ids_map.getCursor(hashKey(id_str)) catch return null) orelse return null;
    var name_buf: [256]u8 = undefined;
    const bytes = cursor.readBytes(&name_buf) catch return null;
    return bytes;
}

/// Get config name from its ID (stored under root/"config_ids"/id_str → name)
fn getConfigInfoById(state: *DbState, id: arcan_configid) ?struct { name: []const u8, target_name: []const u8 } {
    const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return null) orelse return null;
    const root = DB.HashMap(.read_only).init(root_cursor) catch return null;
    const ids_map = getSubMapRO(root, "config_ids") orelse return null;
    var buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&buf, "{d}", .{id}) catch return null;
    // Value is "target_name\x00config_name"
    const cursor = (ids_map.getCursor(hashKey(id_str)) catch return null) orelse return null;
    var val_buf: [512]u8 = undefined;
    const bytes = cursor.readBytes(&val_buf) catch return null;
    // Find separator
    const sep_idx = std.mem.indexOfScalar(u8, bytes, 0) orelse return null;
    if (sep_idx + 1 >= bytes.len) return null;
    return .{
        .target_name = bytes[0..sep_idx],
        .name = bytes[sep_idx + 1 ..],
    };
}

/// Initialize a strarr for results
fn initStrarr() arcan_strarr {
    var res: arcan_strarr = .{ .data = null, .count = 0, .limit = 0 };
    const ptr = arcan_alloc_mem(
        @sizeOf(?[*c]u8) * 8,
        ARCAN_MEM_STRINGBUF,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    );
    res.data = @ptrCast(@alignCast(ptr));
    res.limit = 8;
    return res;
}

/// Append a string to a strarr
fn strarrAppend(arr: *arcan_strarr, s: [*c]u8) void {
    if (arr.data == null) return;
    if (arr.count + 1 >= arr.limit)
        arcan_mem_growarr(arr);
    arr.data[arr.count] = s;
    arr.count += 1;
}

/// Setup default DDL (create arcan + arcan_lwa appl groups with dbversion)
fn setup_ddl(dbh: *arcan_dbh) void {
    _ = arcan_db_appl_kv_internal(dbh, "arcan", "dbversion", DB_VERSION_NUM);
    _ = arcan_db_appl_kv_internal(dbh, "arcan_lwa", "dbversion", DB_VERSION_NUM);
}

fn dbh_integrity_check(dbh: *arcan_dbh) bool {
    const state = getDbState(dbh) orelse return false;

    // Check if root map exists and has content
    const root_cursor_opt = state.db.rootCursor().readPath(void, &.{}) catch {
        arcan_warning("Empty database encountered (root readPath errored), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    };
    if (root_cursor_opt == null) {
        // Empty database — run DDL
        arcan_warning("Empty database encountered (root readPath null), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    }
    const root_cursor = root_cursor_opt.?;
    const root = DB.HashMap(.read_only).init(root_cursor) catch {
        arcan_warning("Empty database encountered (HashMap.init errored), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    };

    // Check dbversion in "arcan" appl
    const appl_map = getSubMapRO(root, "appl") orelse {
        arcan_warning("Empty database encountered (root has no 'appl' submap), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    };

    const arcan_map = getSubMapRO(appl_map, "arcan") orelse {
        arcan_warning("Empty database encountered (no 'appl/arcan' submap), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    };

    const val_ptr = mapGetStr(arcan_map, "dbversion");
    if (val_ptr == null) {
        arcan_warning("Empty database encountered (no 'appl/arcan/dbversion' key), running default DDL queries.\n");
        setup_ddl(dbh);
        return true;
    }

    const val_s = cstr(val_ptr);
    const vnum = std.fmt.parseInt(u64, val_s, 10) catch 0;
    arcan_mem_free(@ptrCast(val_ptr));

    switch (vnum) {
        0, 1, 2 => {
            arcan_warning("DB version (< 3) unsupported, rebuild necessary\n");
            return false;
        },
        3 => {
            arcan_warning("DB version (< 4) found, rebuild suggested\n");
        },
        else => {},
    }

    return true;
}

// Internal versions of appl_kv/appl_val (avoid export fn calling export fn)

fn arcan_db_appl_kv_internal(dbh: *arcan_dbh, applname: [*c]const u8, key: [*c]const u8, value: ?[*c]const u8) bool {
    // Note: in_transaction check removed — arcan_db_add_kvpair calls us
    // DURING a transaction when ttype == DVT_APPL, which is the normal path.

    if (applname == null or key == null)
        return false;

    const state = getDbState(dbh) orelse return false;
    const appl_s = cstr(applname);
    const key_s = cstr(key);
    if (appl_s.len == 0) return false;

    const root = ensureRootMap(state) catch return false;
    const appl_root = ensureSubMap(root, "appl") catch return false;
    const appl = ensureSubMap(appl_root, appl_s) catch return false;

    if (value) |v| {
        const val_s = cstr(v);
        if (val_s.len == 0) {
            // Delete: remove the key
            _ = appl.remove(hashKey(key_s)) catch {};
        } else {
            mapPutStr(appl, key_s, val_s);
        }
    } else {
        // Delete: remove the key
        _ = appl.remove(hashKey(key_s)) catch {};
    }

    return true;
}

fn arcan_db_appl_val_internal(dbh: *arcan_dbh, applname: [*c]const u8, key: [*c]const u8) [*c]u8 {
    if (key == null) return null;

    const state = getDbState(dbh) orelse return null;
    const appl_s = cstr(applname);
    const key_s = cstr(key);

    const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return null) orelse return null;
    const root = DB.HashMap(.read_only).init(root_cursor) catch return null;
    const appl_root = getSubMapRO(root, "appl") orelse return null;
    const appl = getSubMapRO(appl_root, appl_s) orelse return null;

    return mapGetStr(appl, key_s);
}

// Exported functions

export fn arcan_db_get_shared(dappl: ?*[*c]const u8) ?*arcan_dbh {
    if (dappl) |d| d.* = ARCAN_TBL;
    return shared_handle;
}

export fn arcan_db_set_shared(new: ?*arcan_dbh) void {
    shared_handle = new;
}

export fn arcan_db_dropappl(dbh_opt: ?*arcan_dbh, appl: [*c]const u8) void {
    const dbh = dbh_opt orelse return;
    if (appl == null) return;

    const appl_s = cstr(appl);
    if (appl_s.len == 0) return;

    const state = getDbState(dbh) orelse return;
    const root = ensureRootMap(state) catch return;
    const appl_root = ensureSubMap(root, "appl") catch return;

    // Remove all keys in the appl's map by removing the entire appl entry and recreating empty
    _ = appl_root.remove(hashKey(appl_s)) catch {};

    if (std.mem.eql(u8, appl_s, ARCAN_TBL)) {
        _ = arcan_db_appl_kv_internal(dbh, ARCAN_TBL, "dbversion", DB_VERSION_NUM);
    }
}

export fn arcan_db_verifytarget(dbh_opt: ?*arcan_dbh, id: arcan_targetid) bool {
    const dbh = dbh_opt orelse return false;
    const state = getDbState(dbh) orelse return false;

    const name = getTargetNameById(state, id) orelse return false;
    const target = getTargetByName(state, name) orelse return false;
    _ = target;
    return true;
}

export fn arcan_db_targetid(dbh_opt: ?*arcan_dbh, identifier: [*c]const u8, defid: ?*arcan_configid) arcan_targetid {
    _ = defid;
    const dbh = dbh_opt orelse return BAD_TARGET;
    const state = getDbState(dbh) orelse return BAD_TARGET;

    const name = cstr(identifier);
    if (name.len == 0) return BAD_TARGET;

    // Look up target by name, get its stored ID
    const target = getTargetByName(state, name) orelse return BAD_TARGET;
    const id = mapGetUint(target, "_id") orelse return BAD_TARGET;
    return @intCast(id);
}

export fn arcan_db_list_appl(dbh_opt: ?*arcan_dbh) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return empty) orelse return empty;
    const root = DB.HashMap(.read_only).init(root_cursor) catch return empty;
    const appl_root = getSubMapRO(root, "appl") orelse return empty;

    var res = initStrarr();

    // Iterate all keys in appl_root
    var iter = appl_root.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        const key_obj = kv.key_cursor.readBytes(&key_buf) catch continue;
        // Return as "appl_<name>" to match SQLite table naming
        var name_buf: [256]u8 = undefined;
        const full_name = std.fmt.bufPrint(&name_buf, "appl_{s}", .{key_obj}) catch continue;
        strarrAppend(&res, allocCStr(full_name));
    }

    return res;
}

export fn arcan_db_config_argv(dbh_opt: ?*arcan_dbh, id: arcan_configid) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const info = getConfigInfoById(state, id) orelse return empty;
    const target = getTargetByName(state, info.target_name) orelse return empty;
    const configs = getSubMapRO(target, "configs") orelse return empty;
    const config = getSubMapRO(configs, info.name) orelse return empty;

    return collectArgv(config);
}

export fn arcan_db_target_argv(dbh_opt: ?*arcan_dbh, id: arcan_targetid) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const name = getTargetNameById(state, id) orelse return empty;
    const target = getTargetByName(state, name) orelse return empty;

    return collectArgv(target);
}

/// Collect argv.0, argv.1, ... from a HashMap into a strarr
fn collectArgv(map: DB.HashMap(.read_only)) arcan_strarr {
    var res = initStrarr();
    var i: u64 = 0;
    while (true) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "argv.{d}", .{i}) catch break;
        const val = mapGetStr(map, key);
        if (val == null) break;
        strarrAppend(&res, val);
    }
    return res;
}

export fn arcan_db_cfgtarget(dbh_opt: ?*arcan_dbh, cfg: arcan_configid) arcan_targetid {
    const dbh = dbh_opt orelse return BAD_TARGET;
    const state = getDbState(dbh) orelse return BAD_TARGET;

    const info = getConfigInfoById(state, cfg) orelse return BAD_TARGET;
    // Look up the target ID by name
    const target = getTargetByName(state, info.target_name) orelse return BAD_TARGET;
    const id = mapGetUint(target, "_id") orelse return BAD_TARGET;
    return @intCast(id);
}

export fn arcan_db_configid(dbh_opt: ?*arcan_dbh, target: arcan_targetid, config: [*c]const u8) arcan_configid {
    const dbh = dbh_opt orelse return BAD_CONFIG;
    const state = getDbState(dbh) orelse return BAD_CONFIG;

    const tgt_name = getTargetNameById(state, target) orelse return BAD_CONFIG;
    const tgt = getTargetByName(state, tgt_name) orelse return BAD_CONFIG;
    const configs = getSubMapRO(tgt, "configs") orelse return BAD_CONFIG;
    const cfg_name = cstr(config);
    const cfg = getSubMapRO(configs, cfg_name) orelse return BAD_CONFIG;
    const id = mapGetUint(cfg, "_id") orelse return BAD_CONFIG;
    return @intCast(id);
}

export fn arcan_db_target_tags(dbh_opt: ?*arcan_dbh) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const targets = getTargetsMap(state, false) orelse return empty;

    var res = initStrarr();
    // Collect unique tags — use a simple linear scan for dedup (targets are few)
    var seen_count: usize = 0;
    var seen_buf: [256][64]u8 = undefined;

    var iter = targets.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        // value_cursor points to the target sub-map
        const tgt_map = DB.HashMap(.read_only).init(kv.value_cursor) catch continue;
        const tag_ptr = mapGetStr(tgt_map, "tag");
        if (tag_ptr == null) continue;
        const tag_s = cstr(tag_ptr);

        // Dedup check
        var found = false;
        for (seen_buf[0..seen_count]) |*s| {
            const seen_s = std.mem.sliceTo(s, 0);
            if (std.mem.eql(u8, seen_s, tag_s)) {
                found = true;
                break;
            }
        }
        if (!found and seen_count < seen_buf.len) {
            @memcpy(seen_buf[seen_count][0..tag_s.len], tag_s);
            if (tag_s.len < 64) seen_buf[seen_count][tag_s.len] = 0;
            seen_count += 1;
            strarrAppend(&res, strdup(tag_ptr));
        } else {
            arcan_mem_free(@ptrCast(tag_ptr));
        }
    }

    return res;
}

export fn arcan_db_targets(dbh_opt: ?*arcan_dbh, tag: [*c]const u8) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const targets = getTargetsMap(state, false) orelse return empty;

    var res = initStrarr();
    const filter_tag = if (tag != null) cstr(tag) else null;

    var iter = targets.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        const key_bytes = kv.key_cursor.readBytes(&key_buf) catch continue;
        const name = key_bytes;

        if (filter_tag) |ft| {
            // Check tag matches
            const tgt_map = DB.HashMap(.read_only).init(kv.value_cursor) catch continue;
            const t = mapGetStr(tgt_map, "tag");
            if (t == null) continue;
            const ts = cstr(t);
            const match = std.mem.eql(u8, ts, ft);
            arcan_mem_free(@ptrCast(t));
            if (!match) continue;
        }

        strarrAppend(&res, allocCStr(name));
    }

    return res;
}

export fn arcan_db_targettag(dbh_opt: ?*arcan_dbh, tid: arcan_targetid) [*c]u8 {
    const dbh = dbh_opt orelse return null;
    const state = getDbState(dbh) orelse return null;

    const name = getTargetNameById(state, tid) orelse return null;
    const target = getTargetByName(state, name) orelse return null;
    return mapGetStr(target, "tag");
}

export fn arcan_db_targetexec(
    dbh_opt: ?*arcan_dbh,
    configid: arcan_configid,
    bfmt: *c_int,
    argv: *arcan_strarr,
    env: *arcan_strarr,
    libs: *arcan_strarr,
) [*c]u8 {
    const dbh = dbh_opt orelse return null;
    const state = getDbState(dbh) orelse return null;

    const tid = arcan_db_cfgtarget(dbh, configid);
    if (tid == BAD_TARGET) return null;

    const tgt_name = getTargetNameById(state, tid) orelse return null;
    const target = getTargetByName(state, tgt_name) orelse return null;

    // Get executable and bfmt
    const execstr = mapGetStr(target, "executable");
    const bfmt_val = mapGetUint(target, "bfmt");
    if (bfmt_val) |b| bfmt.* = @intCast(b);

    // Target argv (index 0 is executable)
    argv.* = initStrarr();
    strarrAppend(argv, if (execstr != null) strdup(execstr) else allocCStr(""));
    {
        const tgt_argv = collectArgv(target);
        var i: usize = 0;
        while (i < tgt_argv.count) : (i += 1) {
            strarrAppend(argv, tgt_argv.data[i]);
        }
    }

    // Config argv
    {
        const info = getConfigInfoById(state, configid) orelse return execstr;
        const configs = getSubMapRO(target, "configs") orelse return execstr;
        const config = getSubMapRO(configs, info.name) orelse return execstr;
        const cfg_argv = collectArgv(config);
        var i: usize = 0;
        while (i < cfg_argv.count) : (i += 1) {
            strarrAppend(argv, cfg_argv.data[i]);
        }
    }

    // Target env
    env.* = collectEnv(target);

    // Config env
    {
        const info = getConfigInfoById(state, configid) orelse return execstr;
        const configs = getSubMapRO(target, "configs") orelse return execstr;
        const config = getSubMapRO(configs, info.name) orelse return execstr;
        const cfg_env = collectEnv(config);
        var i: usize = 0;
        while (i < cfg_env.count) : (i += 1) {
            strarrAppend(env, cfg_env.data[i]);
        }
    }

    // Target libs
    libs.* = collectLibs(target);

    return execstr;
}

/// Collect env entries as "key=val" strings
fn collectEnv(map: DB.HashMap(.read_only)) arcan_strarr {
    var res = initStrarr();
    const env_map = getSubMapRO(map, "env") orelse return res;

    var iter = env_map.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        var val_buf: [4096]u8 = undefined;
        const key_bytes = kv.key_cursor.readBytes(&key_buf) catch continue;
        const val_bytes = kv.value_cursor.readBytes(&val_buf) catch continue;
        // Format as "key=val"
        var fmt_buf: [4352]u8 = undefined;
        const s = std.fmt.bufPrint(&fmt_buf, "{s}={s}", .{ key_bytes, val_bytes }) catch continue;
        strarrAppend(&res, allocCStr(s));
    }

    return res;
}

/// Collect libs.0, libs.1, ... from a HashMap into a strarr
fn collectLibs(map: DB.HashMap(.read_only)) arcan_strarr {
    var res = initStrarr();
    var i: u64 = 0;
    while (true) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "libs.{d}", .{i}) catch break;
        const val = mapGetStr(map, key);
        if (val == null) break;
        strarrAppend(&res, val);
    }
    return res;
}

export fn arcan_db_launch_status(dbh_opt: ?*arcan_dbh, cid: arcan_configid, s: bool) void {
    const dbh = dbh_opt orelse return;
    const state = getDbState(dbh) orelse return;

    const info = getConfigInfoById(state, cid) orelse return;
    const targets = getTargetsMap(state, true) orelse return;
    const target = getSubMapRW(targets, info.target_name) orelse return;
    const configs = getSubMapRW(target, "configs") orelse return;
    const config = getSubMapRW(configs, info.name) orelse return;

    const counter_key = if (s) "passed" else "failed";
    const current = mapGetUint(config, counter_key) orelse 0;
    mapPutUint(config, counter_key, current + 1);
}

export fn arcan_db_configs(dbh_opt: ?*arcan_dbh, tid: arcan_targetid) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const tgt_name = getTargetNameById(state, tid) orelse return empty;
    const target = getTargetByName(state, tgt_name) orelse return empty;
    const configs = getSubMapRO(target, "configs") orelse return empty;

    var res = initStrarr();
    var iter = configs.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        const key_bytes = kv.key_cursor.readBytes(&key_buf) catch continue;
        strarrAppend(&res, allocCStr(key_bytes));
    }

    return res;
}

export fn arcan_db_execname(dbh_opt: ?*arcan_dbh, tid: arcan_targetid) [*c]u8 {
    const dbh = dbh_opt orelse return null;
    const state = getDbState(dbh) orelse return null;

    const name = getTargetNameById(state, tid) orelse return null;
    const target = getTargetByName(state, name) orelse return null;
    return mapGetStr(target, "executable");
}

export fn arcan_db_begin_transaction(dbh_opt: ?*arcan_dbh, kvt: c_int, id: arcan_dbtrans_id) void {
    const dbh = dbh_opt orelse return;
    if (dbh.in_transaction)
        arcan_fatal("arcan_db_begin_transaction() called during a pending transaction\n");

    dbh.trid = id;
    dbh.ttype = kvt;
    dbh.in_transaction = true;
    dbh.trclean = false;
}

export fn arcan_db_getkeys(dbh_opt: ?*arcan_dbh, tgt: c_int, id: arcan_dbtrans_id) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    // Get the appropriate kv map
    const kv_map = blk: {
        if (tgt >= DVT_TARGET and tgt < DVT_CONFIG) {
            const tgt_name = getTargetNameById(state, id.tid) orelse return empty;
            const target = getTargetByName(state, tgt_name) orelse return empty;
            break :blk getSubMapRO(target, "kv") orelse return empty;
        } else {
            const info = getConfigInfoById(state, id.cid) orelse return empty;
            const target = getTargetByName(state, info.target_name) orelse return empty;
            const configs = getSubMapRO(target, "configs") orelse return empty;
            const config = getSubMapRO(configs, info.name) orelse return empty;
            break :blk getSubMapRO(config, "kv") orelse return empty;
        }
    };

    var res = initStrarr();
    var iter = kv_map.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        var val_buf: [4096]u8 = undefined;
        const key_bytes = kv.key_cursor.readBytes(&key_buf) catch continue;
        const val_bytes = kv.value_cursor.readBytes(&val_buf) catch continue;
        var fmt_buf: [4352]u8 = undefined;
        const s = std.fmt.bufPrint(&fmt_buf, "{s}={s}", .{ key_bytes, val_bytes }) catch continue;
        strarrAppend(&res, allocCStr(s));
    }

    return res;
}

export fn arcan_db_applkeys(dbh_opt: ?*arcan_dbh, applname: [*c]const u8, pattern: [*c]const u8) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const appl_s = cstr(applname);
    const pat_s = cstr(pattern);

    const root_cursor = (state.db.rootCursor().readPath(void, &.{}) catch return empty) orelse return empty;
    const root = DB.HashMap(.read_only).init(root_cursor) catch return empty;
    const appl_root = getSubMapRO(root, "appl") orelse return empty;
    const appl = getSubMapRO(appl_root, appl_s) orelse return empty;

    var res = initStrarr();
    var iter = appl.iterator() catch return res;
    while (iter.next() catch null) |kv_cursor| {
        const kv = kv_cursor.readKeyValuePair() catch continue;
        var key_buf: [256]u8 = undefined;
        var val_buf: [4096]u8 = undefined;
        const key_bytes = kv.key_cursor.readBytes(&key_buf) catch continue;
        const val_bytes = kv.value_cursor.readBytes(&val_buf) catch continue;

        // Pattern matching: SQL LIKE — convert '%' wildcards to substring match
        if (matchLikePattern(pat_s, key_bytes)) {
            var fmt_buf: [4352]u8 = undefined;
            const s = std.fmt.bufPrint(&fmt_buf, "{s}={s}", .{ key_bytes, val_bytes }) catch continue;
            strarrAppend(&res, allocCStr(s));
        }
    }

    return res;
}

/// Simple SQL LIKE pattern matching (supports % and _ wildcards)
fn matchLikePattern(pattern: []const u8, text: []const u8) bool {
    var pi: usize = 0;
    var ti: usize = 0;
    var star_pi: ?usize = null;
    var star_ti: usize = 0;

    while (ti < text.len) {
        if (pi < pattern.len and (pattern[pi] == '_' or std.ascii.toLower(pattern[pi]) == std.ascii.toLower(text[ti]))) {
            pi += 1;
            ti += 1;
        } else if (pi < pattern.len and pattern[pi] == '%') {
            star_pi = pi;
            star_ti = ti;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_ti += 1;
            ti = star_ti;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '%') : (pi += 1) {}
    return pi == pattern.len;
}

export fn arcan_db_matchkey(dbh_opt: ?*arcan_dbh, tgt: c_int, pattern: [*c]const u8) arcan_strarr {
    const empty: arcan_strarr = .{ .count = 0, .limit = 0, .data = null };
    const dbh = dbh_opt orelse return empty;
    const state = getDbState(dbh) orelse return empty;

    const pat_s = cstr(pattern);
    const targets = getTargetsMap(state, false) orelse return empty;

    var res = initStrarr();

    if (tgt >= DVT_TARGET and tgt < DVT_CONFIG) {
        // Search target_kv
        var tgt_iter = targets.iterator() catch return res;
        while (tgt_iter.next() catch null) |tgt_kv_cursor| {
            const tgt_kv = tgt_kv_cursor.readKeyValuePair() catch continue;
            const tgt_map = DB.HashMap(.read_only).init(tgt_kv.value_cursor) catch continue;
            const tgt_id = mapGetUint(tgt_map, "_id") orelse continue;
            const kv = getSubMapRO(tgt_map, "kv") orelse continue;

            var kv_iter = kv.iterator() catch continue;
            while (kv_iter.next() catch null) |entry_cursor| {
                const entry = entry_cursor.readKeyValuePair() catch continue;
                var key_buf: [256]u8 = undefined;
                var val_buf: [4096]u8 = undefined;
                const key_bytes = entry.key_cursor.readBytes(&key_buf) catch continue;
                const val_bytes = entry.value_cursor.readBytes(&val_buf) catch continue;

                if (matchLikePattern(pat_s, key_bytes)) {
                    var fmt_buf: [4352]u8 = undefined;
                    const s = std.fmt.bufPrint(&fmt_buf, "{d}:{s}", .{ tgt_id, val_bytes }) catch continue;
                    strarrAppend(&res, allocCStr(s));
                }
            }
        }
    } else {
        // Search config_kv
        var tgt_iter = targets.iterator() catch return res;
        while (tgt_iter.next() catch null) |tgt_kv_cursor| {
            const tgt_kv = tgt_kv_cursor.readKeyValuePair() catch continue;
            const tgt_map = DB.HashMap(.read_only).init(tgt_kv.value_cursor) catch continue;
            const configs = getSubMapRO(tgt_map, "configs") orelse continue;

            var cfg_iter = configs.iterator() catch continue;
            while (cfg_iter.next() catch null) |cfg_kv_cursor| {
                const cfg_kv = cfg_kv_cursor.readKeyValuePair() catch continue;
                const cfg_map = DB.HashMap(.read_only).init(cfg_kv.value_cursor) catch continue;
                const cfg_id = mapGetUint(cfg_map, "_id") orelse continue;
                const kv = getSubMapRO(cfg_map, "kv") orelse continue;

                var kv_iter = kv.iterator() catch continue;
                while (kv_iter.next() catch null) |entry_cursor| {
                    const entry = entry_cursor.readKeyValuePair() catch continue;
                    var key_buf: [256]u8 = undefined;
                    var val_buf: [4096]u8 = undefined;
                    const key_bytes = entry.key_cursor.readBytes(&key_buf) catch continue;
                    const val_bytes = entry.value_cursor.readBytes(&val_buf) catch continue;

                    if (matchLikePattern(pat_s, key_bytes)) {
                        var fmt_buf: [4352]u8 = undefined;
                        const s = std.fmt.bufPrint(&fmt_buf, "{d}:{s}", .{ cfg_id, val_bytes }) catch continue;
                        strarrAppend(&res, allocCStr(s));
                    }
                }
            }
        }
    }

    return res;
}

export fn arcan_db_getvalue(dbh_opt: ?*arcan_dbh, tgt: c_int, id: i64, key: [*c]const u8) [*c]u8 {
    const dbh = dbh_opt orelse return null;
    const state = getDbState(dbh) orelse return null;

    const key_s = cstr(key);

    if (tgt == DVT_APPL) {
        return arcan_db_appl_val_internal(dbh, dbh.applname, key);
    } else if (tgt >= DVT_TARGET and tgt < DVT_CONFIG) {
        const tgt_name = getTargetNameById(state, @intCast(id)) orelse return null;
        const target = getTargetByName(state, tgt_name) orelse return null;
        const kv = getSubMapRO(target, "kv") orelse return null;
        return mapGetStr(kv, key_s);
    } else {
        const info = getConfigInfoById(state, @intCast(id)) orelse return null;
        const target = getTargetByName(state, info.target_name) orelse return null;
        const configs = getSubMapRO(target, "configs") orelse return null;
        const config = getSubMapRO(configs, info.name) orelse return null;
        const kv = getSubMapRO(config, "kv") orelse return null;
        return mapGetStr(kv, key_s);
    }
}

export fn arcan_db_add_kvpair(dbh_opt: ?*arcan_dbh, key: [*c]const u8, val: [*c]const u8) void {
    const dbh = dbh_opt orelse return;
    if (!dbh.in_transaction)
        arcan_fatal("arcan_db_add_kvpair() called without any open transaction.");

    const state = getDbState(dbh) orelse return;

    if (val == null) {
        dbh.trclean = true;
        return;
    }

    const val_s = cstr(val);
    if (val_s.len == 0)
        dbh.trclean = true;

    const key_s = cstr(key);

    if (dbh.ttype == DVT_APPL) {
        _ = arcan_db_appl_kv_internal(dbh, dbh.applname, key, val);
    } else if (dbh.ttype == DVT_TARGET or dbh.ttype == DVT_TARGET_ENV or dbh.ttype == DVT_TARGET_LIBV) {
        const tgt_name = getTargetNameById(state, dbh.trid.tid) orelse return;
        const targets = getTargetsMap(state, true) orelse return;
        const target = getSubMapRW(targets, tgt_name) orelse return;

        if (dbh.ttype == DVT_TARGET) {
            const kv = ensureSubMap(target, "kv") catch return;
            mapPutStr(kv, key_s, val_s);
        } else if (dbh.ttype == DVT_TARGET_ENV) {
            const env = ensureSubMap(target, "env") catch return;
            mapPutStr(env, key_s, val_s);
        } else if (dbh.ttype == DVT_TARGET_LIBV) {
            const libs_map = ensureSubMap(target, "libs_kv") catch return;
            mapPutStr(libs_map, key_s, val_s);
        }
    } else if (dbh.ttype == DVT_CONFIG or dbh.ttype == DVT_CONFIG_ENV) {
        const info = getConfigInfoById(state, dbh.trid.cid) orelse return;
        const targets = getTargetsMap(state, true) orelse return;
        const target = getSubMapRW(targets, info.target_name) orelse return;
        const configs = ensureSubMap(target, "configs") catch return;
        const config = ensureSubMap(configs, info.name) catch return;

        if (dbh.ttype == DVT_CONFIG) {
            const kv = ensureSubMap(config, "kv") catch return;
            mapPutStr(kv, key_s, val_s);
        } else {
            const env = ensureSubMap(config, "env") catch return;
            mapPutStr(env, key_s, val_s);
        }
    }
}

export fn arcan_db_end_transaction(dbh_opt: ?*arcan_dbh) void {
    const dbh = dbh_opt orelse return;
    if (!dbh.in_transaction)
        arcan_fatal("arcan_db_end_transaction() called without any open transaction.");

    const state = getDbState(dbh) orelse {
        dbh.in_transaction = false;
        return;
    };

    if (dbh.trclean) {
        // Remove empty-value entries — for xitdb, keys with empty values
        // were already stored. Clean them up.
        cleanEmptyValues(state, dbh) catch {};
        dbh.trclean = false;
    }

    dbh.in_transaction = false;
}

fn cleanEmptyValues(state: *DbState, dbh: *arcan_dbh) !void {
    if (dbh.ttype == DVT_APPL) {
        // Clean empty values in the current appl's kv store
        const appl_s = cstr(dbh.applname);
        const root = try ensureRootMap(state);
        const appl_root = try ensureSubMap(root, "appl");
        const appl = try ensureSubMap(appl_root, appl_s);
        try removeEmptyValuesFromMap(appl);
    } else if (dbh.ttype == DVT_TARGET) {
        const tgt_name = getTargetNameById(state, dbh.trid.tid) orelse return;
        const targets = getTargetsMap(state, true) orelse return;
        const target = getSubMapRW(targets, tgt_name) orelse return;
        if (getSubMapRW(target, "kv")) |kv| {
            removeEmptyValuesFromMap(kv) catch {};
        }
    } else if (dbh.ttype == DVT_CONFIG) {
        const info = getConfigInfoById(state, dbh.trid.cid) orelse return;
        const targets = getTargetsMap(state, true) orelse return;
        const target = getSubMapRW(targets, info.target_name) orelse return;
        if (getSubMapRW(target, "configs")) |configs| {
            if (getSubMapRW(configs, info.name)) |config| {
                if (getSubMapRW(config, "kv")) |kv| {
                    removeEmptyValuesFromMap(kv) catch {};
                }
            }
        }
    }
}

fn removeEmptyValuesFromMap(map: DB.HashMap(.read_write)) !void {
    // Collect hashes of empty-value entries, then remove them
    var to_remove: [256]HashInt = undefined;
    var remove_count: usize = 0;

    const ro_map = map.readOnly();
    var iter = try ro_map.iterator();
    while (try iter.next()) |kv_cursor| {
        const kv = try kv_cursor.readKeyValuePair();
        var val_buf: [4096]u8 = undefined;
        const val_bytes = kv.value_cursor.readBytes(&val_buf) catch continue;
        if (val_bytes.len == 0 and remove_count < to_remove.len) {
            to_remove[remove_count] = kv.hash;
            remove_count += 1;
        }
    }

    for (to_remove[0..remove_count]) |h| {
        _ = map.remove(h) catch {};
    }
}

export fn arcan_db_appl_kv(dbh_opt: ?*arcan_dbh, applname: [*c]const u8, key: [*c]const u8, value: [*c]const u8) bool {
    const dbh = dbh_opt orelse return false;
    return arcan_db_appl_kv_internal(dbh, applname, key, value);
}

export fn arcan_db_appl_val(dbh_opt: ?*arcan_dbh, applname: [*c]const u8, key: [*c]const u8) [*c]u8 {
    const dbh = dbh_opt orelse return null;
    return arcan_db_appl_val_internal(dbh, applname, key);
}

export fn arcan_db_close(ctx: ?*?*arcan_dbh) void {
    const ptr = ctx orelse return;
    const dbh = ptr.* orelse return;

    if (getDbState(dbh)) |state| {
        if (!is_freestanding) {
            state.file.close();
            _ = state.gpa.deinit();
        } else {
            state.mem_buffer.deinit();
        }
    }

    arcan_mem_free(@ptrCast(dbh.applname));
    arcan_mem_free(dbh.state);
    arcan_mem_free(@ptrCast(@as(?*anyopaque, @ptrCast(dbh))));
    ptr.* = null;
}

export fn arcan_db_open(fname: [*c]const u8, applname_arg: [*c]const u8) ?*arcan_dbh {
    if (fname == null) return null;

    db_init = true;

    const applname: [*c]const u8 = if (applname_arg != null) applname_arg else "_default";

    // Allocate DbState via GPA
    const state_ptr = arcan_alloc_mem(
        @sizeOf(DbState),
        ARCAN_MEM_EXTSTRUCT,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_PAGE,
    ) orelse return null;
    const state: *DbState = @ptrCast(@alignCast(state_ptr));

    // Initialize xitdb
    if (is_freestanding) {
        state.fba_buf = @splat(0);
        state.fba = std.heap.FixedBufferAllocator.init(&state.fba_buf);
        state.mem_buffer = std.Io.Writer.Allocating.init(state.fba.allocator());
        state.db = DB.init(.{
            .buffer = &state.mem_buffer,
            .max_size = 64 * 1024, // 64KB max for freestanding
        }) catch {
            arcan_mem_free(state_ptr);
            return null;
        };
    } else {
        state.gpa = .init;
        const fname_s = cstr(fname);
        // Open existing file or create new one
        const file = std.fs.cwd().openFile(fname_s, .{ .mode = .read_write }) catch
            std.fs.cwd().createFile(fname_s, .{ .read = true }) catch {
            arcan_mem_free(state_ptr);
            return null;
        };
        state.file = file;
        state.db = DB.init(.{ .file = file }) catch {
            file.close();
            arcan_mem_free(state_ptr);
            return null;
        };
    }

    return openFinalize(state, state_ptr, applname);
}

fn openFinalize(_: *DbState, state_ptr: ?*anyopaque, applname: [*c]const u8) ?*arcan_dbh {
    // Allocate arcan_dbh
    const dbh_ptr = arcan_alloc_mem(
        @sizeOf(arcan_dbh),
        ARCAN_MEM_EXTSTRUCT,
        ARCAN_MEM_SENSITIVE | ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_PAGE,
    ) orelse {
        arcan_mem_free(state_ptr);
        return null;
    };

    const res: *arcan_dbh = @ptrCast(@alignCast(dbh_ptr));
    res.state = state_ptr;
    res.in_transaction = false;

    if (!dbh_integrity_check(res)) {
        arcan_mem_free(state_ptr);
        arcan_mem_free(dbh_ptr);
        return null;
    }

    res.applname = strdup(applname);

    return res;
}

// ARCAN_DB_STANDALONE functions (used by arcan_db tool)

export fn arcan_db_droptarget(dbh_opt: ?*arcan_dbh, id: arcan_targetid) bool {
    const dbh = dbh_opt orelse return false;
    const state = getDbState(dbh) orelse return false;

    const name = getTargetNameById(state, id) orelse return false;

    // Remove from targets map
    const targets = getTargetsMap(state, true) orelse return false;
    _ = targets.remove(hashKey(name)) catch return false;

    // Remove ID mapping
    const root = ensureRootMap(state) catch return false;
    const ids_map = ensureSubMap(root, "target_ids") catch return false;
    var buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&buf, "{d}", .{id}) catch return false;
    _ = ids_map.remove(hashKey(id_str)) catch return false;

    return true;
}

export fn arcan_db_dropconfig(dbh_opt: ?*arcan_dbh, id: arcan_configid) bool {
    const dbh = dbh_opt orelse return false;
    const state = getDbState(dbh) orelse return false;

    const info = getConfigInfoById(state, id) orelse return false;

    // Remove from configs sub-map
    const targets = getTargetsMap(state, true) orelse return false;
    const target = getSubMapRW(targets, info.target_name) orelse return false;
    const configs = getSubMapRW(target, "configs") orelse return false;
    _ = configs.remove(hashKey(info.name)) catch return false;

    // Remove config ID mapping
    const root = ensureRootMap(state) catch return false;
    const cids_map = ensureSubMap(root, "config_ids") catch return false;
    var buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&buf, "{d}", .{id}) catch return false;
    _ = cids_map.remove(hashKey(id_str)) catch return false;

    return true;
}

export fn arcan_db_addtarget(
    dbh_opt: ?*arcan_dbh,
    identifier: [*c]const u8,
    group: [*c]const u8,
    exec: [*c]const u8,
    argv_arr: [*c]const [*c]const u8,
    sz: usize,
    bfmt: c_int,
) arcan_targetid {
    const dbh = dbh_opt orelse return BAD_TARGET;
    const state = getDbState(dbh) orelse return BAD_TARGET;

    const name = cstr(identifier);
    if (name.len == 0) return BAD_TARGET;

    const root = ensureRootMap(state) catch return BAD_TARGET;
    const targets = ensureSubMap(root, "targets") catch return BAD_TARGET;

    // Check if target already exists — reuse ID
    var newid: u64 = undefined;
    const existing = getSubMapRO(targets.readOnly(), name);
    if (existing) |ex| {
        newid = mapGetUint(ex, "_id") orelse blk: {
            const next = mapGetUint(root.readOnly(), "_next_target_id") orelse 1;
            mapPutUint(root, "_next_target_id", next + 1);
            break :blk next;
        };
    } else {
        // Allocate new ID
        const next = mapGetUint(root.readOnly(), "_next_target_id") orelse 1;
        mapPutUint(root, "_next_target_id", next + 1);
        newid = next;
    }

    // Create/update target entry
    const target = ensureSubMap(targets, name) catch return BAD_TARGET;
    mapPutUint(target, "_id", newid);
    mapPutStr(target, "tag", cstr(group));
    mapPutStr(target, "executable", cstr(exec));
    mapPutUint(target, "bfmt", @intCast(bfmt));

    // Store ID → name mapping
    const ids_map = ensureSubMap(root, "target_ids") catch return BAD_TARGET;
    var id_buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{newid}) catch return BAD_TARGET;
    mapPutStr(ids_map, id_str, name);

    // Delete previous argv entries. xitdb.HashMap.remove returns !bool
    // where `false` means "key not found" (no error); loop MUST break on
    // `false` or it spins forever since every `argv.<i>` past the last
    // stored index also returns `false`.
    var i: u64 = 0;
    while (true) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "argv.{d}", .{i}) catch break;
        const removed = target.remove(hashKey(key)) catch break;
        if (!removed) break;
    }

    // Add new argv
    for (0..sz) |j| {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "argv.{d}", .{j}) catch break;
        const arg = cstr(argv_arr[j]);
        mapPutStr(target, key, arg);
    }

    return @intCast(newid);
}

export fn arcan_db_addconfig(
    dbh_opt: ?*arcan_dbh,
    id: arcan_targetid,
    identifier: [*c]const u8,
    argv_arr: [*c]const [*c]const u8,
    sz: usize,
) arcan_configid {
    if (!arcan_db_verifytarget(dbh_opt, id))
        return BAD_CONFIG;

    const dbh = dbh_opt.?;
    const state = getDbState(dbh) orelse return BAD_CONFIG;

    const tgt_name = getTargetNameById(state, id) orelse return BAD_CONFIG;
    const cfg_name = cstr(identifier);

    const root = ensureRootMap(state) catch return BAD_CONFIG;
    const targets = ensureSubMap(root, "targets") catch return BAD_CONFIG;
    const target = ensureSubMap(targets, tgt_name) catch return BAD_CONFIG;
    const configs = ensureSubMap(target, "configs") catch return BAD_CONFIG;
    const config = ensureSubMap(configs, cfg_name) catch return BAD_CONFIG;

    // Allocate config ID
    const next_cid = mapGetUint(root.readOnly(), "_next_config_id") orelse 1;
    mapPutUint(root, "_next_config_id", next_cid + 1);
    mapPutUint(config, "_id", next_cid);
    mapPutUint(config, "passed", 0);
    mapPutUint(config, "failed", 0);

    // Store config ID → "target_name\x00config_name" mapping
    const cids_map = ensureSubMap(root, "config_ids") catch return BAD_CONFIG;
    var id_buf: [32]u8 = undefined;
    const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{next_cid}) catch return BAD_CONFIG;
    // Build "target_name\x00config_name" value
    var val_buf: [512]u8 = undefined;
    if (tgt_name.len + 1 + cfg_name.len > val_buf.len) return BAD_CONFIG;
    @memcpy(val_buf[0..tgt_name.len], tgt_name);
    val_buf[tgt_name.len] = 0;
    @memcpy(val_buf[tgt_name.len + 1 ..][0..cfg_name.len], cfg_name);
    const val_slice = val_buf[0 .. tgt_name.len + 1 + cfg_name.len];
    const h = hashKey(id_str);
    cids_map.put(h, .{ .bytes = val_slice }) catch return BAD_CONFIG;
    cids_map.putKey(h, .{ .bytes = id_str }) catch return BAD_CONFIG;

    // Delete previous argv entries (see arcan_db_addtarget for remove's
    // return-value contract).
    var i: u64 = 0;
    while (true) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "argv.{d}", .{i}) catch break;
        const removed = config.remove(hashKey(key)) catch break;
        if (!removed) break;
    }

    // Add new argv
    for (0..sz) |j| {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "argv.{d}", .{j}) catch break;
        const arg = cstr(argv_arr[j]);
        mapPutStr(config, key, arg);
    }

    return @intCast(next_cid);
}
