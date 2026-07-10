
pub fn __init() void {
    return .{
        .title = "Tools of the Trade",
        .subtitle = "Part II · Ch 4 · The Self-Hosted Zig Fork",
        .part_id = 2,
        .chapter_id = 4,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The developer, just like other craftsmen, has an " ++ "extensive array of tools at his disposal.",
                .cite = "Mellstrand & Ståhl 2012, p. 119",
            },
            .{
                .kind = "text",
                .body = "The original groups debugger / tracer / profiler. We add " ++ ("Visualizer, because the senseye-applied substrate did not " ++ ("exist in 2012 and now it does. For the sh-zig domain " ++ ("specifically, the verbs cluster differently than they do " ++ ("in the runtime-arcan domain (Part III) — a compiler is a " ++ ("batch system, so the live tracer is the build stream " ++ ("itself, and the profiler measures correctness rather " ++ "than time.")))))),
            },
            .{
                .kind = "h2",
                .body = "4.1  Roll-call",
            },
            .{
                .kind = "text",
                .body = "Build / compile family: zigbuild, compile, selfhost. " ++ ("Object inspection: disasm, sym, dwarf, dietree, diegraph. " ++ ("Crash and post-mortem: cores list, cores info, cores bt. " ++ ("Build-graph and round telemetry: hilbert, status, " ++ ("auto-arch round-summary. Each verb gets its own paragraph " ++ ("below; the rest of this chapter is which verb to reach " ++ "for when, with verbboxes for each."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "the verb roll-call rendered live",
            },
            .{
                .kind = "h2",
                .body = "4.2  Debugger",
            },
            .{
                .kind = "epigraph",
                .body = "A debugger assist with debugging by allowing " ++ ("manipulation, the intervention, of execution flow " ++ ("and exploring of the state... One important " ++ ("attribute that can be deduced from this description " ++ ("is that a debugger is a dynamic tool working on an " ++ "executing system.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 120",
            },
            .{
                .kind = "text",
                .body = "For a still-running build the live compile.errors spread " ++ ("is the debugger: errors stream in as compile units fail, " ++ ("each row clickable to open the offending source at the " ++ ("right line. For a finished round, cores info on the " ++ ("stage-3 crash is the post-mortem; cores bt walks the " ++ ("backtrace to the panicked function. The bun verb opens a " ++ ("TS shell against the live compile process — useful when " ++ ("the question is 'what is sh-zig doing right now', not " ++ "'what did it just do'."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
                .note = "the open work to make compile-time gdb-attach feasible",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "live debugger: errors as they occur",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores list",
                .note = "post-mortem: every recent crash",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores info 0",
                .note = "post-mortem detail on the most recent core",
            },
            .{
                .kind = "h2",
                .body = "4.3  Tracer",
            },
            .{
                .kind = "text",
                .body = "zigbuild itself is the tracer. Per ticket 0023, the build " ++ ("emits stream-step events — one event per stage transition, " ++ ("one per compile unit start and finish, one per cache " ++ ("hit. The events come through the same pipe the spread " ++ ("renders from. The time builtin buckets them by 100ms " ++ ("windows, which is the natural granularity for spotting " ++ "where a slow build's wall time actually goes."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0023-zigbuild-stream-step-events",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| time",
                .note = "buckets the build event stream by time window",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "the trace source itself",
            },
            .{
                .kind = "h2",
                .body = "4.4  Profiler",
            },
            .{
                .kind = "text",
                .body = "auto-arch.round.fitness is the profiler. It measures " ++ ("compiler-correctness progress, not CPU time. The score " ++ ("per round is the count of compile units that compile " ++ ("cleanly weighted by a per-unit eval-gate result and " ++ ("discounted by regressions against the previous best. A " ++ ("round whose fitness is below the previous best is " ++ ("rejected; rejection still produces a snapshot, so a " ++ "rejected round is replayable for forensics.")))))),
            },
            .{
                .kind = "text",
                .body = "The hilbert spread is the build-time profiler, in the " ++ ("more conventional sense: it shows where build time is " ++ ("going, by compile unit. A unit that lights up red on " ++ ("every round is the obvious candidate for a refactor. " ++ ("Hilbert and round-fitness together answer two different " ++ "questions about the same loop.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
                .note = "build-time profile, spatial",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| auto-arch round-summary",
                .note = "the fitness score and its components for the latest round",
            },
            .{
                .kind = "h2",
                .body = "4.5  Visualizer (NEW)",
            },
            .{
                .kind = "text",
                .body = "The original has no visualizer chapter, and it is the " ++ ("section that most changes the answers to the previous " ++ ("three. For the compiler domain the two visualizers that " ++ ("earn their keep are the dietree and diegraph spreads. " ++ ("dietree renders the DWARF DIE tree of a stage-3 binary " ++ ("as a clickable tree spread; each DIE row links back to " ++ ("the source line that produced it. diegraph renders the " ++ ("type-and-call relations as a graph spread, with the " ++ ("same source-back link. Together they let the analyst " ++ ("answer questions like 'every site that uses this " ++ ("Sema-patched type, across the linked binary' in a few " ++ "clicks instead of a grep + manual cross-reference.")))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dietree",
                .note = "DWARF DIE tree as a clickable spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| diegraph",
                .note = "DWARF relation graph",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dwarf",
                .note = "addr to DIE for crash traces",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Five families, fifteen verbs. The point of cataloguing " ++ ("them this way is so the analyst opens this chapter " ++ ("instead of trying to remember which builtin handled " ++ ("DWARF last week. Part III takes the same roll-call shape " ++ ("and lands it on the runtime-arcan domain, where the " ++ "tracer is monitor and the profiler is metrics.")))),
            },
            .{
                .kind = "crosslink",
                .target = "03_zig_arcan:ch1_introduction",
            },
        },
        .cross_links = .{
            "02_zig_fork:ch3_principal_debugging",
            "03_zig_arcan:ch4_tools_of_the_trade",
            "00_foundations:ch4_tools_of_the_trade",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 2,
                .chapter = 4,
            },
        },
        .tickets = .{
            "0023-zigbuild-stream-step-events",
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
        },
    };
}
