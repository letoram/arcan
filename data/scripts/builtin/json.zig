
var json = .{ ._version = "0.1.1" };
var encode = undefined;
var escape_char_map = .{
    __may_kv("\\", "\\\\"),
    __may_kv("\"", "\\\""),
    __may_kv("\x08", "\\b"),
    __may_kv("\x0c", "\\f"),
    __may_kv("\n", "\\n"),
    __may_kv("\r", "\\r"),
    __may_kv("\t", "\\t"),
};
var escape_char_map_inv = .{ __may_kv("\\/", "/") };

pub fn __init() void {
    for (pairs(escape_char_map)) |__may_pair| {
        const k = __may_pair[0];
        const v = __may_pair[1];
        escape_char_map_inv[v] = k;
    }
    const escape_char = struct { fn escape_char(c: Obj) V {
        return escape_char_map[c] or string.format("\\u%04x", c.byte());
    } }.escape_char;

    const encode_nil = struct { fn encode_nil(val: anytype) []const u8 {
        return "null";
    } }.encode_nil;

    const encode_table = struct { fn encode_table(val: anytype, stack: anytype) []const u8 {
        var res = .{};
        stack = stack or .{};
        if (stack[val]) {
            @"error"("circular reference");
        }
        stack[val] = true;
        if ((rawget(val, 1) != null) or (next(val) == null)) {
            var n = 0;
            for (pairs(val)) |__may_pair| {
                const k = __may_pair[0];
                if (type(k) != "number") {
                    @"error"("invalid table: mixed or invalid key types");
                }
                n = n + 1;
            }
            if (n != @intCast(val.len)) {
                @"error"("invalid table: sparse array");
            }
            for (val, 0..) |v, i| {
                table.insert(res, encode(v, stack));
            }
            stack[val] = null;
            return "[" ++ (table.concat(res, ",") ++ "]");
        } else {
            for (pairs(val)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (type(k) != "string") {
                    @"error"("invalid table: mixed or invalid key types");
                }
                table.insert(res, encode(k, stack) ++ (":" ++ encode(v, stack)));
            }
            stack[val] = null;
            return "{" ++ (table.concat(res, ",") ++ "}");
        }
    } }.encode_table;

    const encode_string = struct { fn encode_string(val: Obj) []const u8 {
        return "\"" ++ (val.gsub("[%z\x01-\x1f\\\"]", escape_char) ++ "\"");
    } }.encode_string;

    const encode_number = struct { fn encode_number(val: i64) V {
        if ((val != val) or (val <= -math.huge) or (val >= math.huge)) {
            @"error"("unexpected number value '" ++ (tostring(val) ++ "'"));
        }
        return string.format("%.14g", val);
    } }.encode_number;

    var type_func_map = .{
        __may_kv("nil", encode_nil),
        __may_kv("table", encode_table),
        __may_kv("string", encode_string),
        __may_kv("number", encode_number),
        __may_kv("boolean", tostring),
    };
    encode = struct { fn anon(val: anytype, stack: anytype) V {
        var t = type(val);
        var f = type_func_map[t];
        if (f) {
            return f(val, stack);
        }
        @"error"("unexpected type '" ++ (t ++ "'"));
    } }.anon;
    json.encode = struct { fn anon(val: anytype) V {
        return (encode(val));
    } }.anon;

    var parse = undefined;
    const create_set = struct { fn create_set(va: anytype) V {
        var res = .{};
        for (1..select("#", va) + 1) |i| {
            res[select(i, va)] = true;
        }
        return res;
    } }.create_set;

    var space_chars = create_set(" ", "\t", "\r", "\n");
    var delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",");
    var escape_chars = create_set("\\", "/", "\"", "b", "f", "n", "r", "t", "u");
    var literals = create_set("true", "false", "null");
    var literal_map = .{
        __may_kv("true", true),
        __may_kv("false", false),
        __may_kv("null", null),
    };
    const next_char = struct { fn next_char(str: Obj, idx: anytype, set: anytype, negate: anytype) V {
        for (idx..(@intCast(str.len)) + 1) |i| {
            if (set[str.sub(i, i)] != negate) {
                return i;
            }
        }
        return @intCast(str.len) + 1;
    } }.next_char;

    const decode_error = struct { fn decode_error(str: Obj, idx: i64, msg: anytype) void {
        var line_count = 1;
        var col_count = 1;
        for (1..(idx - 1) + 1) |i| {
            col_count = col_count + 1;
            if (str.sub(i, i) == "\n") {
                line_count = line_count + 1;
                col_count = 1;
            }
        }
        @"error"(string.format("%s at line %d col %d", msg, line_count, col_count));
    } }.decode_error;

    const codepoint_to_utf8 = struct { fn codepoint_to_utf8(n: anytype) V {
        var f = math.floor;
        if (n <= 0x7f) {
            return string.char(n);
        } else if (n <= 0x7ff) {
            return string.char(f(n / 64) + 192, n % 64 + 128);
        } else if (n <= 0xffff) {
            return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128);
        } else if (n <= 0x10ffff) {
            return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128);
        }
        @"error"(string.format("invalid unicode codepoint '%x'", n));
    } }.codepoint_to_utf8;

    const parse_unicode_escape = struct { fn parse_unicode_escape(s: Obj) V {
        var n1 = tonumber(s.sub(3, 6), 16);
        var n2 = tonumber(s.sub(9, 12), 16);
        if (n2) {
            return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000);
        } else {
            return codepoint_to_utf8(n1);
        }
    } }.parse_unicode_escape;

    const parse_string = struct { fn parse_string(str: Obj, i: i64) V {
        var has_unicode_escape = false;
        var has_surrogate_escape = false;
        var has_escape = false;
        var last = undefined;
        for (i + 1..(@intCast(str.len)) + 1) |j| {
            var x = str.byte(j);
            if (x < 32) {
                decode_error(str, j, "control character in string");
            }
            if (last == 92) {
                if (x == 117) {
                    var hex: Obj = str.sub(j + 1, j + 5);
                    if (!hex.find("%x%x%x%x")) {
                        decode_error(str, j, "invalid unicode escape in string");
                    }
                    if (hex.find("^[dD][89aAbB]")) {
                        has_surrogate_escape = true;
                    } else {
                        has_unicode_escape = true;
                    }
                } else {
                    var c = string.char(x);
                    if (!escape_chars[c]) {
                        decode_error(str, j, "invalid escape char '" ++ (c ++ "' in string"));
                    }
                    has_escape = true;
                }
                last = null;
            } else if (x == 34) {
                var s: Obj = str.sub(i + 1, j - 1);
                if (has_surrogate_escape) {
                    s = s.gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape);
                }
                if (has_unicode_escape) {
                    s = s.gsub("\\u....", parse_unicode_escape);
                }
                if (has_escape) {
                    s = s.gsub("\\.", escape_char_map_inv);
                }
                return __may_mv(s, j + 1);
            } else {
                last = x;
            }
        }
        decode_error(str, i, "expected closing quote for string");
    } }.parse_string;

    const parse_number = struct { fn parse_number(str: Obj, i: anytype) V {
        var x = next_char(str, i, delim_chars);
        var s = str.sub(i, x - 1);
        var n = tonumber(s);
        if (!n) {
            decode_error(str, i, "invalid number '" ++ (s ++ "'"));
        }
        return __may_mv(n, x);
    } }.parse_number;

    const parse_literal = struct { fn parse_literal(str: Obj, i: anytype) V {
        var x = next_char(str, i, delim_chars);
        var word = str.sub(i, x - 1);
        if (!literals[word]) {
            decode_error(str, i, "invalid literal '" ++ (word ++ "'"));
        }
        return __may_mv(literal_map[word], x);
    } }.parse_literal;

    const parse_array = struct { fn parse_array(str: Obj, i: anytype) V {
        var res = .{};
        var n = 1;
        i = i + 1;
        while (1) {
            var x = undefined;
            i = next_char(str, i, space_chars, true);
            if (str.sub(i, i) == "]") {
                i = i + 1;
                break;
            }
            x, i = parse(str, i);
            res[n] = x;
            n = n + 1;
            i = next_char(str, i, space_chars, true);
            var chr = str.sub(i, i);
            i = i + 1;
            if (chr == "]") {
                break;
            }
            if (chr != ",") {
                decode_error(str, i, "expected ']' or ','");
            }
        }
        return __may_mv(res, i);
    } }.parse_array;

    const parse_object = struct { fn parse_object(str: Obj, i: anytype) V {
        var res = .{};
        i = i + 1;
        while (1) {
            var key = undefined;
            var val = undefined;
            i = next_char(str, i, space_chars, true);
            if (str.sub(i, i) == "}") {
                i = i + 1;
                break;
            }
            if (str.sub(i, i) != "\"") {
                decode_error(str, i, "expected string for key");
            }
            key, i = parse(str, i);
            i = next_char(str, i, space_chars, true);
            if (str.sub(i, i) != ":") {
                decode_error(str, i, "expected ':' after key");
            }
            i = next_char(str, i + 1, space_chars, true);
            val, i = parse(str, i);
            res[key] = val;
            i = next_char(str, i, space_chars, true);
            var chr = str.sub(i, i);
            i = i + 1;
            if (chr == "}") {
                break;
            }
            if (chr != ",") {
                decode_error(str, i, "expected '}' or ','");
            }
        }
        return __may_mv(res, i);
    } }.parse_object;

    var char_func_map = .{
        __may_kv("\"", parse_string),
        __may_kv("0", parse_number),
        __may_kv("1", parse_number),
        __may_kv("2", parse_number),
        __may_kv("3", parse_number),
        __may_kv("4", parse_number),
        __may_kv("5", parse_number),
        __may_kv("6", parse_number),
        __may_kv("7", parse_number),
        __may_kv("8", parse_number),
        __may_kv("9", parse_number),
        __may_kv("-", parse_number),
        __may_kv("t", parse_literal),
        __may_kv("f", parse_literal),
        __may_kv("n", parse_literal),
        __may_kv("[", parse_array),
        __may_kv("{", parse_object),
    };
    parse = struct { fn anon(str: Obj, idx: anytype) V {
        var chr = str.sub(idx, idx);
        var f = char_func_map[chr];
        if (f) {
            return f(str, idx);
        }
        decode_error(str, idx, "unexpected character '" ++ (chr ++ "'"));
    } }.anon;
    json.decode = struct { fn anon(str: anytype) V {
        if (type(str) != "string") {
            @"error"("expected argument of type string, got " ++ type(str));
        }
        const res, const idx = parse(str, next_char(str, 1, space_chars, true));
        idx = next_char(str, idx, space_chars, true);
        if (idx <= @intCast(str.len)) {
            decode_error(str, idx, "trailing garbage");
        }
        return res;
    } }.anon;

    return json;
}
