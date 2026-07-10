// Pure Zig port of engine/arcan_main.c — compositor entry point.
// Parses command-line args, initializes subsystems, enters main loop.

const std = @import("std");
const builtin = @import("builtin");

// Constants
const ARCAN_OK: c_int = 0;
const EXIT_SUCCESS: c_int = 0;
const EXIT_FAILURE: c_int = 1;
const BADFD: c_int = -1;
const ARCAN_VIMAGE_NOPOW2: c_int = 0;

// Lua recovery jump codes
const ARCAN_LUA_SWITCH_APPL: c_int = 1;
const ARCAN_LUA_SWITCH_APPL_NOADOPT: c_int = 2;
const ARCAN_LUA_RECOVERY_SWITCH: c_int = 3;
const ARCAN_LUA_RECOVERY_FATAL_IGNORE: c_int = 4;
const ARCAN_LUA_KILL_SILENT: c_int = 5;

// Trigger constants
const EP_TRIGGER_MAIN: c_int = 1 << 17;
const EP_TRIGGER_SHUTDOWN: c_int = 1 << 18;

// Namespace constants
const RESOURCE_APPL_SHARED: c_int = 4;
const RESOURCE_APPL_STATE: c_int = 8;
const RESOURCE_SYS_APPLBASE: c_int = 16;
const RESOURCE_SYS_APPLSTORE: c_int = 32;
const RESOURCE_SYS_FONT: c_int = 128;
// arcan_find_resource access flags (mirrors ARES_* in
// platform/platform_types.h; cf arcan_boot_compat.zig:1463-1474
// where the canonical constants live and the bug 0127 audit
// rationale is documented).
const ARES_FILE: c_uint = 1;
const ARES_RDONLY: c_uint = 512;
const RESOURCE_SYS_BINS: c_int = 256;
const RESOURCE_SYS_LIBS: c_int = 512;
const RESOURCE_SYS_DEBUG: c_int = 1024;
const RESOURCE_SYS_SCRIPTS: c_int = 2048;

// Memory allocation enums
const ARCAN_MEM_STRINGBUF: c_int = 5; // from arcan_mem.h enum (VBUFFER=1,VSTRUCT=2,EXTSTRUCT=3,ABUFFER=4,STRINGBUF=5)
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// SHMIF type
const SHMIF_INPUT: c_int = 1;

// sizeof jmp_buf (platform-dependent, aarch64 Linux = 312)
// Darwin arm64 sigjmp_buf is 392 bytes (49 longs); linux aarch64 is 312.
const JMPBUF_SIZE: usize = if (@import("builtin").os.tag.isDarwin()) 400 else 312;

// arcan_strarr
const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    data: [*c][*c]u8,
};

// getopt types
const option = extern struct {
    name: [*c]const u8,
    has_arg: c_int,
    flag: ?*c_int,
    val: c_int,
};

const no_argument: c_int = 0;
const required_argument: c_int = 1;

// opaque types
const arcan_luactx = anyopaque;
const arcan_dbh = anyopaque;
const arcan_evctx = anyopaque;
const lua_State = anyopaque;
const lua_Debug = anyopaque;
const arcan_shmif_cont = anyopaque;
const FILE = anyopaque;

// data_source / map_region
const data_source = extern struct {
    fd: c_int,
    start: c_long, // off_t
    len: c_long,
    source: [*c]u8,
};

const map_region = extern struct {
    ptr: [*c]u8,
    zbyte: u8,
    sz: usize,
    mmap: bool,
};

// Static state
var arr_hooks: arcan_strarr = std.mem.zeroes(arcan_strarr);

// These must be visible to other C files (arcan_monitor.c, arcan_conductor.c, arcan_lua.c)
// jmp_buf on aarch64-linux is 312 bytes with 8-byte alignment
export var arcanmain_recover_state: [JMPBUF_SIZE]u8 align(8) = undefined;
export var main_lua_context: ?*arcan_luactx = null;

// Extern C functions

// System
extern fn sysconf(name: c_int) c_long;
// Linux sysconf index 30; Darwin spells _SC_PAGESIZE = 29.
const _SC_PAGE_SIZE: c_int = if (builtin.os.tag.isDarwin()) 29 else 30;
extern var system_page_size: c_int;

extern fn getenv(name: [*c]const u8) [*c]u8;
extern fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) c_int;

// MAY-247 Phase 2 — defined in src/main.zig; runs ClEnv.init after vk init.
extern fn cl_env_warmup() void;
extern fn execvp(file: [*c]const u8, argv: [*c][*c]u8) c_int;

extern fn strlen(s: [*c]const u8) usize;
extern fn strcmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn strtol(nptr: [*c]const u8, endptr: [*c][*c]u8, base: c_int) c_long;
extern fn strtoul(nptr: [*c]const u8, endptr: [*c][*c]u8, base: c_int) c_ulong;
extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;
extern fn isalnum(ch: c_int) c_int;
extern fn free(ptr: ?*anyopaque) void;

// stdio
extern var stdin: ?*FILE;
extern var stderr: ?*FILE;
extern var stdout: ?*FILE;
extern fn printf(fmt: [*c]const u8, ...) c_int;
extern fn fprintf(stream: ?*FILE, fmt: [*c]const u8, ...) c_int;
extern fn puts(s: [*c]const u8) c_int;
extern fn fflush(stream: ?*FILE) c_int;
extern fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*FILE;
extern fn fgets(buf: [*c]u8, size: c_int, stream: ?*FILE) [*c]u8;

// getopt
extern fn getopt_long(argc: c_int, argv: [*c][*c]u8, optstring: [*c]const u8, longopts: [*c]const option, longindex: ?*c_int) c_int;
extern var optarg: [*c]u8;
extern var optind: c_int;

// getpid
extern fn getpid() c_int;

// PID 1 init — mount filesystems and load Apple Silicon GPU modules.
// Called when arcan-vk IS /init (no separate init binary needed).
// Shared memory log page — last 4KB of guest RAM.
// Layout: [0..7] = magic "ARCANLOG", [8..15] = write offset (u64 LE),
//         [16..4095] = log text (4080 bytes, wraps)
// The hypervisor reads this via vm_dmesg(ram_base + 4GB - 4096).
var shmlog: ?[*]volatile u8 = null;

fn shmlog_write(msg: []const u8) void {
    const log_ptr = shmlog orelse return;
    // Read current offset from [8..15]
    const off_ptr: *volatile u64 = @ptrCast(@alignCast(log_ptr + 8));
    var off = off_ptr.*;
    for (msg) |c| {
        log_ptr[16 + @as(usize, @intCast(off % 4080))] = c;
        off += 1;
    }
    off_ptr.* = off;
}

