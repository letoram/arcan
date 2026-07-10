// Zig reimplementation of arcan_shmif_mousestate.c
// Drop-in C-ABI-compatible replacement for mousestate functions.
//
// Exports: arcan_shmif_mousestate_setup, arcan_shmif_mousestate,
//          arcan_shmif_mousestate_ioev
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

export fn arcan_shmif_mousestate_setup(
    con: ?*c.struct_arcan_shmif_cont,
    flags: c_int,
    state: ?[*]u8,
) void {
    if (is_freestanding) return;
    if (con == null) return;
    const con_v = con.?;
    if (con_v.priv == null) return;

    var ms: *anyopaque = undefined;
    if (state) |s| {
        ms = @ptrCast(@alignCast(s));
    } else {
        ms = off.Hidden.getMstatePtr(@ptrCast(@alignCast(con_v.priv)));
    }

    off.Mstate.zeroMstate(ms);
    const noclamp_mask: c_int = c.ARCAN_MOUSESTATE_NOCLAMP;
    off.Mstate.setRel(ms, @intFromBool((flags & ~noclamp_mask) > 0));
    off.Mstate.setNoclamp(ms, @intFromBool((flags & noclamp_mask) != 0));
}

/// Clamp absolute coordinates and update history.
/// Returns true if position changed since last sample.
fn absclamp(
    ms: *anyopaque,
    con: *c.struct_arcan_shmif_cont,
    out_x: *c_int,
    out_y: *c_int,
) bool {
    const cw: i32 = @intCast(con.w);
    const ch: i32 = @intCast(con.h);

    if (off.Mstate.getAx(ms) < 0 and off.Mstate.getNoclamp(ms) == 0)
        off.Mstate.setAx(ms, 0)
    else if (off.Mstate.getAx(ms) > cw and off.Mstate.getNoclamp(ms) == 0)
        off.Mstate.setAx(ms, cw);

    if (off.Mstate.getAy(ms) < 0 and off.Mstate.getNoclamp(ms) == 0)
        off.Mstate.setAy(ms, 0)
    else if (off.Mstate.getAy(ms) > ch and off.Mstate.getNoclamp(ms) == 0)
        off.Mstate.setAy(ms, ch);

    // with clamping, we can get relative samples that shouldn't
    // propagate, so test that before updating history
    const res = off.Mstate.getLy(ms) != off.Mstate.getAy(ms) or off.Mstate.getLx(ms) != off.Mstate.getAx(ms);
    off.Mstate.setLy(ms, off.Mstate.getAy(ms));
    out_y.* = off.Mstate.getLy(ms);
    off.Mstate.setLx(ms, off.Mstate.getAx(ms));
    out_x.* = off.Mstate.getLx(ms);

    return res;
}

export fn arcan_shmif_mousestate(
    con: ?*c.struct_arcan_shmif_cont,
    state: ?[*]u8,
    inev: ?*c.arcan_event,
    out_x: ?*c_int,
    out_y: ?*c_int,
) bool {
    if (is_freestanding) return false;
    if (inev) |ev| {
        return arcan_shmif_mousestate_ioev(con, state, ev.io(), out_x, out_y);
    }
    return arcan_shmif_mousestate_ioev(con, state, null, out_x, out_y);
}

