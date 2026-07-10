// Zig port of decode_text.c — text file display mode using TUI buffer widget
const std = @import("std");
const c = @import("shmif_types");

fn run_file_mmap(cont: ?*c.arcan_shmif_cont, fd: c_int, view: c_int) bool {
    var fs: c.struct_stat = undefined;
    if (c.fstat(fd, &fs) == -1) {
        c.arcan_shmif_last_words(cont, "couldn't stat source");
        return false;
    }

    const size: usize = @intCast(fs.st_size);
    const result = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (@intFromPtr(result) == ~@as(usize, 0)) {
        c.arcan_shmif_last_words(cont, "couldn't mmap source");
        return false;
    }
    const buf: [*c]u8 = @ptrCast(result);

    var opts: c.struct_tui_bufferwnd_opts = std.mem.zeroes(c.struct_tui_bufferwnd_opts);
    opts.read_only = true;
    opts.view_mode = view;
    opts.wrap_mode = c.BUFFERWND_WRAP_ACCEPT_LF;
    opts.allow_exit = false;

    var cbcfg: c.struct_tui_cbcfg = std.mem.zeroes(c.struct_tui_cbcfg);
    const tui = c.arcan_tui_setup(cont, null, &cbcfg, @sizeOf(c.struct_tui_cbcfg));
    _ = c.arcan_tui_bufferwnd_setup(tui, buf, size, &opts, @sizeOf(c.struct_tui_bufferwnd_opts));

    while (c.arcan_tui_bufferwnd_status(tui) == 1) {
        var tui_ptr = tui;
        const res = c.arcan_tui_process(&tui_ptr, 1, null, 0, -1);
        if (res.errc == c.TUI_ERRC_OK) {
            if (c.arcan_tui_refresh(tui) == -1 and std.c._errno().* == c.EINVAL)
                break;
        }
    }

    c.arcan_tui_destroy(tui, null);
    _ = c.munmap(result, size);
    return true;
}

export fn decode_text(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    var infile: [*c]const u8 = null;
    if (!c.arg_lookup(args, "file", 0, &infile) or infile == null or c.strlen(infile) == 0) {
        c.arcan_shmif_last_words(cont, "no valid 'file' argument");
        return 1;
    }

    const fd = c.open(infile, c.O_RDONLY);
    if (fd == -1) {
        c.arcan_shmif_last_words(cont, "couldn't open file");
        return 1;
    }

    var view: c_int = c.BUFFERWND_VIEW_UTF8;
    var mode: [*c]const u8 = null;
    if (c.arg_lookup(args, "view", 0, &mode) and mode != null and c.strlen(mode) > 0) {
        if (c.strcasecmp(mode, "hex") == 0) {
            view = c.BUFFERWND_VIEW_HEX;
        } else if (c.strcasecmp(mode, "ascii") == 0) {
            view = c.BUFFERWND_VIEW_ASCII;
        }
    }

    _ = run_file_mmap(cont, fd, view);
    return 0;
}
