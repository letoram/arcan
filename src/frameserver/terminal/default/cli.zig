// Zig reimplementation of cli.c
// Drop-in C-ABI-compatible replacement for the arcan terminal CLI mode.
//
// Exports: arcterm_cli_run
//
const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct — every c.X used below routed to the replacement module
/// that owns the symbol. Eliminates the @cImport("arcan_tui.h" / ...) block.
const c = struct {
    // Libc / POSIX
    pub const struct_stat = libc.struct_stat;
    pub const stat = libc.stat;

    // shmif, tui, readline, cli_builtin types
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const struct_tui_context = shmif.struct_tui_context;
    pub const struct_tui_cbcfg = shmif.struct_tui_cbcfg;
    pub const struct_tui_cell = shmif.struct_tui_cell;
    pub const struct_tui_screen_attr = shmif.struct_tui_screen_attr;
    pub const struct_tui_labelent = shmif.struct_tui_labelent;
    pub const struct_tui_readline_opts = shmif.struct_tui_readline_opts;
    pub const struct_group_ent = shmif.struct_group_ent;
    pub const struct_argv_parse_opt = shmif.struct_argv_parse_opt;
    pub const struct_cli_state = shmif.struct_cli_state;
    pub const struct_cli_command = shmif.struct_cli_command;
    pub const struct_ext_cmd = shmif.struct_ext_cmd;

    // Launch-mode enum values (cli_builtin.h)
    pub const LAUNCH_UNSET = shmif.LAUNCH_UNSET;
    pub const LAUNCH_VT100 = shmif.LAUNCH_VT100;
    pub const LAUNCH_TUI = shmif.LAUNCH_TUI;
    pub const LAUNCH_WL = shmif.LAUNCH_WL;
    pub const LAUNCH_X11 = shmif.LAUNCH_X11;
    pub const LAUNCH_SHMIF = shmif.LAUNCH_SHMIF;

    // readline / tui constants
    pub const READLINE_STATUS_DONE = shmif.READLINE_STATUS_DONE;
    pub const READLINE_STATUS_TERMINATE = shmif.READLINE_STATUS_TERMINATE;
    pub const TUI_ATTR_COLOR_INDEXED = shmif.TUI_ATTR_COLOR_INDEXED;
    pub const TUI_COL_UI = shmif.TUI_COL_UI;
    pub const TUI_ERRC_OK = shmif.TUI_ERRC_OK;
    pub const TUI_MESSAGE_FAILURE = shmif.TUI_MESSAGE_FAILURE;
    pub const TUI_WND_HANDOVER = shmif.TUI_WND_HANDOVER;
    pub const TUIK_F1 = shmif.TUIK_F1;
    pub const TUIK_F2 = shmif.TUIK_F2;
    pub const TUIK_F3 = shmif.TUIK_F3;
    pub const TUIK_F4 = shmif.TUIK_F4;
    pub const SEGID_DEBUG = shmif.SEGID_DEBUG;
    pub const EINVAL = shmif.EINVAL;

    // arg_lookup + extract_argv + cli builtins
    pub const arg_lookup = shmif.arg_lookup;
    pub const extract_argv = shmif.extract_argv;
    pub const cli_get_builtin = shmif.cli_get_builtin;

    // arcan_tui_*
    pub const arcan_tui_setup = shmif.arcan_tui_setup;
    pub const arcan_tui_destroy = shmif.arcan_tui_destroy;
    pub const arcan_tui_process = shmif.arcan_tui_process;
    pub const arcan_tui_refresh = shmif.arcan_tui_refresh;
    pub const arcan_tui_ident = shmif.arcan_tui_ident;
    pub const arcan_tui_message = shmif.arcan_tui_message;
    pub const arcan_tui_cursor_style = shmif.arcan_tui_cursor_style;
    pub const arcan_tui_handover = shmif.arcan_tui_handover;
    pub const arcan_tui_request_subwnd = shmif.arcan_tui_request_subwnd;
    pub const arcan_tui_readline_setup = shmif.arcan_tui_readline_setup;
    pub const arcan_tui_readline_finished = shmif.arcan_tui_readline_finished;
    pub const arcan_tui_readline_prompt = shmif.arcan_tui_readline_prompt;
    pub const arcan_tui_readline_reset = shmif.arcan_tui_readline_reset;
};