fn shmlog_init() void {
    const linux = std.os.linux;
    // Map the LAST page of guest RAM via /dev/mem.
    // The hypervisor knows ram_base + 4GB - 4096.
    // We find our RAM end from /proc/iomem by reading the "System RAM" line.

    // Read /proc/iomem to find RAM end
    const iomem_fd = linux.open("/proc/iomem", .{ .ACCMODE = .RDONLY }, 0);
    if (linux.E.init(iomem_fd) != .SUCCESS) return;
    var iomem_buf: [4096]u8 = undefined;
    const n = linux.read(@intCast(iomem_fd), &iomem_buf, iomem_buf.len);
    _ = linux.close(@intCast(iomem_fd));
    if (linux.E.init(n) != .SUCCESS) return;
    const iomem = iomem_buf[0..@intCast(n)];

    // Find "System RAM" line: "start-end : System RAM"
    // Parse the end address
    var ram_end: u64 = 0;
    var line_start: usize = 0;
    for (iomem, 0..) |c, i| {
        if (c == '\n' or i == iomem.len - 1) {
            const line = iomem[line_start..i];
            // Check if line contains "System RAM"
            if (std.mem.indexOf(u8, line, "System RAM")) |_| {
                // Parse "xxxx-yyyy" from start of line
                if (std.mem.indexOf(u8, line, "-")) |dash| {
                    const end_str_start = dash + 1;
                    if (std.mem.indexOf(u8, line[end_str_start..], " ")) |space| {
                        const end_hex = std.mem.trim(u8, line[end_str_start..end_str_start + space], " ");
                        ram_end = std.fmt.parseInt(u64, end_hex, 16) catch 0;
                    }
                }
            }
            line_start = i + 1;
        }
    }

    if (ram_end == 0) return;

    // Map last page via /dev/mem
    const log_pa = (ram_end + 1) - 4096; // last 4KB page
    const mem_fd = linux.open("/dev/mem", .{ .ACCMODE = .RDWR, .SYNC = true }, 0);
    if (linux.E.init(mem_fd) != .SUCCESS) return;

    const page = linux.mmap(null, 4096, linux.PROT.READ | linux.PROT.WRITE,
        .{ .TYPE = .SHARED }, @intCast(mem_fd), @intCast(log_pa));
    _ = linux.close(@intCast(mem_fd));
    if (linux.E.init(@bitCast(page)) != .SUCCESS) return;

    shmlog = @ptrFromInt(page);
    const magic = "ARCANLOG";
    for (magic, 0..) |c, i| shmlog.?[i] = c;
    const off_ptr: *volatile u64 = @ptrCast(@alignCast(shmlog.? + 8));
    off_ptr.* = 0;
}

fn pid1_init() void {
    const linux = std.os.linux;

    // Initialize shared memory log FIRST (before any log calls)
    shmlog_init();

    const log = struct {
        fn f(comptime fmt: []const u8, args: anytype) void {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "init: " ++ fmt ++ "\n", args) catch return;
            _ = linux.write(2, msg.ptr, msg.len);
            shmlog_write(msg);
        }
    }.f;

    log("arcan-vk as PID 1", .{});

    // Mount essential filesystems
    const mounts = [_]struct { s: [*:0]const u8, t: [*:0]const u8, fs: [*:0]const u8 }{
        .{ .s = "proc", .t = "/proc", .fs = "proc" },
        .{ .s = "sysfs", .t = "/sys", .fs = "sysfs" },
        .{ .s = "devtmpfs", .t = "/dev", .fs = "devtmpfs" },
        .{ .s = "devpts", .t = "/dev/pts", .fs = "devpts" },
        .{ .s = "tmpfs", .t = "/run", .fs = "tmpfs" },
        .{ .s = "tmpfs", .t = "/tmp", .fs = "tmpfs" },
    };
    for (&mounts) |m| {
        _ = linux.mkdir(m.t, 0o755);
        const rc = linux.mount(m.s, m.t, m.fs, 0, 0);
        if (linux.E.init(rc) != .SUCCESS) {
            log("mount {s} failed", .{std.mem.span(m.t)});
        }
    }

    // Create needed directories
    for ([_][*:0]const u8{ "/tmp/arcan", "/state", "/root" }) |dir| {
        _ = linux.mkdir(dir, 0o755);
    }

    // Load Apple Silicon GPU kernel modules (order: deps first)
    const modules = [_][*:0]const u8{
        "/lib/modules/apple-dart.ko",
        "/lib/modules/typec.ko",
        "/lib/modules/mux-core.ko",
        "/lib/modules/drm_dma_helper.ko",
        "/lib/modules/soundcore.ko",
        "/lib/modules/snd.ko",
        "/lib/modules/snd-timer.ko",
        "/lib/modules/snd-pcm.ko",
        "/lib/modules/snd-pcm-dmaengine.ko",
        "/lib/modules/asahi.ko",
        "/lib/modules/appledrm.ko",
    };
    log("loading kernel modules...", .{});
    for (&modules) |mod| {
        const fd_rc = linux.open(mod, .{ .ACCMODE = .RDONLY }, 0);
        switch (linux.E.init(fd_rc)) {
            .SUCCESS => {
                const fd: i32 = @intCast(fd_rc);
                defer _ = linux.close(fd);
                const rc = linux.syscall3(.finit_module, @as(usize, @intCast(fd)), @intFromPtr("".ptr), 0);
                switch (linux.E.init(rc)) {
                    .SUCCESS => log("loaded {s}", .{std.mem.span(mod)}),
                    .EXIST => {},
                    else => |e| log("insmod {s}: {s}", .{ std.mem.span(mod), @tagName(e) }),
                }
            },
            else => {}, // module not in initramfs — skip silently
        }
    }

    // Wait for DRI devices (GPU needs time to initialize)
    log("waiting for /dev/dri/card0...", .{});
    var elapsed: u32 = 0;
    while (elapsed < 10000) : (elapsed += 100) {
        const rc = linux.open("/dev/dri/card0", .{ .ACCMODE = .RDONLY }, 0);
        if (linux.E.init(rc) == .SUCCESS) {
            _ = linux.close(@intCast(rc));
            log("/dev/dri/card0 ready", .{});
            break;
        }
        var ts = linux.timespec{ .sec = 0, .nsec = 100_000_000 };
        _ = linux.nanosleep(&ts, null);
    }

    // Set environment for arcan
    _ = setenv("HOME", "/root", 1);
    _ = setenv("PATH", "/bin:/usr/bin", 1);
    _ = setenv("TERM", "linux", 1);
    _ = setenv("XDG_RUNTIME_DIR", "/run", 1);
    _ = setenv("LD_LIBRARY_PATH", "/lib", 1);
    _ = setenv("XKB_CONFIG_ROOT", "/share/X11/xkb", 1);
    _ = setenv("ARCAN_RESOURCEPATH", "/share/arcan/resources", 1);
    _ = setenv("ARCAN_APPLTEMPPATH", "/tmp/arcan", 1);
    _ = setenv("ARCAN_APPLBASEPATH", "/share/arcan/appl", 1);
    _ = setenv("ARCAN_STATEBASEPATH", "/state", 1);
    _ = setenv("ARCAN_LOGPATH", "/tmp", 1);
    _ = setenv("VK_ICD_FILENAMES", "/share/vulkan/icd.d/asahi_icd.aarch64.json", 1);

    // Capture kernel dmesg to shared log
    {
        const dmesg_fd = linux.open("/dev/kmsg", .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
        if (linux.E.init(dmesg_fd) == .SUCCESS) {
            var dmesg_buf: [4080]u8 = undefined;
            var total: usize = 0;
            while (total < 4000) {
                const n = linux.read(@intCast(dmesg_fd), &dmesg_buf, dmesg_buf.len);
                if (linux.E.init(n) != .SUCCESS) break;
                const count: usize = @intCast(n);
                if (count == 0) break;
                shmlog_write(dmesg_buf[0..count]);
                total += count;
            }
            _ = linux.close(@intCast(dmesg_fd));
            log("captured dmesg ({d} bytes)", .{total});
        }
    }

    log("init done, starting arcan compositor", .{});
}

