
pub fn __init() void {
    return .{
        .title = "Principal Debugging",
        .subtitle = "Part III · Ch 3 · Zig-based arcan",
        .part_id = 3,
        .chapter_id = 3,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "On realizing source code: large software systems " ++ ("are inherently too complex to understand by " ++ ("considering only source code and other static " ++ "sources.")),
                .cite = "Mellstrand & Ståhl 2012, p. 75",
            },
            .{
                .kind = "text",
                .body = "Reading src/shmif/ for a week will not tell you why " ++ ("durian's segment_request hangs against afsrv_bun. Only " ++ ("the live shmif event log will. The visibility rule is " ++ "the corollary.")),
            },
            .{
                .kind = "h2",
                .body = "3.1  Why analyse",
            },
            .{
                .kind = "text",
                .body = "Predicting consequences. A change to shmif's signal-after-" ++ ("commit ordering touches every frameserver; a change to " ++ ("durian's segment routing touches every appl that opens " ++ ("subsegments. The reason ticket 0036 was filed before the " ++ ("first line of bun-side code was written: not to find " ++ ("where to put afsrv_bun, but to predict which existing " ++ ("frameservers' assumptions would break if the new one " ++ ("honoured the existing protocol exactly. The ticket's " ++ ("phase log is the consequence prediction with revisions " ++ "as evidence accumulated.")))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-afsrv-bun-frameserver",
                .note = "the consequence ledger",
            },
            .{
                .kind = "h2",
                .body = "3.2  Static and dynamic",
            },
            .{
                .kind = "text",
                .body = "Static side: src/, the bug ticket trail, the phase logs " ++ ("in 0036, the comments in the C glue. Static answers " ++ ("what the code claims it does. Dynamic side: monitor " ++ ("CLIENT subscribed to the durian control socket, engine " ++ ("watch on the live engine, the hem emit sidecar log " ++ ("(per the cat9_emit_sidecar_log memory note) for " ++ ("what hem itself observed. Dynamic answers what " ++ ("happened this run. The two never quite agree, and the " ++ "disagreement is where most bugs live."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| monitor CLIENT",
                .note = "dynamic: the live shmif protocol stream",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/.local/share/zig-sh-testing/hem_emits.log",
                .note = "dynamic: hem's own observation log",
            },
            .{
                .kind = "h2",
                .body = "3.3  Four actions",
            },
            .{
                .kind = "h3",
                .body = "Subdivide",
            },
            .{
                .kind = "text",
                .body = "Per frameserver. ps name=afsrv lists every live one; " ++ ("procfs <pid> opens the per-process spread for fd, " ++ ("threads, maps, status. Subdivision in this domain is " ++ ("structural — the OS already gives us the boundaries " ++ ("as PIDs — so the analyst's job is mostly about which " ++ "subset to look at.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "Subdivide: every frameserver, one row each",
            },
            .{
                .kind = "h3",
                .body = "Measure",
            },
            .{
                .kind = "text",
                .body = "metrics is the cross-cutting resource view: CPU and " ++ ("memory per process, segment count per frameserver, " ++ ("event-rate per segment. engine watch * subscribes to " ++ ("the engine's internal event firehose. monitor CLIENT " ++ ("is the durian-side analogue. The build.atlas long-line " ++ ("spread (ticket 0024) is the build-time analogue for the " ++ ("engine itself. Each of these is a different timescale: " ++ ("metrics for the second, monitor for the millisecond, " ++ "atlas for the build cycle."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0024-build-atlas-live-paint-long-line",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "Measure: live resource view",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| atlas",
                .note = "Measure: long-line build trace",
            },
            .{
                .kind = "h3",
                .body = "Represent",
            },
            .{
                .kind = "text",
                .body = "The metrics spread, the build.atlas long-line spread, " ++ ("and the hemParent.send SOH-prefix protocol. The last " ++ ("is the bridge that lets a TS script running in a child " ++ ("afsrv_bun cell render structured output back to its " ++ ("parent hem cell as a spread row. The protocol is " ++ ("installed in 0036 Phase 3i.5 but the parent's " ++ ("data_handler does not currently fire — the binding " ++ ("exists, the dispatch is broken, and that is on the " ++ "phase 3i.5 follow-up list."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "Represent: the composition of every spread",
            },
            .{
                .kind = "h3",
                .body = "Intervene",
            },
            .{
                .kind = "text",
                .body = "durian.send writes to the durian control socket. edit " ++ ("and write change source files. hemSpawn brings up a " ++ ("fresh sibling cell with its own chain. The TS-side " ++ ("intervention is the host bindings themselves: a script " ++ ("can fillRect, ident, signalVideo to alter what its own " ++ ("tile looks like, or durian.send to alter the workspace " ++ ("layout. The sibling-cell pattern is the safest way to " ++ ("experiment because it does not put the parent cell at " ++ ("risk; the parent watches the spread, the child runs " ++ "the chain.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/hem-cascade.ts",
                .note = "Intervene: TS orchestrating durian via host bindings",
            },
            .{
                .kind = "h2",
                .body = "3.4  Information sources",
            },
            .{
                .kind = "text",
                .body = "Pre-execution: bugs show <id>, bugs all (filter visually), " ++ ("the phase log within 0036. Pre answers what the " ++ "developers thought was true going in."),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs all",
                .note = "pre: every ticket that mentions shmif",
            },
            .{
                .kind = "text",
                .body = "In-execution: monitor CLIENT, engine watch *, the " ++ ("shmon log (per shmif_observation_recipes), logwatch " ++ ("with the panic|atlas|font|orphan buckets. In answers " ++ "what is happening live.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs orphan",
                .note = "in: the orphan-watchdog stream",
            },
            .{
                .kind = "text",
                .body = "Post-execution: cores list, cores info, the orphan log, " ++ ("the hem emit sidecar (~/.local/share/zig-sh-testing/" ++ ("hem_emits.log) for what hem itself recorded after the " ++ "fact. Post answers what survived to be reasoned about.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores list",
                .note = "post: every recent core",
            },
            .{
                .kind = "h2",
                .body = "3.5  The conundrum",
            },
            .{
                .kind = "epigraph",
                .body = "Snapshots and crash dumps are the central sources " ++ ("for information at a post-execution systemic state. " ++ ("They spring into place from different, but similar " ++ "mechanisms.")),
                .cite = "Mellstrand & Ståhl 2012, p. 105",
            },
            .{
                .kind = "text",
                .body = "A frameserver crash leaves orphans: the shmif page " ++ ("outlives the frameserver process, durian still holds " ++ ("references, the watchdog (ticket 0114) tries to clean " ++ ("up but produces false positives on long-lived external " ++ ("shmif clients. Walking from a crash dump back to 'what " ++ ("segment was being requested when this died' is the " ++ ("chapter's worked example: cores info on the most " ++ ("recent crash, cores bt for the trace, cross-referenced " ++ ("with the durian monitor stream from the same " ++ "wall-clock window. The shmon log is the ground truth.")))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0113-frameserver-orphan-survives-arcan-crash",
            },
            .{
                .kind = "ticketref",
                .id = "0114-watchdog-false-orphan-on-external-shmif-clients",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores bt $(cores list | head -1 | awk '{print $1}')",
                .note = "trace from the most recent crash; pair with logwatch",
            },
            .{
                .kind = "h2",
                .body = "3.6  Imperatives",
            },
            .{
                .kind = "h3",
                .body = "Fail Early",
            },
            .{
                .kind = "text",
                .body = "ARCAN_SHMIF_MONITOR is the env var that turns the " ++ ("shmif protocol from silent-and-fast to noisy-and-" ++ ("auditable. Set it for any session you suspect; the " ++ ("shmon log records every event between engine and " ++ ("frameserver. The cost is wall-clock; the benefit is " ++ "early visibility of protocol drift.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Often",
            },
            .{
                .kind = "text",
                .body = "The hem_workflow_runner.sh harness replays the " ++ ("subprojects' regression suites in a loop. The runner " ++ ("is the analogue of the auto-arch loop for runtime " ++ ("rather than compile-time regressions; it does not " ++ ("drive merge decisions but it does flag drift before it " ++ "lands.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Hard",
            },
            .{
                .kind = "text",
                .body = "Per the no-panics-in-compositor-hot-paths rule: when " ++ ("the engine catches a shmif protocol violation, it " ++ ("panics. The temptation to soften the panic is the " ++ ("antipattern the rule was filed to prevent. A clean " ++ ("DYING is worth more than an INVALID-STATE that " ++ "propagates silently into the next paint.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "the load-bearing panics, every recent one",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Subdivide, Measure, Represent, Intervene; Fail Early, " ++ ("Often, Hard. Ch 4 names the verb roll-call that makes " ++ "all of this operational in one or two clicks."),
            },
            .{
                .kind = "crosslink",
                .target = "03_zig_arcan:ch4_tools_of_the_trade",
            },
        },
        .cross_links = .{
            "03_zig_arcan:ch2_software_demystified",
            "03_zig_arcan:ch4_tools_of_the_trade",
            "00_foundations:ch3_principal_debugging",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 3,
                .chapter = 3,
            },
        },
        .tickets = .{
            "0036-afsrv-bun-frameserver",
            "0024-build-atlas-live-paint-long-line",
            "0113-frameserver-orphan-survives-arcan-crash",
            "0114-watchdog-false-orphan-on-external-shmif-clients",
        },
    };
}
