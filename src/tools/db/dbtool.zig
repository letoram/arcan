// Copyright 2014-2016, Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: http://arcan-fe.com
//
// Zig port of dbtool.c

const std = @import("std");
const libc = @import("posix");

// Dispatch struct replacing the prior `@cImport({ arcan_mem.h, arcan_db.h, ... })`
// block. Keeps the `c.X` spellings used below. libc routes to `posix_libc`;
// arcan_db.h entry points and types are declared inline — they are provided at
// link time by the Zig port in `src/engine/arcan_db.zig`.
//
// One behavioural change: the Zig-ported `arcan_strarr` uses a direct
// `.data` field instead of the C anonymous union. All access sites that
// previously spelled `res.unnamed_0.data` now read `res.data`.

const db = struct {
    pub const arcan_targetid = c_long;
    pub const arcan_configid = c_long;

    pub const arcan_strarr = extern struct {
        count: usize = 0,
        limit: usize = 0,
        // C had `union { char** data; void** cdata; }`. The Zig port
        // flattens the union to the `data` pointer (same storage).
        data: [*c][*c]u8 = null,
    };

    pub const arcan_dbtrans_id = extern union {
        cid: arcan_configid,
        tid: arcan_targetid,
        applname: [*c]const u8,
    };

    pub const arcan_dbh = opaque {};

    pub const BAD_TARGET: arcan_targetid = -1;
    pub const BAD_CONFIG: arcan_configid = -1;

    // enum DB_BFORMAT values (plain c_int on the wire).
    pub const BFRM_SHELL: c_int = 0x00;
    pub const BFRM_BIN: c_int = 0x01;
    pub const BFRM_LWA: c_int = 0x02;
    pub const BFRM_GAME: c_int = 0x03;
    pub const BFRM_EXTERN: c_int = 0x04;
    pub const enum_DB_BFORMAT = c_int;

    // enum DB_KVTARGET values.
    pub const DVT_APPL: c_int = 0;
    pub const DVT_TARGET: c_int = 1;
    pub const DVT_TARGET_ENV: c_int = 2;
    pub const DVT_TARGET_LIBV: c_int = 3;
    pub const DVT_CONFIG: c_int = 10;
    pub const DVT_CONFIG_ENV: c_int = 11;
    pub const enum_DB_KVTARGET = c_int;

    // Linked in from src/engine/arcan_db.zig.
    pub extern "c" fn arcan_db_open(fname: [*c]const u8, applname: [*c]const u8) ?*arcan_dbh;
    pub extern "c" fn arcan_db_close(ctx: ?*?*arcan_dbh) void;
    pub extern "c" fn arcan_db_dropappl(dbh: ?*arcan_dbh, appl: [*c]const u8) void;
    pub extern "c" fn arcan_db_droptarget(dbh: ?*arcan_dbh, id: arcan_targetid) bool;
    pub extern "c" fn arcan_db_dropconfig(dbh: ?*arcan_dbh, id: arcan_configid) bool;
    pub extern "c" fn arcan_db_targetid(
        dbh: ?*arcan_dbh,
        identifier: [*c]const u8,
        defid: ?*arcan_configid,
    ) arcan_targetid;
    pub extern "c" fn arcan_db_configid(
        dbh: ?*arcan_dbh,
        target: arcan_targetid,
        config: [*c]const u8,
    ) arcan_configid;
    pub extern "c" fn arcan_db_targettag(dbh: ?*arcan_dbh, tid: arcan_targetid) [*c]u8;
    pub extern "c" fn arcan_db_execname(dbh: ?*arcan_dbh, tid: arcan_targetid) [*c]u8;
    pub extern "c" fn arcan_db_addtarget(
        dbh: ?*arcan_dbh,
        identifier: [*c]const u8,
        group: [*c]const u8,
        exec: [*c]const u8,
        argv_arr: [*c]const [*c]const u8,
        sz: usize,
        bfmt: c_int,
    ) arcan_targetid;
    pub extern "c" fn arcan_db_addconfig(
        dbh: ?*arcan_dbh,
        id: arcan_targetid,
        identifier: [*c]const u8,
        argv_arr: [*c]const [*c]const u8,
        sz: usize,
    ) arcan_configid;
    pub extern "c" fn arcan_db_begin_transaction(
        dbh: ?*arcan_dbh,
        kvt: c_int,
        id: arcan_dbtrans_id,
    ) void;
    pub extern "c" fn arcan_db_add_kvpair(
        dbh: ?*arcan_dbh,
        key: [*c]const u8,
        val: [*c]const u8,
    ) void;
    pub extern "c" fn arcan_db_end_transaction(dbh: ?*arcan_dbh) void;
    pub extern "c" fn arcan_db_getkeys(
        dbh: ?*arcan_dbh,
        tgt: c_int,
        id: arcan_dbtrans_id,
    ) arcan_strarr;
    pub extern "c" fn arcan_db_applkeys(
        dbh: ?*arcan_dbh,
        applname: [*c]const u8,
        pattern: [*c]const u8,
    ) arcan_strarr;
    pub extern "c" fn arcan_db_target_tags(dbh: ?*arcan_dbh) arcan_strarr;
    pub extern "c" fn arcan_db_target_argv(dbh: ?*arcan_dbh, id: arcan_targetid) arcan_strarr;
    pub extern "c" fn arcan_db_config_argv(dbh: ?*arcan_dbh, id: arcan_configid) arcan_strarr;
    pub extern "c" fn arcan_db_targets(dbh: ?*arcan_dbh, tag: [*c]const u8) arcan_strarr;
    pub extern "c" fn arcan_db_configs(dbh: ?*arcan_dbh, tid: arcan_targetid) arcan_strarr;
    pub extern "c" fn arcan_db_list_appl(dbh: ?*arcan_dbh) arcan_strarr;
    pub extern "c" fn arcan_db_appl_kv(
        dbh: ?*arcan_dbh,
        applname: [*c]const u8,
        key: [*c]const u8,
        value: [*c]const u8,
    ) bool;
    pub extern "c" fn arcan_db_targetexec(
        dbh: ?*arcan_dbh,
        configid: arcan_configid,
        bfmt: *c_int,
        argv: *arcan_strarr,
        env: *arcan_strarr,
        libs: *arcan_strarr,
    ) [*c]u8;
    // arcan_mem.h — only freearr is used by the tool.
    pub extern "c" fn arcan_mem_freearr(arr: *arcan_strarr) void;
};