// Libc functions used directly (no c.X prefix)
const malloc = libc.malloc;
const free = libc.free;
const strdup = libc.strdup;
const strtoul = libc.strtoul;
const strlen = libc.strlen;
const strcmp = libc.strcmp;
const memset = libc.memset;
const memcpy = libc.memcpy;
const getenv = libc.getenv;
const getcwd = libc.getcwd;
const stat = libc.stat;
const snprintf = libc.snprintf;
const asprintf = libc.asprintf;

fn getErrnoValue() c_int {
    return libc.__errno_location().*;
}

// cursor_style_arg — provided by arcterm.zig (same exe). Signature matches
// the old extern decl that cli.zig carried alongside its @cImport block.
extern "c" fn cursor_style_arg(args: [*c]c.struct_arg_arr) c_int;

// Constants

const PATH_MAX: usize = 4096;

const LAUNCH_UNSET: c_uint = c.LAUNCH_UNSET;
const LAUNCH_VT100: c_uint = c.LAUNCH_VT100;
const LAUNCH_TUI: c_uint = c.LAUNCH_TUI;
const LAUNCH_WL: c_uint = c.LAUNCH_WL;
const LAUNCH_X11: c_uint = c.LAUNCH_X11;
const LAUNCH_SHMIF: c_uint = c.LAUNCH_SHMIF;

// Static state

var cli_state_g: c.struct_cli_state = .{
    .env = null,
    .cwd = null,
    .mode = LAUNCH_VT100,
    .alive = true,
    .bgalpha = 255,
    .die_on_finish = false,
    .id_counter = 0,
    .pending = [_]c.struct_ext_cmd{std.mem.zeroes(c.struct_ext_cmd)} ** 4,
    .blocked = false,
    .in_debug = null,
    .prompt = null,
    .prompt_sz = 0,
};

// Helper functions

fn free_strtbl(arg: [*c][*c]u8) void {
    if (arg == null) return;
    var i: usize = 0;
    while (arg[i] != null) : (i += 1) {
        free(@ptrCast(arg[i]));
    }
    free(@ptrCast(arg));
}

fn duplicate_strtbl(arg: [*c][*c]u8, prepad: usize, pad: usize) [*c][*c]u8 {
    var i: usize = 0;

    // nothing to copy? at least alloc pad buffer
    if (arg == null or arg[0] == null) {
        if (pad > 0 or prepad > 0) {
            const buf_sz = @sizeOf([*c]u8) * (pad + prepad + 1);
            const raw = malloc(buf_sz) orelse return null;
            _ = memset(raw, 0, buf_sz);
            return @ptrCast(@alignCast(raw));
        }
        return null;
    }

    // count
    while (arg[i] != null) : (i += 1) {}

    // copy + add NULL
    const alloc_sz = @sizeOf([*c]u8) * (i + prepad + pad + 1);
    const raw = malloc(alloc_sz) orelse return null;
    const buf: [*c][*c]u8 = @ptrCast(@alignCast(raw));

    for (0..prepad) |j| {
        buf[j] = null;
    }

    for (0..i) |j| {
        buf[j + prepad] = strdup(arg[j]);
    }

    for (i..i + pad + 1) |j| {
        buf[j + prepad] = null;
    }

    return buf;
}

fn free_cmd(cmd: *c.struct_ext_cmd) void {
    cmd.id = 0;
    free_strtbl(cmd.env);
    free_strtbl(cmd.argv);
    free(@ptrCast(cmd.wd));
    if (cmd.closure) |closure_fn| {
        closure_fn(cmd.closure_tag);
    }
    const ptr: *anyopaque = @ptrCast(cmd);
    _ = memset(ptr, 0, @sizeOf(c.struct_ext_cmd));
}

