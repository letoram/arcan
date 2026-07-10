// lunix.zig — Lua Unix bindings backed by seL4 capabilities
//
// Runs in the seL4 root task (EL2, single address space). Has direct access
// to kernel functions — no userspace syscall trap needed.
//
// Architecture:
//   - FD table maps integer fds to CNode cap slots (endpoint/notification caps)
//   - fd 0/1/2 are hardwired to UART (via earlyPutc / sel4_libc read)
//   - pipe() creates a seL4 endpoint with read/write cap pair
//   - Filesystem ops send IPC to a well-known fs server endpoint
//   - fork/exec/kill/wait use TCB retype + notification signaling
//   - pledge/unveil manipulate CNode caps (revoke / mint restricted)

const std = @import("std");
extern fn earlyPutc(c: u8) void;

// ============================================================================
// seL4 kernel types (from sel4.zig / kernel_chunks)
// ============================================================================

const word_t = u64;
const bool_t = word_t;
const cptr_t = word_t;
const pptr_t = word_t;

const cap_t = extern struct {
    words: [2]u64 = .{ 0, 0 },

    fn get_capType(self: cap_t) u64 {
        return (self.words[0] >> 59) & 0x1f;
    }

    fn cap_null_cap_new() cap_t {
        return .{ .words = .{ @as(u64, cap_null_cap_tag) << 59, 0 } };
    }
};

const mdb_node_t = extern struct {
    words: [2]u64 = .{ 0, 0 },
};

const cte_t = extern struct {
    cap: cap_t = .{},
    cteMDBNode: mdb_node_t = .{},
};

const endpoint_t = extern struct {
    words: [4]u64 = .{ 0, 0, 0, 0 },
};

const notification_t = extern struct {
    words: [4]u64 = .{ 0, 0, 0, 0 },
};

const seL4_CapRights_t = extern struct {
    words: [1]u64 = .{0},

    fn new(grant_reply: u1, grant: u1, rd: u1, wr: u1) seL4_CapRights_t {
        return .{ .words = .{
            (@as(u64, grant_reply) << 3) |
                (@as(u64, grant) << 2) |
                (@as(u64, rd) << 1) |
                @as(u64, wr),
        } };
    }
};

const seL4_MessageInfo_t = extern struct {
    words: [1]u64 = .{0},

    fn new(label: u64, caps_unwrapped: u64, extra_caps: u64, length: u64) seL4_MessageInfo_t {
        return .{ .words = .{
            ((label & 0xFFFFFFFFFFFFF) << 12) |
                ((caps_unwrapped & 0x7) << 9) |
                ((extra_caps & 0x3) << 7) |
                (length & 0x7F),
        } };
    }

    fn get_label(self: seL4_MessageInfo_t) u64 {
        return (self.words[0] & 0xFFFFFFFFFFFFF000) >> 12;
    }

    fn get_length(self: seL4_MessageInfo_t) u64 {
        return self.words[0] & 0x7F;
    }
};

// Forward-declared opaque; actual struct is in sel4.zig
const tcb_t = opaque {};

const deriveCap_ret_t = extern struct {
    status: word_t = 0,
    cap: cap_t = .{},
};

// Cap tag constants
const cap_null_cap_tag: u5 = 0;
const cap_endpoint_cap_tag: u5 = 4;
const cap_notification_cap_tag: u5 = 6;
const cap_thread_cap_tag: u5 = 12;

// Object type constants (for createObject)
const seL4_TCBObject: word_t = 1;
const seL4_EndpointObject: word_t = 2;
const seL4_NotificationObject: word_t = 3;

// Object sizes in bits
const seL4_EndpointBits: u6 = 4; // 16 bytes
const seL4_NotificationBits: u6 = 6; // 64 bytes
const seL4_TCBBits: u6 = 11; // 2048 bytes

// Exception codes
const EXCEPTION_NONE: word_t = 0;

// Thread states
const ThreadState_Running: word_t = 1;
const ThreadState_Inactive: word_t = 0;

// ============================================================================
// seL4 kernel function externs
// ============================================================================

// CSpace
extern fn lookupCap(thread: *tcb_t, cPtr: cptr_t) callconv(.c) extern struct {
    status: word_t,
    cap: cap_t,
};
extern fn lookupCapAndSlot(thread: *tcb_t, cPtr: cptr_t) callconv(.c) extern struct {
    status: word_t,
    cap: cap_t,
    slot: ?*cte_t,
};

// CNode ops
extern fn cteInsert(newCap: cap_t, srcSlot: *cte_t, destSlot: *cte_t) callconv(.c) void;
extern fn cteDelete(slot: *cte_t, exposed: bool_t) callconv(.c) word_t;
extern fn cteRevoke(slot: *cte_t) callconv(.c) word_t;
extern fn cteDeleteOne(slot: *cte_t) callconv(.c) void;

// Object creation
extern fn createObject(t: word_t, regionBase: ?*anyopaque, userSize: word_t, deviceMemory: bool_t) callconv(.c) cap_t;

// IPC
extern fn sendIPC(blocking: bool_t, do_call: bool_t, badge: word_t, canGrant: bool_t, canGrantReply: bool_t, thread: *tcb_t, epptr: *endpoint_t) callconv(.c) void;
extern fn receiveIPC(thread: *tcb_t, cap: cap_t, isBlocking: bool_t) callconv(.c) void;

