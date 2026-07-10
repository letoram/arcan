// Encode reference frameserver archetype
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: http://arcan-fe.com
// Depends: FFMPEG (GPLv2,v3,LGPL)

const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module. `HAVE_*` macros are
/// gated at module scope via an explicit build flag — see below.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arg_arr = shmif.arg_arr;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_last_words = shmif.arcan_shmif_last_words;
    pub const struct_sigaction = shmif.struct_sigaction;
    pub const sigaction = shmif.sigaction;
    pub const SIGINT = shmif.SIGINT;
    pub const SIGPIPE = shmif.SIGPIPE;
    pub const EXIT_FAILURE = shmif.EXIT_FAILURE;
    pub const EXIT_SUCCESS = shmif.EXIT_SUCCESS;
    pub const fprintf = libc.fprintf;
    // `pub const stdout = libc.stdout` runs afoul of Zig 0.15's "initializer
    // must be comptime-known" rule because libc.stdout is an extern var
    // whose VALUE is runtime. Re-declare the extern here so the symbol
    // is reachable as `c.stdout` / `c.stderr` while satisfying the
    // comptime rule. Both decls resolve to the same libc symbol at link.
    pub extern "c" var stdout: *libc.FILE;
    pub extern "c" var stderr: *libc.FILE;
};

// `@hasDecl(c, "HAVE_VNCSERVER")` was the pre-migration check. The actual
// build only conditionally defines HAVE_V4L2 (see build.zig:addCMacro).
// Hard-code to false for the dispatch struct; enable via build flag if/when
// these protocols come back.
const HAVE_VNCSERVER = false;
const HAVE_V4L2 = false;
const HAVE_OCR = false;

// Functions from encode.h — declared as extern since the header
// is not on the shmif include path and uses types we already have.
extern "c" fn a12_serv_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) c_int;
extern "c" fn png_stream_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) void;
extern "c" fn ffmpeg_run(args: ?*c.arg_arr, cont: ?*c.arcan_shmif_cont) c_int;

// Conditionally-available protocol handlers (guarded by build-time C macros)
const have_vncserver = HAVE_VNCSERVER;
const have_v4l2 = HAVE_V4L2;
const have_ocr = HAVE_OCR;

// Conditional extern declarations — only resolved by the linker when the
// corresponding HAVE_* macro is defined (i.e., the object is compiled in).
const vnc = if (have_vncserver) struct {
    extern "c" fn vnc_serv_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) void;
} else struct {};

const v4l2 = if (have_v4l2) struct {
    extern "c" fn v4l2_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) c_int;
} else struct {};

const ocr = if (have_ocr) struct {
    extern "c" fn ocr_serv_run(args: ?*c.arg_arr, cont: c.arcan_shmif_cont) void;
} else struct {};