fn get_terminal_bin() [*c]const u8 {
    if (comptime @import("builtin").os.tag == .linux) {
        return "/proc/self/exe";
    } else {
        var statbuf: c.struct_stat = undefined;
        if (stat("/usr/local/bin/afsrv_terminal", &statbuf) != -1)
            return "/usr/local/bin/afsrv_terminal";
        if (stat("/usr/bin/afsrv_terminal", &statbuf) != -1)
            return "/usr/bin/afsrv_terminal";
        return "afsrv_terminal";
    }
}

fn get_waybridge_bin() [*c]const u8 {
    var statbuf: c.struct_stat = undefined;
    if (stat("/usr/local/bin/arcan-wayland", &statbuf) != -1)
        return "/usr/local/bin/arcan-wayland";
    if (stat("/usr/bin/arcan-wayland", &statbuf) != -1)
        return "/usr/bin/arcan-wayland";
    return "arcan-wayland";
}

fn argv_to_env(in: [*c][*c]u8) [*c]u8 {
    const prefix = "ARCAN_TERMINAL_ARGV=";
    var buflen: usize = prefix.len + 1; // +1 for null terminator space in prefix sizeof

    var i: usize = 0;
    while (in[i] != null) : (i += 1) {
        var esclen: usize = 0;
        const arg: [*c]const u8 = in[i];
        var j: usize = 0;
        while (arg[j] != 0) : (j += 1) {
            const ch = arg[j];
            if (ch == ' ' or ch == '"')
                esclen += 1;
            esclen += 1;
        }
        buflen += esclen + 1;
    }

    // allocate result
    const raw = malloc(buflen) orelse return null;
    const res: [*c]u8 = @ptrCast(raw);
    var ofs: usize = 0;

    // start with the prefix string
    _ = memcpy(@ptrCast(res), @ptrCast(prefix.ptr), prefix.len);
    ofs = prefix.len;

    // repeat the calc-dance with escaping
    i = 0;
    while (in[i] != null) : (i += 1) {
        const arg: [*c]const u8 = in[i];
        var j: usize = 0;
        while (arg[j] != 0) : (j += 1) {
            const ch = arg[j];
            if (ch == ' ' or ch == '"') {
                res[ofs] = '\\';
                ofs += 1;
            }
            res[ofs] = ch;
            ofs += 1;
        }
        res[ofs] = ' ';
        ofs += 1;
    }
    res[ofs] = 0;

    return res;
}

fn prepend_str(a: [*c]const u8, b: [*c]const u8) [*c]u8 {
    const alen = strlen(a);
    const blen = strlen(b);
    const len = alen + blen;
    const raw = malloc(len + 1) orelse return null;
    const buf: [*c]u8 = @ptrCast(raw);
    if (len == 0)
        return null;

    _ = memcpy(@ptrCast(buf), @ptrCast(a), alen);
    _ = memcpy(@ptrCast(buf + alen), @ptrCast(b), blen);
    buf[len] = 0;

    return buf;
}