// Notifications
extern fn sendSignal(ntfnPtr: *notification_t, badge: word_t) callconv(.c) void;
extern fn receiveSignal(thread: *tcb_t, cap: cap_t, isBlocking: bool_t) callconv(.c) void;
extern fn bindNotification(tcb: *tcb_t, ntfnPtr: *notification_t) callconv(.c) void;

// Capability rights
extern fn maskCapRights(rights: seL4_CapRights_t, cap: cap_t) callconv(.c) cap_t;
extern fn deriveCap(slot: *cte_t, cap: cap_t) callconv(.c) deriveCap_ret_t;

// Thread control
extern fn setThreadState(tptr: *tcb_t, ts: word_t) callconv(.c) void;
extern fn scheduleTCB(tptr: *tcb_t) callconv(.c) void;
extern fn tcbSchedEnqueue(tcb: *tcb_t) callconv(.c) void;

// Globals
extern var ksCurThread: *tcb_t;

// sel4_libc / m1n1
extern fn read(fd: c_int, buf: [*]u8, count: usize) isize;

// ============================================================================
// Lua C API externs
// ============================================================================

extern fn lua_pushstring(L: *anyopaque, s: [*:0]const u8) [*:0]const u8;
extern fn lua_pushlstring(L: *anyopaque, s: [*]const u8, len: usize) [*]const u8;
extern fn lua_pushinteger(L: *anyopaque, n: i64) void;
extern fn lua_pushboolean(L: *anyopaque, b: c_int) void;
extern fn lua_pushnil(L: *anyopaque) void;
extern fn lua_settable(L: *anyopaque, idx: c_int) void;
extern fn luaL_checkstring(L: *anyopaque, arg: c_int) [*:0]const u8;
extern fn luaL_checkinteger(L: *anyopaque, arg: c_int) i64;
extern fn luaL_optinteger(L: *anyopaque, arg: c_int, def: i64) i64;
extern fn luaL_optstring(L: *anyopaque, arg: c_int, def: ?[*:0]const u8) ?[*:0]const u8;
extern fn luaL_setfuncs(L: *anyopaque, l: [*]const LuaLReg, nup: c_int) void;
extern fn lua_createtable(L: *anyopaque, narr: c_int, nrec: c_int) void;
extern fn luaL_error(L: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern fn lua_setfield(L: *anyopaque, idx: c_int, k: [*:0]const u8) void;

const LuaLReg = extern struct {
    name: ?[*:0]const u8,
    func: ?*const fn (*anyopaque) callconv(.c) c_int,
};

// ============================================================================
// Infrastructure: FD table
// ============================================================================

const MAX_FDS = 64;

const FdKind = enum(u8) {
    none = 0,
    uart = 1,
    endpoint = 2,
    notification = 3,
};

const FdEntry = struct {
    kind: FdKind = .none,
    slot: ?*cte_t = null, // CNode slot holding the cap
    ep_ptr: ?*anyopaque = null, // raw pointer to kernel object (endpoint/notification)
};

var fd_table: [MAX_FDS]FdEntry = init_fd_table();

fn init_fd_table() [MAX_FDS]FdEntry {
    var table: [MAX_FDS]FdEntry = [_]FdEntry{.{}} ** MAX_FDS;
    // fd 0 = stdin (UART), fd 1 = stdout (UART), fd 2 = stderr (UART)
    table[0] = .{ .kind = .uart, .slot = null, .ep_ptr = null };
    table[1] = .{ .kind = .uart, .slot = null, .ep_ptr = null };
    table[2] = .{ .kind = .uart, .slot = null, .ep_ptr = null };
    return table;
}

fn allocFd() ?usize {
    for (3..MAX_FDS) |i| {
        if (fd_table[i].kind == .none) return i;
    }
    return null;
}

fn pushError(L: *anyopaque, msg: [*:0]const u8) void {
    lua_pushnil(L);
    _ = lua_pushstring(L, msg);
}

// ============================================================================
// Infrastructure: Object pool (bump allocator for kernel objects)
// ============================================================================

// 64KB pool for seL4 kernel objects (endpoints, notifications, TCBs)
var object_pool: [65536]u8 align(2048) = [_]u8{0} ** 65536;
var object_pool_pos: usize = 0;

fn allocObject(comptime size_bits: u6) ?*anyopaque {
    const size = @as(usize, 1) << size_bits;
    // Align up
    const aligned_pos = (object_pool_pos + size - 1) & ~(size - 1);
    if (aligned_pos + size > object_pool.len) return null;
    const ptr: *anyopaque = @ptrCast(&object_pool[aligned_pos]);
    // Zero-init
    @memset(object_pool[aligned_pos..][0..size], 0);
    object_pool_pos = aligned_pos + size;
    return ptr;
}

// ============================================================================
// Infrastructure: CNode slot allocator
// ============================================================================

// Slots 0-31 reserved (TCB internal slots + well-known caps).
// Bump-allocate from slot 32 onwards.
const SLOT_BASE: usize = 32;
var next_slot: usize = SLOT_BASE;

// Pre-allocated CTE storage for lunix-managed slots
var slot_storage: [MAX_FDS]cte_t = [_]cte_t{.{}} ** MAX_FDS;

fn allocSlot() ?*cte_t {
    const idx = next_slot - SLOT_BASE;
    if (idx >= slot_storage.len) return null;
    next_slot += 1;
    return &slot_storage[idx];
}

// ============================================================================
// Infrastructure: Process table (for fork/wait)
// ============================================================================

const MAX_PROCS = 16;

const ProcEntry = struct {
    in_use: bool = false,
    tcb: ?*tcb_t = null,
    exit_ntfn: ?*notification_t = null, // notification for parent wait()
    exit_ntfn_slot: ?*cte_t = null,
    exit_badge: word_t = 0,
};

var proc_table: [MAX_PROCS]ProcEntry = [_]ProcEntry{.{}} ** MAX_PROCS;

fn allocPid() ?usize {
    for (1..MAX_PROCS) |i| { // pid 0 reserved
        if (!proc_table[i].in_use) return i;
    }
    return null;
}

// ============================================================================
// Infrastructure: Environment table
// ============================================================================

const MAX_ENV = 32;
const MAX_ENV_KEY = 64;
const MAX_ENV_VAL = 256;

const EnvEntry = struct {
    in_use: bool = false,
    key: [MAX_ENV_KEY]u8 = [_]u8{0} ** MAX_ENV_KEY,
    key_len: usize = 0,
    val: [MAX_ENV_VAL]u8 = [_]u8{0} ** MAX_ENV_VAL,
    val_len: usize = 0,
};

var env_table: [MAX_ENV]EnvEntry = init_env_table();

fn init_env_table() [MAX_ENV]EnvEntry {
    var table: [MAX_ENV]EnvEntry = [_]EnvEntry{.{}} ** MAX_ENV;
    // Seed with defaults
    setEnv(&table, "PATH", "/");
    setEnv(&table, "HOME", "/");
    setEnv(&table, "TERM", "sel4-uart");
    return table;
}

fn setEnv(table: *[MAX_ENV]EnvEntry, key: []const u8, val: []const u8) void {
    for (table) |*e| {
        if (!e.in_use) {
            e.in_use = true;
            const klen = @min(key.len, MAX_ENV_KEY);
            const vlen = @min(val.len, MAX_ENV_VAL);
            @memcpy(e.key[0..klen], key[0..klen]);
            e.key_len = klen;
            @memcpy(e.val[0..vlen], val[0..vlen]);
            e.val_len = vlen;
            return;
        }
    }
}

// ============================================================================
// Infrastructure: Filesystem server IPC protocol
// ============================================================================

// Well-known slot for the filesystem server endpoint.
// Set by the boot code when the fs server is initialized.
var fs_server_slot: ?*cte_t = null;

const FsOp = enum(u64) {
    OPEN = 1,
    CLOSE = 2,
    MKDIR = 3,
    RMDIR = 4,
    RENAME = 5,
    LINK = 6,
    SYMLINK = 7,
    UNLINK = 8,
    STAT = 9,
    CHDIR = 10,
    CHOWN = 11,
    CHMOD = 12,
};

/// Pack a string into IPC message registers starting at the given offset.
/// Returns number of words used.
fn packStringToRegs(buf: [*]word_t, offset: usize, s: [*:0]const u8) usize {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    // Word 0: string length
    buf[offset] = len;
    // Remaining words: string data packed 8 bytes per word
    var words_used: usize = 1;
    var i: usize = 0;
    while (i < len) {
        var w: u64 = 0;
        var j: usize = 0;
        while (j < 8 and i + j < len) : (j += 1) {
            w |= @as(u64, s[i + j]) << @intCast(j * 8);
        }
        buf[offset + words_used] = w;
        words_used += 1;
        i += 8;
    }
    return words_used;
}

/// Unpack a string from IPC message registers.
fn unpackStringFromRegs(buf: [*]const word_t, offset: usize, out: []u8) usize {
    const len = @min(buf[offset], out.len);
    var i: usize = 0;
    var word_idx: usize = 1;
    while (i < len) {
        const w = buf[offset + word_idx];
        var j: usize = 0;
        while (j < 8 and i < len) : (j += 1) {
            out[i] = @truncate((w >> @intCast(j * 8)) & 0xFF);
            i += 1;
        }
        word_idx += 1;
    }
    return len;
}

// IPC message buffer for filesystem operations (thread-local in root task)
var ipc_msg_buf: [120]word_t = [_]word_t{0} ** 120;

/// Send a filesystem IPC request and receive reply.
/// Returns 0 on success, -1 if no fs server.
fn fsIpc(op: FsOp, path: [*:0]const u8) i32 {
    const slot = fs_server_slot orelse return -1;
    ipc_msg_buf[0] = @intFromEnum(op);
    _ = packStringToRegs(&ipc_msg_buf, 1, path);

    // Send+receive (call) to fs server
    const ep_cap = slot.cap;
    const ep_ptr: *endpoint_t = @ptrFromInt(ep_cap.words[0] & 0xffffffffffff);
    sendIPC(1, 1, 0, 1, 1, ksCurThread, ep_ptr);
    receiveIPC(ksCurThread, ep_cap, 1);

    // Reply status is in msg register 0
    return if (ipc_msg_buf[0] == 0) @as(i32, 0) else @as(i32, -1);
}

fn fsIpc2(op: FsOp, path1: [*:0]const u8, path2: [*:0]const u8) i32 {
    const slot = fs_server_slot orelse return -1;
    ipc_msg_buf[0] = @intFromEnum(op);
    const n1 = packStringToRegs(&ipc_msg_buf, 1, path1);
    _ = packStringToRegs(&ipc_msg_buf, 1 + n1, path2);

    const ep_cap = slot.cap;
    const ep_ptr: *endpoint_t = @ptrFromInt(ep_cap.words[0] & 0xffffffffffff);
    sendIPC(1, 1, 0, 1, 1, ksCurThread, ep_ptr);
    receiveIPC(ksCurThread, ep_cap, 1);

    return if (ipc_msg_buf[0] == 0) @as(i32, 0) else @as(i32, -1);
}

// ============================================================================
// Infrastructure: Pledge state
// ============================================================================

const PledgeFlags = packed struct {
    stdio: bool = true,
    rpath: bool = true,
    wpath: bool = true,
    cpath: bool = true,
    proc: bool = true,
    exec_flag: bool = true,
    unix_flag: bool = true,
    inet: bool = true,
    _pad: u8 = 0,
};

var pledge_state: PledgeFlags = .{}; // all allowed initially
var pledge_locked: bool = false; // once pledged, can only restrict further

fn pledgeCheck(comptime field: []const u8) bool {
    return @field(pledge_state, field);
}

// ============================================================================
// Lua bindings: Process identity
// ============================================================================

fn lunix_getpid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 1); // root task pid
    return 1;
}

