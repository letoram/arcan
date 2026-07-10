// Zig port of decode.c — Decode reference frameserver archetype dispatcher
// Copyright 2014-2020, Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
//
// The decode frameserver takes some form of compressed / packed input
// and transforms it into a raw format that shmif can use or process.
const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const arcan_shmif_cont = shmif.arcan_shmif_cont;
    pub const arcan_event = shmif.arcan_event;
    pub const arg_arr = shmif.arg_arr;
    pub const arg_lookup = shmif.arg_lookup;
    pub const arcan_shmif_defer_register = shmif.arcan_shmif_defer_register;
    pub const arcan_shmif_drop = shmif.arcan_shmif_drop;
    pub const arcan_shmif_dupfd = shmif.arcan_shmif_dupfd;
    pub const arcan_shmif_enqueue = shmif.arcan_shmif_enqueue;
    pub const arcan_shmif_last_words = shmif.arcan_shmif_last_words;
    pub const arcan_shmif_wait = shmif.arcan_shmif_wait;
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_MESSAGE = shmif.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_REGISTER = shmif.EVENT_EXTERNAL_REGISTER;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const EXIT_FAILURE = shmif.EXIT_FAILURE;
    pub const EXIT_SUCCESS = shmif.EXIT_SUCCESS;
    pub const SEGID_MEDIA = shmif.SEGID_MEDIA;
    pub const SEGID_TUI = shmif.SEGID_TUI;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_EXIT = shmif.TARGET_COMMAND_EXIT;
    pub const strcasecmp = shmif.strcasecmp;
    pub const strdup = shmif.strdup;
    pub const snprintf = shmif.snprintf;
    pub const fprintf = libc.fprintf;
};

// stdout is an extern var — can't route through the dispatch struct as
// `pub const` since pub const needs a comptime value. Provide a module-
// scoped inline accessor instead so `c.fprintf(stdout(), …)` works.
inline fn stdout() *libc.FILE {
    return libc.stdout;
}

// Decode sub-module entry points (from decode.h / other Zig files)
extern "c" fn decode_av(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) c_int;
extern "c" fn decode_3d(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) c_int;
extern "c" fn decode_text(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) c_int;
// decode_image: stub — original C implementation (decode_img.c) deleted in Zig migration
export fn decode_image(_: ?*c.arcan_shmif_cont, _: ?*c.arg_arr) callconv(.c) c_int { return -1; }

export fn show_use(cont: ?*c.arcan_shmif_cont, msg: [*c]const u8) callconv(.c) c_int {
    if (msg != null) {
        _ = c.fprintf(stdout(), "Couldn't start decode, reason: %s\n\n", msg);
    }

    _ = c.fprintf(stdout(), "%s",
        "Environment variables: \nARCAN_CONNPATH=path_to_server\n" ++
            "ARCAN_ARG=packed_args (key1=value:key2:key3=value)\n\n" ++
            "General arguments:\n" ++
            "   key   \t   value   \t   description\n" ++
            "---------\t-----------\t-----------------\n" ++
            " protocol\t 3d        \t set '3d object' mode\n" ++
            " protocol\t text      \t set 'text' mode\n" ++
            " protocol\t image     \t set 'image' mode\n" ++
            " protocol\t list      \t send list of supported protocols as messages\n" ++
            "---------\t-----------\t----------------\n" ++
            "\n" ++
            " Accepted image arguments:\n" ++
            "  key    \t   value   \t   description\n" ++
            "---------\t-----------\t-----------------\n" ++
            " file    \t path      \t one-shot open file >path< for input \n" ++
            " fdin    \t fd        \t one-shot use inherited >fd< for input \n" ++
            "---------\t-----------\t-----------------\n" ++
            "\n" ++
            " Accepted text arguments:\n" ++
            "   key   \t   value   \t   description\n" ++
            "---------\t-----------\t-----------------\n" ++
            " file    \t path      \t try to open file path for playback \n" ++
            " view    \t viewmode  \t (ascii, >utf8<, hex) set default view\n" ++
            "\n" ++
            "Accepted media arguments:\n" ++
            "   key   \t   value   \t   description\n" ++
            "---------\t-----------\t-----------------\n" ++
            " file    \t path      \t try to open file path for playback source\n" ++
            " fd      \t file-no   \t use inherited descriptor for playback source\n" ++
            " pos     \t 0..1      \t set the relative starting position \n" ++
            " noaudio \t           \t disable the audio output entirely \n" ++
            " stream  \t url       \t attempt to open URL for streaming input \n" ++
            " capture \t           \t try to open a capture device\n" ++
            " device  \t number    \t find capture device with specific index\n" ++
            " fps     \t rate      \t force a specific framerate\n" ++
            " width   \t outw      \t scale output to a specific width\n" ++
            " height  \t outh      \t scale output to a specific height\n" ++
            " loop    \t           \t reset playback upon completion\n" ++
            "---------\t-----------\t----------------\n",
    );

    if (cont != null) {
        if (msg != null)
            c.arcan_shmif_last_words(cont, msg);

        c.arcan_shmif_drop(cont);
    }

    return c.EXIT_FAILURE;
}

