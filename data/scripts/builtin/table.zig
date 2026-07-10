
pub fn __init() void {
    if (!table.set_unless_exists) {
        table.set_unless_exists = struct { fn anon(tbl: anytype, key: anytype, val: anytype) void {
            tbl[key] = (tbl[key] and tbl[key]) or val;
        } }.anon;
    }
    if (!table.get_fallback) {
        table.get_fallback = struct { fn anon(tbl: bool, key: anytype, fallback: anytype) V {
            if (!tbl or !tbl[key]) {
                return fallback;
            } else {
                return tbl[key];
            }
        } }.anon;
    }
    if (!table.merge) {
        table.merge = struct { fn anon(dst: anytype, src: anytype, ref: anytype, on_error: anytype) void {
            for (pairs(ref)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (src[k] and (type(src[k]) == type(v))) {
                    v = src[k];
                } else if (src[k]) {
                    on_error(k);
                }
                if (type(k) == "table") {
                    dst[k] = table.copy(v);
                } else {
                    dst[k] = v;
                }
            }
        } }.anon;
    }
    if (!table.copy) {
        table.copy = struct { fn anon(tbl: bool) V {
            if (!tbl or (!type(tbl) == "table")) {
                return .{};
            }
            var res = .{};
            for (pairs(tbl)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                if (type(v) == "table") {
                    res[k] = table.copy(v);
                } else {
                    res[k] = v;
                }
            }
            return res;
        } }.anon;
    }
    if (!table.remove_match) {
        table.remove_match = struct { fn anon(tbl: anytype, match: anytype) V {
            if (tbl == null) {
                return;
            }
            for (tbl, 0..) |v, k| {
                if (v == match) {
                    table.remove(tbl, k);
                    return __may_mv(v, k);
                }
            }
            return null;
        } }.anon;
    }
    if (!table.find_i) {
        table.find_i = struct { fn anon(table: anytype, r: anytype) V {
            for (table, 0..) |v, k| {
                if (v == r) {
                    return k;
                }
            }
        } }.anon;
    }
    if (!table.find_key_i) {
        table.find_key_i = struct { fn anon(table: anytype, field: anytype, r: anytype) V {
            for (table, 0..) |v, k| {
                if (v[field] == r) {
                    return k;
                }
            }
        } }.anon;
    }
    if (!table.insert_unique_i) {
        table.insert_unique_i = struct { fn anon(tbl: anytype, i: anytype, v: anytype) void {
            var ind = table.find_i(tbl, v);
            if (!ind) {
                table.insert(tbl, i, v);
            } else {
                var cpy = tbl[i];
                tbl[i] = tbl[ind];
                tbl[ind] = cpy;
            }
        } }.anon;
    }
    if (!table.filter) {
        table.filter = struct { fn anon(tbl: anytype, filter_fn: anytype, va: anytype) V {
            var res = .{};

            for (tbl, 0..) |v, _| {
                if (filter_fn(v, va) == true) {
                    table.insert(res, v);
                }
            }
            return res;
        } }.anon;
    }
}