// signal
const SIG_IGN: ?*align(1) const fn (c_int) callconv(.c) void = @ptrFromInt(1);
const SIGPIPE: c_int = 13;

const sigset_t = extern struct {
    val: [16]c_ulong,
};

const sigaction_t = extern struct {
    handler: ?*align(1) const fn (c_int) callconv(.c) void,
    sa_mask: sigset_t,
    sa_flags: c_ulong,
    sa_restorer: ?*const fn () callconv(.c) void,
};

extern fn sigaction(sig: c_int, act: ?*const sigaction_t, oact: ?*sigaction_t) c_int;

// setjmp/longjmp
extern "c" fn setjmp(env: *anyopaque) c_int;

// arcan platform
extern fn platform_device_init() void;
extern fn platform_video_preinit() void;
extern fn platform_audio_preinit() void;
extern fn platform_event_preinit() void;
extern fn platform_video_recovery() void;
extern fn platform_event_rescan_idev(ctx: *arcan_evctx) void;
extern fn platform_dbstore_path() [*c]u8;
extern fn platform_video_envopts() [*c][*c]const u8;
extern fn platform_is_lwa_mode() bool;
extern fn platform_event_envopts() [*c][*c]const u8;
extern fn agp_envopts() [*c][*c]const u8;

// arcan conductor
extern fn arcan_conductor_enable_watchdog() void;
extern fn arcan_conductor_setsynch(arg: [*c]const u8) void;
extern fn arcan_conductor_synchopts() [*c][*c]const u8;
extern fn arcan_conductor_run(cb: *const fn (c_int) callconv(.c) void) c_int;
extern fn arcan_conductor_reset_count(step: bool) c_int;
extern fn arcan_conductor_valid_cycle() bool;

// arcan logging/warning
extern fn arcan_log_destination(outf: ?*FILE, minlevel: c_int) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_fatal(fmt: [*c]const u8, ...) callconv(.c) noreturn;

// arcan namespace/appl
extern fn arcan_set_namespace_defaults() void;
extern fn arcan_override_namespace(path: [*c]const u8, space: c_int) void;
extern fn arcan_isdir(path: [*c]const u8) bool;
extern fn arcan_verifyload_appl(appl_id: [*c]const u8, errc: *[*c]const u8) bool;
extern fn arcan_verify_namespaces(report: bool) bool;
extern fn arcan_appl_id() [*c]const u8;
extern fn arcan_appl_basesource(file: *bool) [*c]const u8;
extern fn arcan_expand_resource(label: [*c]const u8, space: c_int) [*c]u8;
extern fn arcan_fetch_namespace(space: c_int) [*c]u8;
extern fn arcan_frameserver_atypes() [*c]const u8;

// arcan resource I/O
extern fn arcan_open_resource(name: [*c]const u8) data_source;
extern fn arcan_release_resource(src: *data_source) void;
extern fn arcan_map_resource(src: *data_source, wr: bool) map_region;
extern fn arcan_release_map(region: map_region) bool;

// arcan memory
extern fn arcan_mem_growarr(arr: *arcan_strarr) void;
extern fn arcan_mem_freearr(arr: *arcan_strarr) void;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, align_v: c_int) ?*anyopaque;

// arcan ffunc
extern fn arcan_ffunc_initlut() void;



// arcan event
extern fn arcan_event_defaultctx() *arcan_evctx;
extern fn arcan_event_init(ctx: *arcan_evctx) void;
extern fn arcan_event_deinit(ctx: *arcan_evctx, flush: bool) void;
extern fn arcan_event_maskall(ctx: *arcan_evctx) void;
extern fn arcan_event_clearmask(ctx: *arcan_evctx) void;

// arcan video
extern fn arcan_video_init(
    width: u16,
    height: u16,
    bpp: u8,
    fullscreen: bool,
    windowed: bool,
    conservative: bool,
    caption: [*c]const u8,
) i8; // arcan_errc = int8_t
extern fn arcan_video_shutdown(release_fsrv: bool) void;
extern fn arcan_video_default_scalemode(mode: c_int) void;
extern fn arcan_video_popcontext() c_uint;

// Ticket 0133 — needed for the standalone-mode default-font init
// before the appl runs (so render_text doesn't dereference a null
// font_cache slot when no parent compositor is supplying one).
extern fn arcan_video_defaultfont(ident: [*c]const u8, fd: c_int, sz: c_int, hintflag: c_int, append: bool) bool;
extern fn arcan_video_fontdefaults(fd: ?*c_int, fdsz: ?*c_int, hint: ?*c_int) void;
extern fn arcan_find_resource(label: [*c]const u8, ns: c_uint, mode: c_uint, dfd: ?*c_int) [*c]u8;
extern fn arcan_video_recoverexternal(
    pop: bool,
    saved: *c_int,
    truncated: *c_int,
    a: ?*anyopaque,
    b: ?*anyopaque,
) void;

// arcan audio (arcan_errc = int8_t)
extern fn arcan_audio_setup(nosound: bool) i8;
extern fn arcan_audio_shutdown() i8;

// arcan misc init
extern fn arcan_math_init() void;
extern fn arcan_img_init() void;
extern fn arcan_led_init() void;
extern fn arcan_led_shutdown() void;

// arcan trace
extern fn arcan_trace_init(vmctx: ?*anyopaque) void;
extern fn arcan_trace_log(message: [*c]const u8, len: usize) void;
extern fn arcan_trace_close() void;
extern fn arcan_trace_threadname(name: [*c]const u8) void;