// bin, argv and env are aliases into offsets of the contents of cmd, if any
// dynamic allocation occurs, replace in [cmd] as they will be freed after the
// exec_handover is done
fn setup_cmd_mode(
    cmd: *c.struct_ext_cmd,
    bin: *[*c]const u8,
    argv: *[*c][*c]u8,
    env: *[*c][*c]u8,
    flags: *c_int,
) void {
    bin.* = cmd.argv[0];
    env.* = cmd.env;
    argv.* = cmd.argv;
    flags.* = cmd.flags;

    switch (cmd.mode) {
        LAUNCH_UNSET => {},
        LAUNCH_VT100 => {
            bin.* = get_terminal_bin();

            // gives us ARCAN_TERMINAL_ARGV=argv[1] .. n
            const arg_env = argv_to_env(cmd.argv + 1);
            const arg_exec = prepend_str("ARCAN_TERMINAL_EXEC=", cmd.argv[0]);

            // which means we no longer need argv
            const new_arg_raw = malloc(@sizeOf([*c]u8) * 2) orelse return;
            const new_arg: [*c][*c]u8 = @ptrCast(@alignCast(new_arg_raw));
            new_arg[0] = strdup("afsrv_terminal");
            new_arg[1] = null;
            free_strtbl(cmd.argv);
            cmd.argv = new_arg;
            argv.* = new_arg;

            // attach them to our env
            const new_env = duplicate_strtbl(cmd.env, 5, 0);
            new_env[0] = arg_exec;
            new_env[1] = arg_env;

            // question if we should build the entire thing from the arguments that we
            // ourselves got (sans -cli) or lest let a few of them through for color
            // overrides and the likes
            _ = asprintf(@ptrCast(&new_env[2]), "ARCAN_ARG=keep_alive:autofit");
            if (cli_state_g.in_debug != null) {
                new_env[3] = strdup(cli_state_g.in_debug);
            }

            free_strtbl(cmd.env);
            cmd.env = new_env;
            env.* = cmd.env;
        },
        LAUNCH_TUI, LAUNCH_SHMIF => {
            // just treat them the same for the time being
        },
        LAUNCH_X11, LAUNCH_WL => {
            const new_arg = duplicate_strtbl(cmd.argv, 2, 0);
            bin.* = get_waybridge_bin();
            free_strtbl(cmd.argv);
            cmd.argv = new_arg;
            argv.* = new_arg;

            // wayland needs xdg_runtime_dir
            const new_env = duplicate_strtbl(cmd.env, 1, 0);
            const rtd = getenv("XDG_RUNTIME_DIR");
            const rtd_str: [*c]const u8 = if (rtd != null) rtd else "/tmp";
            if (-1 == asprintf(@ptrCast(&new_env[0]), "XDG_RUNTIME_DIR=%s", rtd_str)) {
                free_strtbl(new_env);
            } else {
                env.* = new_env;
            }

            new_arg[0] = strdup("arcan-wayland");
            new_arg[1] = strdup(if (cmd.mode == LAUNCH_X11) "-exec-x11" else "-exec");
        },
        else => {},
    }
}

fn on_subwindow(
    T: ?*c.struct_tui_context,
    conn: [*c]c.struct_arcan_shmif_cont,
    id: u32,
    seg_type: u8,
    _: ?*anyopaque,
) callconv(.c) bool {
    var res = false;

    if (seg_type == @as(u8, @intCast(c.SEGID_DEBUG)))
        return false;

    // find the pending command and handover_exec
    for (0..4) |i| {
        if (cli_state_g.pending[i].id == id) {
            const cmd = &cli_state_g.pending[i];

            // inherited state like current working directory, but ignore if we
            // can't store / restore, better than failing outright
            if (malloc(PATH_MAX)) |tmp_raw| {
                const tmp: [*c]u8 = @ptrCast(tmp_raw);
                if (getcwd(tmp, PATH_MAX) == null) {
                    free(tmp_raw);
                }
            }

            // might fiddle with offsets and alias, cmd is still responsible for alloc
            var bin: [*c]const u8 = undefined;
            var env_ptr: [*c][*c]u8 = undefined;
            var argv_ptr: [*c][*c]u8 = undefined;
            var flags: c_int = undefined;

            setup_cmd_mode(cmd, &bin, &argv_ptr, &env_ptr, &flags);
            const pid = c.arcan_tui_handover(T, conn, bin, argv_ptr, env_ptr, flags);

            if (cli_state_g.in_debug != null) {
                var debugspawn: [64]u8 = undefined;
                _ = snprintf(&debugspawn, 64, "%zu: %s", @as(usize, @intCast(pid)), bin);
                _ = c.arcan_tui_message(T, c.TUI_MESSAGE_FAILURE, &debugspawn);
            }

            free_cmd(cmd);
            res = true;
            break;
        }
    }

    var pending = false;
    for (0..4) |i| {
        if (cli_state_g.pending[i].id != 0) {
            pending = true;
            break;
        }
    }

    if (!pending and cli_state_g.die_on_finish) {
        cli_state_g.alive = false;
    }

    return res;
}

fn group_expand(_: ?*c.struct_group_ent, in: [*c]const u8) callconv(.c) [*c]u8 {
    // depending on group, we might perform another extract_argv for specials,
    // expand user-set variables, call into script, ...
    return strdup(in);
}