const c = struct {
    // libc
    pub const feof = libc.feof;
    pub const fgetc = libc.getc;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const isalnum = libc.isalnum;
    pub const printf = libc.printf;
    pub const realloc = libc.realloc;
    pub const strcmp = libc.strcmp;
    pub const strlen = libc.strlen;
    pub const strtok = libc.strtok;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
    pub const EXIT_SUCCESS = libc.EXIT_SUCCESS;

    // stderr / stdin are `extern "c" var` in libc. Aliasing an extern var
    // via `pub const = libc.stderr` triggers a comptime-value error; redeclare
    // the extern vars directly — the linker resolves both to the same libc symbol.
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdin: *libc.FILE;

    // arcan_db.h — types, enum values, entry points.
    pub const arcan_strarr = db.arcan_strarr;
    pub const arcan_dbh = db.arcan_dbh;
    pub const arcan_dbtrans_id = db.arcan_dbtrans_id;
    pub const enum_DB_BFORMAT = db.enum_DB_BFORMAT;
    pub const enum_DB_KVTARGET = db.enum_DB_KVTARGET;
    pub const BAD_TARGET = db.BAD_TARGET;
    pub const BAD_CONFIG = db.BAD_CONFIG;
    pub const BFRM_SHELL = db.BFRM_SHELL;
    pub const BFRM_BIN = db.BFRM_BIN;
    pub const BFRM_LWA = db.BFRM_LWA;
    pub const BFRM_GAME = db.BFRM_GAME;
    pub const BFRM_EXTERN = db.BFRM_EXTERN;
    pub const DVT_APPL = db.DVT_APPL;
    pub const DVT_TARGET = db.DVT_TARGET;
    pub const DVT_TARGET_ENV = db.DVT_TARGET_ENV;
    pub const DVT_TARGET_LIBV = db.DVT_TARGET_LIBV;
    pub const DVT_CONFIG = db.DVT_CONFIG;
    pub const DVT_CONFIG_ENV = db.DVT_CONFIG_ENV;

    pub const arcan_db_open = db.arcan_db_open;
    pub const arcan_db_close = db.arcan_db_close;
    pub const arcan_db_dropappl = db.arcan_db_dropappl;
    pub const arcan_db_droptarget = db.arcan_db_droptarget;
    pub const arcan_db_dropconfig = db.arcan_db_dropconfig;
    pub const arcan_db_targetid = db.arcan_db_targetid;
    pub const arcan_db_configid = db.arcan_db_configid;
    pub const arcan_db_targettag = db.arcan_db_targettag;
    pub const arcan_db_execname = db.arcan_db_execname;
    pub const arcan_db_addtarget = db.arcan_db_addtarget;
    pub const arcan_db_addconfig = db.arcan_db_addconfig;
    pub const arcan_db_begin_transaction = db.arcan_db_begin_transaction;
    pub const arcan_db_add_kvpair = db.arcan_db_add_kvpair;
    pub const arcan_db_end_transaction = db.arcan_db_end_transaction;
    pub const arcan_db_getkeys = db.arcan_db_getkeys;
    pub const arcan_db_applkeys = db.arcan_db_applkeys;
    pub const arcan_db_target_tags = db.arcan_db_target_tags;
    pub const arcan_db_target_argv = db.arcan_db_target_argv;
    pub const arcan_db_config_argv = db.arcan_db_config_argv;
    pub const arcan_db_targets = db.arcan_db_targets;
    pub const arcan_db_configs = db.arcan_db_configs;
    pub const arcan_db_list_appl = db.arcan_db_list_appl;
    pub const arcan_db_appl_kv = db.arcan_db_appl_kv;
    pub const arcan_db_targetexec = db.arcan_db_targetexec;
    pub const arcan_mem_freearr = db.arcan_mem_freearr;
};

