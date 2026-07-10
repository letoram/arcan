
pub fn __init() void {
    return .{
        .title = "Principal Debugging",
        .subtitle = "Part I · Ch 3 · Foundations",
        .part_id = 1,
        .chapter_id = 3,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The principal advantage of using an experimental " ++ ("approach is that one works with the actual behavior " ++ ("of the target system. This enables the analyst to " ++ ("establish a feedback chain where he or she measures " ++ "properties inside the system he or she manipulates."))),
                .cite = "Mellstrand & Ståhl 2012, p. 76",
            },
            .{
                .kind = "text",
                .body = "This is the chapter that earns the appl. The original is " ++ ("where the methodology lives — Subdivide, Measure, " ++ ("Represent, Intervene; the three imperatives Fail Early, " ++ ("Fail Often, Fail Hard. Six sections in the book, six " ++ ("sections here, every one of them landed in hem verbs " ++ ("you can run from where you are reading. The visibility " ++ ("rule was filed for this chapter even before it was " ++ "written; the chapter is what the rule was for.")))))),
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
                .body = "Most of the time the question is not 'where do I change " ++ ("this' — that is usually findable with grep. The question " ++ ("is 'what else does this change touch.' Ticket 0036 (the " ++ ("afsrv_bun work) was opened, in its very first paragraph, " ++ ("by predicting the consequences of swapping the bridge " ++ ("out from under the running Claude Code session. That " ++ ("prediction is the analysis. The fix was downstream of " ++ "the analysis by months.")))))),
            },
            .{
                .kind = "text",
                .body = "There is a related case the original raises that we " ++ ("feel: the people who originally knew why a thing was the " ++ ("way it was may not be available, and even if they are, " ++ ("their memory may be wrong. Half of this codebase is its " ++ ("own first author having forgotten what he was thinking " ++ ("in 2019. The fossil ticket DB is the workaround for that — " ++ "writing the analysis down, in advance of needing it."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "an analysis written down before the fix",
            },
            .{
                .kind = "bridge",
                .body = "The next section says what counts as analysis.",
            },
            .{
                .kind = "h2",
                .body = "3.2  Static and dynamic",
            },
            .{
                .kind = "epigraph",
                .body = "On realizing source code: large software systems " ++ ("are inherently too complex to understand by " ++ ("considering only source code and other static " ++ "sources.")),
                .cite = "Mellstrand & Ståhl 2012, p. 75",
            },
            .{
                .kind = "text",
                .body = "Static is the codebase as text — sources, header files, " ++ ("linker maps, the fossil ticket comments, the comments in " ++ ("build.zig. Dynamic is what happens when the binary runs " ++ ("— the events crossing shmif, the logs in ~/.arcan/logs, " ++ ("the metrics spread, the auto-arch loop's per-round event " ++ ("stream. The original's argument is that no amount of " ++ ("static reading will ever explain why durian's " ++ ("segment_request hangs in a particular configuration. The " ++ ("only way to know is to watch it happen. The visibility " ++ ("rule is the corollary: if dynamic information is the " ++ ("only kind that explains certain failures, then making " ++ ("dynamic information visible to the analyst is the " ++ "load-bearing tool of the trade."))))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep panic /home/x/next/arcan/src",
                .note = "the static surface of one anomaly",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "the dynamic surface of the same anomaly",
            },
            .{
                .kind = "bridge",
                .body = "The original then names the four moves. Naming them is " ++ "the next section.",
            },
            .{
                .kind = "h2",
                .body = "3.3  Four actions: subdivide, measure, represent, intervene",
            },
            .{
                .kind = "epigraph",
                .body = "We can, due to the way software is constructed, " ++ ("always divide a software system into one or more " ++ ("system of subsystems and partitioning a system in " ++ ("ways befitting of the particular problem at hand " ++ ("is one of the primary challenges for an analyst to " ++ "deal with.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 80",
            },
            .{
                .kind = "h3",
                .body = "Subdivide",
            },
            .{
                .kind = "text",
                .body = "The first action is to break the system into pieces you " ++ ("can reason about one at a time. hem's spread metaphor " ++ ("is exactly that — one cell per subsystem, each cell its " ++ ("own job, each job's body its own observation channel. " ++ ("Open status to see every active subsystem at once; click " ++ ("into any one to subdivide further. The dashboard verb is " ++ ("the rolled-up form, intended for the case where you want " ++ ("every relevant cell on screen at once with no manual " ++ "spawning."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "Subdivide: every subsystem at once",
            },
            .{
                .kind = "h3",
                .body = "Measure",
            },
            .{
                .kind = "text",
                .body = "Measurement is what the cell body fills with. metrics " ++ ("for live CPU and memory; procfs for fds, threads, maps; " ++ ("engine watch for live arcan globals; cores for " ++ ("post-mortem state; logwatch for bucketed historical " ++ ("events. The original is careful to point out that " ++ ("dynamic measurement perturbs what it measures — true " ++ ("for us too. metrics polls, logwatch tails, engine watch " ++ ("subscribes to event hooks. Each carries some overhead " ++ "the analyst must keep in mind."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "Measure: live resource use as a spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| engine introspect",
                .note = "Measure: the engine's view of its own state",
            },
            .{
                .kind = "h3",
                .body = "Represent",
            },
            .{
                .kind = "text",
                .body = "Raw measurement is illegible. The chapter quotes the " ++ ("book on this directly: no human has a sense for bad " ++ ("tree balance, NULL pointer use, or cross-segment event " ++ ("drift. Representation is what makes those legible. The " ++ ("spread itself is one representation; senseye-applied " ++ ("layer 5 (the visualizer substrate, see Ch 4) is a " ++ ("richer one — hilbert curves for build graphs, disasm " ++ ("spreads for code-and-asm, the dietree for DWARF " ++ ("structure. The senseye family of views is the " ++ "non-textual end of the same idea.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
                .note = "Represent: the build graph as a spatial map",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "Represent: every spread composed in one " ++ "workspace",
            },
            .{
                .kind = "h3",
                .body = "Intervene",
            },
            .{
                .kind = "text",
                .body = "Intervention is changing the system to test a " ++ ("hypothesis. edit and write are the source-level " ++ ("interventions. durian.send is the running-system one — " ++ ("an IPC line to the window manager that can swap the " ++ ("active workspace, kill a tile, fire a menu path, send a " ++ ("monitor subscription. hemSpawn from a TS module spawns " ++ ("a sibling cell with a pre-loaded chain; the parent-" ++ ("control SOH protocol is the inverse, a child cell " ++ ("telling its parent to dispatch a verb. All of these are " ++ ("interventions, and all of them are visible — the user " ++ ("sees the new cell, the swapped layout, the dispatched " ++ "verb.")))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| edits",
                .note = "Intervene: every recent edit, listed",
            },
            .{
                .kind = "bridge",
                .body = "The four actions need information to act on. The next " ++ "section is where it comes from.",
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
                .body = "The book splits sources by phase: pre-execution " ++ ("(source, design docs, the toolchain itself, symbol " ++ ("tables, debug info), in-execution (system calls, IPC, " ++ ("logs, traces), post-execution (crash dumps, snapshots). " ++ ("Each phase has its own set of hem verbs. read, find, " ++ ("grep, sym, disasm, dwarf for the pre-execution side. " ++ ("monitor, engine watch, metrics, logwatch for the " ++ ("in-execution. cores list, cores info, cores bt for " ++ ("post-execution. The visibility rule applies in all " ++ ("three: a verb a chapter mentions has a verbbox the " ++ "reader runs."))))))))),
            },
            .{
                .kind = "text",
                .body = "The original makes one observation we want to lift " ++ ("directly: post-execution analysis is often the only " ++ ("kind available. Crashes are rare and context-dependent. " ++ ("The auto-arch loop's discipline — every round leaves a " ++ ("snapshot, every failure leaves a coredump, every event " ++ ("stream is logged with timestamps — is what turns rare " ++ "post-execution evidence into a queryable record."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan",
                .note = "pre-execution: the symbol table",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| monitor CLIENT",
                .note = "in-execution: durian's view of every shmif " ++ "client",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores list",
                .note = "post-execution: every recent crash, browseable",
            },
            .{
                .kind = "bridge",
                .body = "The next section is the obstacle that running on rare " ++ "post-execution evidence creates.",
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
                .body = "The conundrum: a crash dump tells you proximally what " ++ ("happened, but the path that got there is gone. The " ++ ("original's resolution is iteration — restart the " ++ ("system, step closer to the failure point, capture a new " ++ ("snapshot, repeat. The auto-arch loop is exactly this. " ++ ("Each round is a snapshot in a fossil branch; each round " ++ ("is replayable; each round's eval gate either passes " ++ ("(merge) or fails (next round picks up at the same " ++ ("branch tip). The fitness score across rounds is what " ++ ("the original calls 'closer to the failure point' — a " ++ "metric that is allowed to be domain-specific."))))))))),
            },
            .{
                .kind = "text",
                .body = "There is a place this argument breaks down. The book " ++ ("assumes the system is restart-cheap. arcan as a running " ++ ("compositor is not — restarting throws out user state " ++ ("and the contents of every running hem cell. So the " ++ ("auto-arch loop runs in fossil branches that work on " ++ ("isolated builds, never on the live compositor. The " ++ ("live compositor is debugged in place; the auto-arch " ++ ("loop is for the parts of the system that can be " ++ "rebooted."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| fossil log",
                .note = "every recent round, branched",
            },
            .{
                .kind = "bridge",
                .body = "The chapter closes on the three imperatives.",
            },
            .{
                .kind = "h2",
                .body = "3.6  Fail early, fail often, fail hard",
            },
            .{
                .kind = "epigraph",
                .body = "The longer it takes from something failing to the " ++ ("failure being discovered the harder it is to find " ++ "out what happened."),
                .cite = "Mellstrand & Ståhl 2012, p. 110",
            },
            .{
                .kind = "text",
                .body = "Fail Early. Zig's comptime catches what it can before " ++ ("execution; the auto-arch loop's eval gates run before " ++ ("merge; the hem builtins lint their own arguments " ++ ("before spawning a job. Each early-fail is one fewer " ++ "round of confusion later."))),
            },
            .{
                .kind = "text",
                .body = "Fail Often. Tests in tools/test/ are run on every " ++ ("round; the hem_workflow_runner.sh harness exists " ++ ("specifically to make failures cheap and frequent; the " ++ ("ARCAN_SHMIF_MONITOR rolling-buffer captures every " ++ ("shmif segment's recent events so post-mortem evidence " ++ "is always available, not gathered after the fact.")))),
            },
            .{
                .kind = "text",
                .body = "Fail Hard. The most counter-intuitive of the three. " ++ ("The discipline this codebase has settled on, after " ++ ("much argument, is that an arcan engine that has " ++ ("detected an invalid state should panic, not soften. " ++ ("This is the rule the visibility-rule article and the " ++ ("no-panics-in-compositor-hot-paths memo agree on: " ++ ("DYING is better than INVALID-STATE, because INVALID-" ++ ("STATE leaks into other subsystems and the eventual " ++ "crash is no longer correlated with its cause."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "Fail Hard, in evidence",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch4_tools_of_the_trade",
            },
            .{
                .kind = "bridge",
                .body = "The next chapter is the tools — the verbs that put the " ++ ("four actions and three imperatives into the analyst's " ++ "hands."),
            },
        },
        .cross_links = .{
            "00_foundations:ch2_software_demystified",
            "00_foundations:ch4_tools_of_the_trade",
            "00_foundations:visibility_rule_article",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 3,
            },
        },
        .tickets = .{
            "0036-visibility-rule",
            "0036-afsrv-bun-frameserver",
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
        },
    };
}
