//! callgraph — Static call graph extractor using Zig's built-in AST parser
//!
//! Parses .zig source files with std.zig.Ast and extracts function declarations
//! and call expressions. Outputs DOT (graphviz) or JSON for use in graph tools.
//!
//! Usage:
//!   zig build callgraph && ./zig-out/bin/callgraph [OPTIONS] [FILES...]
//!
//! Examples:
//!   callgraph --scan | dot -Tsvg > callgraph.svg
//!   callgraph --scan --json | jq . > callgraph.json
//!   callgraph --scan --no-c | dot -Tpng > callgraph.png
//!   callgraph src/engine/arcan_video.zig src/engine/arcan_event.zig

const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const Allocator = std.mem.Allocator;

// Types

const FuncDecl = struct {
    name: []const u8,
    file: []const u8,
    qualified: []const u8, // "file:name"
    is_export: bool,
    is_pub: bool,
};

const CallEdge = struct {
    from: []const u8, // qualified caller
    to: []const u8, // raw callee ("foo", "c.bar", "std.mem.eql")
};

const FnRange = struct {
    qualified: []const u8,
    lo: u32,
    hi: u32,
};

const FileList = std.ArrayList([]const u8);
const FuncList = std.ArrayList(FuncDecl);
const EdgeList = std.ArrayList(CallEdge);
const RangeList = std.ArrayList(FnRange);
const OutBuf = std.ArrayList(u8);

// Main

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var files: FileList = .empty;
    defer files.deinit(alloc);

    var json_mode = false;
    var no_c = false;
    var with_std = false;
    var exports_only = false;

    const scan_dirs = [_][]const u8{ "src/engine", "src/platform", "src/shmif" };

    var ai: usize = 1;
    while (ai < args.len) : (ai += 1) {
        const a = args[ai];
        if (eql(a, "--json")) {
            json_mode = true;
        } else if (eql(a, "--no-c")) {
            no_c = true;
        } else if (eql(a, "--with-std")) {
            with_std = true;
        } else if (eql(a, "--exports-only")) {
            exports_only = true;
        } else if (eql(a, "--scan")) {
            for (scan_dirs) |d| try scanDir(alloc, d, &files);
        } else if (eql(a, "--help") or eql(a, "-h")) {
            return usage();
        } else {
            try files.append(alloc, a);
        }
    }

    // Default: scan src/
    if (files.items.len == 0) {
        for (scan_dirs) |d| try scanDir(alloc, d, &files);
    }

    var funcs: FuncList = .empty;
    defer funcs.deinit(alloc);
    var edges: EdgeList = .empty;
    defer edges.deinit(alloc);

    for (files.items) |path| {
        processFile(alloc, path, &funcs, &edges) catch |err| {
            std.debug.print("warn: {s}: {}\n", .{ path, err });
        };
    }

    // Build name → qualified lookup (first definition wins)
    var name_map = std.StringHashMap([]const u8).init(alloc);
    defer name_map.deinit();
    for (funcs.items) |f| {
        _ = try name_map.getOrPutValue(f.name, f.qualified);
    }

    // Render to buffer, then write to stdout
    var out: OutBuf = .empty;
    defer out.deinit(alloc);

    if (json_mode)
        try emitJson(alloc, &out, funcs.items, edges.items, &name_map, no_c, with_std, exports_only)
    else
        try emitDot(alloc, &out, funcs.items, edges.items, &name_map, no_c, with_std, exports_only);

    try std.fs.File.stdout().writeAll(out.items);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn usage() void {
    std.fs.File.stdout().writeAll(
        \\callgraph — Zig call graph extractor (uses std.zig.Ast)
        \\
        \\Usage: callgraph [OPTIONS] [FILES...]
        \\
        \\  --scan          Scan src/{engine,platform,shmif} recursively
        \\  --json          JSON output (default: DOT/graphviz)
        \\  --no-c          Exclude C interop calls (c.*)
        \\  --with-std      Include std.* calls
        \\  --exports-only  Only exported/pub functions
        \\  --help          This message
        \\
        \\Examples:
        \\  callgraph --scan | dot -Tsvg > callgraph.svg
        \\  callgraph --scan --json > callgraph.json
        \\  callgraph src/engine/arcan_video.zig | dot -Tpng > video.png
        \\
    ) catch {};
}