// Weak attempt of trying to bring some order in the accumulated mouse
// event handling chaos - definitely one of the bigger design fails that
// can't be fixed easily due to legacy.
export fn arcan_shmif_mousestate_ioev(
    con: ?*c.struct_arcan_shmif_cont,
    state: ?[*]u8,
    inev: ?*c.arcan_ioevent,
    out_x: ?*c_int,
    out_y: ?*c_int,
) bool {
    if (is_freestanding) return false;
    if (con == null) return false;
    const con_v = con.?;
    if (con_v.priv == null) return false;

    var ms: *anyopaque = undefined;
    if (state) |s| {
        ms = @ptrCast(@alignCast(s));
    } else {
        ms = off.Hidden.getMstatePtr(@ptrCast(@alignCast(con_v.priv)));
    }

    const ox = out_x orelse return false;
    const oy = out_y orelse return false;

    if (inev == null) {
        if (off.Mstate.getInrel(ms) == 0)
            return absclamp(ms, con_v, ox, oy)
        else {
            ox.* = 0;
            oy.* = 0;
        }
        return true;
    }

    const ev = inev.?;

    if (ev.datatype != c.EVENT_IDATATYPE_ANALOG or
        ev.devkind != c.EVENT_IDEVKIND_MOUSE)
        return false;

    // state switched between samples, reset tracking
    const gotrel: u8 = if (ev.input.analog.gotrel != 0) 1 else 0;
    if (gotrel != off.Mstate.getInrel(ms)) {
        off.Mstate.setInrel(ms, gotrel);
        off.Mstate.setAx(ms, 0);
        off.Mstate.setAy(ms, 0);
        off.Mstate.setLx(ms, 0);
        off.Mstate.setLy(ms, 0);
    }

    const subid = ev.unnamed_0.unnamed_0.subid;

    // packed, both axes in one sample
    if (subid == 2) {
        if (gotrel != 0) {
            // relative input sample
            if (off.Mstate.getRel(ms) != 0) {
                // good case, the sample is already what we want
                off.Mstate.setLx(ms,ev.input.analog.axisval[0]);
                ox.* = off.Mstate.getLx(ms);
                off.Mstate.setLy(ms,ev.input.analog.axisval[2]);
                oy.* = off.Mstate.getLy(ms);
                return ox.* != 0 or oy.* != 0;
            }
            // bad case, the sample is relative and we want absolute,
            // accumulate and clamp
            off.Mstate.setAx(ms,off.Mstate.getAx(ms) + ev.input.analog.axisval[0]);
            off.Mstate.setAy(ms,off.Mstate.getAy(ms) + ev.input.analog.axisval[2]);
            return absclamp(ms, con_v, ox, oy);
        } else {
            // good case, the sample is absolute and we want absolute, clamp
            if (off.Mstate.getRel(ms) == 0) {
                off.Mstate.setAx(ms,ev.input.analog.axisval[0]);
                off.Mstate.setAy(ms,ev.input.analog.axisval[2]);
                return absclamp(ms, con_v, ox, oy);
            }
            // worst case, the sample is absolute and we want relative,
            // need history AND discard large jumps
            const dx = ev.input.analog.axisval[0] - off.Mstate.getLx(ms);
            const dy = ev.input.analog.axisval[2] - off.Mstate.getLy(ms);
            off.Mstate.setLx(ms,ev.input.analog.axisval[0]);
            off.Mstate.setLy(ms,ev.input.analog.axisval[2]);
            if (dx == 0 and dy == 0) {
                return false;
            }
            ox.* = dx;
            oy.* = dy;
            return true;
        }
    }

    // one sample, X axis
    else if (subid == 0) {
        if (gotrel != 0) {
            if (off.Mstate.getRel(ms) != 0) {
                off.Mstate.setLx(ms,ev.input.analog.axisval[0]);
                ox.* = off.Mstate.getLx(ms);
                return ox.* != 0;
            }
            off.Mstate.setAx(ms,off.Mstate.getAx(ms) + ev.input.analog.axisval[0]);
            return absclamp(ms, con_v, ox, oy);
        } else {
            if (off.Mstate.getRel(ms) == 0) {
                off.Mstate.setAx(ms,ev.input.analog.axisval[0]);
                return absclamp(ms, con_v, ox, oy);
            }
            const dx = ev.input.analog.axisval[0] - off.Mstate.getLx(ms);
            off.Mstate.setLx(ms,ev.input.analog.axisval[0]);
            if (dx == 0)
                return false;
            ox.* = dx;
            oy.* = 0;
            return true;
        }
    }

    // one sample, Y axis
    else if (subid == 1) {
        if (gotrel != 0) {
            if (off.Mstate.getRel(ms) != 0) {
                off.Mstate.setLy(ms,ev.input.analog.axisval[0]);
                oy.* = off.Mstate.getLy(ms);
                return oy.* != 0;
            }
            off.Mstate.setAy(ms,off.Mstate.getAy(ms) + ev.input.analog.axisval[0]);
            return absclamp(ms, con_v, ox, oy);
        } else {
            if (off.Mstate.getRel(ms) == 0) {
                off.Mstate.setAy(ms,ev.input.analog.axisval[0]);
                return absclamp(ms, con_v, ox, oy);
            }
            const dy = ev.input.analog.axisval[0] - off.Mstate.getLy(ms);
            off.Mstate.setLy(ms,ev.input.analog.axisval[0]);
            if (dy == 0)
                return false;
            ox.* = 0;
            oy.* = dy;
            return true;
        }
    } else {
        return false;
    }
}