fn lunix_getppid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 0); // no parent
    return 1;
}

fn lunix_getuid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 0); // single authority
    return 1;
}

fn lunix_getgid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 0);
    return 1;
}

fn lunix_geteuid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 0);
    return 1;
}

fn lunix_getegid(L: *anyopaque) callconv(.c) c_int {
    lua_pushinteger(L, 0);
    return 1;
}

// ============================================================================
// Lua bindings: I/O (fd-based, UART + endpoint)
// ============================================================================

fn lunix_write(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("stdio")) {
        pushError(L, "pledge: stdio revoked");
        return 2;
    }
    const fd: usize = @intCast(luaL_checkinteger(L, 1));
    const s = luaL_checkstring(L, 2);
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}

    if (fd >= MAX_FDS) {
        pushError(L, "bad fd");
        return 2;
    }

    const entry = &fd_table[fd];
    switch (entry.kind) {
        .uart => {
            for (s[0..len]) |ch| earlyPutc(ch);
            lua_pushinteger(L, @intCast(len));
            return 1;
        },
        .endpoint => {
            // Pack string data into IPC message and send to endpoint
            if (entry.ep_ptr) |ptr| {
                const ep: *endpoint_t = @ptrCast(@alignCast(ptr));
                // Store length in first msg register, data in subsequent
                ipc_msg_buf[0] = len;
                var i: usize = 0;
                var wi: usize = 1;
                while (i < len) {
                    var w: u64 = 0;
                    var j: usize = 0;
                    while (j < 8 and i + j < len) : (j += 1) {
                        w |= @as(u64, s[i + j]) << @intCast(j * 8);
                    }
                    ipc_msg_buf[wi] = w;
                    wi += 1;
                    i += 8;
                }
                sendIPC(1, 0, @intCast(len), 0, 0, ksCurThread, ep);
                lua_pushinteger(L, @intCast(len));
                return 1;
            }
            pushError(L, "endpoint has no backing object");
            return 2;
        },
        .notification => {
            // Notifications can only carry a badge, not data
            if (entry.ep_ptr) |ptr| {
                const ntfn: *notification_t = @ptrCast(@alignCast(ptr));
                sendSignal(ntfn, @intCast(len));
                lua_pushinteger(L, @intCast(len));
                return 1;
            }
            pushError(L, "notification has no backing object");
            return 2;
        },
        .none => {
            pushError(L, "bad fd");
            return 2;
        },
    }
}