fn parse_command(
    _: [*c]const u8,
    _: usize,
    _: bool,
    _: ?*anyopaque,
) callconv(.c) isize {
    // missing: this should run the normal extract_argv and built-in check,
    // (eval_to_cmd with noxec) if tui- mode is here and we have an oracle, forward
    // the state there and grab completion results or parsing errors from there
    return -1;
}

// build environment based on current state (term-wrapper, ...), thought
// tempting to just add scripting hooks here and go the *sh route
fn eval_to_cmd(out: [*c]u8, cmd: *c.struct_ext_cmd, noexec: bool) bool {
    var groups = [_]c.struct_group_ent{
        .{ .enter = '\'', .leave = '\'', .leave_eol = false, .expand = &group_expand },
        .{ .enter = '"', .leave = '"', .leave_eol = false, .expand = &group_expand },
        .{ .enter = '`', .leave = '`', .leave_eol = false, .expand = &group_expand },
        .{ .enter = 0, .leave = 0, .leave_eol = false, .expand = null },
    };

    // environment variable, kind of expansion is its own step
    var err_ofs: isize = undefined;
    const opts: c.struct_argv_parse_opt = .{
        .prepad = 0,
        .groups = &groups,
        .sep = ' ',
    };
    const argv_result = c.extract_argv(out, opts, &err_ofs);

    if (argv_result == null)
        return false;

    // builtin commands?
    const builtin: [*c]c.struct_cli_command = c.cli_get_builtin(argv_result[0]);

    // now, return the argv- array, this comes post expansion so the first arg in
    // argv (cmd) follows the execlpe format
    if (builtin == null) {
        cmd.argv = argv_result;
        cmd.env = duplicate_strtbl(cli_state_g.env, 0, 0);
        return true;
    }

    // builtin- commands should only be executed if we explicitly request that
    if (noexec) {
        free_strtbl(argv_result);
        return false;
    }

    // but they can also expand to an external command, so let it
    var err: [*c]u8 = null;
    const exec_fn = builtin[0].exec orelse return false;
    const res: [*c]c.struct_ext_cmd = exec_fn(&cli_state_g, argv_result, &err_ofs, &err);
    free_strtbl(argv_result);

    if (res != null) {
        cmd.* = res[0];
        free(@ptrCast(res));
        return true;
    }

    return false;
}

// this updates at quite a high clock (25Hz) so for simple prompts that
// don't query the local environment, just early out
fn rebuild_prompt(T: ?*c.struct_tui_context, S: *c.struct_cli_state) void {
    var pwd: [*c]const u8 = getenv("PWD");
    if (pwd == null) {
        pwd = "";
    } else {
        const len = strlen(pwd);
        var i: isize = @intCast(len);
        i -= 1;
        while (i > 0) : (i -= 1) {
            if (pwd[@intCast(i)] == '/') {
                pwd = pwd + @as(usize, @intCast(i)) + 1;
                break;
            }
        }
    }

    // placeholder prompt, plugin or expansion format goes here
    var attr: c.struct_tui_screen_attr = std.mem.zeroes(c.struct_tui_screen_attr);
    attr.unnamed_2.aflags = @intCast(c.TUI_ATTR_COLOR_INDEXED);
    attr.unnamed_0.fc[0] = @intCast(c.TUI_COL_UI);
    attr.unnamed_1.bc[0] = @intCast(c.TUI_COL_UI);

    if (S.prompt == null) {
        const raw = malloc(@sizeOf(c.struct_tui_cell) * 256) orelse return;
        S.prompt = @ptrCast(@alignCast(raw));
        S.prompt[0].ch = 0;
    }

    const modestr: [*c]const u8 = switch (S.mode) {
        LAUNCH_VT100 => "",
        LAUNCH_TUI, LAUNCH_SHMIF => "(arcan@) ",
        LAUNCH_WL => "(wayland@) ",
        LAUNCH_X11 => "(x11@) ",
        else => "",
    };

    const strlst = [_][*c]const u8{ pwd, " ", modestr, "# " };
    var i: usize = 0;
    var j: usize = 0;
    var cstr: [*c]const u8 = strlst[j];

    const prompt = S.prompt;

    while (i < 255 and j < strlst.len) {
        if (cstr[0] == 0) {
            j += 1;
            if (j >= strlst.len) break;
            cstr = strlst[j];
            continue;
        }

        // does not respect UTF8
        prompt[i].attr = attr;
        prompt[i].ch = cstr[0];
        i += 1;
        cstr = cstr + 1;
    }
    prompt[i].ch = 0;

    c.arcan_tui_ident(T, pwd);
    c.arcan_tui_readline_prompt(T, @ptrCast(prompt));
}

