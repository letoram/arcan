// lvm_execute.zig — Pure Zig implementation of luaV_execute (Lua 5.4)
//
// This file provides the single exported symbol `luaV_execute` which is the
// main interpreter loop. It was translated from lvm.c lines 1160-1915.
//
// All types are declared locally (matching lvm.zig's layout) and all Lua
// internal functions are declared as extern fn.

const std = @import("std");

/// Set from Lua via uart_trace(1/0) to trace VM opcodes to UART
pub var vm_trace: bool = false;

extern fn earlyPutc(c: u8) void;

fn traceOpcode(op: u7) void {
    const hex = "0123456789ABCDEF";
    earlyPutc(hex[op >> 4]);
    earlyPutc(hex[op & 0xF]);
    earlyPutc(' ');
}

// =========================================================================
// Fundamental type aliases (matching lvm.zig / C Lua)
// =========================================================================

const lu_byte = u8;
const ls_byte = i8;
const l_uint32 = c_uint;
const sig_atomic_t = c_int;
const ptrdiff_t = c_long;
const lua_Integer = c_longlong;
const lua_Unsigned = c_ulonglong;
const lua_Number = f64;
const lua_CFunction = ?*const fn ([*c]lua_State) callconv(.c) c_int;
const lua_KContext = isize;
const lua_KFunction = ?*const fn ([*c]lua_State, c_int, lua_KContext) callconv(.c) c_int;
const lua_Hook = ?*const fn ([*c]lua_State, [*c]lua_Debug) callconv(.c) void;
const lua_Alloc = ?*const fn (?*anyopaque, ?*anyopaque, usize, usize) callconv(.c) ?*anyopaque;
const lua_WarnFunction = ?*const fn (?*anyopaque, [*c]const u8, c_int) callconv(.c) void;
const lua_Reader = ?*const fn ([*c]lua_State, ?*anyopaque, [*c]usize) callconv(.c) [*c]const u8;
const l_mem = ptrdiff_t;
const lu_mem = usize;

const Instruction = l_uint32;
const OpCode = c_uint;
const TMS = c_uint;
const F2Imod = c_uint;

// =========================================================================
// Struct definitions (matching lvm.zig layout exactly)
// =========================================================================
const struct_GCObject = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
};
const GCObject = struct_GCObject;

const union_Value = extern union {
    gc: [*c]struct_GCObject,
    p: ?*anyopaque,
    f: lua_CFunction,
    i: lua_Integer,
    n: lua_Number,
    ub: lu_byte,
};
const Value = union_Value;

const struct_TValue = extern struct {
    value_: Value = std.mem.zeroes(Value),
    tt_: lu_byte = 0,
};
const TValue = struct_TValue;

const struct_NodeKey_6 = extern struct {
    value_: Value = std.mem.zeroes(Value),
    tt_: lu_byte = 0,
    key_tt: lu_byte = 0,
    next: c_int = 0,
    key_val: Value = std.mem.zeroes(Value),
};
const union_Node = extern union {
    u: struct_NodeKey_6,
    i_val: TValue,
};
const Node = union_Node;

const struct_Table = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    flags: lu_byte = 0,
    lsizenode: lu_byte = 0,
    alimit: c_uint = 0,
    array: [*c]TValue = null,
    node: [*c]Node = null,
    lastfree: [*c]Node = null,
    metatable: [*c]struct_Table = null,
    gclist: [*c]GCObject = null,
};
const Table = struct_Table;

const struct_unnamed_12 = extern struct {
    value_: Value = std.mem.zeroes(Value),
    tt_: lu_byte = std.mem.zeroes(lu_byte),
    delta: c_ushort = std.mem.zeroes(c_ushort),
};
const union_StackValue = extern union {
    val: TValue,
    tbclist: struct_unnamed_12,
};
const StackValue = union_StackValue;
const StkId = [*c]StackValue;
const StkIdRel = extern union {
    p: StkId,
    offset: ptrdiff_t,
};

const union_unnamed_5 = extern union {
    lnglen: usize,
    hnext: [*c]struct_TString,
};
const struct_TString = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    extra: lu_byte = 0,
    shrlen: lu_byte = 0,
    hash: c_uint = 0,
    u: union_unnamed_5 = std.mem.zeroes(union_unnamed_5),
    contents: [1]u8 = std.mem.zeroes([1]u8),
};
const TString = struct_TString;

const struct_stringtable = extern struct {
    hash: [*c][*c]TString = null,
    nuse: c_int = 0,
    size: c_int = 0,
};

const struct_global_State = extern struct {
    frealloc: lua_Alloc = null,
    ud: ?*anyopaque = null,
    totalbytes: l_mem = 0,
    GCdebt: l_mem = 0,
    GCestimate: lu_mem = 0,
    lastatomic: lu_mem = 0,
    strt: struct_stringtable = std.mem.zeroes(struct_stringtable),
    l_registry: TValue = std.mem.zeroes(TValue),
    nilvalue: TValue = std.mem.zeroes(TValue),
    seed: c_uint = 0,
    currentwhite: lu_byte = 0,
    gcstate: lu_byte = 0,
    gckind: lu_byte = 0,
    gcstopem: lu_byte = 0,
    genminormul: lu_byte = 0,
    genmajormul: lu_byte = 0,
    gcstp: lu_byte = 0,
    gcemergency: lu_byte = 0,
    gcpause: lu_byte = 0,
    gcstepmul: lu_byte = 0,
    gcstepsize: lu_byte = 0,
    allgc: [*c]GCObject = null,
    sweepgc: [*c][*c]GCObject = null,
    finobj: [*c]GCObject = null,
    gray: [*c]GCObject = null,
    grayagain: [*c]GCObject = null,
    weak: [*c]GCObject = null,
    ephemeron: [*c]GCObject = null,
    allweak: [*c]GCObject = null,
    tobefnz: [*c]GCObject = null,
    fixedgc: [*c]GCObject = null,
    survival: [*c]GCObject = null,
    old1: [*c]GCObject = null,
    reallyold: [*c]GCObject = null,
    firstold1: [*c]GCObject = null,
    finobjsur: [*c]GCObject = null,
    finobjold1: [*c]GCObject = null,
    finobjrold: [*c]GCObject = null,
    twups: [*c]struct_lua_State = null,
    panic: lua_CFunction = null,
    mainthread: [*c]struct_lua_State = null,
    memerrmsg: [*c]TString = null,
    tmname: [25][*c]TString = std.mem.zeroes([25][*c]TString),
    mt: [9][*c]struct_Table = std.mem.zeroes([9][*c]struct_Table),
    strcache: [53][2][*c]TString = std.mem.zeroes([53][2][*c]TString),
    warnf: lua_WarnFunction = null,
    ud_warn: ?*anyopaque = null,
};
const global_State = struct_global_State;

const struct_lua_longjmp = opaque {};
const struct_lua_Debug = extern struct {
    event: c_int = 0,
    name: [*c]const u8 = null,
    namewhat: [*c]const u8 = null,
    what: [*c]const u8 = null,
    source: [*c]const u8 = null,
    srclen: usize = 0,
    currentline: c_int = 0,
    linedefined: c_int = 0,
    lastlinedefined: c_int = 0,
    nups: u8 = 0,
    nparams: u8 = 0,
    isvararg: u8 = 0,
    istailcall: u8 = 0,
    ftransfer: c_ushort = 0,
    ntransfer: c_ushort = 0,
    short_src: [60]u8 = std.mem.zeroes([60]u8),
    i_ci: [*c]struct_CallInfo = null,
};
const lua_Debug = struct_lua_Debug;

const struct_unnamed_3 = extern struct {
    savedpc: [*c]const Instruction = null,
    trap: sig_atomic_t = 0,
    nextraargs: c_int = 0,
};
const struct_unnamed_4 = extern struct {
    k: lua_KFunction = null,
    old_errfunc: ptrdiff_t = 0,
    ctx: lua_KContext = 0,
};
const union_unnamed_2 = extern union {
    l: struct_unnamed_3,
    c: struct_unnamed_4,
};
const struct_unnamed_11 = extern struct {
    ftransfer: c_ushort = 0,
    ntransfer: c_ushort = 0,
};
const union_unnamed_10 = extern union {
    funcidx: c_int,
    nyield: c_int,
    nres: c_int,
    transferinfo: struct_unnamed_11,
};
const struct_CallInfo = extern struct {
    func: StkIdRel = std.mem.zeroes(StkIdRel),
    top: StkIdRel = std.mem.zeroes(StkIdRel),
    previous: [*c]struct_CallInfo = null,
    next: [*c]struct_CallInfo = null,
    u: union_unnamed_2 = std.mem.zeroes(union_unnamed_2),
    u2: union_unnamed_10 = std.mem.zeroes(union_unnamed_10),
    nresults: c_short = 0,
    callstatus: c_ushort = 0,
};
const CallInfo = struct_CallInfo;

const struct_lua_State = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    status: lu_byte = 0,
    allowhook: lu_byte = 0,
    nci: c_ushort = 0,
    top: StkIdRel = std.mem.zeroes(StkIdRel),
    l_G: [*c]global_State = null,
    ci: [*c]CallInfo = null,
    stack_last: StkIdRel = std.mem.zeroes(StkIdRel),
    stack: StkIdRel = std.mem.zeroes(StkIdRel),
    openupval: [*c]UpVal = null,
    tbclist: StkIdRel = std.mem.zeroes(StkIdRel),
    gclist: [*c]GCObject = null,
    twups: [*c]struct_lua_State = null,
    errorJmp: ?*struct_lua_longjmp = null,
    base_ci: CallInfo = std.mem.zeroes(CallInfo),
    hook: lua_Hook = null,
    errfunc: ptrdiff_t = 0,
    nCcalls: l_uint32 = 0,
    oldpc: c_int = 0,
    basehookcount: c_int = 0,
    hookcount: c_int = 0,
    hookmask: sig_atomic_t = 0,
};
const lua_State = struct_lua_State;

const union_unnamed_7 = extern union {
    p: [*c]TValue,
    offset: ptrdiff_t,
};
const struct_unnamed_9 = extern struct {
    next: [*c]struct_UpVal = null,
    previous: [*c][*c]struct_UpVal = null,
};
const union_unnamed_8 = extern union {
    open: struct_unnamed_9,
    value: TValue,
};
const struct_UpVal = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    v: union_unnamed_7 = std.mem.zeroes(union_unnamed_7),
    u: union_unnamed_8 = std.mem.zeroes(union_unnamed_8),
};
const UpVal = struct_UpVal;