// Directory scanning

fn scanDir(alloc: Allocator, base: []const u8, files: *FileList) !void {
    var dir = std.fs.cwd().openDir(base, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ base, entry.name });
        switch (entry.kind) {
            .directory => {
                try scanDir(alloc, path, files);
            },
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".zig") and
                    !std.mem.endsWith(u8, entry.name, "_test.zig"))
                {
                    try files.append(alloc, path);
                } else {
                    alloc.free(path);
                }
            },
            else => alloc.free(path),
        }
    }
}

// AST processing

fn readFileZ(alloc: Allocator, path: []const u8) ![:0]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size: usize = @intCast(try file.getEndPos());
    const buf = try alloc.allocSentinel(u8, size, 0);
    _ = try file.readAll(buf);
    return buf;
}

fn processFile(
    alloc: Allocator,
    path: []const u8,
    funcs: *FuncList,
    edges: *EdgeList,
) !void {
    const src = try readFileZ(alloc, path);
    defer alloc.free(src);

    var tree = try Ast.parse(alloc, src, .zig);
    defer tree.deinit(alloc);

    const n_nodes = tree.nodes.items(.tag).len;
    const sp = shortPath(path);

    // Phase 1: collect fn_decl nodes with token ranges
    var ranges: RangeList = .empty;
    defer ranges.deinit(alloc);

    for (0..n_nodes) |i| {
        const node: Node.Index = @enumFromInt(i);
        if (tree.nodeTag(node) != .fn_decl) continue;

        var buf: [1]Node.Index = undefined;
        const proto = tree.fullFnProto(&buf, node) orelse continue;
        const name_tok = proto.name_token orelse continue;
        const name = try alloc.dupe(u8, tree.tokenSlice(name_tok));

        const is_exp = if (proto.extern_export_inline_token) |t|
            tree.tokenTag(t) == .keyword_export
        else
            false;

        const qualified = try std.fmt.allocPrint(alloc, "{s}:{s}", .{ sp, name });

        try funcs.append(alloc, .{
            .name = name,
            .file = path,
            .qualified = qualified,
            .is_export = is_exp,
            .is_pub = proto.visib_token != null,
        });
        try ranges.append(alloc, .{
            .qualified = qualified,
            .lo = tree.firstToken(node),
            .hi = tree.lastToken(node),
        });
    }

    // Phase 2: find call expressions and map to containing functions
    for (0..n_nodes) |i| {
        const node: Node.Index = @enumFromInt(i);
        var buf: [1]Node.Index = undefined;
        const call = tree.fullCall(&buf, node) orelse continue;
        const callee = resolveCallee(alloc, &tree, call.ast.fn_expr) catch continue;
        if (callee.len == 0) continue;

        const tok = tree.nodeMainToken(node);
        const caller = findOwner(ranges.items, tok) orelse continue;

        try edges.append(alloc, .{ .from = caller, .to = callee });
    }
}

fn resolveCallee(alloc: Allocator, tree: *const Ast, node: Node.Index) ![]const u8 {
    return switch (tree.nodeTag(node)) {
        .identifier => try alloc.dupe(u8, tree.tokenSlice(tree.nodeMainToken(node))),
        .field_access => blk: {
            const data = tree.nodeData(node).node_and_token;
            const obj = try resolveCallee(alloc, tree, data[0]);
            const fld = tree.tokenSlice(data[1]);
            break :blk try std.fmt.allocPrint(alloc, "{s}.{s}", .{ obj, fld });
        },
        else => "",
    };
}

fn findOwner(ranges: []const FnRange, tok: u32) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_span: u32 = std.math.maxInt(u32);
    for (ranges) |r| {
        if (tok >= r.lo and tok <= r.hi) {
            const span = r.hi - r.lo;
            if (span < best_span) {
                best_span = span;
                best = r.qualified;
            }
        }
    }
    return best;
}

fn shortPath(p: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, p, "src/")) p[4..] else p;
}

// DOT output

