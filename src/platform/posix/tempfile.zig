// Zig port of posix/tempfile.c
// Creates an anonymous temp file, writes msg into it, seeks to start, returns fd.

const std = @import("std");
const c = @import("posix");

export fn arcan_strbuf_tempfile(
    msg: [*c]const u8,
    msg_sz: usize,
    err_out: *[*c]const u8,
) c_int {
    // mkstemp + unlink for anonymous temp file
    var filename = "arcantemp-XXXXXX".*;
    const state_fd = c.mkstemp(&filename);
    if (state_fd == -1) {
        err_out.* = "temp file creation failed";
        return -1;
    }
    _ = c.unlink(&filename);

    // Write loop
    var ntw = msg_sz;
    var pos: usize = 0;
    while (ntw > 0) {
        const nw = c.write(state_fd, msg + pos, ntw);
        if (nw == -1) {
            continue; // retry (matches C behavior: EINTR retry)
        }
        const written: usize = @intCast(nw);
        ntw -= written;
        pos += written;
    }

    _ = c.lseek(state_fd, 0, c.SEEK_SET);
    return state_fd;
}