const struct_Upvaldesc = extern struct {
    name: [*c]TString = null,
    instack: lu_byte = 0,
    idx: lu_byte = 0,
    kind: lu_byte = 0,
};

const struct_LocVar = extern struct {
    varname: [*c]TString = null,
    startpc: c_int = 0,
    endpc: c_int = 0,
};

const struct_AbsLineInfo = extern struct {
    pc: c_int = 0,
    line: c_int = 0,
};

const struct_Proto = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    numparams: lu_byte = 0,
    is_vararg: lu_byte = 0,
    maxstacksize: lu_byte = 0,
    sizeupvalues: c_int = 0,
    sizek: c_int = 0,
    sizecode: c_int = 0,
    sizelineinfo: c_int = 0,
    sizep: c_int = 0,
    sizelocvars: c_int = 0,
    sizeabslineinfo: c_int = 0,
    linedefined: c_int = 0,
    lastlinedefined: c_int = 0,
    k: [*c]TValue = null,
    code: [*c]Instruction = null,
    p: [*c][*c]struct_Proto = null,
    upvalues: [*c]struct_Upvaldesc = null,
    lineinfo: [*c]ls_byte = null,
    abslineinfo: [*c]struct_AbsLineInfo = null,
    locvars: [*c]struct_LocVar = null,
    source: [*c]TString = null,
    gclist: [*c]GCObject = null,
};
const Proto = struct_Proto;

const struct_CClosure = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    nupvalues: lu_byte = 0,
    gclist: [*c]GCObject = null,
    f: lua_CFunction = null,
    upvalue: [1]TValue = std.mem.zeroes([1]TValue),
};

const struct_LClosure = extern struct {
    next: [*c]struct_GCObject = null,
    tt: lu_byte = 0,
    marked: lu_byte = 0,
    nupvalues: lu_byte = 0,
    gclist: [*c]GCObject = null,
    p: [*c]struct_Proto = null,
    upvals: [1][*c]UpVal = std.mem.zeroes([1][*c]UpVal),
};
const LClosure = struct_LClosure;

const union_Closure = extern union {
    c: struct_CClosure,
    l: struct_LClosure,
};

const union_GCUnion = extern union {
    gc: GCObject,
    ts: struct_TString,
    u: @import("std").meta.fieldInfo(struct_LClosure, .next).type, // placeholder; not used
    cl: union_Closure,
    h: struct_Table,
    p: struct_Proto,
    th: struct_lua_State,
    upv: struct_UpVal,
};

// =========================================================================
// Constants
// =========================================================================

// Tag types
const LUA_TNIL = 0;
const LUA_TBOOLEAN = 1;
const LUA_TNUMBER = 3;
const LUA_TSTRING = 4;
const LUA_TTABLE = 5;
const LUA_TFUNCTION = 6;

inline fn makevariant(t: c_int, v: c_int) c_int {
    return t | (v << 4);
}

const LUA_VNIL = makevariant(LUA_TNIL, 0);
const LUA_VFALSE = makevariant(LUA_TBOOLEAN, 0);
const LUA_VTRUE = makevariant(LUA_TBOOLEAN, 1);
const LUA_VNUMINT = makevariant(LUA_TNUMBER, 0);
const LUA_VNUMFLT = makevariant(LUA_TNUMBER, 1);
const LUA_VTABLE: c_int = makevariant(LUA_TTABLE, 0);
const LUA_VLCL: c_int = makevariant(LUA_TFUNCTION, 0);

const BIT_ISCOLLECTABLE: c_int = (1 << 6);

const LUA_OK = 0;
const CLOSEKTOP = -@as(c_int, 1);
const CIST_FRESH: c_ushort = @as(c_ushort, 1) << 2;

// GC bits
const WHITE0BIT = 3;
const WHITE1BIT = 4;
const BLACKBIT = 5;
const WHITEBITS: c_int = (1 << WHITE0BIT) | (1 << WHITE1BIT);

// Instruction field sizes and positions
const SIZE_OP = 7;
const SIZE_A = 8;
const SIZE_B = 8;
const SIZE_C = 8;
const SIZE_Bx = SIZE_C + SIZE_B + 1;
const SIZE_Ax = SIZE_Bx + SIZE_A;
const SIZE_sJ = SIZE_Bx + SIZE_A;

const POS_OP = 0;
const POS_A = POS_OP + SIZE_OP;
const POS_k = POS_A + SIZE_A;
const POS_B = POS_k + 1;
const POS_C = POS_B + SIZE_B;
const POS_Bx = POS_k;
const POS_Ax = POS_A;
const POS_sJ = POS_A;

const MAXARG_Bx = (1 << SIZE_Bx) - 1;
const OFFSET_sBx = MAXARG_Bx >> 1;
const MAXARG_Ax = (1 << SIZE_Ax) - 1;
const MAXARG_C = (1 << SIZE_C) - 1;
const OFFSET_sC = MAXARG_C >> 1;
const MAXARG_sJ = (1 << SIZE_sJ) - 1;
const OFFSET_sJ = MAXARG_sJ >> 1;

// Opcodes
const OP_MOVE = 0;
const OP_LOADI = 1;
const OP_LOADF = 2;
const OP_LOADK = 3;
const OP_LOADKX = 4;
const OP_LOADFALSE = 5;
const OP_LFALSESKIP = 6;
const OP_LOADTRUE = 7;
const OP_LOADNIL = 8;
const OP_GETUPVAL = 9;
const OP_SETUPVAL = 10;
const OP_GETTABUP = 11;
const OP_GETTABLE = 12;
const OP_GETI = 13;
const OP_GETFIELD = 14;
const OP_SETTABUP = 15;
const OP_SETTABLE = 16;
const OP_SETI = 17;
const OP_SETFIELD = 18;
const OP_NEWTABLE = 19;
const OP_SELF = 20;
const OP_ADDI = 21;
const OP_ADDK = 22;
const OP_SUBK = 23;
const OP_MULK = 24;
const OP_MODK = 25;
const OP_POWK = 26;
const OP_DIVK = 27;
const OP_IDIVK = 28;
const OP_BANDK = 29;
const OP_BORK = 30;
const OP_BXORK = 31;
const OP_SHRI = 32;
const OP_SHLI = 33;
const OP_ADD = 34;
const OP_SUB = 35;
const OP_MUL = 36;
const OP_MOD = 37;
const OP_POW = 38;
const OP_DIV = 39;
const OP_IDIV = 40;
const OP_BAND = 41;
const OP_BOR = 42;
const OP_BXOR = 43;
const OP_SHL = 44;
const OP_SHR = 45;
const OP_MMBIN = 46;
const OP_MMBINI = 47;
const OP_MMBINK = 48;
const OP_UNM = 49;
const OP_BNOT = 50;
const OP_NOT = 51;
const OP_LEN = 52;
const OP_CONCAT = 53;
const OP_CLOSE = 54;
const OP_TBC = 55;
const OP_JMP = 56;
const OP_EQ = 57;
const OP_LT = 58;
const OP_LE = 59;
const OP_EQK = 60;
const OP_EQI = 61;
const OP_LTI = 62;
const OP_LEI = 63;
const OP_GTI = 64;
const OP_GEI = 65;
const OP_TEST = 66;
const OP_TESTSET = 67;
const OP_CALL = 68;
const OP_TAILCALL = 69;
const OP_RETURN = 70;
const OP_RETURN0 = 71;
const OP_RETURN1 = 72;
const OP_FORLOOP = 73;
const OP_FORPREP = 74;
const OP_TFORPREP = 75;
const OP_TFORCALL = 76;
const OP_TFORLOOP = 77;
const OP_SETLIST = 78;
const OP_CLOSURE = 79;
const OP_VARARG = 80;
const OP_VARARGPREP = 81;
const OP_EXTRAARG = 82;

// TMS constants
const TM_INDEX: c_int = 0;
const TM_NEWINDEX: c_int = 1;
const TM_EQ: c_int = 5;
const TM_LT: c_int = 20;
const TM_LE: c_int = 21;
const TM_UNM: c_int = 18;
const TM_BNOT: c_int = 19;
const TM_LEN: c_int = 4;

const F2Ieq: c_int = 0;

// =========================================================================
// Instruction decoding helpers
// =========================================================================

inline fn MASK1(comptime n: comptime_int, comptime p: comptime_int) Instruction {
    return (~(~@as(Instruction, 0) << n)) << p;
}

inline fn GET_OPCODE(i: Instruction) OpCode {
    return @as(OpCode, (i >> POS_OP) & MASK1(SIZE_OP, 0));
}

inline fn GETARG_A(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_A) & MASK1(SIZE_A, 0)));
}

inline fn GETARG_B(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_B) & MASK1(SIZE_B, 0)));
}

inline fn GETARG_C(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_C) & MASK1(SIZE_C, 0)));
}

inline fn GETARG_Bx(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_Bx) & MASK1(SIZE_Bx, 0)));
}

inline fn GETARG_Ax(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_Ax) & MASK1(SIZE_Ax, 0)));
}

inline fn GETARG_sBx(i: Instruction) c_int {
    return GETARG_Bx(i) - OFFSET_sBx;
}

inline fn GETARG_sC(i: Instruction) c_int {
    return GETARG_C(i) - OFFSET_sC;
}

inline fn GETARG_sB(i: Instruction) c_int {
    return GETARG_B(i) - OFFSET_sC; // same offset as sC
}

inline fn GETARG_k(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_k) & MASK1(1, 0)));
}

inline fn TESTARG_k(i: Instruction) bool {
    return (i & (@as(Instruction, 1) << POS_k)) != 0;
}

inline fn GETARG_sJ(i: Instruction) c_int {
    return @as(c_int, @bitCast((i >> POS_sJ) & MASK1(SIZE_sJ, 0))) - OFFSET_sJ;
}

// =========================================================================
// TValue / Object access helpers
// =========================================================================

/// s2v(o) — get TValue* from StkId (StackValue*)
inline fn s2v(o: StkId) [*c]TValue {
    return &o.*.val;
}

