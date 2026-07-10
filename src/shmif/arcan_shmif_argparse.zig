// Zig reimplementation of arcan_shmif_argparse.c
// Drop-in C-ABI-compatible replacement for argparse functions.
//
// Exports: arg_unpack, arg_cleanup, arg_remove, arg_add,
//          arg_lookup, arg_serialize
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// Extern C declarations

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*c]const u8) [*c]u8;
extern "c" fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
extern "c" fn strlen(s: [*c]const u8) usize;
extern "c" fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;

const FILE = opaque {};
extern "c" fn open_memstream(bufp: *[*c]u8, sizep: *usize) ?*FILE;
extern "c" fn fputs(s: [*c]const u8, stream: *FILE) c_int;
extern "c" fn fputc(ch: c_int, stream: *FILE) c_int;
extern "c" fn fclose(stream: *FILE) c_int;

const arg_arr = c.struct_arg_arr;

// strrep: in-place character replacement

fn strrep(dst: [*c]u8, key: u8, repl: u8) [*c]u8 {
    const src = dst;
    if (dst == null) return src;

    var p: [*c]u8 = dst;
    while (p[0] != 0) {
        if (p[0] == key)
            p[0] = repl;
        p += 1;
    }

    return src;
}

// arg_unpack

export fn arg_unpack(resource: [*c]const u8) [*c]arg_arr {
    if (is_freestanding) return null;
    if (resource == null) return null;

    // count arguments: always at least 1 unless empty
    var argc: usize = 1;
    {
        var i: usize = 0;
        while (resource[i] != 0) : (i += 1) {
            if (resource[i] == ':')
                argc += 1;
        }
    }

    // prepare space: argc+1 entries (last is sentinel)
    const alloc_sz = (argc + 1) * @sizeOf(arg_arr);
    const raw = malloc(alloc_sz) orelse return null;
    const argv: [*c]arg_arr = @ptrCast(@alignCast(raw));

    // null-terminate sentinel
    argv[argc].key = null;
    argv[argc].value = null;

    const base: [*c]u8 = strdup(resource);
    var workstr: [*c]u8 = base;

    // sweep for key=val:key:key style packed arguments
    var curarg: usize = 0;
    const result: [*c]arg_arr = unpack_loop: {
        while (curarg < argc) {
            var endp: [*c]u8 = workstr;
            var inv = false;
            argv[curarg].key = null;
            argv[curarg].value = null;

            while (endp[0] != 0 and endp[0] != ':') {
                if (!inv and endp[0] == '=') {
                    if (argv[curarg].key == null) {
                        endp[0] = 0;
                        argv[curarg].key = strrep(strdup(workstr), '\t', ':');
                        argv[curarg].value = null;
                        workstr = endp + 1;
                        inv = true;
                    } else {
                        free(@as(?*anyopaque, @ptrCast(argv)));
                        break :unpack_loop @as([*c]arg_arr, null);
                    }
                }

                endp += 1;
            }

            if (endp[0] == ':')
                endp[0] = 0;

            if (argv[curarg].key != null)
                argv[curarg].value = strrep(strdup(workstr), '\t', ':')
            else
                argv[curarg].key = strrep(strdup(workstr), '\t', ':');

            workstr = endp + 1;
            curarg += 1;
        }
        break :unpack_loop argv;
    };

    free(@as(?*anyopaque, @ptrCast(base)));
    return result;
}

// arg_cleanup

export fn arg_cleanup(arr: [*c]arg_arr) void {
    if (is_freestanding) return;
    if (arr == null) return;

    var cur: [*c]arg_arr = arr;
    while (cur[0].key != null) {
        free(@as(?*anyopaque, @ptrCast(cur[0].key)));
        free(@as(?*anyopaque, @ptrCast(cur[0].value)));
        cur += 1;
    }

    free(@as(?*anyopaque, @ptrCast(arr)));
}

// shift_left

fn shift_left(arr: [*c]arg_arr, pos_in: c_int) void {
    const start = pos_in;
    var pos = pos_in;

    while (true) {
        if (pos == start and arr[@intCast(pos)].key != null)
            free(@as(?*anyopaque, @ptrCast(arr[@intCast(pos)].key)));
        if (pos == start and arr[@intCast(pos)].value != null)
            free(@as(?*anyopaque, @ptrCast(arr[@intCast(pos)].value)));
        _ = memcpy(
            @as(?*anyopaque, @ptrCast(&arr[@intCast(pos)])),
            @as(?*const anyopaque, @ptrCast(&arr[@as(usize, @intCast(pos)) + 1])),
            @sizeOf(arg_arr),
        );
        const done = arr[@intCast(pos)].key == null;
        pos += 1;
        if (done) break;
    }
}