// arcan database
extern fn arcan_db_open(fname: [*c]const u8, applname: [*c]const u8) ?*arcan_dbh;
extern fn arcan_db_close(dbh: *?*arcan_dbh) void;
extern fn arcan_db_set_shared(dbh: ?*arcan_dbh) void;
extern fn arcan_db_get_shared(appl: *[*c]const u8) ?*arcan_dbh;
extern fn arcan_db_appl_val(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;
extern fn arcan_db_appl_kv(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8, val: [*c]const u8) bool;

// arcan lua
extern fn arcan_lua_alloc(watchdog: ?*const fn (?*lua_State, ?*lua_Debug) callconv(.c) void) ?*arcan_luactx;
extern fn arcan_lua_mapfunctions(ctx: ?*arcan_luactx, debuglevel: c_int) void;
extern fn arcan_lua_main(ctx: ?*arcan_luactx, input: [*c]const u8, file_in: bool) [*c]u8;
extern fn arcan_lua_callvoidfun(
    ctx: ?*arcan_luactx,
    name: [*c]const u8,
    trigger: c_int,
    locked: bool,
    args: [*c]const [*c]const u8,
) bool;
extern fn arcan_lua_cbdrop() void;
extern fn arcan_lua_shutdown(ctx: ?*arcan_luactx) void;
extern fn arcan_lua_adopt(ctx: ?*arcan_luactx) void;
extern fn arcan_lua_setglobalnum(ctx: ?*arcan_luactx, key: [*c]const u8, val: f64) void;
extern fn arcan_lua_dostring(ctx: ?*arcan_luactx, sbuf: [*c]const u8, name: [*c]const u8) void;
extern fn arcan_lua_launch_cp(ctx: ?*arcan_luactx, connp: [*c]const u8, key: [*c]const u8) bool;
extern fn arcan_lua_crash_source(ctx: ?*arcan_luactx) [*c]const u8;

// arcan monitor
extern fn arcan_monitor_configure(srate: c_int, arg: [*c]const u8, ctrl: ?*FILE) bool;
extern fn arcan_monitor_tick(nticks: c_int) callconv(.c) void;
extern fn arcan_monitor_watchdog(L: ?*lua_State, ar: ?*lua_Debug) callconv(.c) void;
extern fn arcan_monitor_finish(ok: bool) void;

// arcan shmif
extern fn arcan_shmif_cookie() u64;
extern fn arcan_shmif_primary(stype: c_int) ?*arcan_shmif_cont;
extern fn arcan_shmif_last_words(cont: ?*arcan_shmif_cont, msg: [*c]const u8) void;

// arcan timemillis
extern fn arcan_timemillis() c_longlong;

// arcan_fatal_hook (defined in warning.c)
extern var arcan_fatal_hook: ?*const fn () callconv(.c) void;

// Build version — must match -DARCAN_BUILDVERSION in build.zig
export const arcan_buildversion_ptr: [*c]const u8 = "mayhem-2026-03-09";
const LUAAPI_VERSION_MAJOR: c_int = 0;
const LUAAPI_VERSION_MINOR: c_int = 13;

// c_ticks is at offset 0 in arcan_evctx (first field, i32)
fn get_cticks(ctx: *arcan_evctx) i32 {
    const ptr: *const i32 = @ptrCast(@alignCast(ctx));
    return ptr.*;
}

// Helper: print env opts pair list
fn print_envopt_pairs(cur_init: [*c][*c]const u8) void {
    var cur = cur_init;
    while (true) {
        const a: [*c]const u8 = cur[0];
        cur += 1;
        if (a == null) break;
        const b: [*c]const u8 = cur[0];
        cur += 1;
        if (b == null) break;
        _ = printf("\t%s - %s\n", a, b);
    }
}

// vplatform_usage
fn vplatform_usage() void {
    var cur: [*c][*c]const u8 = platform_video_envopts();
    if (cur[0] != null) {
        _ = printf("Video platform configuration options:\n");
        _ = printf("(use ARCAN_VIDEO_XXX=val for env, or " ++
            "arcan_db add_appl_kv arcan video_xxx for db)\n");
        _ = printf("\tignore_dirty - always update regardless of 'dirty' state\n");
        print_envopt_pairs(cur);
        _ = printf("\n");
    }

    cur = agp_envopts();
    _ = printf("Graphics platform configuration options:\n");
    _ = printf("(use ARCAN_GRAPHICS_XXX=val for env, graphics_xxx=val for db)\n");
    if (cur[0] != null) {
        print_envopt_pairs(cur);
    }
    _ = printf("\n");
}

// usage
fn usage() void {
    _ = printf("Usage: arcan [-whfmWMOqspTBtHbdgaSV] applname " ++
        "[appl specific arguments]\n\n" ++
        "-w\t--width       \tdesired initial canvas width (auto: 0)\n" ++
        "-h\t--height      \tdesired initial canvas height (auto: 0)\n" ++
        "-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n" ++
        "-m\t--conservative\ttoggle conservative memory management (default: off)\n" ++
        "-W\t--sync-strat  \tspecify video synchronization strategy (see below)\n" ++
        "-M\t--monitor     \tenable monitor session (arg: [ticks/sample], -1 debug only)\n" ++
        "-O\t--monitor-out \tLOG:fname or LOGFD:num\n" ++
        "-C\t--monitor-ctrl\tfilename or - for STDIN\n" ++
        "-s\t--windowed    \ttoggle borderless window mode\n" ++
        "-B\t--binpath     \tchange default searchpath for arcan_frameserver/afsrv*\n" ++
        "-L\t--libpath     \tchange library search patch\n" ++
        "-0\t--pipe-stdin  \t(for pipe-mode) accept requests for an initial connection\n" ++
        "-p\t--rpath       \tchange default searchpath for shared resources\n" ++
        "-t\t--applpath    \tchange default searchpath for applications\n" ++
        "-T\t--scriptpath  \tchange default searchpath for builtin (system) scripts\n" ++
        "-H\t--hook        \trun a post-appl() script (shared/sys-script namespaces)\n" ++
        "-b\t--fallback    \tset a recovery/fallback application if appname crashes\n" ++
        "-d\t--database    \tsqlite database (default: arcandb.sqlite)\n" ++
        "-g\t--debug       \ttoggle debug output (events, coredumps, etc.)\n" ++
        "-S\t--nosound     \tdisable audio output\n" ++
        "-V\t--version     \tdisplay a version string then exit\n\n");

    var cur: [*c][*c]const u8 = arcan_conductor_synchopts();
    if (cur[0] != null) {
        _ = printf("Video platform synchronization options (-W strat):\n");
        print_envopt_pairs(cur);
        _ = printf("\n");
    }

    vplatform_usage();

    // built-in envopts for _event.c
    _ = printf("Input platform configuration options:\n");
    cur = platform_event_envopts();
    if (cur[0] != null) {
        print_envopt_pairs(cur);
        _ = printf("\n");
    }
}

// override_resspaces
fn override_resspaces(respath: [*c]const u8) void {
    const len = strlen(respath);
    if (len == 0 or !arcan_isdir(respath)) {
        arcan_warning("-p argument ignored, invalid path specified.\n");
        return;
    }

    var debug_buf: [4096]u8 = undefined;
    var state_buf: [4096]u8 = undefined;
    var font_buf: [4096]u8 = undefined;

    _ = snprintf(&debug_buf, debug_buf.len, "%s/logs", respath);
    _ = snprintf(&state_buf, state_buf.len, "%s/savestates", respath);
    _ = snprintf(&font_buf, font_buf.len, "%s/fonts", respath);

    arcan_override_namespace(respath, RESOURCE_APPL_SHARED);
    arcan_override_namespace(&debug_buf, RESOURCE_SYS_DEBUG);
    arcan_override_namespace(&state_buf, RESOURCE_APPL_STATE);
    arcan_override_namespace(&font_buf, RESOURCE_SYS_FONT);
}

// appl_user_warning
export fn appl_user_warning(name: [*c]const u8, err_msg: [*c]const u8) void {
    arcan_warning(
        "\x1b[1mCouldn't load application \x1b[33m(%s): \x1b[31m%s\x1b[39m\n",
        name,
        err_msg,
    );

    if (name == null or strlen(name) == 0) {
        arcan_warning("\x1b[1m\tthe appl-name argument is empty\x1b[22m\n");
    } else if (name[0] == '.') {
        arcan_warning(
            "\x1b[32m\ttried to load " ++
                "relative to current directory\x1b[22m\x1b[39m\n",
        );
    } else if (name[0] == '/') {
        arcan_warning(
            "\x1b[32m\ttried to load " ++
                "from absolute path. \x1b[39m\x1b[22m\n",
        );
    } else {
        const space = arcan_expand_resource("", RESOURCE_SYS_APPLBASE);
        arcan_warning(
            "\x1b[32m\ttried to load " ++
                "appl relative to base: \x1b[33m %s\x1b[22m\x1b[39m\n",
            space,
        );
    }
}

// fatal_shutdown
fn fatal_shutdown() callconv(.c) void {
    _ = arcan_audio_shutdown();
    arcan_video_shutdown(false);
}

// add_hookscript
fn add_hookscript(instr: [*c]const u8) void {
    // convert to filesystem path
    const expand: [*c]u8 = arcan_expand_resource(instr, RESOURCE_SYS_SCRIPTS);
    if (expand == null) {
        arcan_warning("-H, couldn't expand hook-script: %s\n", if (instr != null) instr else @as([*c]const u8, ""));
        return;
    }

    // open for reading
    var src = arcan_open_resource(expand);
    if (src.fd == BADFD) {
        arcan_warning("-H, couldn't open hook-script: %s\n", expand);
        free(@ptrCast(expand));
        return;
    }

    // get a memory mapping
    const reg = arcan_map_resource(&src, false);
    if (reg.ptr == null) {
        arcan_release_resource(&src);
        return;
    }

    // grow array if needed
    if (arr_hooks.count + 1 >= arr_hooks.limit)
        arcan_mem_growarr(&arr_hooks);

    // to "reuse" the string, take the approach of string-in-string
    const dlen = strlen(reg.ptr);
    const blen = strlen(instr);
    const comp: [*c]u8 = @ptrCast(arcan_alloc_mem(
        dlen + blen + 2,
        ARCAN_MEM_STRINGBUF,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return);
    _ = memcpy(@ptrCast(comp), @ptrCast(instr), blen);
    _ = memcpy(@ptrCast(comp + blen + 1), @ptrCast(reg.ptr), dlen);

    arr_hooks.data[arr_hooks.count] = comp;
    arr_hooks.count += 1;

    _ = arcan_release_map(reg);
    arcan_release_resource(&src);
}

// Long options table
const longopts = [_]option{
    .{ .name = "help", .has_arg = no_argument, .flag = null, .val = '?' },
    .{ .name = "sync-strat", .has_arg = required_argument, .flag = null, .val = 'W' },
    .{ .name = "width", .has_arg = required_argument, .flag = null, .val = 'w' },
    .{ .name = "height", .has_arg = required_argument, .flag = null, .val = 'h' },
    .{ .name = "fullscreen", .has_arg = no_argument, .flag = null, .val = 'f' },
    .{ .name = "windowed", .has_arg = no_argument, .flag = null, .val = 's' },
    .{ .name = "debug", .has_arg = no_argument, .flag = null, .val = 'g' },
    .{ .name = "binpath", .has_arg = required_argument, .flag = null, .val = 'B' },
    .{ .name = "libpath", .has_arg = required_argument, .flag = null, .val = 'L' },
    .{ .name = "rpath", .has_arg = required_argument, .flag = null, .val = 'p' },
    .{ .name = "applpath", .has_arg = required_argument, .flag = null, .val = 't' },
    .{ .name = "scriptpath", .has_arg = required_argument, .flag = null, .val = 'T' },
    .{ .name = "conservative", .has_arg = no_argument, .flag = null, .val = 'm' },
    .{ .name = "fallback", .has_arg = required_argument, .flag = null, .val = 'b' },
    .{ .name = "database", .has_arg = required_argument, .flag = null, .val = 'd' },
    .{ .name = "scalemode", .has_arg = required_argument, .flag = null, .val = 'r' },
    .{ .name = "nosound", .has_arg = no_argument, .flag = null, .val = 'S' },
    .{ .name = "hook", .has_arg = required_argument, .flag = null, .val = 'H' },
    .{ .name = "pipe-stdin", .has_arg = no_argument, .flag = null, .val = '0' },
    .{ .name = "monitor", .has_arg = required_argument, .flag = null, .val = 'M' },
    .{ .name = "monitor-out", .has_arg = required_argument, .flag = null, .val = 'O' },
    .{ .name = "monitor-ctrl", .has_arg = required_argument, .flag = null, .val = 'C' },
    .{ .name = "version", .has_arg = no_argument, .flag = null, .val = 'V' },
    .{ .name = null, .has_arg = no_argument, .flag = null, .val = 0 },
};

// MAY-110: engine entry point exported as `arcan_main` so it doesn't
// collide with may's own `main` when the engine is linked into the may
// binary. `src/main.zig`'s runArcanAppl calls this via extern decl
// after the personality / verb dispatch resolves an appl. The C side's
// MAIN_REDIR machinery is bypassed in this layout — may owns argv[0].
export fn arcan_main(argc: c_int, argv: [*c][*c]u8) c_int {
    // If running as PID 1 (init): mount filesystems and load GPU modules
    // before any arcan initialization.
    if (getpid() == 1) pid1_init();

    // needed first as device_init might fork and need some shared mem
    system_page_size = @intCast(sysconf(_SC_PAGE_SIZE));
    arcan_conductor_enable_watchdog();

    // one-time platform pre-init calls
    platform_device_init();
    platform_video_preinit();
    platform_audio_preinit();
    platform_event_preinit();
    arcan_log_destination(stderr, 0);

    // Mode detection now happens in platform_video_init():
    //   ARCAN_CONNPATH/ARCAN_SOCKIN_FD set → LWA (nested compositor)
    //   DISPLAY set → XCB windowed (VK_KHR_xcb_surface)
    //   Otherwise → VK_KHR_display (direct-to-display)

    arcan_mem_growarr(&arr_hooks);

    var windowed: bool = false;
    var fullscreen: bool = false;
    var conservative: bool = false;
    var nosound: bool = false;
    var stdin_connpoint: bool = false;

    var debuglevel: u8 = 0;

    const scalemode: c_int = ARCAN_VIMAGE_NOPOW2;
    var width: c_int = 3024;
    var height: c_int = 1710;

    // monitor mode state
    var monitor_rate: c_int = 0;
    var monitor_arg: [*c]u8 = null;
    var monitor_ctrl: ?*FILE = null;

    // fallback appl on crash
    var fallback: [*c]u8 = null;
    var dbfname: [*c]u8 = null;

    // initialize conductor default profile early
    arcan_conductor_setsynch("vsynch");

    // accumulation list for -H filenames (namespaces not resolved yet)
    var tmplist: arcan_strarr = std.mem.zeroes(arcan_strarr);

    // Command-line parsing
    while (true) {
        const ch = getopt_long(
            argc,
            argv,
            "w:h:mx:y:fsW:d:Sq:a:p:b:B:L:M:O:C:t:T:H:g01V",
            &longopts,
            null,
        );
        if (ch < 0) break;

        switch (ch) {
            '?' => {
                usage();
                std.c.exit(EXIT_SUCCESS);
            },
            'w' => {
                width = @intCast(strtol(optarg, null, 10));
            },
            'h' => {
                height = @intCast(strtol(optarg, null, 10));
            },
            'm' => {
                conservative = true;
            },
            'f' => {
                fullscreen = true;
            },
            's' => {
                windowed = true;
            },
            'W' => {
                arcan_conductor_setsynch(optarg);
            },
            'd' => {
                dbfname = strdup(optarg);
            },
            'S' => {
                nosound = true;
            },
            '0' => {
                if (monitor_ctrl != null) {
                    arcan_fatal("argument misuse, cannot combing -0 with -C");
                }
                stdin_connpoint = true;
            },
            'p' => {
                override_resspaces(optarg);
            },
            'T' => {
                arcan_override_namespace(optarg, RESOURCE_SYS_SCRIPTS);
            },
            'b' => {
                fallback = strdup(optarg);
            },
            'V' => {
                _ = fprintf(stdout, "%s\nshmif-%lu\nluaapi-%d:%d\n", arcan_buildversion_ptr, arcan_shmif_cookie(), LUAAPI_VERSION_MAJOR, LUAAPI_VERSION_MINOR);
                std.c.exit(EXIT_SUCCESS);
            },
            'H' => {
                if (tmplist.count + 1 >= tmplist.limit)
                    arcan_mem_growarr(&tmplist);
                tmplist.data[tmplist.count] = strdup(optarg);
                tmplist.count += 1;
            },
            'M' => {
                monitor_rate = @intCast(strtol(optarg, null, 10));
            },
            'O' => {
                monitor_arg = strdup(optarg);
            },
            'C' => {
                if (stdin_connpoint) {
                    arcan_fatal("argument misuse, cannot combine -C with -0");
                }
                if (strcmp(optarg, "-") == 0) {
                    monitor_ctrl = stdin;
                } else {
                    monitor_ctrl = fopen(optarg, "r");
                    if (monitor_ctrl == null) {
                        arcan_fatal("-C %s : couldn't open", optarg);
                    }
                }
            },
            't' => {
                arcan_override_namespace(optarg, RESOURCE_SYS_APPLBASE);
                arcan_override_namespace(optarg, RESOURCE_SYS_APPLSTORE);
            },
            'B' => {
                arcan_override_namespace(optarg, RESOURCE_SYS_BINS);
            },
            'L' => {
                arcan_override_namespace(optarg, RESOURCE_SYS_LIBS);
            },
            'g' => {
                debuglevel += 1;
            },
            else => {},
        }
    }

    if (optind >= argc) {
        argv[@intCast(optind)] = @constCast(@ptrCast("durian"));
    }

    // probe system, load environment variables
    arcan_set_namespace_defaults();
    arcan_ffunc_initlut();

    var err_msg: [*c]const u8 = null;

    if (!arcan_verifyload_appl(argv[@intCast(optind)], &err_msg)) {
        appl_user_warning(argv[@intCast(optind)], err_msg);

        if (fallback != null and strcmp(fallback, ":self") != 0) {
            arcan_warning("trying to load fallback appl (%s)\n", fallback);
            if (!arcan_verifyload_appl(fallback, &err_msg)) {
                arcan_warning("fallback application failed to load (%s), giving up.\n", err_msg);
                return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
            }
        } else {
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
        }
    }

    if (!arcan_verify_namespaces(false)) {
        arcan_warning("\x1b[32mCouldn't verify filesystem namespaces.\x1b[39m\n");
        if (debuglevel == 0) {
            arcan_warning("\x1b[33mLook through the following list and note the " ++
                "entries marked broken, \nCheck the manpage for config and environment " ++
                "variables, or try the arguments: \n" ++
                "\t <system-scripts> : -T path/to/arcan/data/scripts\n" ++
                "\t <application-shared> : -p any/valid/user/path\n" ++
                "\x1b[39m\n");
            _ = arcan_verify_namespaces(true);
        }
        return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
    }

    if (debuglevel > 1)
        _ = arcan_verify_namespaces(true);

    // namespaces resolved, process hookscripts
    if (tmplist.count > 0) {
        var i: usize = 0;
        while (i < tmplist.count) : (i += 1) {
            if (tmplist.data[i] != null)
                add_hookscript(tmplist.data[i]);
        }
        arcan_mem_freearr(&tmplist);
    }

    // external cooperation - monitor mode
    if (monitor_rate != 0 or monitor_ctrl != null)
        _ = arcan_monitor_configure(monitor_rate, monitor_arg, monitor_ctrl);

    // mask SIGPIPE
    var sa: sigaction_t = std.mem.zeroes(sigaction_t);
    sa.handler = SIG_IGN;
    _ = sigaction(SIGPIPE, &sa, null);

    var dbhandle: ?*arcan_dbh = null;
    // fallback to platform database storepath
    if (dbfname != null) {
        dbhandle = arcan_db_open(dbfname, arcan_appl_id());
    } else {
        dbfname = platform_dbstore_path();
        if (dbfname != null)
            dbhandle = arcan_db_open(dbfname, arcan_appl_id());
    }

    if (dbhandle == null) {
        arcan_warning(
            "Couldn't open/create database (%s), fallback to :memory:\n",
            dbfname,
        );
        dbhandle = arcan_db_open(":memory:", arcan_appl_id());
    }

    if (dbhandle == null) {
        arcan_warning("In memory db fallback failed, giving up\n");
        return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
    }

    arcan_db_set_shared(dbhandle);
    var target_appl: [*c]const u8 = null;
    dbhandle = arcan_db_get_shared(&target_appl);

    // resolve width from db or command line
    if (width == -1) {
        const dbw: [*c]u8 = arcan_db_appl_val(dbhandle, target_appl, "width");
        if (dbw != null) {
            width = @intCast(@as(u16, @truncate(strtoul(dbw, null, 10))));
            arcan_mem_free(@ptrCast(dbw));
        } else {
            width = 0;
        }
    } else {
        var buf: [6]u8 = std.mem.zeroes([6]u8);
        _ = snprintf(&buf, buf.len, "%d", width);
        _ = arcan_db_appl_kv(dbhandle, target_appl, "width", &buf);
    }

    // resolve height from db or command line
    if (height == -1) {
        const dbh: [*c]u8 = arcan_db_appl_val(dbhandle, target_appl, "height");
        if (dbh != null) {
            height = @intCast(@as(u16, @truncate(strtoul(dbh, null, 10))));
            arcan_mem_free(@ptrCast(dbh));
        } else {
            height = 0;
        }
    } else {
        var buf: [6]u8 = std.mem.zeroes([6]u8);
        _ = snprintf(&buf, buf.len, "%d", height);
        _ = arcan_db_appl_kv(dbhandle, target_appl, "height", &buf);
    }

    arcan_video_default_scalemode(scalemode);

    if (windowed)
        fullscreen = false;

    // grab video (necessary)
    const evctx = arcan_event_defaultctx();
    arcan_event_init(evctx);

    if (arcan_video_init(
        @intCast(@as(u32, @bitCast(width))),
        @intCast(@as(u32, @bitCast(height))),
        32,
        fullscreen,
        windowed,
        conservative,
        arcan_appl_id(),
    ) != 0) {
        _ = printf("Error: couldn't initialize video subsystem. Check permissions, " ++
            " try other video platform options (-f, -w, -h)\n");
        vplatform_usage();
        arcan_fatal("Video platform initialization failed\n");
    }
    _ = fprintf(stderr, "arcan_main: video init OK\n");

    // MAY-247 Phase 2 hypothesis probe — opt-in via CL_ENV_WARMUP=1.
    // 2026-05-27: warm-process hypothesis FALSIFIED — same crash in
    // _dl_update_slotinfo when zig_dlopen'ing libOpenCL.so.1, even
    // with libvulkan_asahi already loaded. Root cause is libstdc++ /
    // libgcc_s / libLLVM (which libRusticlOpenCL.so.1 pulls in but
    // libvulkan_asahi.so doesn't) failing TLS slot init via the
    // glibc-ld-linux-embedded-in-musl-static path. Probe stays here
    // (gated) so future zig_dlopen fixes can re-test without a code
    // change. cl_env_warmup is in src/main.zig (already has cl_env
    // imported) — engine_mod doesn't need a new build.zig dep.
    if (std.c.getenv("CL_ENV_WARMUP") != null) {
        cl_env_warmup();
    }

    // set fatal hook for shutdown
    arcan_fatal_hook = &fatal_shutdown;

    // Set ARCAN_CONNPATH for child processes (terminals, etc.) so that
    // programs launched from within the compositor can connect back as
    // LWA clients. Only do this if we're the compositor (not LWA ourselves).
    if (!platform_is_lwa_mode()) {
        _ = setenv("ARCAN_CONNPATH", arcan_appl_id(), 1);
    }

    std.c._errno().* = 0;
    // grab audio (possible to live without)
    if (arcan_audio_setup(nosound) != 0)
        arcan_warning("Warning: No audio devices could be found.\n");
    _ = fprintf(stderr, "arcan_main: audio OK\n");

    arcan_math_init();
    arcan_img_init();

    // setup device polling, cleanup
    arcan_led_init();
    _ = fprintf(stderr, "arcan_main: math/img/led OK\n");

    // recovery / adopt state
    var adopt: bool = false;
    var in_recover: bool = false;

    const jumpcode = setjmp(@ptrCast(&arcanmain_recover_state));
    var saved: c_int = 0;
    var truncated: c_int = 0;

    if (jumpcode == ARCAN_LUA_SWITCH_APPL or
        jumpcode == ARCAN_LUA_SWITCH_APPL_NOADOPT)
    {
        // close down the database and reinitialize with the new appl name
        arcan_db_close(&dbhandle);
        arcan_db_set_shared(null);
        _ = arcan_conductor_reset_count(true);

        dbhandle = arcan_db_open(dbfname, arcan_appl_id());
        if (dbhandle == null)
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);

        arcan_db_set_shared(dbhandle);
        arcan_lua_cbdrop();
        arcan_lua_shutdown(main_lua_context);

        const trace_msg = "Switching appls, resetting trace";
        arcan_trace_log(trace_msg, trace_msg.len);
        arcan_trace_close();

        // mask off errors so shutdowns won't queue new events
        arcan_event_maskall(evctx);

        if (jumpcode == ARCAN_LUA_SWITCH_APPL_NOADOPT) {
            var lastctxc = arcan_video_popcontext();
            while (true) {
                const lastctxa = arcan_video_popcontext();
                if (lastctxc == lastctxa) break;
                lastctxc = lastctxa;
            }
            // rescan so devices seem to be added again
            platform_event_rescan_idev(evctx);
        } else {
            // for adopt the rescan is deferred
            arcan_video_recoverexternal(true, &saved, &truncated, null, null);
            adopt = true;
        }
        arcan_event_clearmask(evctx);
    } else if (jumpcode == ARCAN_LUA_RECOVERY_SWITCH) {
        // fallback recovery with adoption
        if (in_recover or !arcan_conductor_valid_cycle()) {
            arcan_warning("Double-Failure (main appl + adopt appl), giving up.\n");
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
        }

        // crash-recovery timeout and counter
        const S = struct {
            var last_recover: u64 = 0;
            var recover_counter: u8 = 0;
        };
        if (S.last_recover == 0)
            S.last_recover = @intCast(arcan_timemillis());

        if (S.last_recover != 0 and @as(u64, @intCast(arcan_timemillis())) -| S.last_recover < 5000) {
            S.recover_counter += 1;
            if (S.recover_counter > 5) {
                arcan_warning("Script handover / recover safety timeout exceeded.\n");
                return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
            }
        } else {
            S.recover_counter = 0;
        }

        if (fallback == null) {
            arcan_warning("Lua VM failed with no fallback defined, (see -b arg).\n");
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
        }

        _ = arcan_conductor_reset_count(true);
        arcan_event_maskall(evctx);
        arcan_video_recoverexternal(true, &saved, &truncated, null, null);
        arcan_event_clearmask(evctx);
        platform_video_recovery();

        var errmsg: [*c]const u8 = null;
        arcan_lua_cbdrop();
        arcan_lua_shutdown(main_lua_context);
        if (strcmp(fallback, ":self") == 0)
            fallback = argv[@intCast(optind)];

        const trace_msg = "Recovering from crash, resetting trace";
        arcan_trace_log(trace_msg, trace_msg.len);
        arcan_trace_close();

        if (!arcan_verifyload_appl(fallback, &errmsg)) {
            arcan_warning("Lua VM error fallback, failure loading (%s), reason: %s\n", fallback, errmsg);
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
        }

        if (!arcan_verify_namespaces(false))
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);

        // track if we get a crash in the fallback application
        in_recover = true;
        adopt = true;
    } else if (jumpcode == ARCAN_LUA_RECOVERY_FATAL_IGNORE) {
        // goto run_loop equivalent — skip setup, go straight to conductor
        return do_run_loop(evctx, &arr_hooks, dbfname, &dbhandle);
    } else if (jumpcode == ARCAN_LUA_KILL_SILENT) {
        // goto cleanup equivalent
        return do_cleanup(evctx, &arr_hooks, dbfname, &dbhandle, 0);
    }

    // setup VM, map arguments and possible overrides
    main_lua_context = arcan_lua_alloc(
        if (monitor_ctrl != null) &arcan_monitor_watchdog else null,
    );
    arcan_lua_mapfunctions(main_lua_context, @intCast(debuglevel));
    arcan_trace_init(@ptrCast(main_lua_context));
    arcan_trace_threadname("main");
    _ = fprintf(stderr, "arcan_main: lua ctx OK\n");

    var inp_file: bool = false;
    const inp: [*c]const u8 = arcan_appl_basesource(&inp_file);
    if (inp == null) {
        arcan_warning("main(), No main script found for (%s)\n", arcan_appl_id());
        return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
    }
    const msg: [*c]u8 = arcan_lua_main(main_lua_context, inp, inp_file);
    if (msg != null) {
        arcan_warning(
            "\n\x1b[1mParsing error in (\x1b[33m%s\x1b[39m):\n" ++
                "\x1b[35m%s\x1b[22m\x1b[39m\n\n",
            arcan_appl_id(),
            msg,
        );
        return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
    }
    free(@ptrCast(msg));

    if (monitor_ctrl != null)
        arcan_monitor_watchdog(@ptrCast(main_lua_context), null);

    // Compute args pointer: if argc > optind, pass argv + optind + 1, else null
    const appl_args: [*c]const [*c]const u8 = if (argc > optind)
        @ptrCast(argv + @as(usize, @intCast(optind)) + 1)
    else
        null;

    // Ticket 0133 — standalone-mode default font init.
    //
    // When arcan runs as the primary compositor (no ARCAN_CONNPATH),
    // there is no parent shmif segment to read init.fonts[0] from,
    // so vk_lwa's font-inheritance path doesn't run. Any appl that
    // calls render_text before manually calling system_defaultfont
    // then dereferences a null font_cache slot and the engine
    // panics with "cast causes pointer to be null".
    //
    // Fix: try to load the bundled jetbrain_variable.font from the
    // RESOURCE_SYS_FONT namespace and install it via
    // arcan_video_defaultfont. Skip if a font is already set
    // (LWA preroll path or a prior appl call already populated
    // font_cache[0]). All-defensive: any failure is silent — the
    // appl can still call system_defaultfont itself.
    {
        var existing_fd: c_int = BADFD;
        arcan_video_fontdefaults(&existing_fd, null, null);
        if (existing_fd == BADFD) {
            const candidates = [_][*:0]const u8{
                "default.font",
                "jetbrain_variable.font",
                // durden's install renames the bundled font to default.ttf
                // (its appl/durden/fonts holds default.ttf, not the two above),
                // and resources/fonts also ships default.ttf — so this catches
                // both whichever dir RESOURCE_SYS_FONT currently resolves to.
                "default.ttf",
            };
            var picked_fd: c_int = BADFD;
            var picked_name: [*:0]const u8 = "default";
            for (candidates) |name| {
                var fd: c_int = BADFD;
                const path = arcan_find_resource(
                    @ptrCast(name),
                    @intCast(RESOURCE_SYS_FONT),
                    ARES_FILE | ARES_RDONLY,
                    &fd,
                );
                if (path != null) free(@ptrCast(path));
                if (fd != BADFD) {
                    picked_fd = fd;
                    picked_name = name;
                    break;
                }
            }
            if (picked_fd != BADFD) {
                _ = arcan_video_defaultfont(
                    @ptrCast(picked_name),
                    picked_fd,
                    14,    // pt size — modest default; appls override
                    2,     // hinting normal
                    false, // not append; this is the primary slot
                );
                _ = fprintf(stderr,
                    "arcan_main: default font installed (%s, fd=%d)\n",
                    @as([*:0]const u8, @ptrCast(picked_name)),
                    picked_fd);
            } else {
                _ = fprintf(stderr,
                    "arcan_main: no default font found in RESOURCE_SYS_FONT" ++
                    " — appls calling render_text before system_defaultfont" ++
                    " will panic (ticket 0133)\n");
            }
        }
    }

    _ = fprintf(stderr, "arcan_main: appl parsed, calling main()\n");
    if (!arcan_lua_callvoidfun(
        main_lua_context,
        "",
        EP_TRIGGER_MAIN,
        false,
        appl_args,
    )) {
        arcan_warning(
            "\n\x1b[1mCouldn't load (\x1b[33m%s\x1b[39m):" ++
                "\x1b[35m missing '%s' function\x1b[22m\x1b[39m\n\n",
            arcan_appl_id(),
            arcan_appl_id(),
        );
        return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
    }

    // run hook scripts
    arcan_lua_setglobalnum(main_lua_context, "IN_HOOK", 1);
    {
        var i: usize = 0;
        while (i < arr_hooks.count) : (i += 1) {
            if (arr_hooks.data[i] != null) {
                const name: [*c]const u8 = arr_hooks.data[i];
                const src: [*c]const u8 = name + strlen(name) + 1;
                arcan_lua_dostring(main_lua_context, src, name);
            }
        }
    }
    arcan_lua_setglobalnum(main_lua_context, "IN_HOOK", 0);

    if (adopt) {
        arcan_lua_setglobalnum(main_lua_context, "CLOCK", @floatFromInt(get_cticks(evctx)));
        arcan_lua_adopt(main_lua_context);

        // re-issue video recovery (adopt clears the event queue)
        platform_video_recovery();
        platform_event_rescan_idev(evctx);

        in_recover = false;
    } else if (stdin_connpoint) {
        var cbuf: [33]u8 = undefined;
        // read desired connection point from stdin
        const res = fgets(&cbuf, @intCast(cbuf.len), stdin);
        if (res != null) {
            const len = strlen(&cbuf);
            if (len > 0) cbuf[len - 1] = 0; // strip trailing newline
            // validate alphanumeric
            var valid = true;
            var ci: usize = 0;
            while (cbuf[ci] != 0) : (ci += 1) {
                if (isalnum(@intCast(cbuf[ci])) == 0) {
                    arcan_warning("-1, %s failed (only [a->Z0-9] accepted)\n", @as([*c]u8, &cbuf));
                    valid = false;
                    break;
                }
            }
            if (!valid)
                return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
            if (!arcan_lua_launch_cp(main_lua_context, &cbuf, null)) {
                arcan_fatal("-1, couldn't setup connection point (%s)\n", @as([*c]u8, &cbuf));
            }
        } else {
            arcan_warning("-1, couldn't read a valid connection point from stdin\n");
            return do_error(monitor_ctrl, debuglevel, argc, argv, dbfname);
        }
    }

    _ = fprintf(stderr, "arcan_main: entering run loop\n");
    return do_run_loop(evctx, &arr_hooks, dbfname, &dbhandle);
}

