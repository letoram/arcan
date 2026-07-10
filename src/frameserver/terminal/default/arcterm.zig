// Zig port of arcterm.c — terminal frameserver main loop.
//
// Key improvement over C original: term.screen is ?*TuiContext (optional pointer),
// so all uses must handle the null case. When arcan_tui_process returns an error,
// screen is set to null, preventing SEGV in arcan_tui_refresh.
//
// Exports: afsrv_terminal, cursor_style_arg (C-ABI compatible)

const std = @import("std");
const GhosttyBridge = @import("ghostty_bridge").GhosttyBridge;

const c = @import("shmif_types");

// shl_pty extern declarations (shl-pty.h can't be @cImport'd)
const struct_shl_pty = opaque {};
extern "c" fn shl_pty_open(out: *?*struct_shl_pty, fn_input: ?*const anyopaque, fn_input_data: ?*anyopaque, term_width: c_ushort, term_height: c_ushort, stderr_fileno: c_int) c.pid_t;
extern "c" fn shl_pipe_open(out: *?*struct_shl_pty, alloc: bool) c.pid_t;
extern "c" fn shl_pty_close(pty: ?*struct_shl_pty) void;
extern "c" fn shl_pty_get_fd(pty: ?*struct_shl_pty, is_write: bool) c_int;
extern "c" fn shl_pty_dispatch(pty: ?*struct_shl_pty) c_int;
extern "c" fn shl_pty_resize(pty: ?*struct_shl_pty, term_width: c_ushort, term_height: c_ushort) c_int;
extern "c" fn shl_pty_signal(pty: ?*struct_shl_pty, sig: c_int) c_int;

// Type aliases
const TuiContext = c.struct_tui_context;
const TuiCell = c.struct_tui_cell;
const TuiLabelent = c.struct_tui_labelent;
const TuiCbcfg = c.struct_tui_cbcfg;
const TuiConstraints = c.struct_tui_constraints;
const TuiProcessRes = c.struct_tui_process_res;
const TuiScreenAttr = c.struct_tui_screen_attr;
const ArcanEvent = c.arcan_event;
const ArcanShmifCont = c.struct_arcan_shmif_cont;
const ArgArr = c.struct_arg_arr;

// Extern C functions (cli.h, cli_builtin.h)
extern "c" fn arcterm_cli_run(con: *ArcanShmifCont, args: *ArgArr) c_int;
extern "c" fn arcterm_luacli_run(con: *ArcanShmifCont, args: *ArgArr) c_int;
// TSM legacy labels removed — ghostty has no label concept
fn legacy_query_label(_: *TuiContext, _: usize, _: *TuiLabelent) bool {
    return false;
}
fn legacy_consume_label(_: *TuiContext, _: [*c]const u8) bool {
    return false;
}
extern "c" fn tui_event_inject(tui: *TuiContext, ev: *ArcanEvent) void;

// cli_builtin.h argv parsing
const GroupEnt = extern struct {
    enter: u8,
    leave: u8,
    leave_eol: bool,
    expand: ?*const fn (*GroupEnt, [*c]const u8) callconv(.c) [*c]u8,
};

const ArgvParseOpt = extern struct {
    prepad: usize,
    groups: [*c]GroupEnt,
    sep: u8,
};

extern "c" fn extract_argv(message: [*c]const u8, opts: ArgvParseOpt, err_ofs: *isize) [*c][*c]u8;

// C library functions
extern "c" fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern "c" fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
extern "c" fn sscanf(str: [*c]const u8, fmt: [*c]const u8, ...) c_int;
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*c]const u8) [*c]u8;
extern "c" fn strcmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
extern "c" fn strlen(s: [*c]const u8) usize;
extern "c" fn memset(dst: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;

extern "c" fn getenv(name: [*c]const u8) [*c]u8;
extern "c" fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*c]const u8) c_int;
extern "c" fn putenv(s: [*c]u8) c_int;
extern "c" fn getuid() c.uid_t;
extern "c" fn getpid() c.pid_t;
extern "c" fn getpwuid(uid: c.uid_t) ?*const Passwd;

const Passwd = extern struct {
    pw_name: [*c]u8,
    pw_passwd: [*c]u8,
    pw_uid: c.uid_t,
    pw_gid: c.gid_t,
    pw_gecos: [*c]u8,
    pw_dir: [*c]u8,
    pw_shell: [*c]u8,
};

