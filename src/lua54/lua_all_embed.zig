// Slim variant of lua_all.zig for embedding into arcan userspace binaries
// (arcan-net, afsrv_terminal, arcan compositor). Excludes the seL4 /
// boot-environment specific modules (lrepl, lunix, serialize, visitor, llock,
// lnotice, ltests, and the luaencode*/luaparse*/luapush*/luaformat*/luaprintstack/
// luacallwithtrace helpers that depend on them). Excludes lvm.zig because
// lvm_execute.zig provides the interpreter loop (luaV_execute).
pub const lapi = @import("lapi.zig");
pub const lauxlib = @import("lauxlib.zig");
pub const lbaselib = @import("lbaselib.zig");
pub const lcode = @import("lcode.zig");
pub const lcorolib = @import("lcorolib.zig");
pub const ldblib = @import("ldblib.zig");
pub const ldebug = @import("ldebug.zig");
pub const ldo = @import("ldo.zig");
pub const ldump = @import("ldump.zig");
pub const lfunc = @import("lfunc.zig");
pub const lgc = @import("lgc.zig");
pub const linit = @import("linit.zig");
pub const liolib = @import("liolib.zig");
pub const llex = @import("llex.zig");
pub const lmathlib = @import("lmathlib.zig");
pub const lmem = @import("lmem.zig");
pub const loadlib = @import("loadlib.zig");
pub const lobject = @import("lobject.zig");
pub const lopcodes = @import("lopcodes.zig");
pub const loslib = @import("loslib.zig");
pub const lparser = @import("lparser.zig");
pub const lstate = @import("lstate.zig");
pub const lstring = @import("lstring.zig");
pub const lstrlib = @import("lstrlib.zig");
pub const ltable = @import("ltable.zig");
pub const ltablib = @import("ltablib.zig");
pub const ltm = @import("ltm.zig");
pub const lundump = @import("lundump.zig");
pub const lutf8lib = @import("lutf8lib.zig");
pub const lvm = @import("lvm.zig");
pub const lvm_execute = @import("lvm_execute.zig");
pub const lzio = @import("lzio.zig");
pub const compat51 = @import("compat51.zig");

comptime {
    _ = lapi;
    _ = lauxlib;
    _ = lbaselib;
    _ = lcode;
    _ = lcorolib;
    _ = ldblib;
    _ = ldebug;
    _ = ldo;
    _ = ldump;
    _ = lfunc;
    _ = lgc;
    _ = linit;
    _ = liolib;
    _ = llex;
    _ = lmathlib;
    _ = lmem;
    _ = loadlib;
    _ = lobject;
    _ = lopcodes;
    _ = loslib;
    _ = lparser;
    _ = lstate;
    _ = lstring;
    _ = lstrlib;
    _ = ltable;
    _ = ltablib;
    _ = ltm;
    _ = lundump;
    _ = lutf8lib;
    _ = lvm;
    _ = lvm_execute;
    _ = lzio;
    _ = compat51;
}
