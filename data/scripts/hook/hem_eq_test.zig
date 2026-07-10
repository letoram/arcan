
var _orig_clock = _G[APPLID ++ "_clock_pulse"];
var _tick = 0;
var lash_vid = null;
var capture_armed = false;

pub fn __init() void {
    if (type(durian_launch) == "function") {
        var _orig_dl = durian_launch;
        durian_launch = struct { fn anon(vid: anytype, prefix: anytype, title: []const u8, wnd: anytype, wargs: anytype) V {
            if (type(shmifmon) == "function") {
                shmifmon("hem_eq:hook:durian_launch:armed=" ++ (tostring(capture_armed) ++ (":vid=" ++ (tostring(vid) ++ (":title=" ++ tostring(title))))));
            }
            if (capture_armed and !lash_vid and ((title == "terminal") or (title == "lash") or (title and string.find(title, "lash", 1, true)))) {
                lash_vid = vid;
                if (type(shmifmon) == "function") {
                    shmifmon("hem_eq:hook:captured_lash_vid=" ++ tostring(vid));
                }
            }
            return _orig_dl(vid, prefix, title, wnd, wargs);
        } }.anon;
    }
    const tag = struct { fn tag(s: []const u8) void {
        if (type(shmifmon) == "function") {
            shmifmon("hem_eq:hook:" ++ s);
        }
    } }.tag;

    var KSYM_RETURN = 13;
    const send_char = struct { fn send_char(vid: anytype, ch: anytype, sym: anytype) bool {
        if (!(vid and valid_vid(vid))) {
            return false;
        }
        sym = sym or 0;
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = true,
            .devid = 0,
            .subid = sym,
            .number = sym,
            .keysym = sym,
            .modifiers = 0,
            .utf8 = ch,
        });
        target_input(vid, .{
            .kind = "digital",
            .translated = true,
            .active = false,
            .devid = 0,
            .subid = sym,
            .number = sym,
            .keysym = sym,
            .modifiers = 0,
            .utf8 = "",
        });
        return true;
    } }.send_char;

    const send_line = struct { fn send_line(vid: anytype, line: anytype) void {
        for (1..(@intCast(line.len)) + 1) |i| {
            var ch = string.sub(line, i, i);
            send_char(vid, ch, string.byte(ch));
        }
        send_char(vid, "\r", KSYM_RETURN);
    } }.send_line;

    var cmds = .{
        .{
            .tool = "BuiltinSwitch",
            .cmd = "builtin dev",
        },
        .{
            .tool = "Read",
            .cmd = "!!cat /tmp/eq_read.txt",
        },
        .{
            .tool = "Read",
            .cmd = "!!sed -n '1,2p' /tmp/eq_read.txt",
        },
        .{
            .tool = "Read",
            .cmd = "!!head -1 /tmp/eq_read.txt",
        },
        .{
            .tool = "Read",
            .cmd = "!!tail -1 /tmp/eq_read.txt",
        },
        .{
            .tool = "Glob",
            .cmd = "list /tmp",
        },
        .{
            .tool = "Glob",
            .cmd = "!!find /tmp -maxdepth 1 -name eq_read.txt",
        },
        .{
            .tool = "Grep",
            .cmd = "!!grep hello /tmp/eq_read.txt",
        },
        .{
            .tool = "Grep",
            .cmd = "!!grep -c world /tmp/eq_read.txt",
        },
        .{
            .tool = "Bash",
            .cmd = "!!echo bash-equiv-out",
        },
        .{
            .tool = "Bash",
            .cmd = "!!true",
        },
        .{
            .tool = "Bash",
            .cmd = "!!false",
        },
        .{
            .tool = "Bash",
            .cmd = "!!sleep 0.05",
        },
        .{
            .tool = "Write",
            .cmd = "!!sh -c 'echo written-by-hem > /tmp/eq_write.txt'",
        },
        .{
            .tool = "Write",
            .cmd = "!!touch /tmp/eq_touch.txt",
        },
        .{
            .tool = "Edit",
            .cmd = "!!sed -i 's|hello|HELLO|' /tmp/eq_read.txt",
        },
        .{
            .tool = "Edit",
            .cmd = "!!sed -i 's|world|WORLD|g' /tmp/eq_read.txt",
        },
        .{
            .tool = "WebFetch",
            .cmd = "!!curl -sSL --max-time 3 file:///tmp/eq_read.txt",
        },
        .{
            .tool = "Monitor",
            .cmd = "!!seq 1 3",
        },
        .{
            .tool = "Monitor",
            .cmd = "!!ls /etc",
        },
        .{
            .tool = "Bash",
            .cmd = "view #1 expand",
        },
        .{
            .tool = "Bash",
            .cmd = "view #1 collapse",
        },
        .{
            .tool = "Bash",
            .cmd = "copy #1 clipboard:",
        },
        .{
            .tool = "Bash",
            .cmd = "forget #1",
        },
        .{
            .tool = "LSP",
            .cmd = "!!grep -rn 'fn cat9_test' /home/x/next/arcan/data/lash",
        },
        .{
            .tool = "LSP",
            .cmd = "!!rg --no-heading -n 'function ' /home/x/next/arcan/data/lash/hem_test.lua",
        },
        .{
            .tool = "Notebook",
            .cmd = "!!command -v jupytext",
        },
        .{
            .tool = "Notebook",
            .cmd = "!!jupytext --to py /tmp/eq_nb.ipynb",
        },
        .{
            .tool = "Notebook",
            .cmd = "!!jupytext --to notebook /tmp/eq_nb.py",
        },
        .{
            .tool = "ReadNat",
            .cmd = "read /tmp/eq_read.txt",
        },
        .{
            .tool = "ReadNat",
            .cmd = "head /tmp/eq_read.txt 1",
        },
        .{
            .tool = "ReadNat",
            .cmd = "tail /tmp/eq_read.txt 1",
        },
        .{
            .tool = "ReadNat",
            .cmd = "wc /tmp/eq_read.txt",
        },
        .{
            .tool = "WriteNat",
            .cmd = "write /tmp/eq_native_write.txt native-by-hem",
        },
        .{
            .tool = "WriteNat",
            .cmd = "write /tmp/eq_native_edit.txt one-two-three",
        },
        .{
            .tool = "EditNat",
            .cmd = "edit /tmp/eq_native_edit.txt one ONE",
        },
        .{
            .tool = "EditNat",
            .cmd = "edit /tmp/eq_native_edit.txt two TWO",
        },
        .{
            .tool = "GrepNat",
            .cmd = "grep hello /tmp/eq_read.txt",
        },
        .{
            .tool = "GlobNat",
            .cmd = "glob eq_*.txt /tmp",
        },
        .{
            .tool = "FindNat",
            .cmd = "find /tmp eq_",
        },
        .{
            .tool = "RunNat",
            .cmd = "run /bin/echo native-run-output",
        },
        .{
            .tool = "ZigBuild",
            .cmd = "zigbuild --help",
        },
        .{
            .tool = "EditsTracker",
            .cmd = "edits",
        },
        .{
            .tool = "Disasm",
            .cmd = "disasm /tmp/eq_disasm_demo.o",
        },
        .{
            .tool = "Sheet",
            .cmd = "sheet read /tmp/eq_read.txt",
        },
        .{
            .tool = "Sheet",
            .cmd = "sheet grep hello /tmp/eq_read.txt",
        },
        .{
            .tool = "Bash",
            .cmd = "!!echo eq-done",
        },
        .{
            .tool = "Bash",
            .cmd = "!!echo eq-final",
        },
    };
    var SLOT_BASE = 60;
    var SLOT_GAP = 30;
    var SHUTDOWN_GAP = 200;
    var total = @intCast(cmds.len);
    var fired = .{};
    _G[APPLID ++ "_clock_pulse"] = struct { fn anon(va: anytype) void {
        if (_orig_clock) {
            _orig_clock(va);
        }
        _tick = _tick + 1;
        if ((_tick == 60) and !fired.spawn) {
            fired.spawn = true;
            capture_armed = true;
            tag("tick=60:spawn_lash:armed_capture");
            if (type(dispatch_symbol) == "function") {
                dispatch_symbol("/global/open/lash");
            }
        }
        var START = SLOT_BASE + 120;
        for (cmds, 0..) |slot, i| {
            var at = START + (i - 1) * SLOT_GAP;
            var key = "s" ++ i;
            if ((_tick == at) and !fired[key]) {
                fired[key] = true;
                if (!lash_vid or !valid_vid(lash_vid)) {
                    tag(string.format("slot=%d:tool=%s:no_lash_vid", i, slot.tool));
                } else {
                    tag(string.format("slot=%d:tool=%s:start", i, slot.tool));
                    send_line(lash_vid, slot.cmd);
                }
            }
        }
        var SHUTDOWN_TICK = START + total * SLOT_GAP + SHUTDOWN_GAP;
        if ((_tick == SHUTDOWN_TICK) and !fired.eof) {
            fired.eof = true;
            tag(string.format("tick=%d:delete_lash_vid", SHUTDOWN_TICK));
            if (lash_vid and valid_vid(lash_vid)) {
                delete_image(lash_vid);
            }
        }
        var FINAL_TICK = SHUTDOWN_TICK + SHUTDOWN_GAP;
        if ((_tick == FINAL_TICK) and !fired.done) {
            fired.done = true;
            tag(string.format("tick=%d:shutdown", FINAL_TICK));
            if (type(shutdown) == "function") {
                shutdown("hem_eq:done");
            }
        }
    } }.anon;
}