// UTF-8 decoder (Bjoern Hoehrmann, MIT license)
// Reimplemented in Zig since the C version is static inline in utf8.c
const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

const utf8d = [_]u8{
    // 00..1f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 20..3f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 40..5f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 60..7f
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // 80..9f
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    // a0..bf
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    // c0..df
    8, 8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    // e0..ef
    0xa, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x3, 0x4, 0x3, 0x3,
    // f0..ff
    0xb, 0x6, 0x6, 0x6, 0x5, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
    // s0..s0
    0x0, 0x1, 0x2, 0x3, 0x5, 0x8, 0x7, 0x1, 0x1, 0x1, 0x4, 0x6, 0x1, 0x1, 0x1, 0x1,
    // s1..s2
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1,
    // s3..s4
    1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1,
    // s5..s6
    1, 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1,
    // s7..s8
    1, 3, 1, 1, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

fn utf8_decode(state: *u32, codep: *u32, byte: u32) u32 {
    const char_type: u32 = utf8d[@as(usize, @intCast(byte))];

    codep.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3f) | (codep.* << 6)
    else
        (@as(u32, 0xff) >> @intCast(char_type)) & byte;

    state.* = utf8d[@as(usize, @intCast(256 + state.* * 16 + char_type))];
    return state.*;
}

// From warning.zig / dbpath.zig (compiled separately)
extern "c" fn arcan_warning(msg: [*c]const u8, ...) void;
extern "c" fn platform_dbstore_path() [*c]u8;

fn usage() void {
    _ = c.printf(
        \\usage: arcan_db [-d dbfile] command args
        \\
        \\Available data creation / manipulation commands:
        \\  add_target       name (-tag) bfrm executable argv
        \\  add_target_kv    target key value
        \\  add_target_env   target key value
        \\  add_target_lib   target libstr
        \\  add_config       target argv
        \\  add_config_kv    target config key val
        \\  add_config_env   target config key val
        \\  add_appl_kv      appl key value
        \\  drop_appl_key    appl
        \\  drop_config      target config
        \\  drop_all_configs target
        \\  drop_target      name
        \\  drop_appl        name
        \\
        \\Available data extraction commands:
        \\  list_targets
        \\  list_tags
        \\  list_appls
        \\  show_target      name
        \\  show_config      targetname configname
        \\  show_appl        applname
        \\  show_exec        targetname configname
        \\Accepted keys are restricted to the set [a-Z0-9_+=/]
        \\
        \\alternative (scripted) usage: arcan_db dbfile -
        \\above commands are supplied using STDIN, tab as arg separator, linefeed
        \\as command submit. Close stdin to terminate execution.
        \\
    );
}

fn validate_key(key: [*c]const u8) bool {
    var k = key;
    while (k[0] != 0) {
        if (c.isalnum(@as(c_int, k[0])) == 0 and k[0] != '_' and k[0] != '+' and k[0] != '/' and k[0] != '=')
            return false;
        k += 1;
    }
    return true;
}