extern "c" fn open(path: [*c]const u8, flags: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
extern "c" fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern "c" fn dup(fd: c_int) c_int;
extern "c" fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn chdir(path: [*c]const u8) c_int;
extern "c" fn stat(path: [*c]const u8, buf: *anyopaque) c_int;
extern "c" fn execv(path: [*c]const u8, argv: [*c]const [*c]const u8) c_int;
extern "c" fn execvp(file: [*c]const u8, argv: [*c]const [*c]const u8) c_int;
extern "c" fn exit(status: c_int) noreturn;
extern "c" fn strtol(s: [*c]const u8, endptr: ?*[*c]u8, base: c_int) c_long;
extern "c" fn socketpair(domain: c_int, sock_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
extern "c" fn poll(fds: [*c]PollFd, nfds: c_ulong, timeout: c_int) c_int;
extern "c" fn signal(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*const fn (c_int) callconv(.c) void;
extern "c" fn sigemptyset(set: *anyopaque) c_int;
extern "c" fn isascii(ch: c_int) c_int;

extern "c" fn fdopen(fd: c_int, mode: [*c]const u8) ?*anyopaque;
extern "c" fn fwrite(ptr: ?*const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;

extern "c" fn pthread_mutex_trylock(mutex: *c.pthread_mutex_t) c_int;
extern "c" fn pthread_mutex_lock(mutex: *c.pthread_mutex_t) c_int;
extern "c" fn pthread_mutex_unlock(mutex: *c.pthread_mutex_t) c_int;
extern "c" fn pthread_create(thread: *c.pthread_t, attr: ?*const c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
extern "c" fn pthread_attr_init(attr: *c.pthread_attr_t) c_int;
extern "c" fn pthread_attr_setdetachstate(attr: *c.pthread_attr_t, detachstate: c_int) c_int;
extern "c" fn pthread_sigmask(how: c_int, set: *const anyopaque, oset: ?*anyopaque) c_int;

extern "c" fn arg_lookup(arr: ?*const ArgArr, key: [*c]const u8, ind: c_int, val: ?*[*c]const u8) bool;

// Libc/POSIX constants
const STDIN_FILENO: c_int = 0;
const STDOUT_FILENO: c_int = 1;
const STDERR_FILENO: c_int = 2;
const EXIT_SUCCESS: c_int = 0;
const EXIT_FAILURE: c_int = 1;

const O_WRONLY: c_int = 0x01;
const O_CREAT: c_int = 0x40;
const O_NONBLOCK: c_int = 0x800;
const O_RDWR: c_int = 0x02;
const FD_CLOEXEC: c_int = 1;
const F_SETFD: c_int = 2;
const F_GETFD: c_int = 1;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const AF_UNIX: c_int = 1;
const SOCK_STREAM: c_int = 1;
const SIG_SETMASK: c_int = 2;

const POLLIN: c_short = 0x001;
const POLLOUT: c_short = 0x004;
const POLLERR: c_short = 0x008;
const POLLHUP: c_short = 0x010;
const POLLNVAL: c_short = 0x020;

const PollFd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const EAGAIN: c_int = 11;
const EINTR: c_int = 4;
const EWOULDBLOCK: c_int = 11;

const SIGHUP: c_int = 1;
const SIGCONT: c_int = 18;
const SIGSTOP: c_int = 19;
const SIG_DFL: ?*const fn (c_int) callconv(.c) void = null;

const PTHREAD_CREATE_DETACHED: c_int = 1;

// TUI / VTE constants
const DIRTY_PARTIAL: u32 = 2;
const DIRTY_FULL: u32 = 4;

const TUI_HIDE_CURSOR: c_uint = 16;
const TUI_PROGRESS_INTERNAL: c_int = 0;
const TUI_ERRC_OK: c_int = 0;
const TUI_COL_BG: c_int = 4;
const TUI_COL_TEXT: c_int = 5;
const TUI_COL_TBASE: c_int = 16;
const TUI_COL_LIMIT: c_int = 36;

const CURSOR_BLOCK: c_int = 16;
const CURSOR_BAR: c_int = 32;
const CURSOR_UNDER: c_int = 64;
const CURSOR_HOLLOW: c_int = 128;

// TSM VTE color constants (indices into 256-color palette + fg/bg)
// ghostty uses standard xterm palette indices: 0-15 = named, 16-231 = 6x6x6, 232-255 = grayscale
// Background is palette index 0 (black), foreground is index 7 (white) by default
const VTE_COLOR_NUM: u8 = 18; // TSM: 16 palette + 2 (bg, fg)
const VTE_COLOR_BACKGROUND_IDX: u8 = 0; // ghostty palette index for default bg
const VTE_COLOR_FOREGROUND_IDX: u8 = 7; // ghostty palette index for default fg

const EVENT_TARGET: u8 = 16;

const TUIK_F1: u16 = 282;
const TUIK_F2: u16 = 283;
const TUIK_F3: u16 = 284;
const TUIM_LSHIFT: u16 = 0x0001;

// Verified byte offsets into tui_context (aarch64-linux, gcc offsetof)
const OFF_TUI_DIRTY: usize = 128; // enum dirty_state (u32)
const OFF_TUI_INACT_TIMER: usize = 88; // int inact_timer
const OFF_TUI_IN_SELECT: usize = 200; // bool
const OFF_TUI_SCROLLBACK: usize = 204; // int
const OFF_TUI_ROWS: usize = 228; // int rows
const OFF_TUI_COLS: usize = 232; // int cols

// Hook function pointer offsets in tui_context
const OFF_HOOKS_CURSOR_UPDATE: usize = 3824;
const OFF_HOOKS_INPUT: usize = 3832;
const OFF_HOOKS_RESET: usize = 3840;
const OFF_HOOKS_DESTROY: usize = 3848;
const OFF_HOOKS_RESIZE: usize = 3856;
const OFF_HOOKS_REFRESH: usize = 3864;
const OFF_HOOKS_CURSOR_LOOKUP: usize = 3872;

const DIRTY_CURSOR: u32 = 1;

// Offset-based field access helpers
fn ptrAdd(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

fn readField(comptime T: type, base: *anyopaque, off: usize) T {
    const p: *align(1) const T = @ptrCast(ptrAdd(base, off));
    return p.*;
}

fn writeField(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    const p: *align(1) T = @ptrCast(ptrAdd(base, off));
    p.* = val;
}

fn fieldPtr(comptime T: type, base: *anyopaque, off: usize) *T {
    return @ptrCast(@alignCast(ptrAdd(base, off)));
}

/// Read dirty flags from tui_context via offset
fn tuiGetDirtyPtr(tui: *TuiContext) *u32 {
    return fieldPtr(u32, @ptrCast(tui), OFF_TUI_DIRTY);
}

/// Read in_select from tui_context via offset
fn tuiGetInSelect(tui: *TuiContext) bool {
    return readField(bool, @ptrCast(tui), OFF_TUI_IN_SELECT);
}

/// Read scrollback from tui_context via offset
fn tuiGetScrollback(tui: *TuiContext) c_int {
    return readField(c_int, @ptrCast(tui), OFF_TUI_SCROLLBACK);
}

/// Write scrollback to tui_context via offset
fn tuiSetScrollback(tui: *TuiContext, val: c_int) void {
    writeField(c_int, @ptrCast(tui), OFF_TUI_SCROLLBACK, val);
}

// Hook function types (must match tui_int.h layout)
const HookFn = ?*const fn (*TuiContext) callconv(.c) void;
const CursorLookupHookFn = ?*const fn (*TuiContext, *usize, *usize) callconv(.c) void;

extern "c" fn arcan_tui_content_size(tui: *TuiContext, rows: usize, cols: usize, pad_w: c_int, pad_h: c_int) void;
extern "c" fn arcan_tui_copy(tui: *TuiContext, utf8_msg: [*c]const u8) bool;
// Fallback that ships the clipboard-out payload as a "CLIP_OUT:<text>"
// MESSAGE on the main shmif segment. Implemented in
// src/shmif/tui/core/clipboard.zig. Used because the clip_out subsegment
// NEWSEGMENT never reaches the tui dispatcher in our tree, so arcan_tui_copy
// silently drops. Pairs with the CLIP_OUT: prefix handler in
// src/sel4-zig/durian_appl/atypes/terminal.lua.
extern "c" fn tui_clipboard_push_main(tui: *TuiContext, sel: [*c]const u8, len: usize) bool;

// arkmod shift bits (from shmif_types.zig ARKMOD_L/R_SHIFT).
const ARKMOD_LSHIFT_BIT: c_int = 0x0001;
const ARKMOD_RSHIFT_BIT: c_int = 0x0002;
const ARKMOD_SHIFT_MASK: c_int = ARKMOD_LSHIFT_BIT | ARKMOD_RSHIFT_BIT;

/// Install ghostty-backed hooks into a TUI context (replaces arcan_tui_allow_deprecated).
fn installGhosttyHooks(scr: *TuiContext) void {
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_REFRESH, @ptrCast(&ghosttyRefreshHook));
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_RESIZE, @ptrCast(&ghosttyResizeHook));
    writeField(CursorLookupHookFn, @ptrCast(scr), OFF_HOOKS_CURSOR_LOOKUP, @ptrCast(&ghosttyCursorLookup));
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_CURSOR_UPDATE, @ptrCast(&ghosttyCursorUpdateHook));
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_DESTROY, @ptrCast(&ghosttyDestroyHook));
    // hooks.input = null — arcterm handles input via TUI callbacks, not hook
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_INPUT, null);
    // hooks.reset = null — reset handled by on_reset callback
    writeField(HookFn, @ptrCast(scr), OFF_HOOKS_RESET, null);
}

fn ghosttyRefreshHook(tui: *TuiContext) callconv(.c) void {
    if (term.gterm) |gterm| {
        gterm.syncToFrontBuffer(@ptrCast(tui));
    }
}

fn ghosttyResizeHook(tui: *TuiContext) callconv(.c) void {
    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(tui, &rows, &cols);
    if (rows == 0 or cols == 0) return;

    // Lazy bridge creation: if arcterm init ran before the first resize
    // fired, term.gterm is still null. Create it now at the real
    // dimensions so we never render a dummy frame at a fallback size.
    if (term.gterm == null) {
        const pty_fd: i32 = if (term.pty) |pty| shl_pty_get_fd(pty, true) else -1;
        term.gterm = GhosttyBridge.init(
            std.heap.c_allocator,
            @intCast(cols),
            @intCast(rows),
            pty_fd,
            @ptrCast(tui),
        ) catch return;
        return;
    }

    if (term.gterm) |gterm| {
        gterm.resize(@intCast(cols), @intCast(rows));
    }
}

fn ghosttyCursorLookup(_: *TuiContext, x: *usize, y: *usize) callconv(.c) void {
    if (term.gterm) |gterm| {
        const pos = gterm.getCursorPos();
        x.* = pos.x;
        y.* = pos.y;
    }
}

fn ghosttyCursorUpdateHook(tui: *TuiContext) callconv(.c) void {
    // Equivalent of tuiint_flag_cursor but without TSM screen access
    tuiGetDirtyPtr(tui).* |= DIRTY_CURSOR;
    writeField(c_int, @ptrCast(tui), OFF_TUI_INACT_TIMER, -4);

    // Update content size from ghostty scrollback
    if (term.gterm) |gterm| {
        const sb_count = gterm.getScrollbackCount();
        const sbofs = tuiGetScrollback(tui);
        const rows: usize = @intCast(readField(c_int, @ptrCast(tui), OFF_TUI_ROWS));
        const ofs: usize = if (sbofs >= 0) @intCast(sbofs) else 0;
        arcan_tui_content_size(tui, sb_count -| ofs, sb_count + rows, 0, 0);
    }
}

fn ghosttyDestroyHook(_: *TuiContext) callconv(.c) void {
    if (term.gterm) |gterm| {
        gterm.deinit();
        term.gterm = null;
    }
}

// errno access
fn getErrno() c_int {
    return std.c._errno().*;
}

// Data types

const TLine = struct {
    count: usize,
    cells: ?[*]TuiCell,
};

const PipeMode = enum(u8) {
    raw = 0,
    plain_lf = 1,
    utf8 = 2,
    stats_basic = 3,
};

// Global terminal state
// CRITICAL: screen is ?*TuiContext (optional pointer) — all uses must handle null.
const TermState = struct {
    screen: ?*TuiContext = null,

    gterm: ?*GhosttyBridge = null,
    pty: ?*struct_shl_pty = null,
    args: ?*ArgArr = null,

    synch: c.pthread_mutex_t = std.mem.zeroes(c.pthread_mutex_t),
    hold: c.pthread_mutex_t = std.mem.zeroes(c.pthread_mutex_t),

    child: c.pid_t = 0,

    alive: bool = false,
    defer_resize: c_int = 0,

    die_on_term: bool = true,
    complete_signal: bool = false,
    pipe: bool = false,
    keep_stderr: c_int = 0,
    bytes_in: usize = 0,
    bytes_out: usize = 0,
    u8_buf: [4]u8 = [_]u8{0} ** 4,
    pipe_mode: PipeMode = .raw,

    fit_contents: bool = false,
    initial_hint: struct {
        rows: usize = 0,
        cols: usize = 0,
    } = .{},

    restore: ?[*]?*TLine = null,
    restore_cxy: [2]usize = [_]usize{ 0, 0 },

    pending_bout_buf: ?[*]u8 = null,
    pending_bout_buf_sz: usize = 0,

    dirtyfd: c_int = -1,
    signalfd: c_int = -1,
};

var term = TermState{};

// Initialize mutexes (PTHREAD_MUTEX_INITIALIZER equivalent happens at C level,
// but our zeroed struct is valid for Linux default mutex)

// Forward declarations / label state

const LabelEnt = struct {
    handler: *const fn (*LabelEnt) void,
    disabled: bool,
    tag: c_int,
    ent: TuiLabelent,
};

fn force_autofit(self: *LabelEnt) void {
    _ = self;
    const old_fit = term.fit_contents;
    term.fit_contents = true;
    create_restore_buffer(term.fit_contents);
    term.fit_contents = old_fit;
}

fn set_pipe(self: *LabelEnt) void {
    if (term.screen) |scr| {
        c.arcan_tui_erase_screen(scr, false);
    }
    term.pipe_mode = @enumFromInt(@as(u8, @intCast(self.tag)));
}

var labels = [_]LabelEnt{
    .{
        .handler = &force_autofit,
        .disabled = false,
        .tag = 0,
        .ent = makeLabelent("AUTOFIT", "Resize window to buffer contents", TUIK_F1, TUIM_LSHIFT),
    },
    .{
        .handler = &set_pipe,
        .disabled = true,
        .tag = @intFromEnum(PipeMode.raw),
        .ent = makeLabelent("VIEW_RAW", "Show pipe output in window as unfiltered", TUIK_F1, 0),
    },
    .{
        .handler = &set_pipe,
        .disabled = true,
        .tag = @intFromEnum(PipeMode.raw),
        .ent = makeLabelent("VIEW_RAW_LF", "Show pipe output in window as unfiltered, respect linefeed", TUIK_F1, 0),
    },
    .{
        .handler = &set_pipe,
        .disabled = true,
        .tag = @intFromEnum(PipeMode.plain_lf),
        .ent = makeLabelent("VIEW_UTF8", "Convert input to UTF8, mark invalid values", TUIK_F2, 0),
    },
    .{
        .handler = &set_pipe,
        .disabled = true,
        .tag = @intFromEnum(PipeMode.stats_basic),
        .ent = makeLabelent("VIEW_STATS", "Only show read/written/pending", TUIK_F3, 0),
    },
};

fn makeLabelent(
    comptime label_str: []const u8,
    comptime descr_str: []const u8,
    initial: u16,
    modifiers: u16,
) TuiLabelent {
    var ent: TuiLabelent = std.mem.zeroes(TuiLabelent);
    @memcpy(ent.label[0..label_str.len], label_str);
    @memcpy(ent.descr[0..descr_str.len], descr_str);
    ent.initial = initial;
    ent.modifiers = modifiers;
    return ent;
}

// Static helper functions

fn reset_restore_buffer() void {
    const cur = @atomicLoad(?[*]?*TLine, &term.restore, .seq_cst);
    @atomicStore(?[*]?*TLine, &term.restore, null, .seq_cst);

    if (cur == null) return;
    const ptr = cur.?;

    var i: usize = 0;
    while (ptr[i] != null) : (i += 1) {
        const line = ptr[i].?;
        if (line.count != 0) {
            free(@ptrCast(line.cells));
        }
        free(@ptrCast(line));
    }
    free(@ptrCast(ptr));
}

fn apply_restore_buffer() void {
    const scr = term.screen orelse return;

    c.arcan_tui_erase_screen(scr, false);
    const cur = @atomicLoad(?[*]?*TLine, &term.restore, .seq_cst);
    if (cur == null) return;
    const lines = cur.?;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(scr, &rows, &cols);

    // Write saved cells directly to TUI front buffer
    const front: ?[*]TuiCell = readField(?[*]TuiCell, @ptrCast(scr), 32); // OFF_TUI_FRONT
    if (front == null) return;
    const fb = front.?;

    var row: usize = 0;
    while (row < rows and lines[row] != null) : (row += 1) {
        const line = lines[row].?;
        const cells = line.cells orelse continue;
        const n = line.count;

        var i: usize = 0;
        while (i < n and i < cols) : (i += 1) {
            fb[row * cols + i] = cells[i];
        }
    }

    // Flag cursor dirty
    ghosttyCursorUpdateHook(scr);
    tuiGetDirtyPtr(scr).* |= DIRTY_PARTIAL;
}

fn create_restore_buffer(refit: bool) void {
    reset_restore_buffer();
    const scr = term.screen orelse return;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_dimensions(scr, &rows, &cols);

    const bufsz = @sizeOf(?*TLine) * (rows + 1);
    const raw_buf = malloc(bufsz) orelse {
        term.die_on_term = true;
        return;
    };
    _ = memset(raw_buf, 0, bufsz);
    const buffer: [*]?*TLine = @ptrCast(@alignCast(raw_buf));

    // Get cursor position from ghostty
    if (term.gterm) |gterm| {
        const pos = gterm.getCursorPos();
        term.restore_cxy[0] = pos.x;
        term.restore_cxy[1] = pos.y;
    } else {
        term.restore_cxy[0] = 0;
        term.restore_cxy[1] = 0;
    }

    var max_row: usize = 0;
    var max_col: usize = 0;

    var row: usize = 0;
    const ok = ok_blk: {
        while (row < rows) : (row += 1) {
            const line_raw = malloc(@sizeOf(TLine)) orelse break :ok_blk false;
            const line: *TLine = @ptrCast(@alignCast(line_raw));
            buffer[row] = line;

            const cell_bufsz = @sizeOf(TuiCell) * cols;
            const cells_raw = malloc(cell_bufsz) orelse break :ok_blk false;
            const cells: [*]TuiCell = @ptrCast(@alignCast(cells_raw));
            _ = memset(cells_raw, 0, cell_bufsz);

            line.cells = cells;
            line.count = cols;

            var row_dirty = false;

            var col: usize = 0;
            while (col < cols) : (col += 1) {
                const cell = c.arcan_tui_getxy(scr, col, row, true);
                const ch: u32 = if (cell.draw_ch != 0) cell.draw_ch else cell.ch;
                row_dirty = row_dirty or (ch != 0 and ch != ' ');

                if (ch != 0 and ch != ' ' and max_col < col + 1)
                    max_col = col + 1;

                cells[col] = cell;
            }

            if (row_dirty) max_row = row + 1;
        }
        break :ok_blk true;
    };

    if (ok) {
        if (refit) {
            if (max_row != 0 and max_col != 0) {
                if (term.initial_hint.rows == 0 or term.initial_hint.cols == 0) {
                    term.initial_hint.rows = rows;
                    term.initial_hint.cols = cols;
                }

                c.arcan_tui_wndhint(scr, null, .{
                    .max_rows = @intCast(max_row),
                    .min_rows = @intCast(max_row),
                    .max_cols = @intCast(max_col),
                    .min_cols = @intCast(max_col),
                    .anch_row = 0,
                    .anch_col = 0,
                    .hide = 0,
                    .embed = 0,
                });
            }
        }
        @atomicStore(?[*]?*TLine, &term.restore, buffer, .seq_cst);
    } else {
        // allocation failure — store what we have, then clean up
        @atomicStore(?[*]?*TLine, &term.restore, buffer, .seq_cst);
        reset_restore_buffer();
        term.die_on_term = true;
    }
}

fn flush_buffer(fd: c_int, dst: *[4096]u8) isize {
    const nr = read(fd, dst, 4096);
    if (nr == -1) {
        const err = getErrno();
        if (err == EAGAIN or err == EINTR) return -1;

        @atomicStore(bool, &term.alive, false, .seq_cst);
        if (term.screen) |scr| {
            _ = c.arcan_tui_set_flags(scr, TUI_HIDE_CURSOR);
        }
        return -1;
    }
    return nr;
}

fn synch_quit(fd: c_int) bool {
    var buf: [256]u8 = undefined;
    const nr = read(fd, &buf, 256);
    if (nr <= 0) return false;

    var i: usize = 0;
    while (i < @as(usize, @intCast(nr))) : (i += 1) {
        if (buf[i] == 'q') return true;
    }
    return false;
}

fn flush_ascii(buf: [*]u8, nb: usize, raw: bool) void {
    const scr = term.screen orelse return;
    var pos: usize = 0;
    while (pos < nb) : (pos += 1) {
        if (isascii(@intCast(buf[pos])) != 0) {
            if (!raw and buf[pos] == '\n') {
                c.arcan_tui_newline(scr);
            } else {
                c.arcan_tui_write(scr, buf[pos], null);
            }
        }
    }
}

fn write_number(num: usize) void {
    _ = num;
    if (term.screen) |scr| {
        _ = c.arcan_tui_writeu8(scr, "MISSING", 7, null);
    }
}

fn flush_stats() void {
    const scr = term.screen orelse return;
    c.arcan_tui_erase_screen(scr, false);
    c.arcan_tui_move_to(scr, 0, 0);
    _ = c.arcan_tui_writeu8(scr, "In: ", 4, null);
    write_number(term.bytes_in);
    c.arcan_tui_move_to(scr, 0, 1);
    _ = c.arcan_tui_writeu8(scr, "Out: ", 5, null);
    write_number(term.bytes_out);
}

fn flush_utf8(buf: [*]u8, nb: usize) void {
    _ = buf;
    _ = nb;
    if (term.screen) |scr| {
        c.arcan_tui_move_to(scr, 0, 0);
        _ = c.arcan_tui_writeu8(scr, "MISSING-U8", 10, null);
    }
}

fn flush_out(buf: *[4096]u8, left: *usize, ofs: *usize, fdout: c_int, die: *bool) void {
    if (left.* == 0) return;

    var set = [2]PollFd{
        .{ .fd = fdout, .events = POLLOUT, .revents = 0 },
        .{ .fd = term.dirtyfd, .events = POLLIN, .revents = 0 },
    };

    if (-1 == poll(&set, 2, if (die.*) @as(c_int, 0) else @as(c_int, -1)))
        return;

    if (set[1].revents != 0 and synch_quit(term.dirtyfd)) {
        die.* = true;
        return;
    }

    var nw: isize = 0;
    if (set[0].revents != 0) {
        nw = write(fdout, &buf[ofs.*], left.*);
    }

    if (nw < 0) {
        const err = getErrno();
        if (err != EAGAIN and err != EINTR) {
            die.* = true;
        }
        return;
    }

    const written: usize = @intCast(nw);
    term.bytes_out += written;
    if (term.pipe_mode == .stats_basic)
        flush_stats();

    left.* -= written;
    ofs.* += written;

    // tail recurse until flushed or die
    return flush_out(buf, left, ofs, fdout, die);
}

fn readout_pty(fd: c_int) bool {
    var buf: [4096]u8 = undefined;
    var got_hold = false;
    const nr = flush_buffer(fd, &buf);

    if (nr < 0) return false;
    if (nr == 0) return true;

    const scr = term.screen orelse return false;

    if (0 != pthread_mutex_trylock(&term.synch)) {
        _ = pthread_mutex_lock(&term.hold);
        const one: [1]u8 = .{'1'};
        _ = write(term.dirtyfd, &one, 1);
        _ = pthread_mutex_lock(&term.synch);
        got_hold = true;
    }

    if (term.gterm) |gterm| {
        gterm.feedInput(buf[0..@intCast(nr)]);
    }
    tuiGetDirtyPtr(scr).* |= DIRTY_PARTIAL;

    var h: usize = 0;
    var w: usize = 0;
    c.arcan_tui_dimensions(scr, &h, &w);
    var cap: isize = @intCast(w * h * 4);
    var nr2 = nr;

    while (nr2 > 0 and cap > 0) {
        var pfd = PollFd{ .fd = fd, .events = POLLIN, .revents = 0 };
        if (1 != poll(&pfd, 1, 0)) break;
        nr2 = flush_buffer(fd, &buf);
        if (nr2 > 0) {
            if (term.gterm) |gterm| {
                gterm.feedInput(buf[0..@intCast(nr2)]);
            }
            cap -= nr2;
        }
    }

    if (got_hold) {
        _ = pthread_mutex_unlock(&term.hold);
    }
    _ = pthread_mutex_unlock(&term.synch);

    return true;
}

fn pump_pipe(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    var buffer: [4096]u8 = undefined;
    var left: usize = 0;
    var ofs: usize = 0;
    var die = false;
    var out_dst: c_int = STDOUT_FILENO;

    var set = [3]PollFd{
        .{ .fd = shl_pty_get_fd(term.pty, false), .events = POLLIN | POLLERR | POLLNVAL | POLLHUP, .revents = 0 },
        .{ .fd = STDIN_FILENO, .events = POLLIN, .revents = 0 },
        .{ .fd = term.dirtyfd, .events = POLLIN, .revents = 0 },
    };

    while (@atomicLoad(bool, &term.alive, .seq_cst) and !die) {
        if (left != 0) {
            flush_out(&buffer, &left, &ofs, out_dst, &die);
            continue;
        }

        // reset revents
        set[0].revents = 0;
        set[1].revents = 0;
        set[2].revents = 0;

        if (-1 == poll(&set, 3, -1))
            continue;

        if (set[2].revents != 0 and synch_quit(term.dirtyfd)) {
            die = true;
            break;
        }

        var nr: isize = 0;

        if (set[0].revents & POLLIN != 0) {
            nr = read(set[0].fd, &buffer, 4096);
            if (nr > 0) {
                const count: usize = @intCast(nr);
                term.bytes_in += count;

                switch (term.pipe_mode) {
                    .raw => flush_ascii(&buffer, count, true),
                    .plain_lf => flush_ascii(&buffer, count, false),
                    .stats_basic => flush_stats(),
                    .utf8 => flush_utf8(&buffer, count),
                }
                left = count;
                ofs = 0;
                out_dst = STDOUT_FILENO;
                continue;
            }
        }

        if (nr <= 0 and (set[1].revents & POLLIN != 0)) {
            nr = read(set[1].fd, &buffer, 4096);
            if (nr > 0) {
                left = @intCast(nr);
                ofs = 0;
                out_dst = shl_pty_get_fd(term.pty, true);
                continue;
            }
        }

        if (nr <= 0) {
            if (set[1].revents & (POLLERR | POLLNVAL | POLLHUP) != 0) {
                die = true;
                break;
            }
            continue;
        }
    }

    flush_out(&buffer, &left, &ofs, out_dst, &die);

    if (term.screen) |scr| {
        c.arcan_tui_progress(scr, TUI_PROGRESS_INTERNAL, 1.0);
    }

    const q_ch: [1]u8 = .{'Q'};
    _ = write(term.dirtyfd, &q_ch, 1);
    @atomicStore(bool, &term.alive, false, .seq_cst);

    return null;
}

fn pump_pty(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    const fd = shl_pty_get_fd(term.pty, false);
    const pollev: c_short = POLLIN | POLLERR | POLLNVAL | POLLHUP;

    var set = [2]PollFd{
        .{ .fd = fd, .events = pollev, .revents = 0 },
        .{ .fd = term.dirtyfd, .events = pollev, .revents = 0 },
    };

    while (@atomicLoad(bool, &term.alive, .seq_cst)) {
        if (@atomicLoad(c_int, &term.defer_resize, .seq_cst) != 0) {
            _ = @atomicRmw(c_int, &term.defer_resize, .Sub, 1, .seq_cst);
            if (term.screen) |scr| {
                var rows: usize = 0;
                var cols: usize = 0;
                c.arcan_tui_dimensions(scr, &rows, &cols);
                _ = shl_pty_resize(term.pty, @intCast(cols), @intCast(rows));
            }
        }

        _ = shl_pty_dispatch(term.pty);

        set[0].revents = 0;
        set[1].revents = 0;
        if (-1 == poll(&set, 2, 30))
            continue;

        if (set[0].revents != 0) {
            if (!readout_pty(fd) or (set[0].revents & POLLHUP != 0))
                break;
        }

        if (set[1].revents != 0 and synch_quit(set[1].fd))
            break;
    }

    const q_ch: [1]u8 = .{'Q'};
    _ = write(term.dirtyfd, &q_ch, 1);
    return null;
}

fn dump_help() void {
    const msg =
        "Environment variables: \nARCAN_CONNPATH=path_to_server\n" ++
        "ARCAN_TERMINAL_EXEC=value : run value through /bin/sh -c instead of shell\n" ++
        "ARCAN_TERMINAL_ARGV : exec will route through execv instead of execvp\n" ++
        "ARCAN_TERMINAL_PIDFD_OUT : writes exec pid into pidfd\n" ++
        "ARCAN_TERMINAL_PIDFD_IN  : exec continues on incoming data\n\n" ++
        "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n" ++
        "Accepted packed_args:\n" ++
        "    key      \t   value   \t   description\n" ++
        "-------------\t-----------\t-----------------\n" ++
        " env         \t key=val   \t override default environment (repeatable)\n" ++
        " chdir       \t dir       \t change working dir before spawning shell\n" ++
        " bgalpha     \t rv(0..255)\t opacity (default: 255, opaque) - deprecated\n" ++
        " ci          \t ind,r,g,b \t override palette at index\n" ++
        " blink       \t ticks     \t set blink period, 0 to disable (default: 12)\n" ++
        " login       \t [user]    \t login (optional: user, only works for root)\n" ++
        " exec        \t cmd       \t allows arcan scripts to run shell commands\n" ++
        " keep_alive  \t           \t don't exit if the terminal or shell terminates\n" ++
        " keep_stderr \t           \t forward whatever [stderr] is into the child\n" ++
        "             \t           \t and disable logging for afsrv_terminal\n" ++
        " autofit     \t           \t (with exec, keep_alive) shrink window to fit\n" ++
        " record      \t fname     \t record everything in main window in tpackani fmt\n" ++
        " pipe        \t [mode]    \t map stdin-stdout (mode: raw, lf)\n" ++
        " palette     \t name      \t use built-in palette (below)\n" ++
        " cli         \t [lua]     \t switch to non-vt cli/builtin shell mode\n" ++
        " cursor      \t [style]   \t set default cursor: block, bar, underline, hollow\n" ++
        "Built-in palettes:\n" ++
        "default, solarized, solarized-black, solarized-white, srcery\n" ++
        "-------------\t-----------\t----------------\n\n" ++
        "Cli mode (pty-less) specific args:\n" ++
        "    key      \t   value   \t   description\n" ++
        "-------------\t-----------\t-----------------\n" ++
        " env         \t key=val   \t override default environment (repeatable)\n" ++
        " mode        \t exec_mode \t arcan, wayland, x11, vt100 (default: vt100)\n" ++
        " oneshot     \t           \t use with exec, shut down after evaluating command\n" ++
        "-------------\t-----------\t----------------\n";
    _ = write(STDOUT_FILENO, msg, msg.len);
}

fn sighuph(_: c_int) callconv(.c) void {
    if (term.pty) |pty| {
        shl_pty_close(pty);
        term.pty = null;
    }
}

// TUI callback functions

fn on_mouse_motion(ctx: *TuiContext, relative: bool, x: c_int, y: c_int, modifiers: c_int, _: ?*anyopaque) callconv(.c) void {
    if (relative) return;
    const gterm = term.gterm orelse return;

    // Drag update: while the user is still holding the button, widen the
    // selection range and redraw so the inverse-video rectangle follows.
    if (gterm.selection) |sel| {
        if (sel.active and x >= 0 and y >= 0) {
            gterm.selectionUpdate(@intCast(y), @intCast(x));
            tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
            return;
        }
    }

    gterm.encodeMouseMotion(x, y, @intCast(@as(u32, @bitCast(modifiers))));
}

fn on_mouse_button(ctx: *TuiContext, last_x: c_int, last_y: c_int, button: c_int, active: bool, modifiers: c_int, _: ?*anyopaque) callconv(.c) void {
    const gterm = term.gterm orelse return;

    // Wheel on press only, primary screen only → scroll the terminal's
    // own history pages via ghostty's viewport pin. Transparent to the
    // foreground program (bash, claude, etc.). Alt-screen TUIs (htop,
    // vim, less) keep their xterm mouse-mode wheel handling below.
    if (active and (button == 4 or button == 5) and
        gterm.terminal.screens.active_key == .primary)
    {
        const dy: isize = if (button == 4) -3 else 3;
        gterm.terminal.screens.active.pages.scroll(.{ .delta_row = dy });
        // pages.scroll() moves ghostty's viewport pin but doesn't mark
        // our side's front buffer dirty, so ghosttyRefreshHook never
        // re-runs and the new viewport isn't drawn. Force a full redraw.
        tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
        return;
    }

    // Left-button press: start a drag-select on the primary screen, or on
    // the alt-screen when Shift is held (same override pattern we use for
    // wheel scrollback; mouse-mode TUIs like htop keep their plain clicks).
    if (button == 1 and active and last_x >= 0 and last_y >= 0) {
        const shift_held = (modifiers & ARKMOD_SHIFT_MASK) != 0;
        const on_primary = gterm.terminal.screens.active_key == .primary;
        if (on_primary or shift_held) {
            gterm.selectionStart(@intCast(last_y), @intCast(last_x));
            tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
            return;
        }
    }

    // Left-button release: finalise the drag. If the user dragged far
    // enough to produce a non-empty range, push the text onto the host
    // clipboard. Primary path is arcan_tui_copy (clip_out subsegment), but
    // that silently drops in our tree (NEWSEGMENT never arrives); fall
    // back to a "CLIP_OUT:<text>" MESSAGE on the main segment which the
    // durian terminal atype recognises and routes to CLIPBOARD:set_global.
    if (button == 1 and !active and gterm.selection != null) {
        const was_active = gterm.selection.?.active;
        gterm.selectionEnd();
        if (was_active and gterm.selection != null) {
            const text = gterm.selectionText(std.heap.c_allocator) catch null;
            if (text) |buf| {
                defer std.heap.c_allocator.free(buf);
                const payload_len = if (buf.len > 0) buf.len - 1 else 0; // strip NUL
                if (!arcan_tui_copy(ctx, buf.ptr)) {
                    _ = tui_clipboard_push_main(ctx, buf.ptr, payload_len);
                }
            }
        }
        tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
        return;
    }

    gterm.encodeMouseButton(last_x, last_y, button, active, @intCast(@as(u32, @bitCast(modifiers))));
}

fn on_key(ctx: *TuiContext, keysym: u32, _: u8, mods: u16, subid: u16, _: ?*anyopaque) callconv(.c) void {
    if (term.pipe) return;
    if (term.gterm) |gterm| {
        // Any keypress snaps the viewport back to the live content area,
        // matching alacritty/kitty/ghostty convention: the user is typing
        // a new command, they want to see what they're typing.
        gterm.terminal.screens.active.pages.scroll(.active);
        tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;

        // The shmif tui dispatches keyboard events with `subid = scancode`
        // (evdev keycode), not the unicode codepoint. ghostty's CSI-u
        // encoder reads the third arg as the codepoint to put into the
        // sequence — passing the scancode produces nonsense (e.g. ctrl+c
        // emits `^[[46;5u`, where 46 is KEY_C, not 99 = 'c'). For ASCII
        // printable keysyms the SDL1.2 keysym IS the unicode codepoint, so
        // promote it; for everything else fall back to subid (the existing
        // behaviour, which doesn't matter for non-printables anyway).
        const codepoint: u16 = if (keysym >= 0x20 and keysym <= 0x7e)
            @intCast(keysym)
        else
            subid;
        gterm.encodeAndWriteKey(keysym, mods, codepoint);
    }
}

fn on_u8(_: *TuiContext, u8_str: [*c]const u8, len: usize, _: ?*anyopaque) callconv(.c) bool {
    const pty_fd = shl_pty_get_fd(term.pty, true);
    if (write(pty_fd, u8_str, len) < 0) {
        const err = getErrno();
        if (err != EAGAIN and err != EWOULDBLOCK and err != EINTR) {
            @atomicStore(bool, &term.alive, false, .seq_cst);
        }
    }
    return true;
}

fn on_utf8_paste(_: *TuiContext, str: [*c]const u8, len: usize, _: bool, _: ?*anyopaque) callconv(.c) void {
    if (term.gterm) |gterm| {
        gterm.encodeAndWritePaste(str, len);
    }
}

/// MESSAGE event on the main shmif segment. Some clipboard-paste paths
/// (e.g. durian's `target_input(wnd.clipboard_out, str)` when the
/// SEGID_CLIPBOARD_PASTE NEWSEGMENT round-trip didn't establish an
/// actual subsegment) deliver the paste payload via this main-segment
/// MESSAGE instead of the dedicated clip_in queue. Treat it the same
/// as a paste — bracketed paste handling stays consistent.
fn on_message(ctx: *TuiContext, msg: [*c]const u8, _multipart: bool, _: ?*anyopaque) callconv(.c) void {
    _ = _multipart;
    if (msg == null) return;
    var len: usize = 0;
    while (len < 78 and msg[len] != 0) : (len += 1) {}
    if (len == 0) return;
    const gterm = term.gterm orelse return;

    // Control MESSAGEs coming in from durian's menu handlers. These carry
    // a CLIP: prefix so we don't confuse them with paste payloads from the
    // host clipboard bridge.
    const slice = msg[0..len];
    if (len >= 5 and std.mem.eql(u8, slice[0..5], "CLIP:")) {
        const cmd = slice[5..];
        if (std.mem.eql(u8, cmd, "copy")) {
            const text = gterm.selectionText(std.heap.c_allocator) catch null;
            if (text) |buf| {
                defer std.heap.c_allocator.free(buf);
                const payload_len = if (buf.len > 0) buf.len - 1 else 0;
                if (!arcan_tui_copy(ctx, buf.ptr)) {
                    _ = tui_clipboard_push_main(ctx, buf.ptr, payload_len);
                }
            }
            return;
        }
        // Debug / IPC test: push a hardcoded string via both paths so we
        // can probe whichever actually gets through.
        if (std.mem.eql(u8, cmd, "testpush")) {
            const s = "testpush-from-arcan";
            if (!arcan_tui_copy(ctx, s)) {
                _ = tui_clipboard_push_main(ctx, s, s.len);
            }
            return;
        }
        if (std.mem.eql(u8, cmd, "deselect")) {
            gterm.selectionClear();
            tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
            return;
        }
        // Unknown CLIP: command — ignore rather than feeding to the PTY.
        return;
    }

    // Default: host-clipboard paste arriving via durian's wrapped
    // clipboard_paste_default → message_target(wnd.external, text).
    gterm.encodeAndWritePaste(msg, len);
}

var last_frame: c_ulonglong = 0;

fn on_resize(_: *TuiContext, _: usize, _: usize, _: usize, _: usize, _: ?*anyopaque) callconv(.c) void {
    create_restore_buffer(false);
}

fn on_resized(_: *TuiContext, _: usize, _: usize, _: usize, _: usize, _: ?*anyopaque) callconv(.c) void {
    if (@atomicLoad(?[*]?*TLine, &term.restore, .seq_cst) != null and !@atomicLoad(bool, &term.alive, .seq_cst)) {
        apply_restore_buffer();
    }
    _ = @atomicRmw(c_int, &term.defer_resize, .Add, 1, .seq_cst);
    last_frame = 0;
}

// write_callback and str_callback removed — handled by ghostty ArcanHandler

fn get_shellenv() [*c]u8 {
    var shell_ptr: [*c]u8 = getenv("SHELL");

    if (getenv("PATH") == null) {
        _ = setenv("PATH", "/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin", 1);
    }

    if (getpwuid(getuid())) |pass| {
        _ = setenv("LOGNAME", pass.pw_name, 1);
        _ = setenv("USER", pass.pw_name, 1);
        _ = setenv("SHELL", pass.pw_shell, 0);
        _ = setenv("HOME", pass.pw_dir, 0);
        shell_ptr = pass.pw_shell;
    }

    if (shell_ptr == null) {
        return @constCast("/bin/sh");
    }
    return shell_ptr;
}

fn group_expand(_: *GroupEnt, in_str: [*c]const u8) callconv(.c) [*c]u8 {
    return strdup(in_str);
}

fn build_argv(appname: [*c]u8, instr: [*c]u8) [*c][*c]u8 {
    var groups = [_]GroupEnt{
        .{ .enter = '"', .leave = '"', .leave_eol = false, .expand = &group_expand },
        .{ .enter = 0, .leave = 0, .leave_eol = false, .expand = null },
    };

    const opts = ArgvParseOpt{
        .prepad = 1,
        .groups = &groups,
        .sep = ' ',
    };

    var err_ofs: isize = -1;
    const res = extract_argv(instr, opts, &err_ofs);
    if (res != null) {
        res[0] = appname;
    }
    return res;
}

fn setup_shell(argarr: ?*ArgArr, args_argv: [*c]const [*c]const u8) void {
    const unset_vars = [_][*c]const u8{
        "COLUMNS",          "LINES",       "TERMCAP",
        "ARCAN_ARG",        "ARCAN_APPLPATH", "ARCAN_APPLTEMPPATH",
        "ARCAN_FRAMESERVER_LOGDIR", "ARCAN_RESOURCEPATH",
        "ARCAN_SHMKEY",     "ARCAN_SOCKIN_FD",
    };

    for (unset_vars) |v| {
        _ = unsetenv(v);
    }

    _ = setenv("LANG", "en_GB.UTF-8", 0);
    _ = setenv("LC_CTYPE", "en_GB.UTF-8", 0);
    _ = setenv("TERM", "xterm-256color", 1);

    var ind: c_int = 0;
    var val: [*c]const u8 = undefined;
    while (arg_lookup(argarr, "env", ind, &val)) {
        _ = putenv(strdup(val));
        ind += 1;
    }

    if (arg_lookup(argarr, "chdir", 0, &val)) {
        _ = chdir(val);
    }

    // reset signals
    var sigset_buf: [128]u8 = std.mem.zeroes([128]u8);
    _ = sigemptyset(@ptrCast(&sigset_buf));
    _ = pthread_sigmask(SIG_SETMASK, @ptrCast(&sigset_buf), null);

    var i: usize = 1;
    while (i < 32) : (i += 1) {
        _ = signal(@intCast(i), SIG_DFL);
    }

    const exec_arg_env = getenv("ARCAN_TERMINAL_EXEC");
    var exec_arg: [*c]u8 = exec_arg_env;

    if (arg_lookup(argarr, "exec", 0, &val)) {
        exec_arg = strdup(val);
        if (term.screen) |scr| {
            c.arcan_tui_ident(scr, exec_arg);
        }
    }

    if (exec_arg != null) {
        const inarg = getenv("ARCAN_TERMINAL_ARGV");

        const pidfd_in = getenv("ARCAN_TERMINAL_PIDFD_IN");
        const pidfd_out = getenv("ARCAN_TERMINAL_PIDFD_OUT");

        if (pidfd_in != null and pidfd_out != null) {
            const infd = @as(c_int, @intCast(strtol(pidfd_in, null, 10)));
            const outfd = @as(c_int, @intCast(strtol(pidfd_out, null, 10)));
            var pid = getpid();
            _ = write(outfd, &pid, @sizeOf(c.pid_t));
            _ = read(infd, &pid, 1);
            _ = close(infd);
            _ = close(outfd);
        }

        _ = unsetenv("ARCAN_TERMINAL_EXEC");
        _ = unsetenv("ARCAN_TERMINAL_PIDFD_IN");
        _ = unsetenv("ARCAN_TERMINAL_PIDFD_OUT");
        _ = unsetenv("ARCAN_TERMINAL_ARGV");

        if (inarg != null) {
            _ = execvp(exec_arg, build_argv(exec_arg, @constCast(getenv("ARCAN_TERMINAL_ARGV"))));
        } else {
            var sh_args = [_][*c]const u8{ "/bin/sh", "-c", exec_arg, null };
            _ = execv("/bin/sh", &sh_args);
        }
        exit(EXIT_FAILURE);
    }

    _ = execvp(args_argv[0], args_argv);
    exit(EXIT_FAILURE);
}

fn on_exec_state(_: *TuiContext, state: c_int, _: ?*anyopaque) callconv(.c) void {
    if (term.pty) |pty| {
        if (state == 0)
            _ = shl_pty_signal(pty, SIGCONT)
        else if (state == 1)
            _ = shl_pty_signal(pty, SIGSTOP)
        else if (state == 2)
            _ = shl_pty_signal(pty, SIGHUP);
    }
}

fn setup_build_term() bool {
    const scr = term.screen orelse return false;

    var rows: usize = 0;
    var cols: usize = 0;
    c.arcan_tui_reset(scr);
    if (term.gterm) |gterm| gterm.fullReset();
    c.arcan_tui_dimensions(scr, &rows, &cols);
    term.complete_signal = false;

    if (term.pipe) {
        term.child = shl_pipe_open(&term.pty, true);
    } else {
        term.child = shl_pty_open(&term.pty, null, null, @intCast(cols), @intCast(rows), term.keep_stderr);
    }

    if (term.child < 0) {
        c.arcan_tui_destroy(scr, "Shell process died unexpectedly");
        term.screen = null;
        return false;
    }

    // child process
    if (term.child == 0) {
        var val: [*c]const u8 = undefined;
        var argv = [_][*c]const u8{ get_shellenv(), "-i", null, null };

        if (arg_lookup(term.args, "cmd", 0, &val) and val != null) {
            argv[2] = strdup(val);
        }

        if (arg_lookup(term.args, "login", 0, &val)) {
            argv[1] = "-p";
            // try /bin/login or /usr/bin/login
            var stat_buf: [256]u8 = undefined;
            if (stat("/bin/login", @ptrCast(&stat_buf)) == 0) {
                argv[0] = "/bin/login";
            } else if (stat("/usr/bin/login", @ptrCast(&stat_buf)) == 0) {
                argv[0] = "/usr/bin/login";
            }
        }

        setup_shell(term.args, &argv);
        return false;
    }

    // parent — spawn background thread
    var pth: c.pthread_t = undefined;
    var pthattr: c.pthread_attr_t = undefined;
    _ = pthread_attr_init(&pthattr);
    _ = pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
    @atomicStore(bool, &term.alive, true, .seq_cst);

    if (term.pipe) {
        const flags = fcntl(STDOUT_FILENO, F_GETFL);
        _ = fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK);
        if (-1 == pthread_create(&pth, &pthattr, &pump_pipe, null)) {
            @atomicStore(bool, &term.alive, false, .seq_cst);
            return false;
        }
    } else {
        if (-1 == pthread_create(&pth, &pthattr, &pump_pty, null)) {
            @atomicStore(bool, &term.alive, false, .seq_cst);
            return false;
        }
    }

    return true;
}