fn lunix_read(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("stdio")) {
        pushError(L, "pledge: stdio revoked");
        return 2;
    }
    const fd: usize = @intCast(luaL_checkinteger(L, 1));
    const count: usize = @intCast(luaL_optinteger(L, 2, 4096));

    if (fd >= MAX_FDS) {
        pushError(L, "bad fd");
        return 2;
    }

    const entry = &fd_table[fd];
    switch (entry.kind) {
        .uart => {
            var buf: [4096]u8 = undefined;
            const actual = @min(count, 4096);
            const n = read(@intCast(fd), &buf, actual);
            if (n < 0) {
                pushError(L, "read failed");
                return 2;
            }
            _ = lua_pushlstring(L, &buf, @intCast(n));
            return 1;
        },
        .endpoint => {
            if (entry.slot) |slot| {
                receiveIPC(ksCurThread, slot.cap, 1);
                // Data comes back in ipc_msg_buf: [0]=length, [1..]=data words
                const len = @min(ipc_msg_buf[0], count);
                var buf: [4096]u8 = undefined;
                const actual = @min(len, buf.len);
                var i: usize = 0;
                var wi: usize = 1;
                while (i < actual) {
                    const w = ipc_msg_buf[wi];
                    var j: usize = 0;
                    while (j < 8 and i < actual) : (j += 1) {
                        buf[i] = @truncate((w >> @intCast(j * 8)) & 0xFF);
                        i += 1;
                    }
                    wi += 1;
                }
                _ = lua_pushlstring(L, &buf, actual);
                return 1;
            }
            pushError(L, "endpoint has no cap slot");
            return 2;
        },
        .notification => {
            if (entry.slot) |slot| {
                receiveSignal(ksCurThread, slot.cap, 1);
                // Badge value is the "data"
                lua_pushinteger(L, 0); // TODO: extract badge from registers
                return 1;
            }
            pushError(L, "notification has no cap slot");
            return 2;
        },
        .none => {
            pushError(L, "bad fd");
            return 2;
        },
    }
}