fn dump_help() void {
    const base_help =
        "Encode should be run authoritatively (spawned from arcan)\n" ++
        "ARCAN_ARG (environment variable, " ++
        "key1=value:key2:key3=value), arguments: \n" ++
        "  key   \t   value   \t   description\n" ++
        "--------\t-----------\t-----------------\n" ++
        "protocol\t name      \t switch protocol/mode, default=video\n\n";

    const vnc_help = if (have_vncserver)
        "protocol=vnc\n" ++
            "  key   \t   value   \t   description\n" ++
            "--------\t-----------\t-----------------\n" ++
            " name   \t string    \t set exported 'desktopName'\n" ++
            " pass   \t string    \t set server password (insecure)\n" ++
            " port   \t number    \t set server listen port\n\n"
    else
        "";

    const v4l2_help = if (have_v4l2)
        "protocol=cam\n" ++
            " key    \t  value    \t   description\n" ++
            "--------\t-----------\t-----------------\n" ++
            " device \t  number   \t set videoN device to write into (/dev/videoN)\n" ++
            " format \t  pxfmt    \t output pixel format (rgb, bgr)\n" ++
            " fps    \t  fps      \t (=25), target framerate\n" ++
            " fdout  \t           \t slow write path instead of mmap\n\n"
    else
        "";

    const ocr_help = if (have_ocr)
        "protocol=ocr\n" ++
            "  key   \t   value   \t   description\n" ++
            "--------\t-----------\t-----------------\n" ++
            " lang   \t string    \t set OCR engine language (default: eng)\n\n"
    else
        "";

    const tail_help =
        "protocol=a12\n" ++
        " key      \t   value   \t   description\n" ++
        "----------\t-----------\t-----------------\n" ++
        " authk    \t key       \t set authentication pre-shared key\n" ++
        " pubk     \t b64(key)  \t allow connection from pre-authenticated public key\n" ++
        " host     \t ip|host   \t make an outbound connection to a host or IP\n" ++
        " tag      \t name      \t make an outbound connection to a keystore tagged name\n" ++
        " pass     \t passphrase\t combine a passphrase to authenticate x25519 keys\n" ++
        " ident    \t name      \t set name to identify when registering in a directory\n" ++
        " tunnel   \t           \t prefer to tunnel traffic through directory when possible\n" ++
        " vcodec   \t codec     \t force codec to [h264, raw, raw565] rather than default\n" ++
        " bias     \t mode      \t set codec bias mode [latency, balanced, quality]\n" ++
        " port     \t number    \t set server listening port\n" ++
        " softauth \t           \t trust the key presented by the remote party\n\n" ++
        "protocol=png\n" ++
        "  key   \t   value   \t   description\n" ++
        "--------\t-----------\t-----------------\n" ++
        "prefix  \t filename  \t (png) set prefix_number.png\n" ++
        "limit   \t number    \t stop after 'number' frames\n" ++
        "skip    \t number    \t skip first 'number' frames\n\n" ++
        "protocol=video\n" ++
        "  key   \t   value   \t   description\n" ++
        "----------\t-----------\t-----------------\n" ++
        "vbitrate  \t kilobits  \t nominal video bitrate\n" ++
        "abitrate  \t kilobits  \t nominal audio bitrate\n" ++
        "vpreset   \t 1..10     \t video preset quality level\n" ++
        "apreset   \t 1..10     \t audio preset quality level\n" ++
        "fps       \t float     \t targeted framerate\n" ++
        "noaudio   \t           \t ignore/omit audio encoding\n" ++
        "vptsofs   \t ms        \t delay video presentation\n" ++
        "aptsofs   \t ms        \t delay audio presentation\n" ++
        "presilence\t ms        \t buffer audio with silence\n" ++
        "vcodec    \t format    \t try to specify video codec\n" ++
        "acodec    \t format    \t try to specify audio codec\n" ++
        "container \t format    \t try to specify container format\n" ++
        "stream    \t           \t enable remote streaming\n" ++
        "streamdst \t rtmp://.. \t stream to server url\n\n";

    _ = c.fprintf(c.stdout, "%s%s%s%s%s", base_help.ptr, vnc_help.ptr, v4l2_help.ptr, ocr_help.ptr, tail_help.ptr);
}

fn streql(a: [*c]const u8, b: []const u8) bool {
    if (a == null) return false;
    const span = std.mem.span(a);
    return std.mem.eql(u8, span, b);
}

export fn afsrv_encode(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    var argval: [*c]const u8 = null;

    if (args == null or cont == null or c.arg_lookup(args, "help", 0, &argval)) {
        dump_help();
        return c.EXIT_FAILURE;
    }

    // Disable SIGINT and SIGPIPE — they might be delivered with other uses
    // of afsrv_encode, typically arcan-net.
    var sa = std.mem.zeroes(c.struct_sigaction);
    // SIG_IGN = (void(*)(int))1 — unaligned sentinel, must bypass safety
    sa.__sa_handler = @bitCast(@as(usize, 1));
    _ = c.sigaction(c.SIGINT, &sa, null);
    _ = c.sigaction(c.SIGPIPE, &sa, null);

    if (c.arg_lookup(args, "protocol", 0, &argval) or
        c.arg_lookup(args, "proto", 0, &argval))
    {
        if (argval == null) {
            c.arcan_shmif_last_words(cont, "missing proto= argument");
            return c.EXIT_FAILURE;
        }

        if (have_vncserver and streql(argval, "vnc")) {
            vnc.vnc_serv_run(args, cont.?.*);
            return c.EXIT_SUCCESS;
        }

        if (have_v4l2 and streql(argval, "cam")) {
            return v4l2.v4l2_run(args, cont.?.*);
        }

        if (streql(argval, "a12")) {
            _ = a12_serv_run(args, cont.?.*);
            return c.EXIT_SUCCESS;
        }

        if (have_ocr and streql(argval, "ocr")) {
            ocr.ocr_serv_run(args, cont.?.*);
            return c.EXIT_SUCCESS;
        }

        if (streql(argval, "png")) {
            png_stream_run(args, cont.?.*);
            return c.EXIT_SUCCESS;
        } else if (streql(argval, "video")) {
            // fall through to ffmpeg_run below
        } else {
            _ = c.fprintf(c.stderr, "unsupported encoding protocol (%s) specified, giving up.\n", argval);
            return c.EXIT_FAILURE;
        }
    }

    return ffmpeg_run(args, cont);
}
