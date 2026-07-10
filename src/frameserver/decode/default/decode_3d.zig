// Zig port of decode_3d.c — 3D model decoder (tinyobj via C helper)
const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arg_arr = shmif.arg_arr;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_privsep = shmif.arcan_shmif_privsep;
    pub const FILE = libc.FILE;
    pub const fopen = libc.fopen;
    pub const fclose = libc.fclose;
    pub const fdopen = libc.fdopen;
    pub const fread = libc.fread;
    pub const fseek = libc.fseek;
    pub const ftell = libc.ftell;
    pub const malloc = libc.malloc;
    pub const free = libc.free;
    pub const SEEK_END = libc.SEEK_END;
    pub const SEEK_SET = libc.SEEK_SET;
};

// From decode.h
extern "c" fn show_use(cont: ?*c.arcan_shmif_cont, msg: [*c]const u8) c_int;
extern "c" fn wait_for_file(cont: ?*c.arcan_shmif_cont, extstr: [*c]const u8, id: ?*[*c]u8) c_int;

// decode_3d_process_obj: stub — tinyobj C wrapper deleted in Zig migration
export fn decode_3d_process_obj(_: [*c]u8, _: usize) callconv(.c) c_int { return -1; }

export fn decode_3d(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    var fpek: ?*c.FILE = null;
    var file: [*c]const u8 = null;

    if (c.arg_lookup(args, "file", 0, &file)) {
        fpek = c.fopen(file, "r");
        if (fpek == null) {
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrintZ(&buf, "couldn't open {s}", .{
                if (file != null) std.mem.span(file.?) else "<null>",
            }) catch "couldn't open file";
            return show_use(cont, msg.ptr);
        }
    } else {
        const fd = wait_for_file(cont, "obj;gltf", null);
        if (fd == -1) return 1;
        fpek = c.fdopen(fd, "r");
    }

    const fp = fpek.?;
    _ = c.fseek(fp, 0, c.SEEK_END);
    const pos = c.ftell(fp);
    _ = c.fseek(fp, 0, c.SEEK_SET);
    if (pos <= 0) {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buf, "invalid length ({d}) in {s}", .{
            pos,
            if (file != null) std.mem.span(file.?) else "<null>",
        }) catch "invalid file length";
        _ = c.fclose(fp);
        return show_use(cont, msg.ptr);
    }

    const size: usize = @intCast(pos);
    const inbuf: [*c]u8 = @ptrCast(c.malloc(size) orelse {
        _ = c.fclose(fp);
        return show_use(cont, "out of memory");
    });

    if (c.fread(inbuf, size, 1, fp) != 1) {
        _ = c.fclose(fp);
        c.free(inbuf);
        return show_use(cont, "couldn't load");
    }
    _ = c.fclose(fp);

    if (size == 0) return show_use(cont, "no data in file");

    c.arcan_shmif_privsep(cont, "shmif", null, 0);

    return decode_3d_process_obj(inbuf, size);
}
