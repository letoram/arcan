
pub fn __init() void {
    return .{
        .title = "Principal Debugging",
        .subtitle = "Part II · Ch 3 · The Self-Hosted Zig Fork",
        .part_id = 2,
        .chapter_id = 3,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The principal advantage of using an experimental " ++ ("approach is that one works with the actual behavior " ++ ("of the target system. This enables the analyst to " ++ ("establish a feedback chain where he or she measures " ++ "properties inside the system he or she manipulates."))),
                .cite = "Mellstrand & Ståhl 2012, p. 76",
            },
            .{
                .kind = "text",
                .body = "The original §3 names four moves and three imperatives. " ++ ("Subdivide, Measure, Represent, Intervene; Fail Early, " ++ "Often, Hard. We work them on the live sh-zig loop."),
            },
            .{
                .kind = "h2",
                .body = "3.1  Why analyse",
            },
            .{
                .kind = "epigraph",
                .body = "To make these kinds of alterations, we need to " ++ ("understand the system at hand, not only to discover " ++ ("where to change something but also to determine " ++ "potentially adverse consequences to such alteration.")),
                .cite = "Mellstrand & Ståhl 2012, p. 72",
            },
            .{
                .kind = "text",
                .body = "In this domain, 'where to change' is rarely the hard " ++ ("question — the auto-arch loop's panic-line draft tickets " ++ ("name a file:line within minutes of a regression. The hard " ++ ("question is the consequence: a fix to the aarch64 " ++ ("varargs prologue may break the x86_64 builds we test " ++ ("against, may fix one panic and uncover a second that was " ++ ("always there but masked, may improve fitness on the " ++ ("callgraph appl while regressing on the texttest one. The " ++ ("round model is built so that the consequence shows up in " ++ "the same round telemetry as the change.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "the round in flight, with consequences as they land",
            },
            .{
                .kind = "h2",
                .body = "3.2  Static and dynamic for compilers",
            },
            .{
                .kind = "epigraph",
                .body = "On realizing source code: large software systems " ++ ("are inherently too complex to understand by " ++ ("considering only source code and other static " ++ "sources.")),
                .cite = "Mellstrand & Ståhl 2012, p. 75",
            },
            .{
                .kind = "text",
                .body = "The static side: the fork's source diff against upstream " ++ ("zig, the IR dumps from a single round, the build log. " ++ ("The dynamic side: the actual codegen output of stage N, " ++ ("captured as ELF, replayable as disasm, comparable across " ++ ("rounds. The trap the original warns about applies " ++ ("doubly here — reading the codegen source for the " ++ ("varargs prologue tells you what the developer intended; " ++ ("only the disassembled output of stage 2 tells you what " ++ "stage 1 actually emitted."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/arcan",
                .note = "the dynamic side: actual emitted instructions",
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
                .body = "By compile unit. Each .zig file in the fork is its own " ++ ("subsystem for the loop's purposes; the units spread " ++ ("lists them with last-touched, error count, and " ++ ("build-state per unit. A regression in one round either " ++ ("appears in one unit (proximal cause: that unit's source " ++ ("or the codegen for one of its constructs) or in many " ++ ("(distal cause: a backend change that affects everything " ++ "lowering through it).")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "the units spread; one row per compile unit",
            },
            .{
                .kind = "h3",
                .body = "Measure",
            },
            .{
                .kind = "text",
                .body = "compile.errors is the live spread the build emits to. " ++ ("build_dur_ms and build_state per unit are the per-row " ++ ("instruments. selfhost.errors is the round-level " ++ ("aggregator. metrics is the host-side resource view — " ++ ("memory and IO during a build matter because a stage-2 " ++ ("binary that miscompiles may also leak; the leak is a " ++ "second symptom of the same fault."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0023-zigbuild-stream-step-events",
                .note = "the ticket that made the build stream observable",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "Measure: the build, with the spread updating live",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "Measure: host-side, during the build",
            },
            .{
                .kind = "h3",
                .body = "Represent",
            },
            .{
                .kind = "text",
                .body = "The hilbert spread renders the build dependency graph as " ++ ("a Hilbert-curve-tiled spatial view: each compile unit " ++ ("is a tile, colour encodes build state, neighbours in " ++ ("the curve are neighbours in the import graph. A " ++ ("regression that hits one tile is local; one that hits a " ++ ("diagonal stripe is a backend-wide effect. The senseye-" ++ ("applied substrate (layer 5 in the hem visual-agent " ++ ("plan) is what makes hilbert work as a live view rather " ++ "than a one-shot render."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
                .note = "Represent: the build graph as a spatial view",
            },
            .{
                .kind = "h3",
                .body = "Intervene",
            },
            .{
                .kind = "text",
                .body = "edit changes the fork's source. write creates a new " ++ ("selfhost-round driver script. hemSpawn brings up a " ++ ("fresh cell for a parallel investigation. After the " ++ ("edit, zigbuild runs in this cell while a sibling cell " ++ ("watches hilbert. The intervention and its consequence " ++ "are visible at the same time.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| edit /home/x/next/arcan/build_llvm/vendor/sh-zig/src/codegen/aarch64/Mir.zig FOO BAR",
                .note = "the edit verb; do not run blindly",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "the immediate consequence",
            },
            .{
                .kind = "h2",
                .body = "3.4  Information sources",
            },
            .{
                .kind = "epigraph",
                .body = "Source code is the first formal description that " ++ ("has enough precision to either directly – or " ++ ("through some transformation – form each individual " ++ "component of the intended system.")),
                .cite = "Mellstrand & Ståhl 2012, p. 95",
            },
            .{
                .kind = "text",
                .body = "Pre-execution: read on the fork's source, find on the " ++ ("codegen tree, grep for the offending construct, sym on " ++ ("the previous round's stage-2 binary. Pre-execution " ++ "answers what the system claims it will do.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep prologue /home/x/next/arcan/build_llvm/vendor/sh-zig/src/codegen/aarch64",
                .note = "pre: source-level claims about the prologue",
            },
            .{
                .kind = "text",
                .body = "In-execution: the zigbuild stream (ticket 0023 made it " ++ ("visible). engine watch on the live build. logwatch with " ++ ("the panic, atlas, and orphan buckets. monitor CLIENT to " ++ ("see what arcan does the moment the new stage-3 binary is " ++ ("loaded. In-execution answers what the system actually " ++ "does this time.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "in: panics, bucketed live",
            },
            .{
                .kind = "text",
                .body = "Post-execution: cores list, cores info on the most " ++ ("recent crash, cores bt for the backtrace. The auto-" ++ ("drafted panic-line ticket is the link from " ++ "post-execution back into the offline artifact.")),
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
                .body = "A miscompile in stage 1 only shows up at stage 3 runtime, " ++ ("and by then the stage-1 source diff that caused it may be " ++ ("twenty rounds back. The auto-arch loop's answer is to " ++ ("treat each round as a snapshot — fossil branch per " ++ ("round, all four binaries archived, the round telemetry " ++ ("saved as a JSON sidecar. To pin a regression to a round " ++ ("we walk the snapshots backwards, replaying the eval gate " ++ ("on each, until the first round that fails. The diff " ++ ("between that round and the previous one is the cause " ++ "spelled out.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| fossil log",
                .note = "the rounds, as fossil branches",
            },
            .{
                .kind = "h2",
                .body = "3.6  Imperatives",
            },
            .{
                .kind = "epigraph",
                .body = "The longer it takes from something failing to the " ++ ("failure being discovered the harder it is to find " ++ "out what happened."),
                .cite = "Mellstrand & Ståhl 2012, p. 110",
            },
            .{
                .kind = "h3",
                .body = "Fail Early",
            },
            .{
                .kind = "text",
                .body = "Zig comptime: assertions on type widths, alignment, " ++ ("signedness, fire at compile time and prevent the bad " ++ ("binary from existing. The eval gate in the auto-arch " ++ ("loop fires before merge, on the same hardware that runs " ++ ("the next round, so a regression cannot poison the next " ++ "round's stage 1.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Often",
            },
            .{
                .kind = "text",
                .body = "test_suite.sh runs every round; the hem runners under " ++ ("data/lash/hem_runners/ replay durian + sysdebug + " ++ ("callgraph + texttest as a four-appl matrix. A " ++ ("regression that affects only one of the four still " ++ "fails the round."))),
            },
            .{
                .kind = "h3",
                .body = "Fail Hard",
            },
            .{
                .kind = "text",
                .body = "Zig panics on UB rather than miscompiling-and-continuing. " ++ ("The fork keeps the panic paths even in release builds — " ++ ("see the no-panics-in-compositor-hot-paths feedback note. " ++ ("A clean crash that names a file:line is worth more than " ++ ("a soft fallback that lets stage 2 keep running with " ++ "invalid state.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "the load-bearing panics",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "The four actions, applied. Ch 4 names the verbs that " ++ ("make each action work and groups them as the debugger / " ++ "tracer / profiler / visualizer roll-call."),
            },
            .{
                .kind = "crosslink",
                .target = "02_zig_fork:ch4_tools_of_the_trade",
            },
        },
        .cross_links = .{
            "02_zig_fork:ch2_software_demystified",
            "02_zig_fork:ch4_tools_of_the_trade",
            "00_foundations:ch3_principal_debugging",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 2,
                .chapter = 3,
            },
        },
        .tickets = .{
            "0023-zigbuild-stream-step-events",
            "0001-sh-codegen-stack-overflow",
            "0002-sh-setSignedness-small-size-assert",
            "0007-statesnap-vcontext-stack-miscompile",
            "0008-lua-close-alignment-panic",
            "draft-d001-panic-select-zig-13053-body",
        },
    };
}