fn on_reset(tui: *TuiContext, state: c_int, tag: ?*anyopaque) callconv(.c) void {
    switch (state) {
        0 => {
            // soft reset
            c.arcan_tui_reset(tui);
            if (term.gterm) |gterm| gterm.fullReset();
        },
        1 => {
            // hard reset — re-execute
            reset_restore_buffer();
            if (term.gterm) |gterm| gterm.fullReset();

            if (@atomicLoad(bool, &term.alive, .seq_cst)) {
                on_exec_state(tui, 2, tag);
                var q: u8 = 'q';
                _ = write(term.dirtyfd, &q, 1);
                while (q != 'Q') {
                    _ = read(term.dirtyfd, &q, 1);
                }
                @atomicStore(bool, &term.alive, false, .seq_cst);
            }

            if (!term.die_on_term) {
                if (term.screen) |scr| {
                    c.arcan_tui_progress(scr, TUI_PROGRESS_INTERNAL, 0.0);
                }
            }

            if (term.initial_hint.rows != 0 and term.initial_hint.cols != 0) {
                if (term.screen) |scr| {
                    c.arcan_tui_wndhint(scr, null, .{
                        .max_rows = @intCast(term.initial_hint.rows),
                        .min_rows = @intCast(term.initial_hint.rows),
                        .max_cols = @intCast(term.initial_hint.cols),
                        .min_cols = @intCast(term.initial_hint.cols),
                        .anch_row = 0,
                        .anch_col = 0,
                        .hide = 0,
                        .embed = 0,
                    });
                }
            }

            if (term.pty) |pty| {
                shl_pty_close(pty);
                term.pty = null;
            }
            _ = setup_build_term();
        },
        else => {},
    }
}