/// op_order (for OP_LT): integer fast path + number + metamethod
inline fn op_order(L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, i: Instruction, pc_ptr: *[*c]const Instruction, trap_ptr: *c_int) void {
    const ra_v = s2v(RA(base, i));
    const rb = vRB(base, i);
    var cond: c_int = undefined;
    if (ttisinteger(ra_v) and ttisinteger(rb)) {
        cond = @intFromBool(ivalue(ra_v) < ivalue(rb));
    } else if (ttisnumber(ra_v) and ttisnumber(rb)) {
        cond = LTnum(ra_v, rb);
    } else {
        ci.*.u.l.savedpc = pc_ptr.*;
        cond = luaV_lessthan(L, ra_v, rb);
        trap_ptr.* = ci.*.u.l.trap;
    }
    docondjump(pc_ptr, ci, i, cond, trap_ptr);
}

/// op_order_le (for OP_LE): integer fast path + number + metamethod
inline fn op_order_le(L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, i: Instruction, pc_ptr: *[*c]const Instruction, trap_ptr: *c_int) void {
    const ra_v = s2v(RA(base, i));
    const rb = vRB(base, i);
    var cond: c_int = undefined;
    if (ttisinteger(ra_v) and ttisinteger(rb)) {
        cond = @intFromBool(ivalue(ra_v) <= ivalue(rb));
    } else if (ttisnumber(ra_v) and ttisnumber(rb)) {
        cond = LEnum(ra_v, rb);
    } else {
        ci.*.u.l.savedpc = pc_ptr.*;
        cond = luaV_lessequal(L, ra_v, rb);
        trap_ptr.* = ci.*.u.l.trap;
    }
    docondjump(pc_ptr, ci, i, cond, trap_ptr);
}

/// op_orderI (for OP_LTI/LEI/GTI/GEI): compare with immediate
inline fn op_orderI(L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, i: Instruction, pc_ptr: *[*c]const Instruction, trap_ptr: *c_int, comptime is_lt: bool, comptime inv: bool, tm: TMS) void {
    const ra_v = s2v(RA(base, i));
    var cond: c_int = undefined;
    const im: c_int = GETARG_sB(i);
    if (ttisinteger(ra_v)) {
        const ia = ivalue(ra_v);
        const ib: lua_Integer = @intCast(im);
        if (is_lt) {
            cond = if (inv) @intFromBool(ib < ia) else @intFromBool(ia < ib);
        } else {
            cond = if (inv) @intFromBool(ib <= ia) else @intFromBool(ia <= ib);
        }
    } else if (ttisfloat(ra_v)) {
        const fa = fltvalue(ra_v);
        const fim: lua_Number = @floatFromInt(im);
        if (is_lt) {
            cond = if (inv) @intFromBool(fim < fa) else @intFromBool(fa < fim);
        } else {
            cond = if (inv) @intFromBool(fim <= fa) else @intFromBool(fa <= fim);
        }
    } else {
        const isf = GETARG_C(i);
        ci.*.u.l.savedpc = pc_ptr.*;
        cond = luaT_callorderiTM(L, ra_v, im, @intFromBool(inv), isf, tm);
        trap_ptr.* = ci.*.u.l.trap;
    }
    docondjump(pc_ptr, ci, i, cond, trap_ptr);
}

/// docondjump: if (cond != GETARG_k(i)) pc++; else donextjump(ci)
inline fn docondjump(pc_ptr: *[*c]const Instruction, ci: [*c]CallInfo, i: Instruction, cond: c_int, trap_ptr: *c_int) void {
    if (cond != GETARG_k(i)) {
        pc_ptr.* += 1;
    } else {
        // donextjump: ni = *pc; dojump(ci, ni, 1)
        const ni = pc_ptr.*[0];
        pc_ptr.* = stkid_to_pc(pc_ptr.*, @as(c_int, @bitCast(GETARG_sJ(ni))) + 1);
        trap_ptr.* = ci.*.u.l.trap; // updatetrap(ci)
    }
}

/// PC pointer arithmetic (offset by signed integer)
inline fn stkid_to_pc(p: [*c]const Instruction, n: anytype) [*c]const Instruction {
    const offset: isize = @intCast(n);
    if (offset >= 0) {
        return p + @as(usize, @intCast(offset));
    } else {
        return p - @as(usize, @intCast(-offset));
    }
}

/// StkId pointer arithmetic
inline fn stkid_add(s: StkId, n: anytype) StkId {
    const offset: isize = @intCast(n);
    if (offset >= 0) {
        return s + @as(usize, @intCast(offset));
    } else {
        return s - @as(usize, @intCast(-offset));
    }
}

/// RA(i) = base + GETARG_A(i)
inline fn RA(base: StkId, i: Instruction) StkId {
    return stkid_add(base, GETARG_A(i));
}

/// RB(i) = base + GETARG_B(i)
inline fn RB(base: StkId, i: Instruction) StkId {
    return stkid_add(base, GETARG_B(i));
}

/// vRB(i) = s2v(RB(i))
inline fn vRB(base: StkId, i: Instruction) [*c]TValue {
    return s2v(RB(base, i));
}

/// KB(i) = k + GETARG_B(i)
inline fn KB(k: [*c]TValue, i: Instruction) [*c]TValue {
    const b = GETARG_B(i);
    if (b >= 0) return k + @as(usize, @intCast(b)) else return k - @as(usize, @intCast(-b));
}

/// RC(i) = base + GETARG_C(i)
inline fn RC(base: StkId, i: Instruction) StkId {
    return stkid_add(base, GETARG_C(i));
}

/// vRC(i) = s2v(RC(i))
inline fn vRC(base: StkId, i: Instruction) [*c]TValue {
    return s2v(RC(base, i));
}

/// KC(i) = k + GETARG_C(i)
inline fn KC(k: [*c]TValue, i: Instruction) [*c]TValue {
    const c = GETARG_C(i);
    if (c >= 0) return k + @as(usize, @intCast(c)) else return k - @as(usize, @intCast(-c));
}

/// RKC(i) — either KC or vRC depending on k bit
inline fn RKC(base: StkId, k: [*c]TValue, i: Instruction) [*c]TValue {
    if (TESTARG_k(i)) {
        return KC(k, i);
    } else {
        return vRC(base, i);
    }
}

// Tag type checks
inline fn ttisinteger(o: [*c]const TValue) bool {
    return @as(c_int, @bitCast(@as(c_uint, o.*.tt_))) == LUA_VNUMINT;
}

inline fn ttisfloat(o: [*c]const TValue) bool {
    return @as(c_int, @bitCast(@as(c_uint, o.*.tt_))) == LUA_VNUMFLT;
}

inline fn ttisnumber(o: [*c]const TValue) bool {
    return (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & 15) == LUA_TNUMBER;
}

inline fn ttisnil(o: [*c]const TValue) bool {
    return (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & 15) == LUA_TNIL;
}

inline fn ttistable(o: [*c]const TValue) bool {
    return @as(c_int, @bitCast(@as(c_uint, o.*.tt_))) == (LUA_VTABLE | BIT_ISCOLLECTABLE);
}

inline fn ttisstring(o: [*c]const TValue) bool {
    return (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & 15) == LUA_TSTRING;
}

inline fn ttisLclosure(o: [*c]const TValue) bool {
    return (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & 63) == LUA_VLCL;
}

inline fn isempty(o: [*c]const TValue) bool {
    return ttisnil(o);
}

// Value accessors
inline fn ivalue(o: [*c]const TValue) lua_Integer {
    return o.*.value_.i;
}

inline fn fltvalue(o: [*c]const TValue) lua_Number {
    return o.*.value_.n;
}

inline fn hvalue(o: [*c]const TValue) [*c]Table {
    return &@as([*c]union_GCUnion, @ptrCast(@alignCast(o.*.value_.gc))).*.h;
}

inline fn tsvalue(o: [*c]const TValue) [*c]TString {
    return &@as([*c]union_GCUnion, @ptrCast(@alignCast(o.*.value_.gc))).*.ts;
}

inline fn clLvalue(o: [*c]const TValue) [*c]LClosure {
    return &@as([*c]union_GCUnion, @ptrCast(@alignCast(o.*.value_.gc))).*.cl.l;
}

inline fn gcvalue(o: [*c]const TValue) [*c]GCObject {
    return o.*.value_.gc;
}

inline fn iscollectable(o: [*c]const TValue) bool {
    return (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) & BIT_ISCOLLECTABLE) != 0;
}

inline fn l_isfalse(o: [*c]const TValue) bool {
    return ttisnil(o) or (@as(c_int, @bitCast(@as(c_uint, o.*.tt_))) == LUA_VFALSE);
}

// Value setters
inline fn settt_(o: [*c]TValue, t: c_int) void {
    o.*.tt_ = @as(lu_byte, @bitCast(@as(i8, @truncate(t))));
}

inline fn setobj(L: [*c]lua_State, o1: [*c]TValue, o2: [*c]const TValue) void {
    _ = L;
    o1.*.value_ = o2.*.value_;
    o1.*.tt_ = o2.*.tt_;
}

inline fn setobjs2s(L: [*c]lua_State, o1: StkId, o2: StkId) void {
    setobj(L, s2v(o1), s2v(o2));
}

inline fn setobj2s(L: [*c]lua_State, o1: StkId, o2: [*c]const TValue) void {
    setobj(L, s2v(o1), o2);
}

inline fn setobj2t(L: [*c]lua_State, o1: [*c]TValue, o2: [*c]const TValue) void {
    setobj(L, o1, o2);
}

inline fn setnilvalue(o: [*c]TValue) void {
    settt_(o, LUA_VNIL);
}

inline fn setivalue(o: [*c]TValue, x: lua_Integer) void {
    o.*.value_.i = x;
    settt_(o, LUA_VNUMINT);
}

inline fn chgivalue(o: [*c]TValue, x: lua_Integer) void {
    o.*.value_.i = x;
}

inline fn setfltvalue(o: [*c]TValue, x: lua_Number) void {
    o.*.value_.n = x;
    settt_(o, LUA_VNUMFLT);
}

inline fn setbfvalue(o: [*c]TValue) void {
    settt_(o, LUA_VFALSE);
}

inline fn setbtvalue(o: [*c]TValue) void {
    settt_(o, LUA_VTRUE);
}

