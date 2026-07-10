const std = @import("std");
pub const String = []const u8;

pub fn linkPkgConfig(step: *std.Build.Step.Compile, name: []const u8) void {
    const b = step.step.owner;
    const pkg_config = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    if (std.process.Child.run(.{ .allocator = b.graph.arena, .argv = &.{ pkg_config, "--cflags", name } })) |result| {
        if (result.term == .Exited and result.term.Exited == 0)
            parsePkgConfigCflags(step, result.stdout);
    } else |_| {}
    if (std.process.Child.run(.{ .allocator = b.graph.arena, .argv = &.{ pkg_config, "--libs", name } })) |result| {
        if (result.term == .Exited and result.term.Exited == 0) {
            var it = std.mem.tokenizeScalar(u8, std.mem.trim(u8, result.stdout, &std.ascii.whitespace), ' ');
            while (it.next()) |flag| {
                if (std.mem.startsWith(u8, flag, "-L")) step.addLibraryPath(.{ .cwd_relative = flag[2..] })
                else if (std.mem.startsWith(u8, flag, "-l")) step.root_module.linkSystemLibrary(flag[2..], .{ .use_pkg_config = .no });
            }
        }
    } else |_| {}
}

pub fn addPkgConfigCflags(step: *std.Build.Step.Compile, name: []const u8) void {
    const b = step.step.owner;
    const pkg_config = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    if (std.process.Child.run(.{ .allocator = b.graph.arena, .argv = &.{ pkg_config, "--cflags", name } })) |result| {
        if (result.term == .Exited and result.term.Exited == 0)
            parsePkgConfigCflags(step, result.stdout);
    } else |_| {}
}

fn parsePkgConfigCflags(step: *std.Build.Step.Compile, stdout: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, std.mem.trim(u8, stdout, &std.ascii.whitespace), ' ');
    while (it.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I")) {
            step.addSystemIncludePath(.{ .cwd_relative = flag[2..] });
        } else if (std.mem.startsWith(u8, flag, "-D")) {
            const def = flag[2..];
            const name_end = std.mem.indexOfScalar(u8, def, '=') orelse def.len;
            if (std.mem.eql(u8, def[0..name_end], "_GNU_SOURCE")) continue;
            if (name_end < def.len) step.root_module.addCMacro(def[0..name_end], def[name_end + 1 ..]) else step.root_module.addCMacro(def, "");
        }
    }
}

pub fn getPkgConfigVariable(b: *std.Build, pkg_name: []const u8, variable: []const u8) ?[]const u8 {
    const pkg_config = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    if (std.process.Child.run(.{ .allocator = b.graph.arena, .argv = &.{ pkg_config, b.fmt("--variable={s}", .{variable}), pkg_name } })) |result| {
        if (result.term == .Exited and result.term.Exited == 0) {
            const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
            if (trimmed.len > 0) return trimmed;
        }
    } else |_| {}
    return null;
}

/// Run pkg-config --cflags at configure time for multiple packages and return split flags.
pub fn getPkgConfigCflags(b: *std.Build, pkgs: []const String) ?[]const []const u8 {
    const a = b.allocator;
    var argv_list: std.ArrayList([]const u8) = .{};
    argv_list.append(a, "pkg-config") catch return null;
    argv_list.append(a, "--cflags") catch return null;
    for (pkgs) |pkg| argv_list.append(a, pkg) catch return null;
    const result = std.process.Child.run(.{ .allocator = a, .argv = argv_list.items }) catch return null;
    const trimmed = std.mem.trim(u8, result.stdout, " \t\n\r");
    if (trimmed.len == 0) return &.{};
    var flags: std.ArrayList([]const u8) = .{};
    var iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
    while (iter.next()) |flag| flags.append(a, flag) catch return null;
    return flags.toOwnedSlice(a) catch return null;
}

/// Compile a single C++ file with system g++ and add the resulting .o to the exe.
pub fn addGppCppFile(
    b: *std.Build, exe: *std.Build.Step.Compile,
    root: std.Build.LazyPath, file: []const u8,
    flags: []const String, include_dirs: []const std.Build.LazyPath,
    pkg_cflags: []const []const u8,
) void {
    const cmd = b.addSystemCommand(&.{"g++"});
    cmd.addArgs(flags);
    for (include_dirs) |dir| cmd.addPrefixedDirectoryArg("-I", dir);
    cmd.addArgs(pkg_cflags);
    cmd.addArg("-c");
    cmd.addFileArg(root.path(b, file));
    cmd.addArg("-o");
    const obj = cmd.addOutputFileArg(b.fmt("{s}.o", .{file}));
    exe.addObjectFile(obj);
}
