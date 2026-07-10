
pub fn __init() void {
    return .{
        .title = "Tools of the Trade",
        .subtitle = "Part III · Ch 4 · Zig-based arcan",
        .part_id = 3,
        .chapter_id = 4,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The kernel call trace - creates a log of the " ++ ("communication between its target and the operating " ++ "system kernel."),
                .cite = "Mellstrand & Ståhl 2012, ch 3",
            },
            .{
                .kind = "text",
                .body = "For this domain the kernel-call analogue is the shmif " ++ ("event log. Every other tool below either is or extends " ++ "that one."),
            },
            .{
                .kind = "h2",
                .body = "4.1  Roll-call",
            },
            .{
                .kind = "text",
                .body = "Frameserver inspection: ps, procfs <pid> {fd,threads," ++ ("maps,status}, proc family. Shmif and durian: monitor " ++ ("CLIENT, durian.send, the hem emit sidecar, " ++ ("ARCAN_SHMIF_MONITOR + shmon. Build and binary: zigbuild, " ++ ("disasm, sym, atlas. Crash: cores list, cores info, " ++ ("cores bt, logwatch <bucket>. Ticket-bound: bugs show, " ++ ("bugs all + visual filter, fossil log/diff. TS-side: bun <script>, " ++ "the host bindings on globalThis.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "the verb roll-call rendered live",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "the composition: every spread in one workspace",
            },
            .{
                .kind = "h2",
                .body = "4.2  Debugger",
            },
            .{
                .kind = "epigraph",
                .body = "A debugger is a dynamic tool working on an " ++ "executing system.",
                .cite = "Mellstrand & Ståhl 2012, p. 120",
            },
            .{
                .kind = "text",
                .body = "Our debugger is bugs show <id>: the ticket record IS " ++ ("the breakpoint. A 0036 phase log entry pins exactly " ++ ("what state the engine should be in for a given segment " ++ ("request, and the ticket's resolution checklist is the " ++ ("expected post-condition. Reading the ticket alongside " ++ ("the live state IS the debugger session. engine " ++ ("introspect is the live-state inspector — what segments " ++ ("exist, what type each is, what their owner Lua " ++ ("callbacks are. Ticket 0117 is the open work to make " ++ ("this a true gdb-attach equivalent: pause the engine " ++ "main loop, query state, step, resume."))))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
            },
            .{
                .kind = "ticketref",
                .id = "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
                .note = "the gdb-attach-equivalent ticket",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| engine introspect",
                .note = "live state, today",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores info 0",
                .note = "post-mortem on the most recent crash",
            },
            .{
                .kind = "h2",
                .body = "4.3  Tracer",
            },
            .{
                .kind = "text",
                .body = "monitor CLIENT writes to the durian control socket; " ++ ("every shmif event between durian and a frameserver " ++ ("appears on the stream. logwatch with the panic / atlas " ++ ("/ font / orphan buckets reduces the engine log to the " ++ ("interesting lines. The bun verb running poll-test.ts " ++ ("is the per-event tracer for one segment in isolation: " ++ ("a 3-second loop over shmif.poll() that prints every " ++ ("event the segment receives. Useful when the question " ++ "is 'is durian sending us anything at all'."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| monitor CLIENT",
                .note = "all shmif events between durian and frameservers",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/poll-test.ts",
                .note = "single-segment event tracer, runs as its own tile",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs orphan",
                .note = "orphan-bucket filter on the engine log",
            },
            .{
                .kind = "h2",
                .body = "4.4  Profiler",
            },
            .{
                .kind = "text",
                .body = "metrics is the live profiler. atlas is the build-time " ++ ("profiler — the long-line spread (ticket 0024) shows " ++ ("every glyph atlas allocation as a horizontal bar; if " ++ ("one allocation is taking longer than the rest it stands " ++ ("out. The time builtin buckets any emitter into per-" ++ ("100ms windows; pair it with monitor or logwatch to " ++ "find the wall-clock distribution of an event class."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0024-build-atlas-live-paint-long-line",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "live: CPU, memory, segment count",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| atlas",
                .note = "build-time: glyph atlas allocations",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| time",
                .note = "bucketing for any emitter",
            },
            .{
                .kind = "h2",
                .body = "4.5  Visualizer (NEW)",
            },
            .{
                .kind = "text",
                .body = "dashboard is the hem builtin (auto-arch layer-6) that " ++ ("composes every spread into one workspace: status, " ++ ("metrics, monitor, logwatch, atlas, bugs all on one " ++ ("screen, each one its own cell, each one updating live. " ++ ("The senseye-applied substrate underneath is what makes " ++ ("the layout work — the hem visual-agent plan's layer 5 " ++ ("defines the spread/payload contract every cell honours. " ++ ("The point of dashboard is the same as the original " ++ ("Visualizer-as-fourth-tool argument: in 2012 you could " ++ "not see the system as a whole; now you can.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "the visualizer composition; one cell per spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/hem-cascade.ts",
                .note = "the visualizer being driven from TS",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "The roll-call complete for this domain. Part IV takes the " ++ ("same shape but lands it on a domain — seL4 in zig — " ++ ("where many of the verbs above do not exist yet, and the " ++ "chapter's job is partly to file the missing-verb tickets.")),
            },
            .{
                .kind = "crosslink",
                .target = "04_sel4_zig:ch1_introduction",
            },
        },
        .cross_links = .{
            "03_zig_arcan:ch3_principal_debugging",
            "04_sel4_zig:ch4_tools_of_the_trade",
            "00_foundations:ch4_tools_of_the_trade",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 3,
                .chapter = 4,
            },
        },
        .tickets = .{
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
            "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
            "0024-build-atlas-live-paint-long-line",
        },
    };
}
