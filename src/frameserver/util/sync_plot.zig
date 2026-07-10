// Zig port of sync_plot.c -- synchronization timing visualization
// Copyright 2012-2016, Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: http://arcan-fe.com

const std = @import("std");
const c = @import("shmif_types");

const graph_buffer_size = 160;

pub const SynchState = enum(c_int) {
    none = 0,
    overlay = 1,
    independent = 2,
};

pub const timestamp_t = u64;

const GraphInt = struct {
    cont: ?*c.arcan_shmif_cont = null,
    frametimes: [graph_buffer_size]timestamp_t = [_]timestamp_t{0} ** graph_buffer_size,
    framedrops: [graph_buffer_size]timestamp_t = [_]timestamp_t{0} ** graph_buffer_size,
    framexfer: [graph_buffer_size]timestamp_t = [_]timestamp_t{0} ** graph_buffer_size,
    xfercosts: [graph_buffer_size]u32 = [_]u32{0} ** graph_buffer_size,
    abufsizes: [graph_buffer_size]u32 = [_]u32{0} ** graph_buffer_size,
    ofs_time: usize = 0,
    ofs_drop: usize = 0,
    ofs_xfer: usize = 0,
    ofs_cost: usize = 0,
    ofs_abufsz: usize = 0,
};

/// Sync graphing context with function pointers for various operations.
/// This is a Zig equivalent of the C struct synch_graphing with function
/// pointer fields replaced by optional method pointers.
pub const SynchGraphing = struct {
    state: SynchState = .none,
    priv: ?*GraphInt = null,

    pub fn update(self: *SynchGraphing, period: f32, msg: []const u8) bool {
        _ = self;
        _ = period;
        _ = msg;
        // stub -- real implementation would render timing overlay
        return true;
    }

    pub fn markInput(self: *SynchGraphing, ts: timestamp_t) void {
        _ = self;
        _ = ts;
    }

    pub fn markDrop(self: *SynchGraphing, ts: timestamp_t) void {
        if (self.priv) |g| {
            g.framedrops[g.ofs_drop] = ts;
            g.ofs_drop = (g.ofs_drop + 1) % graph_buffer_size;
        }
    }

    pub fn markAbufSize(self: *SynchGraphing, size: u32) void {
        if (self.priv) |g| {
            g.abufsizes[g.ofs_abufsz] = size;
            g.ofs_abufsz = (g.ofs_abufsz + 1) % graph_buffer_size;
        }
    }

    pub fn markStart(self: *SynchGraphing, ts: timestamp_t) void {
        if (self.priv) |g| {
            g.frametimes[g.ofs_time] = ts;
            g.ofs_time = (g.ofs_time + 1) % graph_buffer_size;
        }
    }

    pub fn markStop(self: *SynchGraphing, ts: timestamp_t) void {
        _ = self;
        _ = ts;
        // stub
    }

    pub fn markTransfer(self: *SynchGraphing, when: timestamp_t, cost: u32) void {
        if (self.priv) |g| {
            g.framexfer[g.ofs_xfer] = when;
            g.xfercosts[g.ofs_xfer] = cost;
            g.ofs_xfer = (g.ofs_xfer + 1) % graph_buffer_size;
        }
    }

    pub fn contSwitch(self: *SynchGraphing, newcont: *c.arcan_shmif_cont) void {
        if (self.priv) |g| {
            g.cont = newcont;
        }
    }

    pub fn deinit(self: *SynchGraphing, allocator: std.mem.Allocator) void {
        if (self.priv) |g| {
            allocator.destroy(g);
            self.priv = null;
        }
    }
};

/// Set up a sync graphing context. If overlay is false, the context manages
/// its own segment; otherwise it overlays on the provided shmif_cont.
pub fn setupSynchGraph(
    cont: *c.arcan_shmif_cont,
    overlay: bool,
    allocator: std.mem.Allocator,
) ?*SynchGraphing {
    const g = allocator.create(GraphInt) catch return null;
    g.* = .{};
    g.cont = cont;

    const result = allocator.create(SynchGraphing) catch {
        allocator.destroy(g);
        return null;
    };
    result.* = .{
        .state = if (overlay) .overlay else .independent,
        .priv = g,
    };
    return result;
}

// C-compatible interface for the C code that may still reference these
// (the frameserver.zig chainloader, etc.)

const synch_graphing = extern struct {
    state: c_int = 0,
    update: ?*const fn (?*synch_graphing, f32, [*c]const u8) callconv(.c) bool = null,
    mark_input: ?*const fn (?*synch_graphing, timestamp_t) callconv(.c) void = null,
    mark_drop: ?*const fn (?*synch_graphing, timestamp_t) callconv(.c) void = null,
    mark_abuf_size: ?*const fn (?*synch_graphing, c_uint) callconv(.c) void = null,
    mark_start: ?*const fn (?*synch_graphing, timestamp_t) callconv(.c) void = null,
    mark_stop: ?*const fn (?*synch_graphing, timestamp_t) callconv(.c) void = null,
    mark_cost: ?*const fn (?*synch_graphing, c_uint) callconv(.c) void = null,
    mark_transfer: ?*const fn (?*synch_graphing, timestamp_t, c_uint) callconv(.c) void = null,
    free_fn: ?*const fn (?*?*synch_graphing) callconv(.c) void = null,
    cont_switch: ?*const fn (?*synch_graphing, ?*c.arcan_shmif_cont) callconv(.c) void = null,
    priv: ?*anyopaque = null,
};

// Stub C-compatible entry point
export fn setup_synch_graph(cont: ?*c.arcan_shmif_cont, overlay: bool) ?*synch_graphing {
    _ = cont;
    _ = overlay;
    // stub -- return null for now, the Zig SynchGraphing is the preferred interface
    return null;
}