fn lunix_close(L: *anyopaque) callconv(.c) c_int {
    const fd: usize = @intCast(luaL_checkinteger(L, 1));
    if (fd >= MAX_FDS) {
        pushError(L, "bad fd");
        return 2;
    }
    if (fd < 3) {
        pushError(L, "cannot close stdio fds");
        return 2;
    }

    const entry = &fd_table[fd];
    if (entry.kind == .none) {
        pushError(L, "bad fd");
        return 2;
    }

    // Delete the capability from the CNode
    if (entry.slot) |slot| {
        cteDeleteOne(slot);
    }

    entry.* = .{};
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_dup(L: *anyopaque) callconv(.c) c_int {
    const fd: usize = @intCast(luaL_checkinteger(L, 1));
    if (fd >= MAX_FDS or fd_table[fd].kind == .none) {
        pushError(L, "bad fd");
        return 2;
    }

    const new_fd = allocFd() orelse {
        pushError(L, "too many open fds");
        return 2;
    };

    const src = &fd_table[fd];
    const new_slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };

    // Copy the capability into the new slot
    if (src.slot) |src_slot| {
        const derived = deriveCap(src_slot, src_slot.cap);
        if (derived.status != EXCEPTION_NONE) {
            pushError(L, "cap derivation failed");
            return 2;
        }
        cteInsert(derived.cap, src_slot, new_slot);
    }

    fd_table[new_fd] = .{
        .kind = src.kind,
        .slot = new_slot,
        .ep_ptr = src.ep_ptr,
    };

    lua_pushinteger(L, @intCast(new_fd));
    return 1;
}

// ============================================================================
// Lua bindings: pipe (seL4 endpoint pair)
// ============================================================================

fn lunix_pipe(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("stdio")) {
        pushError(L, "pledge: stdio revoked");
        return 2;
    }

    // Allocate endpoint kernel object from pool
    const ep_mem = allocObject(seL4_EndpointBits) orelse {
        pushError(L, "out of endpoint memory");
        return 2;
    };

    // Create full-rights endpoint cap
    const full_cap = createObject(seL4_EndpointObject, ep_mem, 0, 0);

    // Allocate two fds + two CNode slots
    const read_fd = allocFd() orelse {
        pushError(L, "too many open fds");
        return 2;
    };
    const write_fd = allocFd() orelse {
        pushError(L, "too many open fds");
        return 2;
    };

    const read_slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };
    const write_slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };

    // Create read-only cap (CanReceive=1, CanSend=0)
    const read_rights = seL4_CapRights_t.new(0, 0, 1, 0); // grant_reply=0, grant=0, read=1, write=0
    const read_cap = maskCapRights(read_rights, full_cap);

    // Create write-only cap (CanSend=1, CanReceive=0)
    const write_rights = seL4_CapRights_t.new(0, 0, 0, 1); // grant_reply=0, grant=0, read=0, write=1
    const write_cap = maskCapRights(write_rights, full_cap);

    // Install caps into slots
    read_slot.cap = read_cap;
    write_slot.cap = write_cap;

    const ep_ptr: *endpoint_t = @ptrCast(@alignCast(ep_mem));

    fd_table[read_fd] = .{ .kind = .endpoint, .slot = read_slot, .ep_ptr = ep_ptr };
    fd_table[write_fd] = .{ .kind = .endpoint, .slot = write_slot, .ep_ptr = ep_ptr };

    // Return {read_fd, write_fd} as Lua table
    lua_createtable(L, 2, 0);
    lua_pushinteger(L, @intCast(read_fd));
    lua_pushinteger(L, 1);
    lua_settable(L, -3); // t[1] = read_fd — wait, Lua settable is t[key]=val from stack
    // Actually: push key, push val, settable. Let me use indexed assignment.
    // Simpler: just push two values
    lua_pushinteger(L, @intCast(read_fd));
    lua_pushinteger(L, @intCast(write_fd));
    return 2; // return read_fd, write_fd as two values
}

// ============================================================================
// Lua bindings: Process control (fork, exec, kill, wait)
// ============================================================================

fn lunix_fork(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("proc")) {
        pushError(L, "pledge: proc revoked");
        return 2;
    }

    // Allocate TCB from object pool
    const tcb_mem = allocObject(seL4_TCBBits) orelse {
        pushError(L, "out of TCB memory");
        return 2;
    };

    // Create TCB kernel object
    const tcb_cap = createObject(seL4_TCBObject, tcb_mem, 0, 0);
    const tcb_addr = tcb_cap.words[0] & 0xffffffffffff;
    const child_tcb: *tcb_t = @ptrFromInt(tcb_addr);

    // Allocate a notification for wait()
    const ntfn_mem = allocObject(seL4_NotificationBits) orelse {
        pushError(L, "out of notification memory");
        return 2;
    };
    const ntfn_cap = createObject(seL4_NotificationObject, ntfn_mem, 0, 0);
    _ = ntfn_cap;
    const ntfn: *notification_t = @ptrCast(@alignCast(ntfn_mem));

    // Bind notification to child — when child dies, parent can receiveSignal
    bindNotification(child_tcb, ntfn);

    // Allocate pid
    const pid = allocPid() orelse {
        pushError(L, "too many processes");
        return 2;
    };

    const ntfn_slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };

    proc_table[pid] = .{
        .in_use = true,
        .tcb = child_tcb,
        .exit_ntfn = ntfn,
        .exit_ntfn_slot = ntfn_slot,
    };

    // Schedule the child (same address space, starts running)
    setThreadState(child_tcb, ThreadState_Running);
    tcbSchedEnqueue(child_tcb);
    scheduleTCB(child_tcb);

    // Parent gets pid, child would get 0 (but since both share address space
    // and seL4 doesn't do POSIX fork semantics, parent always gets pid)
    lua_pushinteger(L, @intCast(pid));
    return 1;
}