// run_loop + cleanup (factored out for goto replacement)
fn do_run_loop(evctx: *arcan_evctx, hooks: *arcan_strarr, dbfname: [*c]u8, dbhandle: *?*arcan_dbh) c_int {
    const exit_code = arcan_conductor_run(&arcan_monitor_tick);
    _ = arcan_lua_callvoidfun(
        main_lua_context,
        "shutdown",
        EP_TRIGGER_SHUTDOWN,
        false,
        null,
    );
    arcan_monitor_finish(exit_code == 256 or exit_code == 0);

    return do_cleanup(evctx, hooks, dbfname, dbhandle, exit_code);
}

fn do_cleanup(_: *arcan_evctx, hooks: *arcan_strarr, dbfname: [*c]u8, dbhandle: *?*arcan_dbh, exit_code: c_int) c_int {
    const evctx = arcan_event_defaultctx();
    arcan_mem_freearr(hooks);
    arcan_led_shutdown();
    arcan_event_deinit(evctx, true);
    _ = arcan_audio_shutdown();
    arcan_video_shutdown(exit_code != 256);
    arcan_mem_free(@ptrCast(dbfname));

    if (dbhandle.* != null) {
        arcan_db_close(dbhandle);
        arcan_db_set_shared(null);
    }

    return if (exit_code == 256 or exit_code == 0) EXIT_SUCCESS else exit_code;
}