fn emitDot(
    alloc: Allocator,
    out: *OutBuf,
    funcs: []const FuncDecl,
    edges: []const CallEdge,
    name_map: *const std.StringHashMap([]const u8),
    no_c: bool,
    with_std: bool,
    exports_only: bool,
) !void {
    const w = out.writer(alloc);

    try w.writeAll("digraph arcan {\n");
    try w.writeAll("  rankdir=LR;\n");
    try w.writeAll("  node [fontname=\"monospace\", fontsize=9];\n");
    try w.writeAll("  edge [arrowsize=0.7, color=\"#888888\"];\n\n");

    // Group functions by file → subgraph clusters
    var groups = std.StringArrayHashMap(FuncList).init(alloc);
    defer {
        var it = groups.iterator();
        while (it.next()) |e| e.value_ptr.deinit(alloc);
        groups.deinit();
    }

    for (funcs) |f| {
        if (exports_only and !f.is_export and !f.is_pub) continue;
        const gop = try groups.getOrPut(shortPath(f.file));
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(alloc, f);
    }

    var ci: usize = 0;
    var git = groups.iterator();
    while (git.next()) |ent| {
        try w.print("  subgraph cluster_{d} {{\n", .{ci});
        try w.print("    label=\"{s}\";\n", .{ent.key_ptr.*});
        try w.writeAll("    style=filled; color=\"#cccccc\"; fillcolor=\"#f5f5f5\";\n");
        try w.writeAll("    fontname=\"monospace\"; fontsize=11;\n");

        for (ent.value_ptr.items) |f| {
            if (f.is_export) {
                try w.print("    \"{s}\" [label=\"{s}\", shape=box, style=filled, fillcolor=\"#4a90d9\", fontcolor=white];\n", .{ f.qualified, f.name });
            } else if (f.is_pub) {
                try w.print("    \"{s}\" [label=\"{s}\", shape=box, style=filled, fillcolor=\"#7ab648\", fontcolor=white];\n", .{ f.qualified, f.name });
            } else {
                try w.print("    \"{s}\" [label=\"{s}\", shape=ellipse];\n", .{ f.qualified, f.name });
            }
        }

        try w.writeAll("  }\n\n");
        ci += 1;
    }

    // Edges
    for (edges) |e| {
        if (no_c and std.mem.startsWith(u8, e.to, "c.")) continue;
        if (!with_std and std.mem.startsWith(u8, e.to, "std.")) continue;

        // Resolve plain callee names to qualified names
        const target = if (std.mem.indexOf(u8, e.to, ".") == null)
            name_map.get(e.to) orelse e.to
        else
            e.to;

        if (std.mem.startsWith(u8, e.to, "c.")) {
            try w.print("  \"{s}\" -> \"{s}\" [style=dashed, color=\"#cc4444\"];\n", .{ e.from, target });
        } else {
            try w.print("  \"{s}\" -> \"{s}\";\n", .{ e.from, target });
        }
    }

    try w.writeAll("}\n");
}

// JSON output

fn emitJson(
    alloc: Allocator,
    out: *OutBuf,
    funcs: []const FuncDecl,
    edges: []const CallEdge,
    name_map: *const std.StringHashMap([]const u8),
    no_c: bool,
    with_std: bool,
    exports_only: bool,
) !void {
    const w = out.writer(alloc);

    try w.writeAll("{\n  \"nodes\": [\n");
    var first = true;
    for (funcs) |f| {
        if (exports_only and !f.is_export and !f.is_pub) continue;
        if (!first) try w.writeAll(",\n");
        try w.print(
            "    {{\"id\":\"{s}\",\"name\":\"{s}\",\"file\":\"{s}\",\"export\":{},\"pub\":{}}}",
            .{ f.qualified, f.name, shortPath(f.file), f.is_export, f.is_pub },
        );
        first = false;
    }

    try w.writeAll("\n  ],\n  \"edges\": [\n");
    first = true;
    for (edges) |e| {
        if (no_c and std.mem.startsWith(u8, e.to, "c.")) continue;
        if (!with_std and std.mem.startsWith(u8, e.to, "std.")) continue;

        const target = if (std.mem.indexOf(u8, e.to, ".") == null)
            name_map.get(e.to) orelse e.to
        else
            e.to;

        if (!first) try w.writeAll(",\n");
        try w.print(
            "    {{\"from\":\"{s}\",\"to\":\"{s}\"}}",
            .{ e.from, target },
        );
        first = false;
    }

    try w.writeAll("\n  ]\n}\n");
}