fn lunix_exec(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("exec_flag")) {
        pushError(L, "pledge: exec revoked");
        return 2;
    }

    const path = luaL_checkstring(L, 1);

    // Send exec request to loader server via fs server endpoint
    if (fsIpc(.OPEN, path) < 0) {
        pushError(L, "exec: no loader server");
        return 2;
    }

    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_kill(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("proc")) {
        pushError(L, "pledge: proc revoked");
        return 2;
    }

    const pid: usize = @intCast(luaL_checkinteger(L, 1));
    const sig: u64 = @intCast(luaL_optinteger(L, 2, 15)); // default SIGTERM=15

    if (pid >= MAX_PROCS or !proc_table[pid].in_use) {
        pushError(L, "no such process");
        return 2;
    }

    const proc = &proc_table[pid];
    const tcb = proc.tcb orelse {
        pushError(L, "process has no TCB");
        return 2;
    };

    if (sig == 9 or sig == 15) {
        // SIGKILL / SIGTERM: suspend and destroy
        setThreadState(tcb, ThreadState_Inactive);
        // Signal the exit notification so wait() unblocks
        if (proc.exit_ntfn) |ntfn| {
            sendSignal(ntfn, sig);
        }
        proc.in_use = false;
    } else {
        // Other signals: deliver as notification badge
        if (proc.exit_ntfn) |ntfn| {
            sendSignal(ntfn, sig);
        }
    }

    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_wait(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("proc")) {
        pushError(L, "pledge: proc revoked");
        return 2;
    }

    // Find any child process and wait on its notification
    for (1..MAX_PROCS) |pid| {
        const proc = &proc_table[pid];
        if (proc.in_use) {
            if (proc.exit_ntfn_slot) |slot| {
                // Block until child signals
                receiveSignal(ksCurThread, slot.cap, 1);

                const exit_code = proc.exit_badge;
                proc.in_use = false;

                // Return pid, exit_code
                lua_pushinteger(L, @intCast(pid));
                lua_pushinteger(L, @intCast(exit_code));
                return 2;
            }
        }
    }

    pushError(L, "no children");
    return 2;
}

// ============================================================================
// Lua bindings: Filesystem (IPC to fs server)
// ============================================================================

fn lunix_open(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("rpath")) {
        pushError(L, "pledge: rpath revoked");
        return 2;
    }

    const path = luaL_checkstring(L, 1);
    _ = luaL_optinteger(L, 2, 0); // flags (unused for now)

    if (fs_server_slot == null) {
        pushError(L, "no filesystem server");
        return 2;
    }

    if (fsIpc(.OPEN, path) < 0) {
        pushError(L, "open failed");
        return 2;
    }

    // The fs server replies with an endpoint cap for the opened file.
    // Receive it into a new fd slot.
    const fd = allocFd() orelse {
        pushError(L, "too many open fds");
        return 2;
    };
    const slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };

    // Cap was placed in our receive slot by the kernel during IPC
    // For now: the reply message contains the endpoint pointer in msg reg 1
    const ep_addr = ipc_msg_buf[1];
    slot.cap = createObject(seL4_EndpointObject, @ptrFromInt(ep_addr), 0, 0);

    fd_table[fd] = .{
        .kind = .endpoint,
        .slot = slot,
        .ep_ptr = @ptrFromInt(ep_addr),
    };

    lua_pushinteger(L, @intCast(fd));
    return 1;
}