inline fn sethvalue2s(L: [*c]lua_State, o: StkId, h: [*c]Table) void {
    const io: [*c]TValue = s2v(o);
    io.*.value_.gc = @as([*c]GCObject, @ptrCast(@alignCast(h)));
    settt_(io, LUA_VTABLE | BIT_ISCOLLECTABLE);
    _ = L;
}

// tonumberns: convert to number without string coercion
inline fn tonumberns(o: [*c]const TValue, n: *lua_Number) bool {
    if (ttisfloat(o)) {
        n.* = fltvalue(o);
        return true;
    } else if (ttisinteger(o)) {
        n.* = @as(lua_Number, @floatFromInt(ivalue(o)));
        return true;
    }
    return false;
}

// tointegerns: convert to integer without string coercion
inline fn tointegerns(o: [*c]const TValue, p: *lua_Integer) bool {
    if (ttisinteger(o)) {
        p.* = ivalue(o);
        return true;
    }
    return luaV_tointegerns(o, p, @as(F2Imod, @bitCast(F2Ieq))) != 0;
}

// intop: wrapping integer arithmetic
fn intop_add(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) +% @as(lua_Unsigned, @bitCast(b))));
}

fn intop_sub(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) -% @as(lua_Unsigned, @bitCast(b))));
}

fn intop_mul(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) *% @as(lua_Unsigned, @bitCast(b))));
}

fn intop_band(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) & @as(lua_Unsigned, @bitCast(b))));
}

fn intop_bor(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) | @as(lua_Unsigned, @bitCast(b))));
}

fn intop_bxor(a: lua_Integer, b: lua_Integer) lua_Integer {
    return @as(lua_Integer, @bitCast(@as(lua_Unsigned, @bitCast(a)) ^ @as(lua_Unsigned, @bitCast(b))));
}

// =========================================================================
// luaV_fastget / luaV_fastgeti / luaV_finishfastset
// =========================================================================

const FastGetResult = struct {
    slot: [*c]const TValue,
    found: bool,
};

inline fn luaV_fastget_shortstr(t: [*c]const TValue, key: [*c]TString) FastGetResult {
    if (!ttistable(t)) return .{ .slot = null, .found = false };
    const slot = luaH_getshortstr(hvalue(t), key);
    return .{ .slot = slot, .found = !isempty(slot) };
}

inline fn luaV_fastget_str(t: [*c]const TValue, key: [*c]TString) FastGetResult {
    if (!ttistable(t)) return .{ .slot = null, .found = false };
    const slot = luaH_getstr(hvalue(t), key);
    return .{ .slot = slot, .found = !isempty(slot) };
}

inline fn luaV_fastget_generic(t: [*c]const TValue, key: [*c]const TValue) FastGetResult {
    if (!ttistable(t)) return .{ .slot = null, .found = false };
    const slot = luaH_get(hvalue(t), key);
    return .{ .slot = slot, .found = !isempty(slot) };
}

inline fn luaV_fastgeti(t: [*c]const TValue, key: lua_Unsigned) FastGetResult {
    if (!ttistable(t)) return .{ .slot = null, .found = false };
    const h = hvalue(t);
    const slot: [*c]const TValue = if (key -% 1 < @as(lua_Unsigned, h.*.alimit))
        h.*.array + @as(usize, @intCast(key - 1))
    else
        luaH_getint(h, @as(lua_Integer, @bitCast(key)));
    return .{ .slot = slot, .found = !isempty(slot) };
}

inline fn luaV_finishfastset(L: [*c]lua_State, t: [*c]const TValue, slot: [*c]const TValue, v: [*c]const TValue) void {
    // setobj2t(L, cast(TValue*,slot), v)
    const mslot: [*c]TValue = @constCast(slot);
    setobj(L, mslot, v);
    // luaC_barrierback(L, gcvalue(t), v)
    if (iscollectable(v)) {
        const obj = gcvalue(t);
        const vgc = gcvalue(v);
        if (((@as(c_int, @bitCast(@as(c_uint, obj.*.marked))) & (1 << BLACKBIT)) != 0) and
            ((@as(c_int, @bitCast(@as(c_uint, vgc.*.marked))) & WHITEBITS) != 0))
        {
            luaC_barrierback_(L, obj);
        }
    }
}

// luaC_barrier for upvalues
inline fn luaC_barrier_upval(L: [*c]lua_State, uv: [*c]UpVal, v: [*c]const TValue) void {
    if (iscollectable(v)) {
        const p_gc = &@as([*c]union_GCUnion, @ptrCast(@alignCast(uv))).*.gc;
        const v_gc = gcvalue(v);
        if (((@as(c_int, @bitCast(@as(c_uint, p_gc.*.marked))) & (1 << BLACKBIT)) != 0) and
            ((@as(c_int, @bitCast(@as(c_uint, v_gc.*.marked))) & WHITEBITS) != 0))
        {
            luaC_barrier_(L, p_gc, v_gc);
        }
    }
}

// GC check inline
inline fn checkGC(L: [*c]lua_State, ci: [*c]CallInfo, pc: [*c]const Instruction, c_limit: StkId, trap: *c_int) void {
    if (L.*.l_G.*.GCdebt > 0) {
        ci.*.u.l.savedpc = pc;
        L.*.top.p = c_limit;
        luaC_step(L);
        trap.* = ci.*.u.l.trap;
    }
}

// =========================================================================
// Extern function declarations
// =========================================================================

extern fn luaV_lessthan(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) c_int;
extern fn luaV_lessequal(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) c_int;
extern fn luaV_equalobj(L: [*c]lua_State, t1: [*c]const TValue, t2: [*c]const TValue) c_int;
extern fn luaV_finishget(L: [*c]lua_State, t: [*c]const TValue, key: [*c]TValue, val: StkId, slot: [*c]const TValue) void;
extern fn luaV_finishset(L: [*c]lua_State, t: [*c]const TValue, key: [*c]TValue, val: [*c]TValue, slot: [*c]const TValue) void;
extern fn luaV_tointegerns(obj: [*c]const TValue, p: [*c]lua_Integer, mode: F2Imod) c_int;
extern fn luaV_tonumber_(obj: [*c]const TValue, n: [*c]lua_Number) c_int;
extern fn luaV_concat(L: [*c]lua_State, total: c_int) void;
extern fn luaV_objlen(L: [*c]lua_State, ra: StkId, rb: [*c]const TValue) void;
extern fn luaV_shiftl(x: lua_Integer, y: lua_Integer) lua_Integer;
extern fn luaV_idiv(L: [*c]lua_State, m: lua_Integer, n: lua_Integer) lua_Integer;
extern fn luaV_mod(L: [*c]lua_State, m: lua_Integer, n: lua_Integer) lua_Integer;
extern fn luaV_modf(L: [*c]lua_State, m: lua_Number, n: lua_Number) lua_Number;

extern fn luaD_hookcall(L: [*c]lua_State, ci: [*c]CallInfo) void;
extern fn luaD_precall(L: [*c]lua_State, func: StkId, nResults: c_int) [*c]CallInfo;
extern fn luaD_pretailcall(L: [*c]lua_State, ci: [*c]CallInfo, func: StkId, narg1: c_int, delta: c_int) c_int;
extern fn luaD_poscall(L: [*c]lua_State, ci: [*c]CallInfo, nres: c_int) void;
extern fn luaD_call(L: [*c]lua_State, func: StkId, nResults: c_int) void;

extern fn luaF_newtbcupval(L: [*c]lua_State, level: StkId) void;
extern fn luaF_closeupval(L: [*c]lua_State, level: StkId) void;
extern fn luaF_close(L: [*c]lua_State, level: StkId, status: c_int, yy: c_int) StkId;

extern fn luaG_traceexec(L: [*c]lua_State, pc: [*c]const Instruction) c_int;
extern fn luaG_runerror(L: [*c]lua_State, fmt: [*c]const u8, ...) noreturn;

extern fn luaH_new(L: [*c]lua_State) [*c]Table;
extern fn luaH_resize(L: [*c]lua_State, t: [*c]Table, nasize: c_uint, nhsize: c_uint) void;
extern fn luaH_resizearray(L: [*c]lua_State, t: [*c]Table, nasize: c_uint) void;
extern fn luaH_realasize(t: [*c]const Table) c_uint;
extern fn luaH_getshortstr(t: [*c]Table, key: [*c]TString) [*c]const TValue;
extern fn luaH_getstr(t: [*c]Table, key: [*c]TString) [*c]const TValue;
extern fn luaH_get(t: [*c]Table, key: [*c]const TValue) [*c]const TValue;
extern fn luaH_getint(t: [*c]Table, key: lua_Integer) [*c]const TValue;

extern fn luaT_trybinTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, res: StkId, event: TMS) void;
extern fn luaT_trybiniTM(L: [*c]lua_State, p1: [*c]const TValue, i2: lua_Integer, inv: c_int, res: StkId, event: TMS) void;
extern fn luaT_trybinassocTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, inv: c_int, res: StkId, event: TMS) void;
extern fn luaT_callorderTM(L: [*c]lua_State, p1: [*c]const TValue, p2: [*c]const TValue, event: TMS) c_int;
extern fn luaT_callorderiTM(L: [*c]lua_State, p1: [*c]const TValue, v2: c_int, inv: c_int, isfloat: c_int, event: TMS) c_int;
extern fn luaT_adjustvarargs(L: [*c]lua_State, nfixparams: c_int, ci: [*c]CallInfo, p: [*c]const Proto) void;
extern fn luaT_getvarargs(L: [*c]lua_State, ci: [*c]CallInfo, where: StkId, wanted: c_int) void;

extern fn luaC_step(L: [*c]lua_State) void;
extern fn luaC_barrier_(L: [*c]lua_State, o: [*c]GCObject, v: [*c]GCObject) void;
extern fn luaC_barrierback_(L: [*c]lua_State, o: [*c]GCObject) void;

// Functions defined in lvm.zig (not extern — exported from same compilation)
extern fn forprep(L: [*c]lua_State, ra: StkId) callconv(.c) c_int;
extern fn floatforloop(ra: StkId) callconv(.c) c_int;
extern fn pushclosure(L: [*c]lua_State, p: [*c]Proto, encup: [*c][*c]UpVal, base: StkId, ra: StkId) callconv(.c) void;
extern fn LTnum(l: [*c]const TValue, r: [*c]const TValue) callconv(.c) c_int;
extern fn LEnum(l: [*c]const TValue, r: [*c]const TValue) callconv(.c) c_int;
extern fn lessthanothers(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) callconv(.c) c_int;
extern fn lessequalothers(L: [*c]lua_State, l: [*c]const TValue, r: [*c]const TValue) callconv(.c) c_int;