fn valid_str(msg: [*c]const u8) bool {
    var state: u32 = 0;
    var codepoint: u32 = 0;
    var len: usize = 0;
    while (msg[len] != 0) {
        if (UTF8_REJECT == utf8_decode(&state, &codepoint, @as(u32, msg[len])))
            return false;
        len += 1;
    }
    return state == UTF8_ACCEPT;
}

fn add_target(dst: *c.arcan_dbh, argc_raw: c_int, argv: [*c][*c]u8) c_int {
    const argc: usize = @intCast(argc_raw);

    if (argc < 3) {
        _ = c.printf("add_target(name (-tag) bfmt executable argv) unexpected number of arguments, (%d) vs 3+.\n\t accepted bfmts: BIN, LWA, GAME, SHELL, EXTERN\n", argc_raw);
        return c.EXIT_FAILURE;
    }

    var fi: usize = 1;
    var tag: [*c]const u8 = "default";
    if (argv[1][0] == '-') {
        tag = argv[1] + 1;
        fi += 1;
    }

    const bfmt_str = argv[fi];
    const bfmt: c.enum_DB_BFORMAT = if (c.strcmp(bfmt_str, "BIN") == 0)
        c.BFRM_BIN
    else if (c.strcmp(bfmt_str, "LWA") == 0)
        c.BFRM_LWA
    else if (c.strcmp(bfmt_str, "GAME") == 0)
        c.BFRM_GAME
    else if (c.strcmp(bfmt_str, "SHELL") == 0)
        c.BFRM_SHELL
    else if (c.strcmp(bfmt_str, "EXTERNAL") == 0)
        c.BFRM_EXTERN
    else {
        _ = c.printf("add_target(name (-tag) *bfrm* executable argv\nunknown bfrm, %s - accepted (BIN, LWA, GAME, SHELL, EXTERNAL).\n", bfmt_str);
        return c.EXIT_FAILURE;
    };

    if (!valid_str(argv[0])) {
        _ = c.printf("add_target(name), invalid/incomplete UTF8 sequence in name\n");
        return c.EXIT_FAILURE;
    }

    const tid = c.arcan_db_addtarget(
        dst,
        argv[0],
        tag,
        argv[fi + 1],
        @ptrCast(&argv[fi + 2]),
        @intCast(argc - fi - 2),
        bfmt,
    );

    if (tid == c.BAD_TARGET) {
        _ = c.printf("couldn't add target (%s)\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    _ = c.arcan_db_addconfig(dst, tid, "default", null, 0);

    return c.EXIT_SUCCESS;
}

fn drop_appl(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 1) {
        _ = c.printf("drop_appl(appl) unexpected number of arguments (%d vs 1)\n", argc);
        return c.EXIT_FAILURE;
    }

    c.arcan_db_dropappl(dst, argv[0]);
    return c.EXIT_SUCCESS;
}

fn drop_target(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 1) {
        _ = c.printf("drop_target(target) unexpected number of arguments (%d vs 1)\n", argc);
        return c.EXIT_FAILURE;
    }

    const tid = c.arcan_db_targetid(dst, argv[0], null);

    if (tid == c.BAD_TARGET) {
        _ = c.printf("couldn't find a matching target for (%s).\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    return if (c.arcan_db_droptarget(dst, tid)) c.EXIT_SUCCESS else c.EXIT_FAILURE;
}

fn drop_config(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        _ = c.printf("drop_config(target, config) unexpected number of arguments (%d vs 2)\n", argc);
        return c.EXIT_FAILURE;
    }

    const tid = c.arcan_db_targetid(dst, argv[0], null);

    if (tid == c.BAD_TARGET) {
        _ = c.printf("couldn't find a matching target for (%s).\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    const cid = c.arcan_db_configid(dst, tid, argv[1]);
    if (cid == c.BAD_CONFIG) {
        _ = c.printf("couldn't find a matching config for (%s).\n", argv[1]);
    }

    return if (c.arcan_db_dropconfig(dst, cid)) c.EXIT_SUCCESS else c.EXIT_FAILURE;
}

fn drop_all_config(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 1) {
        _ = c.printf("drop_all_configs(target), invalid number of arguments (%d vs 1).\n", argc);
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.tid = c.arcan_db_targetid(dst, argv[0], null);
    var res = c.arcan_db_configs(dst, id.tid);
    if (res.data == null) {
        _ = c.printf("drop_all_configs(target), no valid list returned.\n");
        return c.EXIT_FAILURE;
    }

    var curr = res.data;
    while (curr[0] != null) {
        const cid = c.arcan_db_configid(dst, id.tid, curr[0]);
        if (cid != c.BAD_CONFIG)
            _ = c.arcan_db_dropconfig(dst, cid);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);
    return c.EXIT_SUCCESS;
}

fn set_kv(
    dst: *c.arcan_dbh,
    tgt: c.enum_DB_KVTARGET,
    id: c.arcan_dbtrans_id,
    key: [*c]u8,
    val: [*c]u8,
) c_int {
    c.arcan_db_begin_transaction(dst, tgt, id);
    c.arcan_db_add_kvpair(dst, key, if (c.strlen(val) > 0) val else null);
    c.arcan_db_end_transaction(dst);

    return c.EXIT_SUCCESS;
}

fn add_appl_kv(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 3) {
        _ = c.printf("add_appl_kv(appl, key, val) invalid number of arguments, %d vs 3\n", argc);
        return c.EXIT_FAILURE;
    }

    if (c.strlen(argv[0]) == 0) {
        _ = c.printf("invalid appl specified (0-length) \n");
        return c.EXIT_FAILURE;
    }

    if (!validate_key(argv[1])) {
        _ = c.printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
        return c.EXIT_FAILURE;
    }

    return if (c.arcan_db_appl_kv(
        dst,
        argv[0],
        argv[1],
        if (c.strlen(argv[2]) > 0) argv[2] else null,
    ))
        c.EXIT_SUCCESS
    else
        c.EXIT_FAILURE;
}

fn drop_appl_key(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        _ = c.printf("drop_appl_key(appl, key) invalid number of arguments, %d vs 2\n", argc);
        return c.EXIT_FAILURE;
    }

    if (c.strlen(argv[0]) == 0) {
        _ = c.printf("invalid appl specified (0-length) \n");
        return c.EXIT_FAILURE;
    }

    if (!validate_key(argv[1])) {
        _ = c.printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
        return c.EXIT_FAILURE;
    }

    return if (c.arcan_db_appl_kv(dst, argv[0], argv[1], null))
        c.EXIT_SUCCESS
    else
        c.EXIT_FAILURE;
}

fn add_target_kv(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 3) {
        _ = c.printf("add_target_kv(target, key, val) invalid number of arguments, %d vs 3\n", argc);
        return c.EXIT_FAILURE;
    }

    if (!validate_key(argv[1])) {
        _ = c.printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.tid = c.arcan_db_targetid(dst, argv[0], null);

    if (id.tid == c.BAD_TARGET) {
        _ = c.printf("unknown target (%s) for add_target_kv\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    return set_kv(dst, c.DVT_TARGET, id, argv[1], argv[2]);
}

fn add_target_env(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 3) {
        _ = c.printf("add_target_env(target, key, val) invalid number of arguments, %d vs 3", argc);
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.tid = c.arcan_db_targetid(dst, argv[0], null);

    if (id.tid == c.BAD_TARGET) {
        _ = c.printf("unknown target (%s) for add_target_env\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    return set_kv(dst, c.DVT_TARGET_ENV, id, argv[1], argv[2]);
}

fn add_target_libv(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        _ = c.printf("add_target_lib (target, soname) invalid number of arguments, %d vs 2", argc);
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.tid = c.arcan_db_targetid(dst, argv[0], null);

    if (id.tid == c.BAD_TARGET) {
        _ = c.printf("unknown target (%s) for add_target_libv\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    return set_kv(dst, c.DVT_TARGET_LIBV, id, argv[1], @constCast(""));
}

fn add_config(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc < 2) {
        _ = c.printf("add_config(target, identifier, argv) invalid number of arguments (%d vs at least 2).\n", argc);
        return c.EXIT_FAILURE;
    }

    const tid = c.arcan_db_targetid(dst, argv[0], null);

    if (tid == c.BAD_TARGET) {
        _ = c.printf("couldn't find a matching target for (%s).\n", argv[0]);
        return c.EXIT_FAILURE;
    }

    if (!valid_str(argv[1])) {
        _ = c.printf("add_config(identifier), invalid/incomplete UTF8 sequence\n");
        return c.EXIT_FAILURE;
    }

    _ = c.arcan_db_addconfig(dst, tid, argv[1], @ptrCast(&argv[2]), @as(usize, @intCast(argc - 2)));

    return c.EXIT_SUCCESS;
}

fn add_config_kv(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 4) {
        _ = c.printf("add_config_kv(target, config, key, value) invalid number of arguments (%d vs 4).\n", argc);
        return c.EXIT_FAILURE;
    }

    if (!validate_key(argv[2])) {
        _ = c.printf("invalid key specified (restricted to [a-Z0-9_/+=])\n");
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.cid = c.arcan_db_configid(dst, c.arcan_db_targetid(dst, argv[0], null), argv[1]);

    return set_kv(dst, c.DVT_CONFIG, id, argv[2], argv[3]);
}

fn add_config_env(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 4) {
        _ = c.printf("add_config_env(target config key value) invalid numberof arguments (%d vs 4).\n", argc);
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.cid = c.arcan_db_configid(dst, c.arcan_db_targetid(dst, argv[0], null), argv[1]);

    return set_kv(dst, c.DVT_CONFIG_ENV, id, argv[2], argv[3]);
}

fn show_target(dbh: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 1) {
        _ = c.printf("show_target(target), invalid number of arguments (%d vs 1).\n", argc);
        return c.EXIT_FAILURE;
    }

    var id: c.arcan_dbtrans_id = undefined;
    id.tid = c.arcan_db_targetid(dbh, argv[0], null);

    var res = c.arcan_db_configs(dbh, id.tid);

    if (res.data == null) {
        _ = c.printf("show_target(), no valid target data returned.\n");
        return c.EXIT_FAILURE;
    }

    const exec = c.arcan_db_execname(dbh, id.tid);
    const tag = c.arcan_db_targettag(dbh, id.tid);

    _ = c.printf(
        "target (%s), tag: (%s)\nexecutable:%s\nconfigurations:\n",
        argv[0],
        tag,
        if (exec != null) exec else @as([*c]const u8, "(none)"),
    );
    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("\t%s\n", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    _ = c.printf("\narguments: \n\t");
    res = c.arcan_db_target_argv(dbh, id.tid);
    curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%s ", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    _ = c.printf("\n\nkvpairs:\n");
    res = c.arcan_db_getkeys(dbh, c.DVT_TARGET, id);
    curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("\t%s\n", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);
    _ = c.printf("\n");

    c.free(exec);
    return c.EXIT_SUCCESS;
}

fn show_config(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        _ = c.printf("show_config(target, config) invalid number of arguments (%d vs 2).\n", argc);
        return c.EXIT_FAILURE;
    }

    var tgt: c.arcan_dbtrans_id = undefined;
    var cfg: c.arcan_dbtrans_id = undefined;
    tgt.tid = c.arcan_db_targetid(dst, argv[0], null);
    cfg.cid = c.arcan_db_configid(dst, tgt.tid, argv[1]);

    var res = c.arcan_db_config_argv(dst, cfg.cid);

    if (res.data == null) {
        _ = c.printf("show_config(), no valid config data returned.\n");
        return c.EXIT_FAILURE;
    }

    _ = c.printf("target (%s) config (%s)\narguments:\n", argv[0], argv[1]);

    var count: c_int = 1;
    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%d\t%s \n", count, curr[0]);
        count += 1;
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    _ = c.printf("\n\nkvpairs:\n");
    res = c.arcan_db_getkeys(dst, c.DVT_CONFIG, cfg);
    curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("\t%s\n", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);
    _ = c.printf("\n");

    return c.EXIT_SUCCESS;
}

fn show_exec(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    var env: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);
    var outargv: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);
    var libs: c.arcan_strarr = std.mem.zeroes(c.arcan_strarr);

    if (argc != 2) {
        _ = c.printf("show_exec(target, config) invalid number of arguments (%d vs 2).\n", argc);
        return c.EXIT_FAILURE;
    }

    const cfgid = c.arcan_db_configid(dst, c.arcan_db_targetid(dst, argv[0], null), argv[1]);

    var bfmt: c.enum_DB_BFORMAT = undefined;
    const execstr = c.arcan_db_targetexec(dst, cfgid, &bfmt, &outargv, &env, &libs);
    if (execstr == null) {
        _ = c.printf("show_exec() couldn't generate execution string\n");
        return c.EXIT_FAILURE;
    }

    if (outargv.data != null) {
        _ = c.printf("ARGV:\n");
        var curr = outargv.data;
        while (curr[0] != null) {
            _ = c.printf("\t%s\n", curr[0]);
            curr += 1;
        }
    } else {
        _ = c.printf("ARGV: empty\n");
    }

    if (env.data != null) {
        _ = c.printf("ENV:\n");
        var curr = env.data;
        while (curr[0] != null) {
            _ = c.printf("\t%s\n", curr[0]);
            curr += 1;
        }
    } else {
        _ = c.printf("ENV: empty\n");
    }

    return c.EXIT_SUCCESS;
}

fn list_targets(dst: *c.arcan_dbh, _: c_int, _: [*c][*c]u8) c_int {
    var res = c.arcan_db_targets(dst, null);
    if (res.data == null) {
        _ = c.printf("list_targets(), no valid list of targets returned.\n");
        return c.EXIT_FAILURE;
    }

    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%s\n", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    return c.EXIT_SUCCESS;
}

fn list_tags(dst: *c.arcan_dbh, _: c_int, _: [*c][*c]u8) c_int {
    var res = c.arcan_db_target_tags(dst);
    if (res.data == null) {
        _ = c.printf("list_tags(), no valid list of tags returned.\n");
        return c.EXIT_FAILURE;
    }

    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%s\n", curr[0]);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    return c.EXIT_SUCCESS;
}

fn list_appls(dst: *c.arcan_dbh, _: c_int, _: [*c][*c]u8) c_int {
    var res = c.arcan_db_list_appl(dst);
    if (res.data == null) {
        _ = c.printf("list_tags(), no valid list of tags returned.\n");
        return c.EXIT_FAILURE;
    }

    // always prefixed appl_
    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%s\n", curr[0] + 5);
        curr += 1;
    }
    c.arcan_mem_freearr(&res);

    return c.EXIT_SUCCESS;
}

fn show_appl(dst: *c.arcan_dbh, argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc <= 0) {
        _ = c.printf("show_appl(), no appl name specified.\n");
        return c.EXIT_FAILURE;
    }

    const ptn: [*c]const u8 = if (argc > 1) argv[1] else "%";

    var res = c.arcan_db_applkeys(dst, argv[0], ptn);
    if (res.data == null) {
        _ = c.printf("show_appl(), no valid list returned");
        return c.EXIT_FAILURE;
    }

    var curr = res.data;
    while (curr[0] != null) {
        _ = c.printf("%s\n", curr[0]);
        curr += 1;
    }

    c.arcan_mem_freearr(&res);
    return c.EXIT_SUCCESS;
}

const DispatchEntry = struct {
    key: [*c]const u8,
    fun: *const fn (*c.arcan_dbh, c_int, [*c][*c]u8) c_int,
};

const dispatch_table = [_]DispatchEntry{
    .{ .key = "add_target", .fun = add_target },
    .{ .key = "drop_target", .fun = drop_target },
    .{ .key = "show_appl", .fun = show_appl },
    .{ .key = "show_config", .fun = show_config },
    .{ .key = "show_target", .fun = show_target },
    .{ .key = "list_targets", .fun = list_targets },
    .{ .key = "list_tags", .fun = list_tags },
    .{ .key = "list_appls", .fun = list_appls },
    .{ .key = "add_config_env", .fun = add_config_env },
    .{ .key = "add_appl_kv", .fun = add_appl_kv },
    .{ .key = "drop_appl_key", .fun = drop_appl_key },
    .{ .key = "add_target_kv", .fun = add_target_kv },
    .{ .key = "add_config_kv", .fun = add_config_kv },
    .{ .key = "add_config", .fun = add_config },
    .{ .key = "drop_config", .fun = drop_config },
    .{ .key = "drop_appl", .fun = drop_appl },
    .{ .key = "drop_all_configs", .fun = drop_all_config },
    .{ .key = "add_target_env", .fun = add_target_env },
    .{ .key = "add_target_lib", .fun = add_target_libv },
    .{ .key = "show_exec", .fun = show_exec },
};

fn grow(inp: ?[*]u8, outsz: *usize) ?[*]u8 {
    outsz.* += 64;
    const res: ?[*]u8 = @ptrCast(c.realloc(inp, outsz.*));
    if (res == null) {
        c.free(inp);
        outsz.* = 0;
        return null;
    }
    return res;
}

fn process_line(in: [*c]u8, dbh: *c.arcan_dbh) void {
    var argv_buf: [64][*c]u8 = undefined;
    for (&argv_buf) |*slot| {
        slot.* = null;
    }
    var argc: usize = 0;

    var work: [*c]u8 = c.strtok(in, "\t");
    while (work != null and argc < 63) {
        argv_buf[argc] = work;
        argc += 1;
        work = c.strtok(null, "\t");
    }

    if (argc == 0) return;

    for (&dispatch_table) |*entry| {
        if (c.strcmp(entry.key, argv_buf[0]) == 0) {
            const argc_minus_1: c_int = @intCast(argc - 1);
            if (c.EXIT_SUCCESS == entry.fun(dbh, argc_minus_1, @ptrCast(&argv_buf[1]))) {
                _ = c.fprintf(c.stderr, "OK\n");
            } else {
                _ = c.fprintf(c.stderr, "FAIL\n");
            }
        }
    }
}

export fn main(argc_raw: c_int, argv: [*c][*c]u8) callconv(.c) c_int {
    const argc: usize = @intCast(argc_raw);

    if (argc < 2) {
        usage();
        return c.EXIT_FAILURE;
    }

    var dbfile: [*c]u8 = null;
    var startind: usize = 1;

    if (c.strcmp(argv[1], "-d") == 0) {
        if (argc < 3) {
            arcan_warning("got -d but missing database file argument\n");
            usage();
            return c.EXIT_FAILURE;
        }

        for (&dispatch_table) |*entry| {
            if (c.strcmp(argv[2], entry.key) == 0) {
                arcan_warning("got command (%s) in database filename slot\n");
                usage();
                return c.EXIT_FAILURE;
            }
        }

        dbfile = argv[2];
        startind = 3;
        if (argc < 4) {
            usage();
            return c.EXIT_FAILURE;
        }
    } else {
        dbfile = platform_dbstore_path();
    }

    // early out on --help or -h
    {
        var i: usize = 1;
        while (i < argc) : (i += 1) {
            if (c.strcmp(argv[i], "-h") == 0 or c.strcmp(argv[i], "--help") == 0) {
                usage();
                return c.EXIT_SUCCESS;
            }
        }
    }

    var dbhandle = c.arcan_db_open(dbfile, "arcan");
    if (dbhandle == null) {
        arcan_warning("database (%s) could not be opened/created.\n", dbfile);
        return c.EXIT_FAILURE;
    }

    if (c.strcmp(argv[startind], "-") == 0) {
        var inbuf: ?[*]u8 = null;
        var bufsz: usize = 0;
        var bufofs: usize = 0;
        inbuf = grow(inbuf, &bufsz);

        while (c.feof(c.stdin) == 0) {
            const ch = c.fgetc(c.stdin);

            if (bufofs == bufsz - 1) {
                inbuf = grow(inbuf, &bufsz);
                if (inbuf == null) {
                    _ = c.fprintf(c.stderr, "couldn't grow input buffer\n");
                    return c.EXIT_FAILURE;
                }
            }

            if (ch == -1)
                continue;

            if (ch == '\n' or ch == 0) {
                inbuf.?[bufofs] = 0;
                process_line(inbuf.?, dbhandle.?);
                bufofs = 0;
            } else {
                inbuf.?[bufofs] = @intCast(ch);
                bufofs += 1;
            }
        }

        if (bufofs == bufsz) {
            inbuf = grow(inbuf, &bufsz);
            if (inbuf == null)
                return c.EXIT_FAILURE;
        }

        if (bufofs > 0) {
            inbuf.?[bufofs] = 0;
            process_line(inbuf.?, dbhandle.?);
        }
        c.free(inbuf);

        return c.EXIT_SUCCESS;
    }

    for (&dispatch_table) |*entry| {
        if (c.strcmp(entry.key, argv[startind]) == 0) {
            const argc_rest: c_int = @intCast(argc_raw - @as(c_int, @intCast(startind)) - 1);
            const rc = entry.fun(dbhandle.?, argc_rest, @ptrCast(&argv[startind + 1]));
            c.arcan_db_close(@ptrCast(&dbhandle));
            return rc;
        }
    }

    usage();
    return c.EXIT_FAILURE;
}