fn on_label_query(_: *TuiContext, index: usize, _: [*c]const u8, _: [*c]const u8, dstlbl: *TuiLabelent, _: ?*anyopaque) callconv(.c) bool {
    var current: usize = 0;

    for (&labels) |*entry| {
        if (entry.disabled) continue;

        if (index != current) {
            current += 1;
        } else {
            dstlbl.* = entry.ent;
            return true;
        }
    }

    // delegate to TSM legacy labels
    if (term.screen) |scr| {
        return legacy_query_label(scr, index - current, dstlbl);
    }
    return false;
}

fn on_label_input(_: *TuiContext, label: [*c]const u8, active: bool, _: ?*anyopaque) callconv(.c) bool {
    if (!active) return true;

    for (&labels) |*entry| {
        if (strcmp(label, &entry.ent.label) == 0 and !entry.disabled) {
            entry.handler(entry);
            return true;
        }
    }

    if (term.screen) |scr| {
        return legacy_consume_label(scr, label);
    }
    return false;
}

fn on_bchunk(_: *TuiContext, input: bool, _: u64, fd: c_int, _: [*c]const u8, _: ?*anyopaque) callconv(.c) void {
    if (input or term.pending_bout_buf == null) return;

    const buf = term.pending_bout_buf.?;
    const sz = term.pending_bout_buf_sz;

    const fpek = fdopen(fd, "w+") orelse return;
    _ = fwrite(@ptrCast(buf), sz, 1, fpek);
    _ = fclose(fpek);
    free(@ptrCast(buf));
    term.pending_bout_buf = null;
}