extern fn memcpy(?*anyopaque, ?*const anyopaque, c_ulong) ?*anyopaque;
extern fn pow(f64, f64) f64;
extern fn floor(f64) f64;
extern fn fmod(f64, f64) f64;

// =========================================================================
// Arithmetic / comparison macro helpers
// =========================================================================

// luai_num* are trivial arithmetic on lua_Number
fn luai_numadd(a: lua_Number, b: lua_Number) lua_Number {
    return a + b;
}
fn luai_numsub(a: lua_Number, b: lua_Number) lua_Number {
    return a - b;
}
fn luai_nummul(a: lua_Number, b: lua_Number) lua_Number {
    return a * b;
}
fn luai_numdiv(a: lua_Number, b: lua_Number) lua_Number {
    return a / b;
}
fn luai_numpow(a: lua_Number, b: lua_Number) lua_Number {
    return pow(a, b);
}
fn luai_numidiv(a: lua_Number, b: lua_Number) lua_Number {
    return floor(a / b);
}

// Shift right wrapper: luaV_shiftl(x, -y)
fn luaV_shiftr_wrap(x: lua_Integer, y: lua_Integer) lua_Integer {
    return luaV_shiftl(x, -%y);
}

// Shift left wrapper (pass through)
fn luaV_shiftl_wrap(x: lua_Integer, y: lua_Integer) lua_Integer {
    return luaV_shiftl(x, y);
}

// Wrappers for extern fn → plain fn (callconv mismatch)
fn luaV_mod_wrap(L_: [*c]lua_State, a: lua_Integer, b: lua_Integer) lua_Integer {
    return luaV_mod(L_, a, b);
}
fn luaV_idiv_wrap(L_: [*c]lua_State, a: lua_Integer, b: lua_Integer) lua_Integer {
    return luaV_idiv(L_, a, b);
}
fn luaV_modf_wrap(L_: [*c]lua_State, a: lua_Number, b: lua_Number) lua_Number {
    return luaV_modf(L_, a, b);
}
fn luai_numidiv_wrap(L_: [*c]lua_State, a: lua_Number, b: lua_Number) lua_Number {
    _ = L_;
    return luai_numidiv(a, b);
}

// =========================================================================
// Arithmetic/bitwise/comparison macro helpers (translated from lvm.c macros)
// =========================================================================