fn lunix_mkdir(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    if (fsIpc(.MKDIR, path) < 0) { pushError(L, "mkdir failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_rmdir(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    if (fsIpc(.RMDIR, path) < 0) { pushError(L, "rmdir failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_rename(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const old = luaL_checkstring(L, 1);
    const new_path = luaL_checkstring(L, 2);
    if (fsIpc2(.RENAME, old, new_path) < 0) { pushError(L, "rename failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_link(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const old = luaL_checkstring(L, 1);
    const new_path = luaL_checkstring(L, 2);
    if (fsIpc2(.LINK, old, new_path) < 0) { pushError(L, "link failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_symlink(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const target = luaL_checkstring(L, 1);
    const path = luaL_checkstring(L, 2);
    if (fsIpc2(.SYMLINK, target, path) < 0) { pushError(L, "symlink failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_unlink(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("cpath")) { pushError(L, "pledge: cpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    if (fsIpc(.UNLINK, path) < 0) { pushError(L, "unlink failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_stat(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("rpath")) { pushError(L, "pledge: rpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    if (fsIpc(.STAT, path) < 0) { pushError(L, "stat failed"); return 2; }

    // Reply has: [1]=size, [2]=mode, [3]=mtime
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, @bitCast(ipc_msg_buf[1]));
    lua_setfield(L, -2, "size");
    lua_pushinteger(L, @bitCast(ipc_msg_buf[2]));
    lua_setfield(L, -2, "mode");
    lua_pushinteger(L, @bitCast(ipc_msg_buf[3]));
    lua_setfield(L, -2, "mtime");
    return 1;
}

fn lunix_chdir(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("rpath")) { pushError(L, "pledge: rpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    if (fsIpc(.CHDIR, path) < 0) { pushError(L, "chdir failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_chown(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("wpath")) { pushError(L, "pledge: wpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    // uid/gid packed into ipc buf before call
    ipc_msg_buf[100] = @intCast(luaL_checkinteger(L, 2));
    ipc_msg_buf[101] = @intCast(luaL_checkinteger(L, 3));
    if (fsIpc(.CHOWN, path) < 0) { pushError(L, "chown failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_chmod(L: *anyopaque) callconv(.c) c_int {
    if (!pledgeCheck("wpath")) { pushError(L, "pledge: wpath revoked"); return 2; }
    const path = luaL_checkstring(L, 1);
    ipc_msg_buf[100] = @intCast(luaL_checkinteger(L, 2)); // mode
    if (fsIpc(.CHMOD, path) < 0) { pushError(L, "chmod failed"); return 2; }
    lua_pushboolean(L, 1);
    return 1;
}

// ============================================================================
// Lua bindings: environ
// ============================================================================

fn lunix_environ(L: *anyopaque) callconv(.c) c_int {
    lua_createtable(L, 0, MAX_ENV);
    for (&env_table) |*e| {
        if (e.in_use) {
            _ = lua_pushlstring(L, &e.val, e.val_len);
            // setfield needs a null-terminated key; our key buffer is zero-padded
            lua_setfield(L, -2, @ptrCast(&e.key));
        }
    }
    return 1;
}

// ============================================================================
// Lua bindings: sleep (timer + notification)
// ============================================================================

// Timer notification for sleep — allocated on first use
var sleep_ntfn: ?*notification_t = null;
var sleep_ntfn_slot: ?*cte_t = null;

extern fn generic_timer_set(ticks: u64) void;

fn lunix_sleep(L: *anyopaque) callconv(.c) c_int {
    const secs: u64 = @intCast(luaL_checkinteger(L, 1));

    // Lazily allocate the timer notification
    if (sleep_ntfn == null) {
        const mem = allocObject(seL4_NotificationBits) orelse {
            pushError(L, "out of notification memory");
            return 2;
        };
        sleep_ntfn = @ptrCast(@alignCast(mem));
        sleep_ntfn_slot = allocSlot();
        if (sleep_ntfn_slot) |slot| {
            slot.cap = createObject(seL4_NotificationObject, mem, 0, 0);
        }
        // Bind to current thread so we can receiveSignal
        bindNotification(ksCurThread, sleep_ntfn.?);
    }

    // Set timer (24MHz ARM generic timer, ticks = secs × 24_000_000)
    const ticks = secs *% 24_000_000;
    generic_timer_set(ticks);

    // Block until timer fires and signals the notification
    if (sleep_ntfn_slot) |slot| {
        receiveSignal(ksCurThread, slot.cap, 1);
    }

    lua_pushboolean(L, 1);
    return 1;
}

fn lunix_exit(L: *anyopaque) callconv(.c) c_int {
    const status: c_int = @intCast(luaL_optinteger(L, 1, 0));
    // Print exit message and halt
    const msg = "EXIT\n";
    for (msg) |ch| earlyPutc(ch);
    _ = status;
    while (true) asm volatile ("wfe");
}

// ============================================================================
// Lua bindings: pledge (CNode cap revocation)
// ============================================================================

fn lunix_pledge(L: *anyopaque) callconv(.c) c_int {
    const promises_str = luaL_checkstring(L, 1);

    // Parse the promises string into flags
    var new_flags = PledgeFlags{
        .stdio = false,
        .rpath = false,
        .wpath = false,
        .cpath = false,
        .proc = false,
        .exec_flag = false,
        .unix_flag = false,
        .inet = false,
    };

    // Tokenize space-separated promise names
    var i: usize = 0;
    while (promises_str[i] != 0) {
        // Skip spaces
        while (promises_str[i] == ' ') : (i += 1) {}
        if (promises_str[i] == 0) break;

        // Find end of token
        const start = i;
        while (promises_str[i] != 0 and promises_str[i] != ' ') : (i += 1) {}
        const len = i - start;

        // Match token to flag
        if (strEql(promises_str + start, len, "stdio")) {
            new_flags.stdio = true;
        } else if (strEql(promises_str + start, len, "rpath")) {
            new_flags.rpath = true;
        } else if (strEql(promises_str + start, len, "wpath")) {
            new_flags.wpath = true;
        } else if (strEql(promises_str + start, len, "cpath")) {
            new_flags.cpath = true;
        } else if (strEql(promises_str + start, len, "proc")) {
            new_flags.proc = true;
        } else if (strEql(promises_str + start, len, "exec")) {
            new_flags.exec_flag = true;
        } else if (strEql(promises_str + start, len, "unix")) {
            new_flags.unix_flag = true;
        } else if (strEql(promises_str + start, len, "inet")) {
            new_flags.inet = true;
        }
        // Unknown tokens silently ignored (OpenBSD behavior)
    }

    // Can only restrict further, never expand
    if (pledge_locked) {
        new_flags.stdio = new_flags.stdio and pledge_state.stdio;
        new_flags.rpath = new_flags.rpath and pledge_state.rpath;
        new_flags.wpath = new_flags.wpath and pledge_state.wpath;
        new_flags.cpath = new_flags.cpath and pledge_state.cpath;
        new_flags.proc = new_flags.proc and pledge_state.proc;
        new_flags.exec_flag = new_flags.exec_flag and pledge_state.exec_flag;
        new_flags.unix_flag = new_flags.unix_flag and pledge_state.unix_flag;
        new_flags.inet = new_flags.inet and pledge_state.inet;
    }

    // Revoke capabilities for categories that are now disallowed

    // stdio revoked → delete UART fd caps (fd 0-2 can't be truly deleted
    // since they're hardwired, but we block at the pledge check level)
    // proc revoked → delete all TCB caps in proc_table
    if (!new_flags.proc and pledge_state.proc) {
        for (&proc_table) |*proc| {
            if (proc.in_use) {
                if (proc.exit_ntfn_slot) |slot| cteDeleteOne(slot);
                proc.in_use = false;
            }
        }
    }

    // rpath/wpath/cpath revoked → revoke fs server endpoint
    if ((!new_flags.rpath and pledge_state.rpath) or
        (!new_flags.wpath and pledge_state.wpath) or
        (!new_flags.cpath and pledge_state.cpath))
    {
        if (fs_server_slot) |slot| {
            // Revoke all derived caps from the fs server endpoint
            _ = cteRevoke(slot);
        }
    }

    pledge_state = new_flags;
    pledge_locked = true;

    lua_pushboolean(L, 1);
    return 1;
}

fn strEql(s: [*]const u8, len: usize, target: []const u8) bool {
    if (len != target.len) return false;
    for (0..len) |j| {
        if (s[j] != target[j]) return false;
    }
    return true;
}

// ============================================================================
// Lua bindings: unveil (mint restricted endpoint cap)
// ============================================================================

fn lunix_unveil(L: *anyopaque) callconv(.c) c_int {
    const path = luaL_checkstring(L, 1);
    const perms = luaL_checkstring(L, 2);

    if (fs_server_slot == null) {
        pushError(L, "no filesystem server");
        return 2;
    }

    // Parse permissions string → seL4 cap rights
    var rd: u1 = 0;
    var wr: u1 = 0;
    var grant: u1 = 0;
    {
        var pi: usize = 0;
        while (perms[pi] != 0) : (pi += 1) {
            switch (perms[pi]) {
                'r' => rd = 1,
                'w' => wr = 1,
                'x' => grant = 1, // exec maps to Grant (can delegate cap)
                'c' => { rd = 1; wr = 1; }, // create = read + write
                else => {},
            }
        }
    }

    const rights = seL4_CapRights_t.new(0, grant, rd, wr);

    // IPC to fs server: "give me a restricted cap for this path"
    ipc_msg_buf[0] = @intFromEnum(FsOp.OPEN);
    _ = packStringToRegs(&ipc_msg_buf, 1, path);

    const slot = fs_server_slot.?;
    const ep_cap = slot.cap;
    const ep_ptr: *endpoint_t = @ptrFromInt(ep_cap.words[0] & 0xffffffffffff);
    sendIPC(1, 1, 0, 1, 1, ksCurThread, ep_ptr);
    receiveIPC(ksCurThread, ep_cap, 1);

    if (ipc_msg_buf[0] != 0) {
        pushError(L, "unveil: path not found");
        return 2;
    }

    // The reply contains an endpoint cap for the resource.
    // Mint it with restricted rights.
    const resource_slot = allocSlot() orelse {
        pushError(L, "out of CNode slots");
        return 2;
    };

    const resource_addr = ipc_msg_buf[1];
    const full_cap = createObject(seL4_EndpointObject, @ptrFromInt(resource_addr), 0, 0);
    const restricted_cap = maskCapRights(rights, full_cap);
    resource_slot.cap = restricted_cap;

    lua_pushboolean(L, 1);
    return 1;
}

// ============================================================================
// Registration table
// ============================================================================

const funcs = [_]LuaLReg{
    // Process identity
    .{ .name = "getpid", .func = lunix_getpid },
    .{ .name = "getppid", .func = lunix_getppid },
    .{ .name = "getuid", .func = lunix_getuid },
    .{ .name = "getgid", .func = lunix_getgid },
    .{ .name = "geteuid", .func = lunix_geteuid },
    .{ .name = "getegid", .func = lunix_getegid },
    // I/O
    .{ .name = "write", .func = lunix_write },
    .{ .name = "read", .func = lunix_read },
    .{ .name = "close", .func = lunix_close },
    .{ .name = "dup", .func = lunix_dup },
    // Pipe
    .{ .name = "pipe", .func = lunix_pipe },
    // Process control
    .{ .name = "fork", .func = lunix_fork },
    .{ .name = "exec", .func = lunix_exec },
    .{ .name = "kill", .func = lunix_kill },
    .{ .name = "wait", .func = lunix_wait },
    // Filesystem
    .{ .name = "open", .func = lunix_open },
    .{ .name = "mkdir", .func = lunix_mkdir },
    .{ .name = "rmdir", .func = lunix_rmdir },
    .{ .name = "rename", .func = lunix_rename },
    .{ .name = "link", .func = lunix_link },
    .{ .name = "symlink", .func = lunix_symlink },
    .{ .name = "unlink", .func = lunix_unlink },
    .{ .name = "stat", .func = lunix_stat },
    .{ .name = "chdir", .func = lunix_chdir },
    .{ .name = "chown", .func = lunix_chown },
    .{ .name = "chmod", .func = lunix_chmod },
    // Environment
    .{ .name = "environ", .func = lunix_environ },
    // Timing
    .{ .name = "sleep", .func = lunix_sleep },
    .{ .name = "exit", .func = lunix_exit },
    // Capability sandboxing
    .{ .name = "pledge", .func = lunix_pledge },
    .{ .name = "unveil", .func = lunix_unveil },
    // Sentinel
    .{ .name = null, .func = null },
};

pub export fn luaopen_unix(L: *anyopaque) callconv(.c) c_int {
    lua_createtable(L, 0, funcs.len);
    luaL_setfuncs(L, &funcs, 0);
    return 1;
}
