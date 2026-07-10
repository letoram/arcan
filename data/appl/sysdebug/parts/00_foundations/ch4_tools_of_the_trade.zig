
pub fn __init() void {
    return .{
        .title = "Tools of the Trade",
        .subtitle = "Part I · Ch 4 · Foundations",
        .part_id = 1,
        .chapter_id = 4,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The developer, just like other craftsmen, has an " ++ "extensive array of tools at his disposal.",
                .cite = "Mellstrand & Ståhl 2012, p. 119",
            },
            .{
                .kind = "text",
                .body = "The original closes Part 1 with a survey of the three " ++ ("instruments any analyst keeps within reach: a debugger, " ++ ("a tracer, a profiler. We close ours the same way, with " ++ ("one addition the original could not have written: a " ++ ("visualizer. The substrate that makes that addition " ++ ("possible (hem spreads, viz_bus, senseye-applied " ++ ("layer 5) did not exist in 2012. It exists now and it " ++ "changes the answers in §4.2 through §4.4.")))))),
            },
            .{
                .kind = "h2",
                .body = "4.1  Layout: the hem_dev roll-call",
            },
            .{
                .kind = "text",
                .body = "The verbs we will keep referring to are six families. " ++ ("system/debug: status, ps, procfs, proc, cores, metrics, " ++ ("engine. files/search: read, edit, write, find, grep, " ++ ("glob, head, tail, wc, fs, hash. build/compile: compile, " ++ ("zigbuild, atlas, refactor, selfhost. code analysis: " ++ ("disasm, dwarf, dietree, diegraph, sym, snippet. time/" ++ ("data: time, hilbert, memcloud. introspection and dispatch: " ++ ("git, fossil, bugs, logwatch, sheet, paste, screenshot, " ++ ("dashboard, run, bun, claude. About fifty verbs total. " ++ ("Each is one Lua file under data/lash_builtins/hem_dev/. " ++ ("The catalogue does not get re-explained in each " ++ "section; sections cite by name.")))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
                .note = "the shared substrate every verb imports",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/compile.lua",
                .note = "the canonical template — copy this when writing " ++ "a new verb",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/data/lash_builtins/hem_dev '*.lua'",
                .note = "the full inventory",
            },
            .{
                .kind = "bridge",
                .body = "The original's first instrument is the debugger.",
            },
            .{
                .kind = "h2",
                .body = "4.2  Debugger",
            },
            .{
                .kind = "epigraph",
                .body = "A debugger assist with debugging by allowing " ++ ("manipulation, the intervention, of execution flow " ++ ("and exploring of the state… One important " ++ ("attribute that can be deduced from this description " ++ ("is that a debugger is a dynamic tool working on an " ++ "executing system.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 120",
            },
            .{
                .kind = "text",
                .body = "Our debugger is not gdb. The reasons are the visibility " ++ ("rule (gdb runs in its own TTY which the user does not " ++ ("watch) and the abstraction mismatch (gdb thinks at the " ++ ("register level, we mostly want to think at the segment " ++ ("level). The hem-native equivalent is split across " ++ ("three verbs depending on what is being debugged. bugs " ++ ("show <id> opens the ticket-bound session: the bug " ++ ("record IS the breakpoint, with paths, repro steps, and " ++ ("the analyst's prior thoughts already loaded. engine " ++ ("introspect is the live state inspector — every arcan " ++ ("global, every active segment, dumped into a spread. " ++ ("cores info <id> is the post-mortem inspector for crash " ++ "dumps."))))))))))),
            },
            .{
                .kind = "text",
                .body = "Ticket 0117 is the open work to make engine introspect a " ++ ("true peer of gdb-attach — register state, instruction " ++ ("pointer, source-line mapping. Until that lands, the " ++ ("register-level work routes through gdb proper, with " ++ ("cores info as the bridge: the spread shows the symbolic " ++ ("summary; click a row and a gdb cell opens at the " ++ "matching frame."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
                .note = "the gap between hem and gdb, written down",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0117",
                .note = "the ticket that defines our gdb-attach equivalent",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| engine introspect",
                .note = "the live debugger surface as it stands today",
            },
            .{
                .kind = "bridge",
                .body = "Where the debugger pauses, the tracer just records.",
            },
            .{
                .kind = "h2",
                .body = "4.3  Tracer",
            },
            .{
                .kind = "text",
                .body = "Three tracers, one per layer. monitor CLIENT (issued " ++ ("over durian's control socket) is the engine-level " ++ ("tracer: every shmif client's lifecycle and every " ++ ("segment event flows back as a structured stream. " ++ ("logwatch is the file-level tracer; it tails ~/.arcan/" ++ ("logs and buckets entries by category — panic, atlas, " ++ ("font, orphan, net — so a one-hour session compresses " ++ ("into a few rows. The time builtin is the bucket-of-" ++ ("anything tracer: pipe any emitter into it and get a " ++ ("spread keyed by time window, useful when correlating " ++ "two streams."))))))))),
            },
            .{
                .kind = "text",
                .body = "There is a fourth tracer that lives on the TS side: " ++ ("bun poll-test.ts (or any equivalent module) reads " ++ ("shmif events directly from inside an afsrv_bun " ++ ("segment. The trace volume can be considerable — the " ++ ("original is right that volume is the tracer's main " ++ ("ergonomic problem. Pair with logwatch's bucketing or " ++ "the time builtin to keep it readable."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| monitor CLIENT",
                .note = "engine-level tracer: every shmif client",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs",
                .note = "file-level tracer: bucketed engine log",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/poll-test.ts",
                .note = "TS-level tracer: shmif events from inside a " ++ "Bun segment",
            },
            .{
                .kind = "bridge",
                .body = "The third instrument balances accuracy against overhead.",
            },
            .{
                .kind = "h2",
                .body = "4.4  Profiler",
            },
            .{
                .kind = "text",
                .body = "Two profilers, with a third we keep insisting is one " ++ ("even though the book would not. metrics is the live " ++ ("profiler — CPU, memory, fd counts per process, per " ++ ("frameserver, per hem cell. atlas is the build-time " ++ ("profiler — every long-line in every translation unit, " ++ ("rolled up so the slowest part of a build stands out " ++ ("without scanning a stream. Both fit the original's " ++ "definition cleanly.")))))),
            },
            .{
                .kind = "text",
                .body = "The third one is the auto-arch loop's per-round " ++ ("fitness score. It is a profiler in the strict sense — " ++ ("it measures progress against an objective — except the " ++ ("objective is compiler correctness, not wall time. The " ++ ("book would call this domain-specific telemetry; we " ++ ("call it a profiler because it serves the same role in " ++ ("the analyst's workflow, and the workflow is the thing " ++ "the chapter is naming.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "live profiler: per-process resources",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| atlas",
                .note = "build-time profiler: long-line tracker",
            },
            .{
                .kind = "bridge",
                .body = "Three instruments down. The fourth is the one the " ++ "original could not write.",
            },
            .{
                .kind = "h2",
                .body = "4.5  Visualizer (new)",
            },
            .{
                .kind = "text",
                .body = "There is no §4.5 in the original book. The reason is " ++ ("structural: in 2012, the substrate did not exist. " ++ ("Senseye was a year away (2013), the visual " ++ ("reverse-engineering work that produced hilbert curves " ++ ("and trigram views came later, and the hem spread " ++ ("model that ties them together is post-2022. By the time " ++ ("all three exist together — which is now, in this " ++ ("codebase — there is a fourth instrument the analyst " ++ "reaches for, distinct from the other three."))))))),
            },
            .{
                .kind = "text",
                .body = "What it is: the senseye-applied layer-5 substrate. The " ++ ("verbs that live there are hilbert (build graph as " ++ ("spatial map), dietree (DWARF DIE forest), diegraph " ++ ("(DIE relations as a graph), memcloud (live mapping " ++ ("point cloud), the disasm spread (asm side-by-side with " ++ ("source). The dashboard verb is the composition root — " ++ ("one keystroke and every relevant spread for the auto-" ++ "arch surface lays itself out across the workspace.")))))),
            },
            .{
                .kind = "text",
                .body = "What it is for: representations no human reads from " ++ ("raw text. The book quoted in §3.3 — no analyst has a " ++ ("sense for tree balance or NULL pointer use — applies " ++ ("doubly to build-time data. Compile graphs are too big " ++ ("to read as a list and too dense to grep. A hilbert " ++ ("curve makes the topology visible at a glance. A dietree " ++ ("spread makes a 200k-line DWARF dump navigable. The " ++ ("visualizer's role in the analyst's loop is to take the " ++ ("output of the other three instruments and put it in a " ++ "shape the eye can scan.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
                .note = "build graph as spatial map",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dietree",
                .note = "DWARF as forest",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "every spread composed in one workspace",
            },
            .{
                .kind = "bridge",
                .body = "Part I is done. The four parts that follow take what " ++ "this chapter named and apply it to one stack each.",
            },
            .{
                .kind = "h2",
                .body = "Hand-off to Parts II through V",
            },
            .{
                .kind = "text",
                .body = "Part II: the self-hosted Zig fork. Owner is Agent A. " ++ ("Verb domain: zigbuild, compile, selfhost, disasm, " ++ ("hilbert, sym, dwarf, dietree, diegraph, cores. " ++ ("Worked example: a stage-1 miscompile that shows up at " ++ "stage 3 runtime."))),
            },
            .{
                .kind = "text",
                .body = "Part III: the zig migration of arcan. Owner is Agent " ++ ("B. Verb domain: bun, the shmif paint primitives, " ++ ("durian.send, monitor, engine introspect/watch, " ++ ("procfs, metrics, bugs. Worked example: a segment " ++ "request hang in afsrv_bun."))),
            },
            .{
                .kind = "text",
                .body = "Part IV: seL4 bootstrap in zig. Owner is Agent C. " ++ ("Verb domain: today, read, grep, find, disasm, sym, " ++ ("logwatch. Tomorrow, a caps verb, a cspace browser, a " ++ ("boot-stage hilbert — Agent C's job to file the tickets " ++ ("and write the verbs first. Worked example: a " ++ "capability-derivation mistake at rootserver bringup.")))),
            },
            .{
                .kind = "text",
                .body = "Part V: a12 over Tailscale. Owner is Agent D. Verb " ++ ("domain: arcan-net, procfs (for socket fd inspection), " ++ ("time (for frame timing), tomorrow a .monitor verb. " ++ ("Worked example: a render glitch that turns out to be " ++ "packet reordering rather than a renderer bug."))),
            },
            .{
                .kind = "text",
                .body = "Each agent gets the same brief: STYLE.md, CONTRACT.md, " ++ ("the relevant section of OUTLINE.md, the ticket list " ++ ("above, and a worktree under parts/0N_<part>/ so the " ++ "four agents can write in parallel without colliding.")),
            },
        },
        .cross_links = .{
            "00_foundations:ch3_principal_debugging",
            "00_foundations:ch0_architecture",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 4,
            },
        },
        .tickets = .{
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
            "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
            "0036-afsrv-bun-frameserver",
        },
    };
}