// arg_remove

export fn arg_remove(arr: [*c]arg_arr, key: [*c]const u8) void {
    if (is_freestanding) return;
    if (key == null) return;
    if (arr == null) return;

    var i: usize = 0;
    while (arr[i].key != null) {
        if (strcmp(arr[i].key, key) == 0) {
            shift_left(arr, @intCast(i));
        } else {
            i += 1;
        }
    }
}

// arg_add

export fn arg_add(
    C: ?*c.struct_arcan_shmif_cont,
    darg: ?*[*c]arg_arr,
    key: [*c]const u8,
    val: [*c]const u8,
    replace: bool,
) bool {
    if (is_freestanding) return false;
    if (key == null) return false;
    const darg_ptr = darg orelse return false;

    var arr: [*c]arg_arr = darg_ptr.*;

    // do we substitute the first we find or append?
    var i: usize = 0;
    while (arr[i].key != null) : (i += 1) {
        if (strcmp(arr[i].key, key) == 0 and replace) {
            // value is permitted to be empty
            if (arr[i].value != null)
                free(@as(?*anyopaque, @ptrCast(arr[i].value)));

            arr[i].value = if (val != null) strdup(val) else null;

            return true;
        }
    }

    // allocate with one more slot; i points to the null slot, hence + 2
    const narg_raw = malloc(@sizeOf(arg_arr) * (i + 2)) orelse return false;
    const narg: [*c]arg_arr = @ptrCast(@alignCast(narg_raw));
    for (0..i + 1) |j| {
        _ = memcpy(
            @as(?*anyopaque, @ptrCast(&narg[j])),
            @as(?*const anyopaque, @ptrCast(&arr[j])),
            @sizeOf(arg_arr),
        );
    }
    narg[i + 1] = std.mem.zeroes(arg_arr);
    narg[i].key = strdup(key);
    if (val != null)
        narg[i].value = strdup(val);

    free(@as(?*anyopaque, @ptrCast(darg_ptr.*)));
    darg_ptr.* = narg;
    if (C) |ctx| {
        const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));
        off.Hidden.setArgs(P, @as(?*anyopaque, @ptrCast(narg)));
    }

    return true;
}

// arg_serialize

export fn arg_serialize(arr: [*c]arg_arr) [*c]u8 {
    if (is_freestanding) return null;
    if (arr == null) return null;

    var buf: [*c]u8 = undefined;
    var buf_sz: usize = undefined;
    const fbuf = open_memstream(&buf, &buf_sz) orelse return null;

    // in wire form we have escaping rules
    var pos: usize = 0;
    while (arr[pos].key != null) {
        _ = strrep(arr[pos].key, ':', '\t');
        _ = fputs(arr[pos].key, fbuf);
        _ = strrep(arr[pos].key, '\t', ':');

        if (arr[pos].value != null) {
            _ = fputc('=', fbuf);
            _ = strrep(arr[pos].value, ':', '\t');
            _ = fputs(arr[pos].value, fbuf);
            _ = strrep(arr[pos].value, '\t', ':');
        }

        // [arr] is NULL item terminated so check if at the end
        if (arr[pos + 1].key != null) {
            _ = fputc(':', fbuf);
        }
        pos += 1;
    }

    _ = fclose(fbuf);
    return buf;
}

// arg_lookup

export fn arg_lookup(
    arr: [*c]arg_arr,
    val: [*c]const u8,
    ind: c_ushort,
    found: ?*[*c]const u8,
) bool {
    if (is_freestanding) return false;
    if (found) |f| f.* = null;

    if (arr == null) return false;

    var remaining = ind;
    var pos: usize = 0;
    while (arr[pos].key != null) : (pos += 1) {
        // return only the 'ind'th match
        if (strcmp(arr[pos].key, val) == 0) {
            if (remaining == 0) {
                if (found) |f| f.* = arr[pos].value;
                return true;
            }
            remaining -= 1;
        }
    }

    return false;
}
