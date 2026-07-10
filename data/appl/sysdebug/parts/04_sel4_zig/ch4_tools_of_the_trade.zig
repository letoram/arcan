
pub fn __init() void {
    return .{
        .title = "Tools of the Trade",
        .subtitle = "Part IV · Ch 4 · seL4 Bootstrapping in Zig",
        .part_id = 4,
        .chapter_id = 4,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The developer, just like other craftsmen, has an " ++ "extensive array of tools at his disposal.",
                .cite = "Mellstrand & Ståhl 2012, p. 119",
            },
            .{
                .kind = "text",
                .body = "An extensive array assumes the tools have been built. " ++ ("For this domain half of them have not, and the chapter " ++ ("is structured as two columns — Today and Tomorrow — " ++ ("with the Tomorrow column doubling as the missing-verb " ++ "ticket queue."))),
            },
            .{
                .kind = "h2",
                .body = "4.1  Roll-call",
            },
            .{
                .kind = "text",
                .body = "Today: qemu (the host), gdb-stub via qemu's gdb-server, " ++ ("serial console capture, the hem verbs that already " ++ ("work on any binary (read, find, grep, sym, disasm). " ++ ("Tomorrow: a caps spread (cap state per kernel object), " ++ ("a fault spread (every kernel rejection in time order), " ++ ("a boot-stage hilbert (where in the boot pipeline is " ++ ("the rootserver right now), a qemu-monitor TS wrapper " ++ "(for run-time intervention into the live qemu).")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/sel4-zig",
                .note = "today's surface, all of it",
            },
            .{
                .kind = "h2",
                .body = "4.2  Debugger",
            },
            .{
                .kind = "text",
                .body = "gdb-stub via qemu's gdb-server gives us conventional " ++ ("single-stepping and watchpoints in the rootserver. The " ++ ("qemu side starts with -s -S; the host side attaches " ++ ("gdb to localhost:1234. The hem-native part of this is " ++ ("the bugs show <id> ticket-as-debugger pattern: the " ++ ("ticket says what state the rootserver should be in at " ++ ("the breakpoint, and the gdb session verifies it. The " ++ "ticket is the spec; gdb is the assertion.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| qemu-system-aarch64 -kernel /path/to/kernel.elf -s -S",
                .note = "the actual command; verbbox makes it copy-pasteable " ++ "from inside the appl",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show draft-d006-tool-t0-invalid-input-sel4-kernel",
                .note = "the ticket as the breakpoint spec",
            },
            .{
                .kind = "h2",
                .body = "4.3  Tracer",
            },
            .{
                .kind = "text",
                .body = "Serial console dump is the trace. logwatch with seL4 " ++ ("fault-pattern bucketing reduces it to the interesting " ++ ("lines — kernel rejections, page faults, the rootserver's " ++ ("own debug prints. The fault-pattern bucket needs to " ++ ("exist in the hem logwatch builtin (today the buckets " ++ ("are panic / atlas / font / orphan; sel4-fault is " ++ "missing). One more ticket Agent C owes."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log fault",
                .note = "the trace, bucketed by fault pattern (bucket NYI)",
            },
            .{
                .kind = "h2",
                .body = "4.4  Profiler",
            },
            .{
                .kind = "text",
                .body = "Boot time as the fitness metric: how long from kernel " ++ ("entry to first t0 instruction. Iteration count as the " ++ ("secondary metric: how many auto-arch rounds were " ++ ("required to reach a stable rootserver. Both are " ++ ("domain-specific profilers; both produce a number you " ++ ("can compare between rounds. There is no analogue for " ++ ("the live metrics spread because there is nothing to " ++ ("instrument until t0 actually runs — the kernel is a " ++ "black box from the analyst's side."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log",
                .note = "wall-clock between kernel-entry and t0-start " ++ "lines is the boot-time profile",
            },
            .{
                .kind = "h2",
                .body = "4.5  Visualizer (NEW)",
            },
            .{
                .kind = "text",
                .body = "The proposed cspace-tree spread renders the rootserver's " ++ ("capability graph as a senseye view: each node a CNode " ++ ("or kernel object, each edge a derivation, colour " ++ ("encoding the type of cap. The proposed boot-stage " ++ ("hilbert renders progress through the boot pipeline as " ++ ("a Hilbert tile, one tile per major stage, colour " ++ ("encoding success / failure / not-yet-reached. Both " ++ ("verbs are tickets Agent C owes; both would change " ++ ("what 'visible' means in this domain from 'a serial " ++ "log scrolled by hand' to 'a spread you can click into'.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cspace-tree",
                .note = "TICKET-DRAFT: the cspace-tree visualizer (NYI); " ++ "file draft-d0NN-hem-cspace-tree.md",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| boot-stage",
                .note = "TICKET-DRAFT: the boot-stage hilbert (NYI); " ++ "file draft-d0NN-hem-boot-stage.md",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show draft-d012-tool-multi-sel4-kernel-parse-skip",
                .note = "the upstream blocker for any of these to be " ++ "exercisable end to end",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Tomorrow column counted: caps spread, fault spread, " ++ ("boot-stage hilbert, cspace-tree visualizer, qemu-" ++ ("monitor TS wrapper, sel4-fault logwatch bucket. Six " ++ ("tickets. Part V's domain is older than seL4-zig but " ++ ("newer than zig-arcan; its tooling lives in the same " ++ "in-between.")))),
            },
            .{
                .kind = "crosslink",
                .target = "05_a12_tailscale:ch1_introduction",
            },
        },
        .cross_links = .{
            "04_sel4_zig:ch3_principal_debugging",
            "05_a12_tailscale:ch4_tools_of_the_trade",
            "00_foundations:ch4_tools_of_the_trade",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 4,
                .chapter = 4,
            },
        },
        .tickets = .{
            "draft-d006-tool-t0-invalid-input-sel4-kernel",
            "draft-d012-tool-multi-sel4-kernel-parse-skip",
        },
    };
}