fn parse_color(inv: [*c]const u8, outv: *[4]u8) c_int {
    return sscanf(inv, "%hhu,%hhu,%hhu,%hhu", &outv[0], &outv[1], &outv[2], &outv[3]);
}

/// Apply a named palette to the ghostty terminal. Supports the same names as TSM.
fn applyNamedPalette(name: [*c]const u8) void {
    const gterm = term.gterm orelse return;
    if (name == null) return;

    // Named palettes
    const palettes = struct {
        const solarized = [16][3]u8{
            .{ 0x07, 0x36, 0x42 }, .{ 0xdc, 0x32, 0x2f }, .{ 0x85, 0x99, 0x00 }, .{ 0xb5, 0x89, 0x00 },
            .{ 0x26, 0x8b, 0xd2 }, .{ 0xd3, 0x36, 0x82 }, .{ 0x2a, 0xa1, 0x98 }, .{ 0xee, 0xe8, 0xd5 },
            .{ 0x00, 0x2b, 0x36 }, .{ 0xcb, 0x4b, 0x16 }, .{ 0x58, 0x6e, 0x75 }, .{ 0x65, 0x7b, 0x83 },
            .{ 0x83, 0x94, 0x96 }, .{ 0x6c, 0x71, 0xc4 }, .{ 0x93, 0xa1, 0xa1 }, .{ 0xfd, 0xf6, 0xe3 },
        };
        const srcery = [16][3]u8{
            .{ 0x1C, 0x1B, 0x19 }, .{ 0xEF, 0x29, 0x17 }, .{ 0x51, 0x9F, 0x50 }, .{ 0xFB, 0xB8, 0x29 },
            .{ 0x2C, 0x78, 0xBF }, .{ 0xE0, 0x2C, 0x6D }, .{ 0x0A, 0xAD, 0xB0 }, .{ 0xBA, 0xA6, 0x7F },
            .{ 0x91, 0x83, 0x75 }, .{ 0xF7, 0x57, 0x41 }, .{ 0x98, 0xBC, 0x37 }, .{ 0xFE, 0xD0, 0x6E },
            .{ 0x68, 0xA8, 0xE4 }, .{ 0xFF, 0x5C, 0x8F }, .{ 0x53, 0xFD, 0xE9 }, .{ 0xFC, 0xE8, 0xC3 },
        };
    };

    const name_slice = std.mem.span(name);
    const pal: ?*const [16][3]u8 = if (std.mem.eql(u8, name_slice, "solarized") or
        std.mem.eql(u8, name_slice, "solarized-black") or
        std.mem.eql(u8, name_slice, "solarized-white"))
        &palettes.solarized
    else if (std.mem.eql(u8, name_slice, "srcery"))
        &palettes.srcery
    else
        null;

    if (pal) |p| {
        for (p, 0..) |rgb, i| {
            gterm.setColor(@intCast(i), rgb[0], rgb[1], rgb[2]);
        }
    }
}