fn on_bchunk(
    _: ?*c.struct_tui_context,
    _: bool,
    _: u64,
    _: c_int,
    _: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) void {
    // map any input to stdin, and output to stdout
}

fn parse_eval(T: ?*c.struct_tui_context, out: [*c]u8) void {
    var ind: usize = 0;

    for (0..4) |i| {
        if (cli_state_g.pending[i].id == 0) {
            ind = i;
            break;
        }
    } else {
        // sorry we are full - alert the user via the prompt
        cli_state_g.blocked = true;
        return;
    }

    const cmd = &cli_state_g.pending[ind];

    if (!eval_to_cmd(out, cmd, false))
        return;

    // we are supposed to execute the thing
    if (cmd.mode == LAUNCH_UNSET)
        cmd.mode = cli_state_g.mode;

    cli_state_g.id_counter += 1;
    cmd.id = cli_state_g.id_counter;
    const wd_raw = malloc(PATH_MAX) orelse return;
    cmd.wd = @ptrCast(wd_raw);
    _ = getcwd(cmd.wd, PATH_MAX);
    c.arcan_tui_request_subwnd(T, c.TUI_WND_HANDOVER, @intCast(cmd.id));
}

// Label handling

const LabelHandler = *const fn (?*c.struct_tui_context, *c.struct_cli_state, c_uint) bool;

const LabelEnt = struct {
    handler: LabelHandler,
    idt: c_uint,
    ent: c.struct_tui_labelent,
};

fn label_modesw(_: ?*c.struct_tui_context, M: *c.struct_cli_state, idt: c_uint) bool {
    M.mode = idt;
    return true;
}

fn makeLabelent(comptime lbl: []const u8, comptime descr_str: []const u8, comptime initial: u16, idt: c_uint) LabelEnt {
    var label_arr: [16]u8 = [_]u8{0} ** 16;
    @memcpy(label_arr[0..lbl.len], lbl);
    var descr_arr: [58]u8 = [_]u8{0} ** 58;
    @memcpy(descr_arr[0..descr_str.len], descr_str);
    return LabelEnt{
        .handler = &label_modesw,
        .idt = idt,
        .ent = .{
            .label = label_arr,
            .descr = descr_arr,
            .initial = initial,
            .vsym = [_]u8{0} ** 5,
            .modifiers = 0,
            .subv = 0,
            .idatatype = 0,
        },
    };
}

const labels = [_]LabelEnt{
    makeLabelent("MODE_ARCAN", "Switch launch mode to arcan", @intCast(c.TUIK_F1), LAUNCH_SHMIF),
    makeLabelent("MODE_VT100", "Switch launch mode to terminal emulation", @intCast(c.TUIK_F2), LAUNCH_VT100),
    makeLabelent("MODE_X11", "Switch launch mode to x11", @intCast(c.TUIK_F3), LAUNCH_X11),
    makeLabelent("MODE_WAYLAND", "Switch launch mode to arcan", @intCast(c.TUIK_F4), LAUNCH_WL),
};

fn on_label_input(
    T: ?*c.struct_tui_context,
    label: [*c]const u8,
    active: bool,
    _: ?*anyopaque,
) callconv(.c) bool {
    if (!active)
        return true;

    for (&labels) |*l| {
        if (strcmp(label, &l.ent.label) == 0)
            return l.handler(T, &cli_state_g, l.idt);
    }

    return false;
}

fn on_label_query(
    _: ?*c.struct_tui_context,
    index: usize,
    _: [*c]const u8,
    _: [*c]const u8,
    dstlbl: [*c]c.struct_tui_labelent,
    _: ?*anyopaque,
) callconv(.c) bool {
    if (index < labels.len) {
        dstlbl[0] = labels[index].ent;
        return true;
    }
    return false;
}

