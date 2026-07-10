
pub fn __init() void {
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
    if (!string.starts_with) {
        string.starts_with = struct { fn anon(instr: anytype, prefix: anytype) bool {
            return string.sub(instr, 1, @intCast(prefix.len)) == prefix;
        } }.anon;
    }
    if (!string.split_first) {
        string.split_first = struct { fn anon(instr: bool, delim: anytype) V {
            if (!instr) {
                return;
            }
            const delim_pos, const delim_stp = string.find(instr, delim, 1);
            if (delim_pos) {
                var first = string.sub(instr, 1, delim_pos - 1);
                var rest = string.sub(instr, delim_stp + 1);
                first = (first and first) or "";
                rest = (rest and rest) or "";
                return __may_mv(first, rest);
            } else {
                return __may_mv("", instr);
            }
        } }.anon;
    }
    if (!string.shorten) {
        string.shorten = struct { fn anon(s: anytype, len: anytype) V {
            if ((s == null) or (string.len(s) == 0)) {
                return "";
            }
            var r = string.gsub(string.gsub(s, " ", ""), "\n", "");
            return string.sub((r and r) or "", 1, len);
        } }.anon;
    }
    if (!string.utf8back) {
        string.utf8back = struct { fn anon(src: anytype, ofs: anytype) V {
            if ((ofs > 1) and ((string.len(src) + 1) >= ofs)) {
                ofs = ofs - 1;
                while ((ofs > 1) and (utf8kind(string.byte(src, ofs)) == 2)) {
                    ofs = ofs - 1;
                }
            }
            return ofs;
        } }.anon;
    }
    if (!string.to_u8) {
        string.to_u8 = struct { fn anon(instr: anytype) V {
            instr = string.gsub(instr, " ", "");
            var len = string.len(instr);
            if (((len % 2) != 0) or (len > 8)) {
                return;
            }
            var s = "";
            for (1..len + 1) |i| {
                __may_step(2);
                var num = tonumber(string.sub(instr, i, i + 1), 16);
                if (!num) {
                    return null;
                }
                s = s ++ string.char(num);
            }
            return s;
        } }.anon;
    }
    if (!string.utf8forward) {
        string.utf8forward = struct { fn anon(src: anytype, ofs: anytype) V {
            if (ofs <= string.len(src)) {
                while (true) {
                    ofs = ofs + 1;
                    if ((ofs > string.len(src)) or (utf8kind(string.byte(src, ofs)) < 2)) break;
                }
            }
            return ofs;
        } }.anon;
    }
    if (!string.utf8lalign) {
        string.utf8lalign = struct { fn anon(src: anytype, ofs: anytype) V {
            while ((ofs > 1) and (utf8kind(string.byte(src, ofs)) == 2)) {
                ofs = ofs - 1;
            }
            return ofs;
        } }.anon;
    }
    if (!string.utf8ralign) {
        string.utf8ralign = struct { fn anon(src: anytype, ofs: anytype) V {
            while ((ofs <= string.len(src)) and string.byte(src, ofs) and (utf8kind(string.byte(src, ofs)) == 2)) {
                ofs = ofs + 1;
            }
            return ofs;
        } }.anon;
    }
    if (!string.translateofs) {
        string.translateofs = struct { fn anon(src: anytype, ofs: anytype, beg: anytype) V {
            var i = beg;
            var eos = string.len(src);

            while ((ofs > 1) and (i <= eos)) {
                var kind = utf8kind(string.byte(src, i));
                if (kind < 2) {
                    ofs = ofs - 1;
                }
                i = i + 1;
            }
            return i;
        } }.anon;
    }
    if (!string.utf8len) {
        string.utf8len = struct { fn anon(src: anytype, ofs: anytype) V {
            var i = 0;
            var rawlen = string.len(src);
            ofs = ((ofs < 1) and 1) or ofs;
            while (ofs <= rawlen) {
                var kind = utf8kind(string.byte(src, ofs));
                if (kind < 2) {
                    i = i + 1;
                }
                ofs = ofs + 1;
            }
            return i;
        } }.anon;
    }
    if (!string.insert) {
        string.insert = struct { fn anon(src: anytype, msg: anytype, ofs: i64, limit: anytype) V {
            if (limit == null) {
                limit = string.len(msg) + ofs;
            }
            if ((ofs + string.len(msg)) > limit) {
                msg = string.sub(msg, 1, limit - ofs);
                while ((string.len(msg) > 0) and (utf8kind(string.byte(msg, string.len(msg))) == 2)) {
                    msg = string.sub(msg, 1, string.len(msg) - 1);
                }
            }
            return __may_mv(string.sub(src, 1, ofs - 1) ++ (msg ++ string.sub(src, ofs, string.len(src))), string.len(msg));
        } }.anon;
    }
    if (!string.delete_at) {
        string.delete_at = struct { fn anon(src: anytype, ofs: i64) V {
            var fwd = string.utf8forward(src, ofs);
            if (fwd != ofs) {
                return string.sub(src, 1, ofs - 1) ++ string.sub(src, fwd, string.len(src));
            }
            return src;
        } }.anon;
    }
    const hb = struct { fn hb(ch: anytype) []const u8 {
        var th = .{
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "a",
            "b",
            "c",
            "d",
            "e",
            "f",
        };

        var fd = math.floor(ch / 16);
        var sd = ch - fd * 16;
        return th[fd + 1] ++ th[sd + 1];
    } }.hb;

    if (!string.hexenc) {
        string.hexenc = struct { fn anon(instr: anytype) V {
            return string.gsub(instr, "(.)", struct { fn anon(ch: Obj) V {
                return hb(ch.byte(1));
            } }.anon);
        } }.anon;
    }
    if (!string.trim) {
        string.trim = struct { fn anon(s: Obj) V {
            return (s.gsub("^%s*(.-)%s*$", "%1"));
        } }.anon;
    }
    if (!string.utf8valid) {
        string.utf8valid = struct { fn anon(str: anytype) V {
            const i, const len = .{ 1, @intCast(str.len) };
            var find = string.find;
            while (i <= len) {
                if (i == find(str, "[%z\x01-\x7f]", i)) {
                    i = i + 1;
                } else if (i == find(str, "[Â-ß][{-¿]", i)) {
                    i = i + 2;
                } else if ((i == find(str, "à[ -¿][€-¿]", i)) or (i == find(str, "[á-ì][€-¿][€-¿]", i)) or (i == find(str, "í[€-Ÿ][€-¿]", i)) or (i == find(str, "[î-ï][€-¿][€-¿]", i))) {
                    i = i + 3;
                } else if ((i == find(str, "ð[-¿][€-¿][€-¿]", i)) or (i == find(str, "[ñ-ó][€-¿][€-¿][€-¿]", i)) or (i == find(str, "ô[€-][€-¿][€-¿]", i))) {
                    i = i + 4;
                } else {
                    return __may_mv(false, i);
                }
            }
            return true;
        } }.anon;
    }
    if (!string.dump) {
        string.dump = struct { fn anon(msg: anytype) void {
            var bt = .{};
            for (1..string.len(msg) + 1) |i| {
                var ch = string.byte(msg, i);
                bt[i] = ch;
            }
        } }.anon;
    }
    if (!string.unpack_shmif_argstr) {
        string.unpack_shmif_argstr = struct { fn anon(a1: anytype, a2: anytype) V {
            var arg = undefined;
            var res = undefined;
            if (type(a1) == "table") {
                res = a1;
                arg = a2;
            } else {
                arg = a1;
                res = .{};
            }
            if ((type(arg) != "string") or (@intCast(arg.len) == 0)) {
                return res;
            }
            var entries = string.split(arg, ":");
            for (entries, 0..) |v, _| {
                var elem = string.split(v, "=");
                if (elem and elem[1] and (@intCast(elem[1].len) > 0)) {
                    if (@intCast(elem.len) == 1) {
                        res[elem[1]] = true;
                    } else if (@intCast(elem.len) == 2) {
                        res[elem[1]] = string.gsub(elem[2], "\t", ":");
                    }
                }
            }
            return res;
        } }.anon;
    }
    if (!string.find(API_ENGINE_BUILD, "luajit51")) {
        var of = string.format;
        string.format = struct { fn anon(va: anytype) V {
            var arg = .{ va };
            for (2..(@intCast(arg.len)) + 1) |i| {
                if (type(arg[i]) == "boolean") {
                    arg[i] = (arg[i] and "true") or "false";
                } else if (arg[i] == null) {
                    arg[i] = "nil";
                }
            }
            return of(unpack(arg));
        } }.anon;
    }
}