fn on_relative(ctx: *TuiContext, dy: isize, _: isize, _: ?*anyopaque) callconv(.c) void {
    if (dy < 0) {
        c.arcan_tui_scroll_up(ctx, @intCast(-1 * dy));
    } else {
        c.arcan_tui_scroll_down(ctx, @intCast(dy));
    }
}

fn copy_palette(tc: *TuiContext, out: *[TUI_COL_LIMIT * 3]u8) bool {
    var i: c_int = TUI_COL_TBASE;
    while (i < TUI_COL_LIMIT) : (i += 1) {
        const ofs: usize = @intCast((i - TUI_COL_TBASE) * 3);
        c.arcan_tui_get_color(tc, i, &out[ofs]);
    }

    var ref = [3]u8{ 0, 0, 0 };
    c.arcan_tui_get_bgcolor(tc, 1, &ref);
    return ref[0] == 255;
}

fn on_tick(ctx: *TuiContext, _: ?*anyopaque) callconv(.c) void {
    const in_select = tuiGetInSelect(ctx);
    const scrollback = tuiGetScrollback(ctx);

    if (in_select and scrollback != 0) {
        if (scrollback < 0) {
            if (scrollback < -1) {
                tuiSetScrollback(ctx, scrollback + 1);
            } else {
                c.arcan_tui_scroll_up(ctx, @intCast(if (scrollback < 0) -scrollback else scrollback));
                tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
            }
        } else {
            if (scrollback > 1) {
                tuiSetScrollback(ctx, scrollback - 1);
            } else {
                c.arcan_tui_scroll_down(ctx, @intCast(scrollback));
                tuiGetDirtyPtr(ctx).* |= DIRTY_FULL;
            }
        }
    }
}