// Public API

export fn arcterm_cli_run(
    cont: ?*c.struct_arcan_shmif_cont,
    args: ?*c.struct_arg_arr,
) c_int {
    // source arguments, prompt, ... from args or config file
    var opts: c.struct_tui_readline_opts = std.mem.zeroes(c.struct_tui_readline_opts);
    opts.allow_exit = false;
    opts.verify = &parse_command;

    // don't need much on top of the normal readline:
    // subwindow handler for dispatching new command basically
    var cfg: c.struct_tui_cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    // cbcfg callback slots are ?*anyopaque in the Zig mirror (function-pointer
    // type unification across consumers is not practical). Cast the typed
    // function pointers through @constCast + @ptrCast to store them.
    cfg.subwindow = @ptrCast(@constCast(&on_subwindow));
    cfg.query_label = @ptrCast(@constCast(&on_label_query));
    cfg.input_label = @ptrCast(@constCast(&on_label_input));
    cfg.bchunk = @ptrCast(@constCast(&on_bchunk));

    var argt: [*c]const u8 = null;

    if (c.arg_lookup(args, "mode", 0, &argt) and argt != null) {
        if (strcmp(argt, "arcan") == 0) {
            cli_state_g.mode = LAUNCH_SHMIF;
        } else if (strcmp(argt, "vt100") == 0) {
            cli_state_g.mode = LAUNCH_VT100;
        } else if (strcmp(argt, "wayland") == 0) {
            cli_state_g.mode = LAUNCH_WL;
        } else if (strcmp(argt, "x11") == 0) {
            cli_state_g.mode = LAUNCH_X11;
        }
    }

    if (c.arg_lookup(args, "bgalpha", 0, &argt) and argt != null) {
        cli_state_g.bgalpha = @truncate(strtoul(argt, null, 10));
    }

    const tui = c.arcan_tui_setup(
        @ptrCast(cont),
        null,
        &cfg,
        @sizeOf(c.struct_tui_cbcfg),
    ) orelse return 1; // EXIT_FAILURE

    _ = c.arcan_tui_cursor_style(tui, cursor_style_arg(args), null);
    c.arcan_tui_readline_setup(tui, &opts, @sizeOf(c.struct_tui_readline_opts));
    var out: [*c]u8 = undefined;

    // #ifndef FSRV_TERMINAL_NOEXEC
    if (!@hasDecl(c, "FSRV_TERMINAL_NOEXEC")) {
        if (c.arg_lookup(args, "exec", 0, &argt) and argt != null) {
            const tmp = strdup(argt);
            parse_eval(tui, tmp);
            free(@ptrCast(tmp));

            // terminate on next exec ..
            var oneshot_val: [*c]const u8 = null;
            if (c.arg_lookup(args, "oneshot", 0, &oneshot_val)) {
                cli_state_g.die_on_finish = true;
            }
        }
    }

    while (cli_state_g.alive) {
        rebuild_prompt(tui, &cli_state_g);
        while (cli_state_g.alive) {
            const status = c.arcan_tui_readline_finished(tui, &out);
            if (status != 0) break;
            var tui_ptr: ?*c.struct_tui_context = tui;
            const res = c.arcan_tui_process(&tui_ptr, 1, null, 0, -1);
            if (res.errc == c.TUI_ERRC_OK) {
                if (c.arcan_tui_refresh(tui) == -1 and getErrnoValue() == c.EINVAL) {
                    cli_state_g.alive = false;
                }
            }
        }

        // check final status after inner loop exits
        const final_status = c.arcan_tui_readline_finished(tui, &out);
        if (final_status == c.READLINE_STATUS_DONE) {
            // parse, commit to history, ...
            if (out != null and strlen(out) > 0) {
                parse_eval(tui, out);
            }
            c.arcan_tui_readline_reset(tui);
        } else if (final_status == c.READLINE_STATUS_TERMINATE) {
            cli_state_g.alive = false;
        }
    }

    c.arcan_tui_destroy(tui, null);
    return 0; // EXIT_SUCCESS
}