export fn wait_for_file(
    cont: ?*c.arcan_shmif_cont,
    extstr: [*c]const u8,
    idstr: ?*[*c]u8,
) callconv(.c) c_int {
    var res: c_int = -1;
    var ev: c.arcan_event = c.arcan_event.zeroes();

    if (idstr != null)
        idstr.?.* = null;

    // Build BCHUNKSTATE event to request a file
    var bchunk: c.arcan_event = c.arcan_event.zeroes();
    bchunk.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    bchunk.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    bchunk.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.hint = 1;
    bchunk.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input = 1;

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&bchunk.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions)),
        @sizeOf(@TypeOf(bchunk.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions)),
        "%s",
        extstr,
    );
    _ = c.arcan_shmif_enqueue(cont, &bchunk);

    while (c.arcan_shmif_wait(cont, &ev) != 0) {
        if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET)
            continue;

        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_EXIT)
            return 0;

        if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) {
            // dup as the next call into shmif will close
            res = c.arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
            if (idstr != null)
                idstr.?.* = c.strdup(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
            break;
        }
    }

    return res;
}

export fn afsrv_decode(cont: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    var @"type": [*c]const u8 = undefined;
    if (!c.arg_lookup(args, "protocol", 0, &@"type")) {
        // previously decode used 'proto' and not 'protocol',
        // as to not break applications out there, silently support the short form
        if (!c.arg_lookup(args, "proto", 0, &@"type")) {
            @"type" = "media";
        }
    }

    if (c.arg_lookup(args, "help", 0, null)) {
        return show_use(cont, null);
    }

    if (c.strcasecmp(@"type", "list") == 0) {
        const pstr = "media:3d:text:image";
        var msg_ev: c.arcan_event = c.arcan_event.zeroes();
        msg_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;
        msg_ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&msg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            @sizeOf(@TypeOf(msg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            "%s",
            pstr,
        );
        _ = c.arcan_shmif_enqueue(cont, &msg_ev);
        var drain_ev: c.arcan_event = c.arcan_event.zeroes();
        while (c.arcan_shmif_wait(cont, &drain_ev) != 0) {}
        c.arcan_shmif_drop(cont);
        return c.EXIT_SUCCESS;
    }

    var segkind: c_int = c.SEGID_MEDIA;
    if (c.strcasecmp(@"type", "text") == 0) {
        segkind = c.SEGID_TUI;
    }

    // Send the deferred register - the sideeffect with this not happening on
    // acquire is that the _initial state isn't directly available so we need
    // to wait for activation manually.
    var reg_ev: c.arcan_event = c.arcan_event.zeroes();
    reg_ev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_REGISTER;
    reg_ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.kind = @intCast(segkind);
    _ = c.arcan_shmif_defer_register(cont, reg_ev);

    if (c.strcasecmp(@"type", "text") == 0)
        return decode_text(cont, args);

    if (c.strcasecmp(@"type", "3d") == 0)
        return decode_3d(cont, args);

    if (c.strcasecmp(@"type", "image") == 0)
        return decode_image(cont, args);

    var errbuf: [64]u8 = undefined;
    const errmsg = std.fmt.bufPrintZ(&errbuf, "unknown type argument: {s}", .{
        std.mem.span(@as([*:0]const u8, @ptrCast(@"type"))),
    }) catch "unknown type argument";
    return show_use(cont, errmsg.ptr);
}
