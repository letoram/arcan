
pub fn __init() void {
    lash = .{
        .jobs = .{},
    };
    lash.tokenize_command = struct { fn anon(wnd: anytype, msg: anytype, simple: anytype) V {
        return __may_mv(.{}, null, 0, .{});
    } }.anon;
    lash.messages = .{};
    lash.message_fmt = .{};
    lash.history = .{};
    unpack = table.unpack or unpack;
    var setup_window = undefined;
    var commands = .{};
    var fallback_handlers = .{};
    var history_limit = 500;
    var prompt_row = 1;
    var message_offset = 0;
    var readline = undefined;
    var readline_row = 0;
    if (!string.split) {
        string.split = struct { fn anon(instr: bool, delim: anytype) V {
            if (!instr) {
                return .{};
            }
            var res = .{};
            var strt = 1;
            const delim_pos, const delim_stp = string.find(instr, delim, strt);
            while (delim_pos) {
                table.insert(res, string.sub(instr, strt, delim_pos - 1));
                strt = delim_stp + 1;
                delim_pos, delim_stp = string.find(instr, delim, strt);
            }
            table.insert(res, string.sub(instr, strt));
            return res;
        } }.anon;
    }
    if (!string.trim) {
        string.trim = struct { fn anon(s: Obj) V {
            var n = s.find("%S");
            return (n and s.match(".*%S", n)) or "";
        } }.anon;
    }
    const get_prompt = struct { fn get_prompt(wnd: Obj) []const u8 {
        var wd = wnd.chdir();
        var path_limit = 8;
        var dirs = string.split(wd, "/");
        var dir = "/";
        if (@intCast(dirs.len)) {
            dir = dirs[@intCast(dirs.len)];
        }
        return "[" ++ (dir ++ "]$ ");
    } }.get_prompt;

    const add_split = struct { fn add_split(wnd: Obj, msg: anytype, cap: i64, dst: anytype) void {
        assert(type(msg) == "string", debug.traceback());
        msg = string.gsub(msg, "\t", "  ");
        var len = wnd.utf8_len(msg);
        var blen = @intCast(msg.len);
        if (len <= cap) {
            table.insert(dst, msg);
            return;
        }
        var count = 0;
        var start = 1;
        var pos = 1;
        while ((start < blen) and (start > 0)) {
            while ((count < (cap - 1)) and (pos > 0)) {
                pos = wnd.utf8_step(msg, pos);
                count = count + 1;
            }
            if (pos < 0) {
                if (start < blen) {
                    table.insert(dst, string.sub(msg, start));
                }
                start = blen;
                break;
            }
            table.insert(dst, string.sub(msg, start, pos));
            start = wnd.utf8_step(msg, pos);
            pos = start;
            count = 0;
        }
    } }.add_split;

    const draw = struct { fn draw(wnd: Obj) void {
        wnd.erase();
        const cols, const rows = wnd.dimensions();
        var count = @intCast(lash.message_fmt.len);
        var rlpos = rows - 1;
        if (count < rows) {
            for (1..count + 1) |i| {
                var msg = lash.message_fmt[i];
                wnd.write_to(1, i - 1, msg);
            }
            rlpos = count;
        } else {
            for (1..(rows - 1) + 1) |i| {
                var msg = lash.message_fmt[@intCast(lash.message_fmt.len) - i + 1];
                wnd.write_to(1, rows - i - 1, msg);
            }
        }
        if (readline) {
            readline_row = rlpos;
            __may_method(readline.bounding_box, 0, readline_row, cols, readline_row);
            __may_method(readline.set_prompt, get_prompt(wnd));
        }
    } }.draw;

    const add_message = struct { fn add_message(wnd: anytype, msg: anytype, cols: anytype) void {
        if (!msg or (@intCast(msg.len) == 0)) {
            return;
        }
        if (type(msg) == "table") {
        } else if (type(msg) == "string") {
            msg = string.split(msg, "\n");
        }
        for (msg, 0..) |v, _| {
            assert(type(v) == "string");
            add_split(wnd, v, cols, lash.message_fmt);
        }
        table.insert(lash.messages, msg);
    } }.add_message;

    const run_usershell = struct { fn run_usershell(wnd: anytype, name: []const u8) V {
        var dirs = .{};
        if (os.getenv("LASH_BASE")) {
            table.insert(dirs, string.format("%s/", os.getenv("LASH_BASE")));
        }
        if (os.getenv("HOME")) {
            table.insert(dirs, string.format("%s/.arcan/lash/", os.getenv("HOME")));
        }
        if (os.getenv("XDG_CONFIG_HOME")) {
            table.insert(dirs, string.format("%s/arcan/lash/", os.getenv("XDG_CONFIG_HOME")));
        }
        if (os.getenv("ARCAN_APPLPATH")) {
            table.insert(dirs, string.format("%s/lash/", os.getenv("ARCAN_APPLPATH")));
        }
        if (@intCast(dirs.len) > 0) {
            for (dirs, 0..) |v, _| {
                var path = v ++ (name ++ ".lua");
                var file = io.open(path);
                if (file) {
                    const fptr, const msg = loadfile(v ++ (name ++ ".lua"));
                    if (!fptr) {
                        if (wnd and wnd.message) {
                            var m = "usershell:fail:name=" ++ (tostring(name) ++ (":err=loadfile:" ++ __may_method(__may_method(tostring(msg).gsub, "[\r\n]", " ").sub, 1, 200)));
                            pcall(struct { fn anon() void {
                                __may_method(wnd.message, m);
                            } }.anon);
                        }
                        return __may_mv(false, msg);
                    }
                    lash.scriptdir = v;
                    const ok, const msg = xpcall(fptr, debug.traceback);
                    if (!ok) {
                        if (wnd and wnd.message) {
                            var m = "usershell:fail:name=" ++ (tostring(name) ++ (":err=" ++ __may_method(__may_method(tostring(msg).gsub, "[\r\n]", " ").sub, 1, 200)));
                            pcall(struct { fn anon() void {
                                __may_method(wnd.message, m);
                            } }.anon);
                        }
                        msg = string.split(msg, ": ");
                        var res = .{ "usershell (" ++ (name ++ ") failed: ") };
                        for (msg, 0..) |v, i| {
                            table.insert(res, string.rep("\t", i - 1) ++ v);
                        }
                        lash.lasterr = res;
                        return __may_mv(false, res);
                    } else {
                        return true;
                    }
                }
            }
        }
        if (wnd and wnd.message) {
            var m = "usershell:fail:name=" ++ (tostring(name) ++ ":err=not-found");
            pcall(struct { fn anon() void {
                __may_method(wnd.message, m);
            } }.anon);
        }
        return __may_mv(false, "shell " ++ (name ++ " not found in ($LASH_BASE, $HOME/.arcan/lash or $XDG_CONFIG_HOME)"));
    } }.run_usershell;

    const finish_job = struct { fn finish_job(wnd: anytype, job: anytype, code: i64, cols: anytype) void {
        while (job.out) {
            var msg = __may_method(job.out.read);
            if (!msg or (@intCast(msg.len) == 0)) {
                break;
            }
            add_message(msg, cols);
        }
        if ((code != 0) and job.cmd) {
            add_message(wnd, "! " ++ (job.cmd ++ (" terminated with " ++ tostring(code))), cols);
        }
    } }.finish_job;

    const process_jobs = struct { fn process_jobs(wnd: Obj) void {
        if (@intCast(lash.jobs.len) == 0) {
            return;
        }
        const cols, const _ = wnd.dimensions();
        for (@intCast(lash.jobs.len)..1 + 1) |i| {
            var job = lash.jobs[i];
            while (job.out) {
                var msg = __may_method(job.out.read);
                if (!msg) {
                    break;
                }
                add_message(wnd, msg, cols);
            }
            if (job.pid) {
                const running, const code = wnd.pwait(job.pid);
                if (!running) {
                    finish_job(wnd, job, code, cols);
                    table.remove(lash.jobs, i);
                }
            }
        }
        draw(wnd);
    } }.process_jobs;

    fallback_handlers.resized = struct { fn anon(wnd: Obj) void {
        var cols = wnd.dimensions();
        lash.message_fmt = .{};
        var msg = lash.messages;
        for (@intCast(msg.len)..1 + 1) |i| {
            __may_step(-1);
            if (type(msg[i]) == "table") {
                for (msg[i], 0..) |v, _| {
                    add_split(wnd, v, cols, lash.message_fmt);
                }
            } else {
                add_split(wnd, msg[i], cols, lash.message_fmt);
            }
        }
        draw(wnd);
    } }.anon;

    fallback_handlers.recolor = draw;
    commands.shell = struct { fn anon(wnd: anytype, name: anytype) V {
        if (!name) {
            name = "default.lua";
        }
        const res, const msg = run_usershell(wnd, name);
        if (!res) {
            return msg;
        }
    } }.anon;

    commands.lasterr = struct { fn anon(wnd: Obj) void {
        const cols, const _ = wnd.dimensions();
        if (lash.lasterr) {
            for (lash.lasterr, 0..) |v, _| {
                add_split(wnd, v, cols, lash.message_fmt);
            }
        }
    } }.anon;

    commands.cd = struct { fn anon(wnd: Obj, path: bool) V {
        if (!path) {
            return wnd.chdir();
        }
        wnd.chdir(path);
    } }.anon;

    commands.flood = struct { fn anon(wnd: Obj, n: anytype) void {
        const cols, const rows = wnd.dimensions();
        for (1..n + 1) |i| {
            add_message(wnd, "line " ++ tostring(i), cols);
        }
    } }.anon;

    commands.debug = struct { fn anon(wnd: anytype) V {
        if (lash.debug_handler) {
            lash.debug_handler = null;
            return;
        }
        const ok, const dbg = pcall(require, "debugger");
        if (!ok) {
            return "couldn't load debugger module";
        }
        dbg();
    } }.anon;

    const run_job = struct { fn run_job(wnd: Obj, cmd: []const u8, argtbl: anytype) []const u8 {
        var cmdstr = cmd ++ (" " ++ table.concat(argtbl, " "));
        const _, const out, const err, const pid = wnd.popen(cmdstr, "r");
        if (!pid) {
            return "could not spawn " ++ cmd;
        }
        var job = .{
            .wd = wnd.chdir(),
            .pid = pid,
            .out = out,
            .err = err,
            .cmd = cmd,
        };
        table.insert(lash.jobs, job);
    } }.run_job;

    const parse_tokens = struct { fn parse_tokens(wnd: anytype, tokens: anytype, types: anytype) V {
        var cmd = tokens[1];
        if ((cmd[1] != types.SYMBOL) and (cmd[1] != types.STRING)) {
            return "parser error: expecting built-in symbol or string";
        }
        var val = cmd[2];
        var arg = .{};
        for (2..(@intCast(tokens.len)) + 1) |i| {
            var tok = tokens[i];
            if ((tok[1] == types.SYMBOL) or (tok[1] == types.STRING)) {
                var outstr = string.gsub(tok[2], "\"", "\\\"");
                table.insert(arg, outstr);
            } else if (tok[1] == types.NUMBER) {
                table.insert(arg, tok[2]);
            } else if (tok[1] == types.BOOLEAN) {
                table.insert(arg, tok[2]);
            } else if (tok[1] == types.OPERATOR) {
                if (tok[2] == types.OP_PIPE) {
                    table.insert(arg, " | ");
                } else {
                    return "parser error: unsupported operator";
                }
            } else {
                return "parser error: bad token (" ++ (table.concat(tok, ",") ++ ")");
            }
        }
        if (commands[val]) {
            return commands[val](wnd, unpack(arg));
        } else {
            return run_job(wnd, val, arg);
        }
    } }.parse_tokens;

    const add_history = struct { fn add_history(msg: anytype) void {
        if (!lash.history[msg]) {
            table.insert(lash.history, msg);
            lash.history[msg] = true;
        }
        if (@intCast(lash.history.len) > history_limit) {
            table.remove(lash.history, 1);
        }
    } }.add_history;

    const readline_handler = struct { fn readline_handler(wnd: Obj, self: anytype, line: anytype) void {
        if (!line or (@intCast(line.len) == 0)) {
            setup_window(wnd);
            return;
        }
        const tokens, const msg, const ofs, const types = lash.tokenize_command(line, true);
        const cols, const _ = wnd.dimensions();
        var cmd = "$ " ++ line;
        add_message(wnd, cmd, cols);
        if (!msg) {
            msg = parse_tokens(wnd, tokens, types);
        }
        if (msg) {
            add_message(wnd, msg, cols);
        }
        add_history(line);
        setup_window(wnd);
    } }.readline_handler;

    setup_window = struct { fn anon(wnd: Obj) void {
        wnd.revert();
        readline = null;
        wnd.set_handlers(fallback_handlers);
        readline = wnd.readline(struct { fn anon(self: anytype, line: anytype) void {
            if (lash.debug_handler) {
                lash.debug_handler(struct { fn anon() void {
                    readline_handler(wnd, self, line);
                } }.anon);
            } else {
                readline_handler(wnd, self, line);
            }
        } }.anon);
        __may_method(readline.set_prompt, get_prompt(wnd));
        __may_method(readline.set_history, lash.history);
    } }.anon;
    const init = struct { fn init() void {
        if (!tui or !tui.root) {
            tui = require("arcantui");
            lash.root = tui.open("lash", "", .{ .handlers = fallback_handlers });
        } else {
            lash.root = tui.root;
        }
        var shellname = (os.getenv("LASH_SHELL") and os.getenv("LASH_SHELL")) or "default";
        const res, const msg = run_usershell(lash.root, shellname);
        setup_window(lash.root);
        if (!res) {
            const cols, const _ = __may_method(lash.root.dimensions);
            add_message(lash.root, msg, cols);
        }
        __may_method(lash.root.refresh);
    } }.init;

    var tokens = .{
        .SYMBOL = 1,
        .FCALL = 2,
        .OPERATOR = 3,
        .STRING = 4,
        .NUMBER = 5,
        .BOOLEAN = 6,
        .IMAGE = 7,
        .AUDIO = 8,
        .VIDEO = 9,
        .NIL = 10,
        .CELL = 11,
        .FACTORY = 12,
        .VARTYPE = 13,
        .VARARG = 14,
        .OP_ADD = 20,
        .OP_SUB = 21,
        .OP_DIV = 22,
        .OP_MUL = 23,
        .OP_LPAR = 24,
        .OP_RPAR = 25,
        .OP_MOD = 26,
        .OP_ASS = 27,
        .OP_SEP = 28,
        .OP_PIPE = 29,
        .OP_ADDR = 30,
        .OP_RELADDR = 31,
        .OP_SYMADDR = 32,
        .OP_STATESEP = 33,
        .OP_NOT = 34,
        .OP_POUND = 35,
        .OP_AND = 36,
        .ERROR = 40,
        .STATIC = 41,
        .DYNAMIC = 42,
        .FN_ALIAS = 50,
        .EXPREND = 51,
    };
    var operators = .{
        __may_kv("+", tokens.OP_ADD),
        __may_kv("-", tokens.OP_SUB),
        __may_kv("*", tokens.OP_MUL),
        __may_kv("/", tokens.OP_DIV),
        __may_kv("(", tokens.OP_LPAR),
        __may_kv(")", tokens.OP_RPAR),
        __may_kv("%", tokens.OP_MOD),
        __may_kv("=", tokens.OP_ASS),
        __may_kv(",", tokens.OP_SEP),
        __may_kv("|", tokens.OP_PIPE),
        __may_kv("$", tokens.OP_RELADDR),
        __may_kv("@", tokens.OP_SYMADDR),
        __may_kv(";", tokens.OP_STATESEP),
        __may_kv("!", tokens.OP_NOT),
        __may_kv("#", tokens.OP_POUND),
        __may_kv("&", tokens.OP_AND),
    };
    var simple_operator_mask = .{
        __may_kv("+", true),
        __may_kv("-", true),
        __may_kv("/", true),
        __may_kv(",", true),
        __may_kv("=", true),
    };
    var constant_ascii_a = string.byte("a");
    var constant_ascii_f = string.byte("f");
    const isnum = struct { fn isnum(ch: anytype) bool {
        return ((string.byte(ch) >= 0x30) and (string.byte(ch) <= 0x39));
    } }.isnum;

    const add_token = struct { fn add_token(state: anytype, dst: anytype, kind: anytype, value: anytype, position: anytype, data: anytype) void {
        table.insert(dst, .{
            kind,
            value,
            position,
            last_position,
            data,
        });
        state.last_position = position;
    } }.add_token;

    const issymch = struct { fn issymch(state: anytype, ch: []const u8, ofs: i64) bool {
        if (isnum(ch) or (ch == "_") or (ch == ".") or (ch == ":")) {
            return ofs > 0;
        }
        var byte = string.byte(ch);
        if (state.buffer == "$") {
            if ((ch == "-") or (ch == "+")) {
                return true;
            }
        }
        return ((byte >= 0x41) and (byte <= 0x5a)) or ((byte >= 0x61) and (byte <= 0x7a));
    } }.issymch;

    var lex_default = undefined;
    var lex_num = undefined;
    var lex_symbol = undefined;
    var lex_str = undefined;
    var lex_err = undefined;
    var lex_whstr = undefined;
    lex_default = struct { fn anon(ch: anytype, tok: anytype, state: anytype, ofs: anytype) V {
        if (!ch or (@intCast(ch.len) == 0) or (ch == "\x00")) {
            if (@intCast(state.buffer.len) > 0) {
                state.@"error" = "(def) unexpected end, buffer: " ++ state.buffer;
                state.error_ofs = ofs;
                return lex_error;
            }
            return lex_default;
        }
        if (issymch(state, ch, 0)) {
            state.buffer = ch;
            return (state.simple and lex_whstr) or lex_symbol;
        } else if (isnum(ch)) {
            state.number_fract = false;
            state.number_hex = false;
            state.number_bin = false;
            state.base = 10;
            return lex_num(ch, tok, state, ofs);
        } else if (ch == ".") {
            if (state.simple) {
                state.buffer = ch;
                return lex_whstr;
            } else {
                state.number_fract = true;
                state.number_hex = false;
                state.number_bin = false;
                state.base = 10;
                return lex_num;
            }
        } else if (ch == "\"") {
            state.buffer = "";
            state.lex_str_ofs = ofs;
            return lex_str;
        } else if ((ch == " ") or (ch == "\t") or (ch == "\n")) {
            return lex_default;
        } else if (operators[ch] != null) {
            if (state.operator_mask[ch]) {
                state.buffer = ch;
                return lex_whstr;
            }
            if (ch == "-") {
                if (!state.last_ch or (state.last_ch == " ") or ((@intCast(tok.len) > 0) and (tok[@intCast(tok.len)][1] == tokens.OPERATOR))) {
                    state.negate = true;
                    state.number_fract = false;
                    state.number_hex = false;
                    state.number_bin = false;
                    state.base = 10;
                    return lex_num;
                }
            }
            add_token(state, tok, tokens.OPERATOR, operators[ch], ofs);
            return lex_default;
        } else {
            state.@"error" = "(def) invalid token: " ++ ch;
            state.error_ofs = ofs;
            return lex_error;
        }
    } }.anon;
    lex_error = struct { fn anon() V {
        return lex_error;
    } }.anon;
    lex_whstr = struct { fn anon(ch: anytype, tok: anytype, state: anytype, ofs: anytype) V {
        if (!ch or (@intCast(ch.len) == 0) or (ch == "\x00")) {
            if (@intCast(state.buffer.len) > 0) {
                add_token(state, tok, tokens.STRING, state.buffer, ofs);
            }
            state.whstr_escape = null;
            return lex_default;
        }
        if (state.whstr_escape) {
            state.whstr_escape = null;
            state.buffer = state.buffer ++ ch;
            return lex_whstr;
        }
        if ((ch == " ") or (ch == "\t") or (ch == "\n") or (ch == "\"")) {
            add_token(state, tok, tokens.STRING, state.buffer, ofs);
            state.buffer = "";
            return lex_default;
        } else if (operators[ch] and !state.operator_mask[ch]) {
            add_token(state, tok, tokens.STRING, state.buffer, ofs);
            state.buffer = "";
            add_token(state, tok, tokens.OPERATOR, operators[ch], ofs);
            return lex_default;
        } else if (ch == "\\") {
            state.whstr_escape = true;
        } else {
            state.buffer = state.buffer ++ ch;
        }
        return lex_whstr;
    } }.anon;
    lex_num = struct { fn anon(ch: []const u8, tok: anytype, state: anytype, ofs: anytype) V {
        if (isnum(ch)) {
            if (state.number_bin and ((ch != "0") and (ch != "1"))) {
                state.@"error" = "(num) invalid binary constant (" ++ (ch ++ ") != [01]");
                state.error_ofs = ofs;
                return lex_error;
            }
            state.buffer = state.buffer ++ ch;
            return lex_num;
        }
        if (ch == ".") {
            if (state.number_fract) {
                state.@"error" = "(num) multiple radix points in number";
                state.error_ofs = ofs;
                return lex_error;
            } else {
                state.number_fract = true;
                state.buffer = state.buffer ++ ch;
                return lex_num;
            }
        } else if ((ch == "b") and !state.number_hex) {
            if (state.number_bin or (@intCast(state.buffer.len) != 1) or (string.sub(state.buffer, 1, 1) != "0")) {
                state.@"error" = "(num) invalid binary constant (0b[01]n expected)";
                state.error_ofs = ofs;
                return lex_error;
            } else {
                state.number_bin = true;
                state.base = 2;
                return lex_num;
            }
        } else if (ch == "x") {
            if (state.number_hex or (@intCast(state.buffer.len) != 1) or (string.sub(state.buffer, 1, 1) != "0")) {
                state.@"error" = "(num) invalid hex constant (0x[0-9a-f]n expected)";
                state.error_ofs = ofs;
                return lex_error;
            } else {
                state.number_hex = true;
                state.base = 16;
                return lex_num;
            }
        } else if (string.byte(ch) == 0) {
        } else {
            if (state.number_hex) {
                var dch = string.byte(string.lower(ch));
                if ((dch >= constant_ascii_a) and (dch <= constant_ascii_f)) {
                    state.buffer = state.buffer ++ ch;
                    return lex_num;
                }
            }
        }
        var num = tonumber(state.buffer, state.base);
        if (!num) {
            if (state.negate and (@intCast(state.buffer.len) == 0)) {
                state.negate = false;
                add_token(state, tok, tokens.OPERATOR, tokens.OP_SUB, ofs);
                return lex_default(ch, tok, state, ofs);
            }
            state.@"error" = string.format("(num) invalid number (%s)b%d", state.buffer, state.base);
            state.error_ofs = ofs;
            return lex_error;
        }
        if (state.negate) {
            num = num * -1;
            state.negate = false;
        }
        add_token(state, tok, tokens.NUMBER, num, ofs);
        state.buffer = "";
        return lex_default(ch, tok, state, ofs);
    } }.anon;
    lex_symbol = struct { fn anon(ch: []const u8, tok: anytype, state: anytype, ofs: anytype) V {
        if ((ch == "(") and (@intCast(state.buffer.len) > 0)) {
            add_token(state, tok, tokens.FCALL, string.lower(state.buffer), ofs, state.got_addr);
            state.buffer = "";
            state.got_addr = null;
            return lex_default;
        } else if (issymch(state, ch, @intCast(state.buffer.len))) {
            if (ch == ".") {
                if (state.got_addr) {
                    state.@"error" = "(str) symbol namespace selection with . only allowed once per symbol";
                    state.error_ofs = state.lex_str_ofs;
                    return lex_error;
                }
                state.got_addr = string.lower(state.buffer);
                state.buffer = "";
                return lex_symbol;
            }
            state.buffer = state.buffer ++ ch;
            return lex_symbol;
        } else {
            if (state.got_addr) {
                add_token(state, tok, tokens.SYMBOL, state.got_addr, ofs, string.lower(state.buffer));
            } else {
                var lc = string.lower(state.buffer);
                if (lc == "true") {
                    add_token(state, tok, tokens.BOOLEAN, true, ofs);
                } else if (lc == "false") {
                    add_token(state, tok, tokens.BOOLEAN, false, ofs);
                } else {
                    add_token(state, tok, tokens.SYMBOL, lc, ofs);
                }
            }
            state.buffer = "";
            state.got_addr = null;
            return lex_default(ch, tok, state, ofs);
        }
    } }.anon;
    lex_str = struct { fn anon(ch: anytype, tok: anytype, state: anytype, ofs: anytype) V {
        if (!ch or (@intCast(ch.len) == 0) or (ch == "\x00")) {
            state.@"error" = "\"(str) unterminated string at end";
            state.error_ofs = state.lex_str_ofs;
            return lex_error;
        }
        if (state.in_escape) {
            state.buffer = state.buffer ++ ch;
            state.in_escape = null;
        } else if (ch == "\"") {
            add_token(state, tok, tokens.STRING, state.buffer, ofs);
            state.buffer = "";
            return lex_default;
        } else if (ch == "\\") {
            state.in_escape = true;
        } else {
            state.buffer = state.buffer ++ ch;
        }
        return lex_str;
    } }.anon;
    lash.tokenize_command = struct { fn anon(msg: anytype, simple: anytype, opts: anytype) V {
        var ofs = 1;
        var nofs = ofs;
        var len = @intCast(msg.len);
        var tokout = .{};
        var state = .{
            .buffer = "",
            .simple = simple,
        };
        if (simple) {
            state.operator_mask = simple_operator_mask;
        } else {
            state.operator_mask = .{};
        }
        if (opts) {
            for (pairs(opts)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                state[k] = v;
            }
        }
        var scope = lex_default;
        var scopestr = struct { fn anon(scope: anytype) []const u8 {
            if (scope == lex_default) {
                return "default";
            } else if (scope == lex_str) {
                return "string";
            } else if (scope == lex_num) {
                return "number";
            } else if (scope == lex_symbol) {
                return "symbol";
            } else if (scope == lex_whstr) {
                return "symstring";
            } else if (scope == lex_err) {
                return "error";
            } else {
                return "unknown";
            }
        } }.anon;
        var root = lash.root;
        while (true) {
            nofs = root.utf8_step(msg, 1, ofs);
            var ch = string.sub(msg, ofs, nofs - 1);
            scope = scope(ch, tokout, state, ofs);
            ofs = nofs;
            state.last_ch = ch;
            if ((nofs < 0) or (nofs > len) or (state.@"error" != null)) break;
        }
        scope("\x00", tokout, state, ofs);
        return __may_mv(tokout, state.@"error", state.error_ofs, tokens);
    } }.anon;
    init();
    while (__may_method(lash.root.process)) {
        process_jobs(lash.root);
        __may_method(lash.root.refresh);
    }
}