// Exported public symbols

export fn cursor_style_arg(args: ?*ArgArr) callconv(.c) c_int {
    var val: [*c]const u8 = undefined;
    if (!arg_lookup(args, "cursor", 0, &val) or val == null)
        return CURSOR_BLOCK;

    if (strcmp(val, "underline") == 0)
        return CURSOR_UNDER
    else if (strcmp(val, "hollow") == 0)
        return CURSOR_HOLLOW
    else if (strcmp(val, "bar") == 0)
        return CURSOR_BAR;

    return CURSOR_BLOCK;
}

export fn afsrv_terminal(con: ?*ArcanShmifCont, args: ?*ArgArr) callconv(.c) c_int {
    if (con == null)
        return EXIT_FAILURE;
    const conn = con.?;

    var val: [*c]const u8 = undefined;

    // pipe mode
    if (arg_lookup(args, "pipe", 0, &val)) {
        term.pipe = true;
        if (val != null and strcmp(val, "lf") == 0)
            term.pipe_mode = .plain_lf;
    }

    // keep_stderr
    if (arg_lookup(args, "keep_stderr", 0, &val)) {
        term.keep_stderr = dup(STDERR_FILENO);
        _ = fcntl(term.keep_stderr, F_SETFD, FD_CLOEXEC);
        const ndev = open("/dev/null", O_WRONLY);
        _ = dup2(ndev, STDERR_FILENO);
        _ = close(ndev);
    }

    // cli mode
    if (arg_lookup(args, "cli", 0, &val)) {
        if (val != null and strcmp(val, "lua") == 0)
            return arcterm_luacli_run(conn, args.?)
        else
            return arcterm_cli_run(conn, args.?);
    }

    // help
    if (arg_lookup(args, "help", 0, &val)) {
        dump_help();
        return EXIT_SUCCESS;
    }

    // set up TUI callbacks
    var cbcfg: TuiCbcfg = std.mem.zeroes(TuiCbcfg);
    cbcfg.input_mouse_motion = @ptrCast(@constCast(&on_mouse_motion));
    cbcfg.input_mouse_button = @ptrCast(@constCast(&on_mouse_button));
    cbcfg.query_label = @ptrCast(@constCast(&on_label_query));
    cbcfg.input_label = @ptrCast(@constCast(&on_label_input));
    cbcfg.input_utf8 = @ptrCast(@constCast(&on_u8));
    cbcfg.input_key = @ptrCast(@constCast(&on_key));
    cbcfg.bchunk = @ptrCast(@constCast(&on_bchunk));
    cbcfg.utf8 = @ptrCast(@constCast(&on_utf8_paste));
    cbcfg.message = @ptrCast(@constCast(&on_message));
    cbcfg.resize = @ptrCast(@constCast(&on_resize));
    cbcfg.resized = @ptrCast(@constCast(&on_resized));
    cbcfg.exec_state = @ptrCast(@constCast(&on_exec_state));
    cbcfg.reset = @ptrCast(@constCast(&on_reset));
    cbcfg.seek_relative = @ptrCast(@constCast(&on_relative));
    cbcfg.tick = @ptrCast(@constCast(&on_tick));

    term.screen = c.arcan_tui_setup(conn, null, &cbcfg, @sizeOf(TuiCbcfg));

    if (term.screen == null)
        return EXIT_FAILURE;

    const scr = term.screen.?;
    _ = c.arcan_tui_cursor_style(scr, cursor_style_arg(args), null);

    // make preroll state copy of legacy-palette range
    var palette_copy: [TUI_COL_LIMIT * 3]u8 = undefined;
    const custom_palette = copy_palette(scr, &palette_copy);

    term.args = args;

    // BUG-13: skip ghostty init while rows/cols=0 (before the first
    // resize has propagated). ghosttyResizeHook creates the bridge
    // lazily once the real dimensions arrive, so we never render a
    // bogus first frame at a fallback size. Null term.gterm is
    // handled everywhere already.
    {
        var rows: usize = 0;
        var cols: usize = 0;
        c.arcan_tui_dimensions(scr, &rows, &cols);
        if (rows > 0 and cols > 0) {
            const pty_fd: i32 = if (term.pty) |pty| shl_pty_get_fd(pty, true) else -1;
            term.gterm = GhosttyBridge.init(
                std.heap.c_allocator,
                @intCast(cols),
                @intCast(rows),
                pty_fd,
                @ptrCast(scr),
            ) catch {
                c.arcan_tui_destroy(scr, "Couldn't setup terminal emulator");
                term.screen = null;
                return EXIT_FAILURE;
            };
        }
    }

    // Install ghostty-backed hooks (replaces arcan_tui_allow_deprecated)
    installGhosttyHooks(scr);

    // keep_alive
    if (arg_lookup(args, "keep_alive", 0, null)) {
        term.die_on_term = false;
        c.arcan_tui_progress(scr, TUI_PROGRESS_INTERNAL, 0.0);
    }

    // record
    if (arg_lookup(args, "record", 0, &val) and val != null) {
        const fd = open(val, O_WRONLY | O_CREAT, @as(c_int, 0o600));
        if (fd != -1) {
            var ev: ArcanEvent = std.mem.zeroes(ArcanEvent);
            ev.unnamed_0.unnamed_0.category = EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = fd;
            @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0..6], "tuiani");
            tui_event_inject(scr, &ev);
            _ = close(fd);
        }
    }

    // autofit
    if (arg_lookup(args, "autofit", 0, null)) {
        term.fit_contents = true;
    }

    // palette: apply named palette to ghostty terminal
    if (arg_lookup(args, "palette", 0, &val)) {
        applyNamedPalette(val);
    }

    // synch back custom colors from TUI preroll
    if (custom_palette) {
        if (term.gterm) |gterm| {
            var i: u8 = 0;
            while (i < VTE_COLOR_NUM) : (i += 1) {
                const ofs: usize = @as(usize, i) * 3;
                gterm.setColor(i, palette_copy[ofs], palette_copy[ofs + 1], palette_copy[ofs + 2]);
            }
        }
    }

    // CI color overrides: set individual palette entries
    var ci_ind: c_int = 0;
    var ccol: [4]u8 = undefined;
    while (arg_lookup(args, "ci", ci_ind, &val)) {
        if (4 == parse_color(val, &ccol)) {
            if (term.gterm) |gterm| {
                gterm.setColor(ccol[0], ccol[1], ccol[2], ccol[3]);
            }
        }
        ci_ind += 1;
    }

    // initial draw
    c.arcan_tui_erase_screen(scr, false);
    const init_refresh_rc = c.arcan_tui_refresh(scr);
    {
        var dbuf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&dbuf, "[DIAG arcterm] initial arcan_tui_refresh rc={d}, entering main loop\n", .{init_refresh_rc}) catch "[DIAG arcterm] initial refresh\n";
        std.fs.File.stderr().writeAll(msg) catch {};
    }

    _ = signal(SIGHUP, &sighuph);

    // socket pair for thread communication
    var pair: [2]c_int = undefined;
    if (-1 == socketpair(AF_UNIX, SOCK_STREAM, 0, &pair))
        return EXIT_FAILURE;

    var flags: c_int = undefined;
    flags = fcntl(pair[0], F_GETFD);
    if (flags != -1) _ = fcntl(pair[0], F_SETFD, flags | FD_CLOEXEC);
    flags = fcntl(pair[1], F_GETFD);
    if (flags != -1) _ = fcntl(pair[1], F_SETFD, flags | FD_CLOEXEC);

    term.dirtyfd = pair[0];
    term.signalfd = pair[1];

    if (!setup_build_term())
        return EXIT_FAILURE;

    // Update bridge's PTY fd now that PTY is open
    if (term.gterm) |gterm| {
        if (term.pty) |pty| {
            gterm.pty_fd = shl_pty_get_fd(pty, true);
            gterm.stream.handler.pty_fd = gterm.pty_fd;
        }
    }

    // fetch fg/bg from ghostty terminal
    if (term.gterm) |gterm| {
        const bg = gterm.getColor(VTE_COLOR_BACKGROUND_IDX);
        const fg = gterm.getColor(VTE_COLOR_FOREGROUND_IDX);
        var bgc = [3]u8{ bg.r, bg.g, bg.b };
        var fgc = [3]u8{ fg.r, fg.g, fg.b };
        c.arcan_tui_set_color(scr, TUI_COL_BG, &bgc);
        c.arcan_tui_set_color(scr, TUI_COL_TEXT, &fgc);
    }
    c.arcan_tui_reset_labels(scr);

    // Main event loop
    // CRITICAL: term.screen is checked before every use. If arcan_tui_process
    // returns an error, we set term.screen = null and break.
    var diag_loop_count: u32 = 0;
    while (@atomicLoad(bool, &term.alive, .seq_cst) or !term.die_on_term) {
        const current_scr = term.screen orelse break;
        _ = pthread_mutex_lock(&term.synch);

        var screen_ptr: ?*TuiContext = current_scr;
        const res: TuiProcessRes = c.arcan_tui_process(
            @ptrCast(&screen_ptr),
            1,
            &term.signalfd,
            1,
            -1,
        );

        if (res.errc < TUI_ERRC_OK) {
            // CRITICAL: mark screen as invalid on error
            term.screen = null;
            _ = pthread_mutex_unlock(&term.synch);
            break;
        }

        // Re-validate: arcan_tui_process may have modified screen_ptr or
        // a callback during processing may have destroyed the context
        const live_scr = screen_ptr orelse {
            term.screen = null;
            _ = pthread_mutex_unlock(&term.synch);
            break;
        };

        // indicate completion on terminal death (once per cycle)
        if (!@atomicLoad(bool, &term.alive, .seq_cst) and !term.die_on_term and !term.complete_signal) {
            c.arcan_tui_progress(live_scr, TUI_PROGRESS_INTERNAL, 1.0);
            term.complete_signal = true;
        }

        const refresh_rc = c.arcan_tui_refresh(live_scr);

        // DIAGNOSTIC: log first 3 refresh calls from arcterm main loop
        if (diag_loop_count < 3) {
            diag_loop_count += 1;
            var dbuf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&dbuf, "[DIAG arcterm loop #{d}] tui_refresh rc={d}, process errc={d}, alive={}\n", .{
                diag_loop_count, refresh_rc, res.errc, @atomicLoad(bool, &term.alive, .seq_cst),
            }) catch "[DIAG arcterm] bufPrint failed\n";
            std.fs.File.stderr().writeAll(msg) catch {};
        }

        // create restore buffer if terminal died and no restore yet
        if (!@atomicLoad(bool, &term.alive, .seq_cst) and
            @atomicLoad(?[*]?*TLine, &term.restore, .seq_cst) == null)
        {
            create_restore_buffer(term.fit_contents);
        }

        _ = pthread_mutex_unlock(&term.synch);

        if (res.ok) {
            var buf: [256]u8 = undefined;
            _ = read(term.signalfd, &buf, 256);
            _ = pthread_mutex_lock(&term.hold);
            _ = pthread_mutex_unlock(&term.hold);
        }
    }

    if (term.keep_stderr != 0)
        _ = close(term.keep_stderr);

    if (term.screen) |final_scr| {
        c.arcan_tui_destroy(final_scr, null);
        term.screen = null;
    }

    return EXIT_SUCCESS;
}