inline fn op_arithI(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k: [*c]TValue,
    i: Instruction, comptime iop: fn (lua_Integer, lua_Integer) lua_Integer,
    comptime fop: fn (lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    _ = k;
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const imm = GETARG_sC(i);
    if (ttisinteger(v1)) {
        const iv1 = ivalue(v1);
        pc_ptr.* += 1;
        setivalue(s2v(ra), iop(iv1, @intCast(imm)));
    } else if (ttisfloat(v1)) {
        const nb = fltvalue(v1);
        const fimm: lua_Number = @floatFromInt(imm);
        pc_ptr.* += 1;
        setfltvalue(s2v(ra), fop(nb, fimm));
    } else {
        // Slow path: metamethod
        ci.*.u.l.savedpc = pc_ptr.*;
        _ = .{ L, v1, ra, trap_ptr };
    }
}

inline fn op_arithK(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime iop: fn (lua_Integer, lua_Integer) lua_Integer,
    comptime fop: fn (lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = KC(k_arr, i);
    if (ttisinteger(v1) and ttisinteger(v2)) {
        const ii1 = ivalue(v1);
        const ii2 = ivalue(v2);
        pc_ptr.* += 1;
        setivalue(s2v(ra), iop(ii1, ii2));
    } else {
        var n1: lua_Number = undefined;
        var n2: lua_Number = undefined;
        if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
            pc_ptr.* += 1;
            setfltvalue(s2v(ra), fop(n1, n2));
        } else {
            ci.*.u.l.savedpc = pc_ptr.*;
            _ = .{ L, v1, ra, trap_ptr };
        }
    }
}

inline fn op_arithK_ii(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime iop: fn ([*c]lua_State, lua_Integer, lua_Integer) lua_Integer,
    comptime fop: fn ([*c]lua_State, lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = KC(k_arr, i);
    if (ttisinteger(v1) and ttisinteger(v2)) {
        const ii1 = ivalue(v1);
        const ii2 = ivalue(v2);
        pc_ptr.* += 1;
        setivalue(s2v(ra), iop(L, ii1, ii2));
    } else {
        var n1: lua_Number = undefined;
        var n2: lua_Number = undefined;
        if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
            pc_ptr.* += 1;
            setfltvalue(s2v(ra), fop(L, n1, n2));
        } else {
            ci.*.u.l.savedpc = pc_ptr.*;
            _ = .{ L, v1, ra, trap_ptr };
        }
    }
}

inline fn op_arithf(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId,
    i: Instruction, comptime fop: fn (lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = vRC(base, i);
    var n1: lua_Number = undefined;
    var n2: lua_Number = undefined;
    if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
        pc_ptr.* += 1;
        setfltvalue(s2v(ra), fop(n1, n2));
    } else {
        ci.*.u.l.savedpc = pc_ptr.*;
        _ = .{ L, v1, ra, trap_ptr };
    }
}

inline fn op_arithfK(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime fop: fn (lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = KC(k_arr, i);
    var n1: lua_Number = undefined;
    var n2: lua_Number = undefined;
    if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
        pc_ptr.* += 1;
        setfltvalue(s2v(ra), fop(n1, n2));
    } else {
        ci.*.u.l.savedpc = pc_ptr.*;
        _ = .{ L, v1, ra, trap_ptr };
    }
}

inline fn op_arith(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime iop: fn (lua_Integer, lua_Integer) lua_Integer,
    comptime fop: fn (lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    _ = k_arr;
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = vRC(base, i);
    if (ttisinteger(v1) and ttisinteger(v2)) {
        const ii1 = ivalue(v1);
        const ii2 = ivalue(v2);
        pc_ptr.* += 1;
        setivalue(s2v(ra), iop(ii1, ii2));
    } else {
        var n1: lua_Number = undefined;
        var n2: lua_Number = undefined;
        if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
            pc_ptr.* += 1;
            setfltvalue(s2v(ra), fop(n1, n2));
        } else {
            ci.*.u.l.savedpc = pc_ptr.*;
            _ = .{ L, v1, ra, trap_ptr };
        }
    }
}

inline fn op_arith_ii(
    L: [*c]lua_State, ci: [*c]CallInfo, base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime iop: fn ([*c]lua_State, lua_Integer, lua_Integer) lua_Integer,
    comptime fop: fn ([*c]lua_State, lua_Number, lua_Number) lua_Number,
    pc_ptr: *[*c]const Instruction, trap_ptr: *c_int,
) void {
    _ = k_arr;
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = vRC(base, i);
    if (ttisinteger(v1) and ttisinteger(v2)) {
        pc_ptr.* += 1;
        setivalue(s2v(ra), iop(L, ivalue(v1), ivalue(v2)));
    } else {
        var n1: lua_Number = undefined;
        var n2: lua_Number = undefined;
        if (tonumberns(v1, &n1) and tonumberns(v2, &n2)) {
            pc_ptr.* += 1;
            setfltvalue(s2v(ra), fop(L, n1, n2));
        } else {
            ci.*.u.l.savedpc = pc_ptr.*;
            _ = .{ L, v1, ra, trap_ptr };
        }
    }
}

inline fn op_bitwiseK(
    base: StkId, k_arr: [*c]TValue,
    i: Instruction, comptime op: fn (lua_Integer, lua_Integer) lua_Integer,
    pc_ptr: *[*c]const Instruction,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = KC(k_arr, i);
    var ii1: lua_Integer = undefined;
    const ii2 = ivalue(v2);
    if (tointegerns(v1, &ii1)) {
        pc_ptr.* += 1;
        setivalue(s2v(ra), op(ii1, ii2));
    }
}

inline fn op_bitwise(
    base: StkId,
    i: Instruction, comptime op: fn (lua_Integer, lua_Integer) lua_Integer,
    pc_ptr: *[*c]const Instruction,
) void {
    const ra = RA(base, i);
    const v1 = vRB(base, i);
    const v2 = vRC(base, i);
    var ii1: lua_Integer = undefined;
    var ii2: lua_Integer = undefined;
    if (tointegerns(v1, &ii1) and tointegerns(v2, &ii2)) {
        pc_ptr.* += 1;
        setivalue(s2v(ra), op(ii1, ii2));
    }
}

// =========================================================================
// The main interpreter loop
// =========================================================================

pub export fn luaV_execute(arg_L: [*c]lua_State, arg_ci: [*c]CallInfo) void {
    @setEvalBranchQuota(100000);
    const L = arg_L;
    var ci = arg_ci;
    var cl: [*c]LClosure = undefined;
    var k: [*c]TValue = undefined;
    var base: StkId = undefined;
    var pc: [*c]const Instruction = undefined;
    var trap: c_int = undefined;

    // go_returning: when true, skip the `trap = L.hookmask` assignment
    var go_returning = false;

    // startfunc loop: goto startfunc => continue :startfunc
    //                 goto ret => break :startfunc
    startfunc: while (true) {
        if (!go_returning) {
            trap = L.*.hookmask;
        }
        go_returning = false;

        // returning: label merged here
        cl = clLvalue(s2v(ci.*.func.p));
        k = cl.*.p.*.k;
        pc = ci.*.u.l.savedpc;

        if (trap != 0) {
            if (pc == cl.*.p.*.code) { // first instruction (not resuming)?
                if (cl.*.p.*.is_vararg != 0) {
                    trap = 0; // hooks will start after VARARGPREP
                } else {
                    luaD_hookcall(L, ci);
                }
            }
            ci.*.u.l.trap = 1; // assume trap is on
        }
        base = ci.*.func.p + @as(usize, 1);

        // main loop of interpreter
        while (true) {
            // vmfetch
            if (trap != 0) {
                trap = luaG_traceexec(L, pc);
                base = ci.*.func.p + @as(usize, 1);
            }
            const i: Instruction = pc[0];
            pc += 1;

            if (vm_trace) traceOpcode(@intCast(GET_OPCODE(i)));

            switch (GET_OPCODE(i)) {
                OP_MOVE => {
                    const ra = RA(base, i);
                    setobjs2s(L, ra, RB(base, i));
                },

                OP_LOADI => {
                    const ra = RA(base, i);
                    const b: lua_Integer = @as(lua_Integer, GETARG_sBx(i));
                    setivalue(s2v(ra), b);
                },

                OP_LOADF => {
                    const ra = RA(base, i);
                    const b: c_int = GETARG_sBx(i);
                    setfltvalue(s2v(ra), @as(lua_Number, @floatFromInt(b)));
                },

                OP_LOADK => {
                    const ra = RA(base, i);
                    const bx = GETARG_Bx(i);
                    const rb: [*c]TValue = if (bx >= 0) k + @as(usize, @intCast(bx)) else k - @as(usize, @intCast(-bx));
                    setobj2s(L, ra, rb);
                },

                OP_LOADKX => {
                    const ra = RA(base, i);
                    const ax = GETARG_Ax(pc[0]);
                    pc += 1;
                    const rb: [*c]TValue = if (ax >= 0) k + @as(usize, @intCast(ax)) else k - @as(usize, @intCast(-ax));
                    setobj2s(L, ra, rb);
                },

                OP_LOADFALSE => {
                    const ra = RA(base, i);
                    setbfvalue(s2v(ra));
                },

                OP_LFALSESKIP => {
                    const ra = RA(base, i);
                    setbfvalue(s2v(ra));
                    pc += 1; // skip next instruction
                },

                OP_LOADTRUE => {
                    const ra = RA(base, i);
                    setbtvalue(s2v(ra));
                },

                OP_LOADNIL => {
                    var ra = RA(base, i);
                    var b: c_int = GETARG_B(i);
                    while (true) {
                        setnilvalue(s2v(ra));
                        ra += 1;
                        if (b == 0) break;
                        b -= 1;
                    }
                },

                OP_GETUPVAL => {
                    const ra = RA(base, i);
                    const b = GETARG_B(i);
                    setobj2s(L, ra, @as([*][*c]UpVal, @ptrCast(&cl.*.upvals))[@as(usize, @intCast(b))].*.v.p);
                },

                OP_SETUPVAL => {
                    const ra = RA(base, i);
                    const uv: [*c]UpVal = @as([*][*c]UpVal, @ptrCast(&cl.*.upvals))[@as(usize, @intCast(GETARG_B(i)))];
                    setobj(L, uv.*.v.p, s2v(ra));
                    luaC_barrier_upval(L, uv, s2v(ra));
                },

                OP_GETTABUP => {
                    const ra = RA(base, i);
                    const upval: [*c]TValue = @as([*][*c]UpVal, @ptrCast(&cl.*.upvals))[@as(usize, @intCast(GETARG_B(i)))].*.v.p;
                    const rc = KC(k, i);
                    const key = tsvalue(rc);
                    const fg = luaV_fastget_shortstr(upval, key);
                    if (fg.found) {
                        setobj2s(L, ra, fg.slot);
                    } else {
                        // Protect(luaV_finishget(L, upval, rc, ra, slot))
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishget(L, upval, rc, ra, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_GETTABLE => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const rc = vRC(base, i);
                    if (ttisinteger(rc)) {
                        const n: lua_Unsigned = @as(lua_Unsigned, @bitCast(ivalue(rc)));
                        const fg = luaV_fastgeti(rb, n);
                        if (fg.found) {
                            setobj2s(L, ra, fg.slot);
                        } else {
                            ci.*.u.l.savedpc = pc;
                            L.*.top.p = ci.*.top.p;
                            luaV_finishget(L, rb, rc, ra, fg.slot);
                            trap = ci.*.u.l.trap;
                        }
                    } else {
                        const fg = luaV_fastget_generic(rb, rc);
                        if (fg.found) {
                            setobj2s(L, ra, fg.slot);
                        } else {
                            ci.*.u.l.savedpc = pc;
                            L.*.top.p = ci.*.top.p;
                            luaV_finishget(L, rb, rc, ra, fg.slot);
                            trap = ci.*.u.l.trap;
                        }
                    }
                },

                OP_GETI => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const c_val: c_int = GETARG_C(i);
                    const fg = luaV_fastgeti(rb, @as(lua_Unsigned, @intCast(c_val)));
                    if (fg.found) {
                        setobj2s(L, ra, fg.slot);
                    } else {
                        var tkey: TValue = undefined;
                        setivalue(&tkey, @as(lua_Integer, c_val));
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishget(L, rb, &tkey, ra, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_GETFIELD => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const rc = KC(k, i);
                    const key = tsvalue(rc);
                    const fg = luaV_fastget_shortstr(rb, key);
                    if (fg.found) {
                        setobj2s(L, ra, fg.slot);
                    } else {
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishget(L, rb, rc, ra, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_SETTABUP => {
                    const upval: [*c]TValue = @as([*][*c]UpVal, @ptrCast(&cl.*.upvals))[@as(usize, @intCast(GETARG_A(i)))].*.v.p;
                    const rb = KB(k, i);
                    const rc = RKC(base, k, i);
                    const key = tsvalue(rb);
                    const fg = luaV_fastget_shortstr(upval, key);
                    if (fg.found) {
                        luaV_finishfastset(L, upval, fg.slot, rc);
                    } else {
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishset(L, upval, rb, rc, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_SETTABLE => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const rc = RKC(base, k, i);
                    if (ttisinteger(rb)) {
                        const n: lua_Unsigned = @as(lua_Unsigned, @bitCast(ivalue(rb)));
                        const fg = luaV_fastgeti(s2v(ra), n);
                        if (fg.found) {
                            luaV_finishfastset(L, s2v(ra), fg.slot, rc);
                        } else {
                            ci.*.u.l.savedpc = pc;
                            L.*.top.p = ci.*.top.p;
                            luaV_finishset(L, s2v(ra), rb, rc, fg.slot);
                            trap = ci.*.u.l.trap;
                        }
                    } else {
                        const fg = luaV_fastget_generic(s2v(ra), rb);
                        if (fg.found) {
                            luaV_finishfastset(L, s2v(ra), fg.slot, rc);
                        } else {
                            ci.*.u.l.savedpc = pc;
                            L.*.top.p = ci.*.top.p;
                            luaV_finishset(L, s2v(ra), rb, rc, fg.slot);
                            trap = ci.*.u.l.trap;
                        }
                    }
                },

                OP_SETI => {
                    const ra = RA(base, i);
                    const c_val: c_int = GETARG_B(i);
                    const rc = RKC(base, k, i);
                    const fg = luaV_fastgeti(s2v(ra), @as(lua_Unsigned, @intCast(c_val)));
                    if (fg.found) {
                        luaV_finishfastset(L, s2v(ra), fg.slot, rc);
                    } else {
                        var tkey: TValue = undefined;
                        setivalue(&tkey, @as(lua_Integer, c_val));
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishset(L, s2v(ra), &tkey, rc, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_SETFIELD => {
                    const ra = RA(base, i);
                    const rb = KB(k, i);
                    const rc = RKC(base, k, i);
                    const key = tsvalue(rb);
                    const fg = luaV_fastget_shortstr(s2v(ra), key);
                    if (fg.found) {
                        luaV_finishfastset(L, s2v(ra), fg.slot, rc);
                    } else {
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishset(L, s2v(ra), rb, rc, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_NEWTABLE => {
                    const ra = RA(base, i);
                    var b: c_int = GETARG_B(i);
                    var c_val: c_int = GETARG_C(i);
                    if (b > 0) b = @as(c_int, 1) << @intCast(b - 1);
                    if (TESTARG_k(i)) {
                        c_val += GETARG_Ax(pc[0]) * (MAXARG_C + 1);
                    }
                    pc += 1; // skip extra argument
                    L.*.top.p = ra + @as(usize, 1); // correct top for emergency GC
                    const t = luaH_new(L);
                    sethvalue2s(L, ra, t);
                    if (b != 0 or c_val != 0)
                        luaH_resize(L, t, @as(c_uint, @intCast(c_val)), @as(c_uint, @intCast(b)));
                    checkGC(L, ci, pc, ra + @as(usize, 1), &trap);
                },

                OP_SELF => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const rc = RKC(base, k, i);
                    const key = tsvalue(rc);
                    setobj2s(L, ra + @as(usize, 1), rb);
                    const fg = luaV_fastget_str(rb, key);
                    if (fg.found) {
                        setobj2s(L, ra, fg.slot);
                    } else {
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaV_finishget(L, rb, rc, ra, fg.slot);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_ADDI => {
                    op_arithI(L, ci, base, k, i, intop_add, luai_numadd, &pc, &trap);
                },
                OP_ADDK => {
                    op_arithK(L, ci, base, k, i, intop_add, luai_numadd, &pc, &trap);
                },
                OP_SUBK => {
                    op_arithK(L, ci, base, k, i, intop_sub, luai_numsub, &pc, &trap);
                },
                OP_MULK => {
                    op_arithK(L, ci, base, k, i, intop_mul, luai_nummul, &pc, &trap);
                },
                OP_MODK => {
                    // savestate for division by 0
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    op_arithK_ii(L, ci, base, k, i, luaV_mod_wrap, luaV_modf_wrap, &pc, &trap);
                },
                OP_POWK => {
                    op_arithfK(L, ci, base, k, i, luai_numpow, &pc, &trap);
                },
                OP_DIVK => {
                    op_arithfK(L, ci, base, k, i, luai_numdiv, &pc, &trap);
                },
                OP_IDIVK => {
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    op_arithK_ii(L, ci, base, k, i, luaV_idiv_wrap, luai_numidiv_wrap, &pc, &trap);
                },
                OP_BANDK => {
                    op_bitwiseK(base, k, i, intop_band, &pc);
                },
                OP_BORK => {
                    op_bitwiseK(base, k, i, intop_bor, &pc);
                },
                OP_BXORK => {
                    op_bitwiseK(base, k, i, intop_bxor, &pc);
                },

                OP_SHRI => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const ic: c_int = GETARG_sC(i);
                    var ib: lua_Integer = undefined;
                    if (tointegerns(rb, &ib)) {
                        pc += 1;
                        setivalue(s2v(ra), luaV_shiftl(ib, intop_sub(0, @as(lua_Integer, ic))));
                    }
                },

                OP_SHLI => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    const ic: c_int = GETARG_sC(i);
                    var ib: lua_Integer = undefined;
                    if (tointegerns(rb, &ib)) {
                        pc += 1;
                        setivalue(s2v(ra), luaV_shiftl(@as(lua_Integer, ic), ib));
                    }
                },

                OP_ADD => {
                    op_arith(L, ci, base, k, i, intop_add, luai_numadd, &pc, &trap);
                },
                OP_SUB => {
                    op_arith(L, ci, base, k, i, intop_sub, luai_numsub, &pc, &trap);
                },
                OP_MUL => {
                    op_arith(L, ci, base, k, i, intop_mul, luai_nummul, &pc, &trap);
                },
                OP_MOD => {
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    op_arith_ii(L, ci, base, k, i, luaV_mod_wrap, luaV_modf_wrap, &pc, &trap);
                },
                OP_POW => {
                    op_arithf(L, ci, base, i, luai_numpow, &pc, &trap);
                },
                OP_DIV => {
                    op_arithf(L, ci, base, i, luai_numdiv, &pc, &trap);
                },
                OP_IDIV => {
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    op_arith_ii(L, ci, base, k, i, luaV_idiv_wrap, luai_numidiv_wrap, &pc, &trap);
                },
                OP_BAND => {
                    op_bitwise(base, i, intop_band, &pc);
                },
                OP_BOR => {
                    op_bitwise(base, i, intop_bor, &pc);
                },
                OP_BXOR => {
                    op_bitwise(base, i, intop_bxor, &pc);
                },
                OP_SHR => {
                    op_bitwise(base, i, luaV_shiftr_wrap, &pc);
                },
                OP_SHL => {
                    op_bitwise(base, i, luaV_shiftl_wrap, &pc);
                },

                OP_MMBIN => {
                    const ra = RA(base, i);
                    const pi = (pc - @as(usize, 2))[0]; // original arith expression
                    const rb = vRB(base, i);
                    const tm: TMS = @as(TMS, @intCast(GETARG_C(i)));
                    const result = RA(base, pi);
                    // Protect
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaT_trybinTM(L, s2v(ra), rb, result, tm);
                    trap = ci.*.u.l.trap;
                },

                OP_MMBINI => {
                    const ra = RA(base, i);
                    const pi = (pc - @as(usize, 2))[0];
                    const imm: c_int = GETARG_sB(i);
                    const tm: TMS = @as(TMS, @intCast(GETARG_C(i)));
                    const flip: c_int = GETARG_k(i);
                    const result = RA(base, pi);
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaT_trybiniTM(L, s2v(ra), @as(lua_Integer, imm), flip, result, tm);
                    trap = ci.*.u.l.trap;
                },

                OP_MMBINK => {
                    const ra = RA(base, i);
                    const pi = (pc - @as(usize, 2))[0];
                    const imm = KB(k, i);
                    const tm: TMS = @as(TMS, @intCast(GETARG_C(i)));
                    const flip: c_int = GETARG_k(i);
                    const result = RA(base, pi);
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaT_trybinassocTM(L, s2v(ra), imm, flip, result, tm);
                    trap = ci.*.u.l.trap;
                },

                OP_UNM => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    if (ttisinteger(rb)) {
                        const ib = ivalue(rb);
                        setivalue(s2v(ra), intop_sub(0, ib));
                    } else {
                        var nb: lua_Number = undefined;
                        if (tonumberns(rb, &nb)) {
                            setfltvalue(s2v(ra), -nb);
                        } else {
                            ci.*.u.l.savedpc = pc;
                            L.*.top.p = ci.*.top.p;
                            luaT_trybinTM(L, rb, rb, ra, @as(TMS, @bitCast(TM_UNM)));
                            trap = ci.*.u.l.trap;
                        }
                    }
                },

                OP_BNOT => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    var ib: lua_Integer = undefined;
                    if (tointegerns(rb, &ib)) {
                        setivalue(s2v(ra), intop_bxor(@as(lua_Integer, @bitCast(~@as(lua_Unsigned, 0))), ib));
                    } else {
                        ci.*.u.l.savedpc = pc;
                        L.*.top.p = ci.*.top.p;
                        luaT_trybinTM(L, rb, rb, ra, @as(TMS, @bitCast(TM_BNOT)));
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_NOT => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    if (l_isfalse(rb))
                        setbtvalue(s2v(ra))
                    else
                        setbfvalue(s2v(ra));
                },

                OP_LEN => {
                    const ra = RA(base, i);
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaV_objlen(L, ra, vRB(base, i));
                    trap = ci.*.u.l.trap;
                },

                OP_CONCAT => {
                    const ra = RA(base, i);
                    const n: c_int = GETARG_B(i);
                    L.*.top.p = ra + @as(usize, @intCast(n));
                    // ProtectNT
                    ci.*.u.l.savedpc = pc;
                    luaV_concat(L, n);
                    trap = ci.*.u.l.trap;
                    checkGC(L, ci, pc, L.*.top.p, &trap);
                },

                OP_CLOSE => {
                    const ra = RA(base, i);
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    _ = luaF_close(L, ra, LUA_OK, 1);
                    trap = ci.*.u.l.trap;
                },

                OP_TBC => {
                    const ra = RA(base, i);
                    // halfProtect
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaF_newtbcupval(L, ra);
                },

                OP_JMP => {
                    // dojump
                    pc = stkid_to_pc(pc, GETARG_sJ(i) + 0);
                    trap = ci.*.u.l.trap;
                },

                OP_EQ => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    var cond: c_int = undefined;
                    // Protect
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    cond = luaV_equalobj(L, s2v(ra), rb);
                    trap = ci.*.u.l.trap;
                    // docondjump
                    docondjump(&pc, ci, i, cond, &trap);
                },

                OP_LT => {
                    op_order(L, ci, base, i, &pc, &trap);
                },

                OP_LE => {
                    op_order_le(L, ci, base, i, &pc, &trap);
                },

                OP_EQK => {
                    const ra = RA(base, i);
                    const rb = KB(k, i);
                    const cond: c_int = luaV_equalobj(null, s2v(ra), rb);
                    docondjump(&pc, ci, i, cond, &trap);
                },

                OP_EQI => {
                    const ra = RA(base, i);
                    var cond: c_int = undefined;
                    const im: c_int = GETARG_sB(i);
                    if (ttisinteger(s2v(ra))) {
                        cond = @intFromBool(ivalue(s2v(ra)) == @as(lua_Integer, im));
                    } else if (ttisfloat(s2v(ra))) {
                        cond = @intFromBool(fltvalue(s2v(ra)) == @as(lua_Number, @floatFromInt(im)));
                    } else {
                        cond = 0;
                    }
                    docondjump(&pc, ci, i, cond, &trap);
                },

                OP_LTI => {
                    op_orderI(L, ci, base, i, &pc, &trap, true, false, @as(TMS, @bitCast(TM_LT)));
                },
                OP_LEI => {
                    op_orderI(L, ci, base, i, &pc, &trap, false, false, @as(TMS, @bitCast(TM_LE)));
                },
                OP_GTI => {
                    op_orderI(L, ci, base, i, &pc, &trap, true, true, @as(TMS, @bitCast(TM_LT)));
                },
                OP_GEI => {
                    op_orderI(L, ci, base, i, &pc, &trap, false, true, @as(TMS, @bitCast(TM_LE)));
                },

                OP_TEST => {
                    const ra = RA(base, i);
                    const cond: c_int = @intFromBool(!l_isfalse(s2v(ra)));
                    docondjump(&pc, ci, i, cond, &trap);
                },

                OP_TESTSET => {
                    const ra = RA(base, i);
                    const rb = vRB(base, i);
                    if (@intFromBool(l_isfalse(rb)) == GETARG_k(i)) {
                        pc += 1;
                    } else {
                        setobj2s(L, ra, rb);
                        // donextjump
                        const ni: Instruction = pc[0];
                        pc = stkid_to_pc(pc, GETARG_sJ(ni) + 1);
                        trap = ci.*.u.l.trap;
                    }
                },

                OP_CALL => {
                    const ra = RA(base, i);
                    const b: c_int = GETARG_B(i);
                    const nresults: c_int = GETARG_C(i) - 1;
                    if (b != 0)
                        L.*.top.p = ra + @as(usize, @intCast(b));
                    // savepc
                    ci.*.u.l.savedpc = pc;
                    const newci = luaD_precall(L, ra, nresults);
                    if (newci == null) {
                        // C call; nothing else to do
                        trap = ci.*.u.l.trap;
                    } else {
                        ci = newci;
                        continue :startfunc;
                    }
                },

                OP_TAILCALL => {
                    const ra = RA(base, i);
                    var b: c_int = GETARG_B(i);
                    const nparams1: c_int = GETARG_C(i);
                    const delta: c_int = if (nparams1 != 0) ci.*.u.l.nextraargs + nparams1 else 0;
                    if (b != 0)
                        L.*.top.p = ra + @as(usize, @intCast(b))
                    else
                        b = @as(c_int, @intCast(@divExact(@intFromPtr(L.*.top.p) - @intFromPtr(ra), @sizeOf(StackValue))));
                    // savepc(ci)
                    ci.*.u.l.savedpc = pc;
                    if (TESTARG_k(i)) {
                        luaF_closeupval(L, base);
                    }
                    const n: c_int = luaD_pretailcall(L, ci, ra, b, delta);
                    if (n < 0) {
                        // Lua function — execute callee
                        continue :startfunc;
                    } else {
                        // C function
                        ci.*.func.p = stkid_add(ci.*.func.p, -delta);
                        luaD_poscall(L, ci, n);
                        trap = ci.*.u.l.trap;
                        // goto ret
                        { if ((ci.*.callstatus & CIST_FRESH) != 0) return; ci = ci.*.previous; go_returning = true; continue :startfunc; }
                    }
                },

                OP_RETURN => {
                    const ra = RA(base, i);
                    var n: c_int = GETARG_B(i) - 1;
                    const nparams1: c_int = GETARG_C(i);
                    if (n < 0) // not fixed?
                        n = @as(c_int, @intCast(@divExact(@intFromPtr(L.*.top.p) - @intFromPtr(ra), @sizeOf(StackValue))));
                    ci.*.u.l.savedpc = pc;
                    if (TESTARG_k(i)) {
                        ci.*.u2.nres = n;
                        if (@intFromPtr(L.*.top.p) < @intFromPtr(ci.*.top.p))
                            L.*.top.p = ci.*.top.p;
                        _ = luaF_close(L, base, CLOSEKTOP, 1);
                        trap = ci.*.u.l.trap;
                        // updatestack
                        if (trap != 0) {
                            base = ci.*.func.p + @as(usize, 1);
                        }
                    }
                    if (nparams1 != 0) {
                        ci.*.func.p = stkid_add(ci.*.func.p, -@as(c_int, ci.*.u.l.nextraargs + nparams1));
                    }
                    L.*.top.p = ra + @as(usize, @intCast(n));
                    luaD_poscall(L, ci, n);
                    trap = ci.*.u.l.trap;
                    { if ((ci.*.callstatus & CIST_FRESH) != 0) return; ci = ci.*.previous; go_returning = true; continue :startfunc; }
                },

                OP_RETURN0 => {
                    if (L.*.hookmask != 0) {
                        const ra = RA(base, i);
                        L.*.top.p = ra;
                        ci.*.u.l.savedpc = pc;
                        luaD_poscall(L, ci, 0);
                        trap = 1;
                    } else {
                        var nres: c_int = ci.*.nresults;
                        L.*.ci = ci.*.previous;
                        L.*.top.p = base - @as(usize, 1);
                        while (nres > 0) : (nres -= 1) {
                            setnilvalue(s2v(L.*.top.p));
                            L.*.top.p += 1;
                        }
                    }
                    { if ((ci.*.callstatus & CIST_FRESH) != 0) return; ci = ci.*.previous; go_returning = true; continue :startfunc; }
                },

                OP_RETURN1 => {
                    if (L.*.hookmask != 0) {
                        const ra = RA(base, i);
                        L.*.top.p = ra + @as(usize, 1);
                        ci.*.u.l.savedpc = pc;
                        luaD_poscall(L, ci, 1);
                        trap = 1;
                    } else {
                        var nres: c_int = ci.*.nresults;
                        L.*.ci = ci.*.previous;
                        if (nres == 0) {
                            L.*.top.p = base - @as(usize, 1);
                        } else {
                            const ra = RA(base, i);
                            setobjs2s(L, base - @as(usize, 1), ra);
                            L.*.top.p = base;
                            nres -= 1;
                            while (nres > 0) : (nres -= 1) {
                                setnilvalue(s2v(L.*.top.p));
                                L.*.top.p += 1;
                            }
                        }
                    }
                    // ret: label — return from Lua function
                    { if ((ci.*.callstatus & CIST_FRESH) != 0) return; ci = ci.*.previous; go_returning = true; continue :startfunc; }
                },

                OP_FORLOOP => {
                    const ra = RA(base, i);
                    if (ttisinteger(s2v(ra + @as(usize, 2)))) {
                        const count: lua_Unsigned = @as(lua_Unsigned, @bitCast(ivalue(s2v(ra + @as(usize, 1)))));
                        if (count > 0) {
                            const step: lua_Integer = ivalue(s2v(ra + @as(usize, 2)));
                            const idx = intop_add(ivalue(s2v(ra)), step);
                            chgivalue(s2v(ra + @as(usize, 1)), @as(lua_Integer, @bitCast(count - 1)));
                            chgivalue(s2v(ra), idx);
                            setivalue(s2v(ra + @as(usize, 3)), idx);
                            pc = stkid_to_pc(pc, -@as(c_int, @intCast(GETARG_Bx(i))));
                        }
                    } else if (floatforloop(ra) != 0) {
                        pc = stkid_to_pc(pc, -@as(c_int, @intCast(GETARG_Bx(i))));
                    }
                    trap = ci.*.u.l.trap;
                },

                OP_FORPREP => {
                    const ra = RA(base, i);
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    if (forprep(L, ra) != 0) {
                        pc = stkid_to_pc(pc, GETARG_Bx(i) + 1);
                    }
                },

                OP_TFORPREP => {
                    var ra = RA(base, i);
                    // halfProtect
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaF_newtbcupval(L, ra + @as(usize, 3));
                    pc = stkid_to_pc(pc, GETARG_Bx(i));
                    const instr2: Instruction = pc[0];
                    pc += 1;
                    // goto l_tforcall — fall through
                    ra = RA(base, instr2);
                    // l_tforcall body
                    _ = memcpy(@as(?*anyopaque, @ptrCast(ra + @as(usize, 4))), @as(?*const anyopaque, @ptrCast(ra)), 3 * @sizeOf(StackValue));
                    L.*.top.p = ra + @as(usize, 4 + 3);
                    ci.*.u.l.savedpc = pc;
                    luaD_call(L, ra + @as(usize, 4), GETARG_C(instr2));
                    trap = ci.*.u.l.trap;
                    // updatestack
                    if (trap != 0) {
                        base = ci.*.func.p + @as(usize, 1);
                        ra = RA(base, instr2);
                    }
                    const instr3: Instruction = pc[0];
                    pc += 1;
                    // l_tforloop body
                    if (!ttisnil(s2v(ra + @as(usize, 4)))) {
                        setobjs2s(L, ra + @as(usize, 2), ra + @as(usize, 4));
                        pc = stkid_to_pc(pc, -@as(c_int, @intCast(GETARG_Bx(instr3))));
                    }
                },

                OP_TFORCALL => {
                    var ra = RA(base, i);
                    _ = memcpy(@as(?*anyopaque, @ptrCast(ra + @as(usize, 4))), @as(?*const anyopaque, @ptrCast(ra)), 3 * @sizeOf(StackValue));
                    L.*.top.p = ra + @as(usize, 4 + 3);
                    ci.*.u.l.savedpc = pc;
                    luaD_call(L, ra + @as(usize, 4), GETARG_C(i));
                    trap = ci.*.u.l.trap;
                    if (trap != 0) {
                        base = ci.*.func.p + @as(usize, 1);
                        ra = RA(base, i);
                    }
                    const instr2: Instruction = pc[0];
                    pc += 1;
                    // l_tforloop
                    if (!ttisnil(s2v(ra + @as(usize, 4)))) {
                        setobjs2s(L, ra + @as(usize, 2), ra + @as(usize, 4));
                        pc = stkid_to_pc(pc, -@as(c_int, @intCast(GETARG_Bx(instr2))));
                    }
                },

                OP_TFORLOOP => {
                    const ra = RA(base, i);
                    if (!ttisnil(s2v(ra + @as(usize, 4)))) {
                        setobjs2s(L, ra + @as(usize, 2), ra + @as(usize, 4));
                        pc = stkid_to_pc(pc, -@as(c_int, @intCast(GETARG_Bx(i))));
                    }
                },

                OP_SETLIST => {
                    const ra = RA(base, i);
                    var n: c_int = GETARG_B(i);
                    var last: c_uint = @as(c_uint, @intCast(GETARG_C(i)));
                    const h: [*c]Table = hvalue(s2v(ra));
                    if (n == 0)
                        n = @as(c_int, @intCast(@divExact(@intFromPtr(L.*.top.p) - @intFromPtr(ra), @sizeOf(StackValue)))) - 1
                    else
                        L.*.top.p = ci.*.top.p;
                    last += @as(c_uint, @intCast(n));
                    if (TESTARG_k(i)) {
                        last += @as(c_uint, @intCast(GETARG_Ax(pc[0]))) * (@as(c_uint, MAXARG_C) + 1);
                        pc += 1;
                    }
                    if (last > luaH_realasize(h))
                        luaH_resizearray(L, h, last);
                    {
                        var nn = n;
                        while (nn > 0) : (nn -= 1) {
                            const val: [*c]TValue = s2v(ra + @as(usize, @intCast(nn)));
                            setobj2t(L, h.*.array + @as(usize, @intCast(last - 1)), val);
                            last -= 1;
                            // luaC_barrierback
                            if (iscollectable(val)) {
                                const obj_gc = &@as([*c]union_GCUnion, @ptrCast(@alignCast(h))).*.gc;
                                const v_gc = gcvalue(val);
                                if (((@as(c_int, @bitCast(@as(c_uint, obj_gc.*.marked))) & (1 << BLACKBIT)) != 0) and
                                    ((@as(c_int, @bitCast(@as(c_uint, v_gc.*.marked))) & WHITEBITS) != 0))
                                {
                                    luaC_barrierback_(L, obj_gc);
                                }
                            }
                        }
                    }
                },

                OP_CLOSURE => {
                    const ra = RA(base, i);
                    const p = cl.*.p.*.p[@as(usize, @intCast(GETARG_Bx(i)))];
                    // halfProtect
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    if (vm_trace) earlyPutc('{');
                    pushclosure(L, p, @as([*c][*c]UpVal, @ptrCast(&cl.*.upvals)), base, ra);
                    if (vm_trace) earlyPutc('}');
                    checkGC(L, ci, pc, ra + @as(usize, 1), &trap);
                    if (vm_trace) earlyPutc('!');
                },

                OP_VARARG => {
                    const ra = RA(base, i);
                    const n: c_int = GETARG_C(i) - 1;
                    ci.*.u.l.savedpc = pc;
                    L.*.top.p = ci.*.top.p;
                    luaT_getvarargs(L, ci, ra, n);
                    trap = ci.*.u.l.trap;
                },

                OP_VARARGPREP => {
                    // ProtectNT
                    ci.*.u.l.savedpc = pc;
                    luaT_adjustvarargs(L, GETARG_A(i), ci, cl.*.p);
                    trap = ci.*.u.l.trap;
                    if (trap != 0) {
                        luaD_hookcall(L, ci);
                        L.*.oldpc = 1;
                    }
                    // updatebase
                    base = ci.*.func.p + @as(usize, 1);
                },

                OP_EXTRAARG => {
                    // lua_assert(0)
                },

                else => {},
            }
        }
    }

    // unreachable — startfunc loop never breaks (ret is handled inside)
    unreachable;
}