// error path (replacement for goto error)
fn do_error(
    monitor_ctrl: ?*FILE,
    debuglevel: u8,
    argc: c_int,
    argv: [*c][*c]u8,
    dbfname: [*c]u8,
) c_int {
    const evctx = arcan_event_defaultctx();

    if (monitor_ctrl == null and debuglevel > 1) {
        arcan_warning("fatal: main loop failed, arguments: \n");
        var i: usize = 0;
        while (i < @as(usize, @intCast(argc))) : (i += 1) {
            arcan_warning("%s ", argv[i]);
        }
        arcan_warning("\n\n");
        _ = arcan_verify_namespaces(true);
    }

    // write the reason as 'last words'
    const crashmsg: [*c]const u8 = arcan_lua_crash_source(main_lua_context);

    // now shutdown the subsystems
    arcan_monitor_finish(false);
    arcan_event_deinit(evctx, true);
    arcan_mem_free(@ptrCast(dbfname));
    _ = arcan_audio_shutdown();
    arcan_video_shutdown(false);

    // write the reason to stdout
    if (crashmsg != null and monitor_ctrl == null) {
        arcan_warning(
            "\n\x1b[1mImproper API use from Lua script\n" ++
                ":\n\t\x1b[32m%s\x1b[39m\n",
            crashmsg,
        );
        arcan_warning(
            "version:\n\t%s\n\tshmif-%lu\n\tluaapi-%d:%d\n",
            arcan_buildversion_ptr,
            arcan_shmif_cookie(),
            LUAAPI_VERSION_MAJOR,
            LUAAPI_VERSION_MINOR,
        );
    }

    return EXIT_FAILURE;
}
