
pub fn __init() void {
    return .{
        .title = "Cross-reference",
        .subtitle = "Back matter",
        .part_id = 1,
        .chapter_id = 99,
        .body = .{
            .{
                .kind = "text",
                .body = "Every section of the original book that this appl " ++ ("mirrors, with the sysdebug section that does the " ++ ("mirroring. Use this to find where in this codebase a " ++ "particular original-book idea is applied.")),
            },
            .{
                .kind = "h2",
                .body = "Original Ch 1 → sysdebug Part I Ch 1",
            },
            .{
                .kind = "text",
                .body = "1.1 Demarcation → sysdebug 1.1 (with " ++ "scope narrowed to the four sub-projects).",
            },
            .{
                .kind = "text",
                .body = "1.2 Software-Intensive Systems → sysdebug " ++ "1.2 (the arcan stack as worked example).",
            },
            .{
                .kind = "text",
                .body = "1.3 Cause and/of Panic → sysdebug 1.3 " ++ ("(proximal/distal mapped onto the segment_request " ++ "hang chain)."),
            },
            .{
                .kind = "text",
                .body = "1.4 Origin of Anomalies → sysdebug 1.4 " ++ "(four shapes of inconsideration, one per part).",
            },
            .{
                .kind = "text",
                .body = "1.5 Debugging Methodology → sysdebug 1.5 " ++ "(the visibility rule as the discipline; not a method).",
            },
            .{
                .kind = "text",
                .body = "1.6 Concluding Remarks → sysdebug 1.6 " ++ ("(“what is software” → " ++ "what crosses shmif)."),
            },
            .{
                .kind = "h2",
                .body = "Original Ch 2 → sysdebug Part I Ch 2",
            },
            .{
                .kind = "text",
                .body = "2.1 Hello World → sysdebug 2.1 (four " ++ "hello worlds, one per part).",
            },
            .{
                .kind = "text",
                .body = "2.2 Source-to-Binary → sysdebug 2.2 (four " ++ "tool chains, decoupled).",
            },
            .{
                .kind = "text",
                .body = "2.3 Developer of High-Level Code → " ++ ("sysdebug 2.3 (developer's assumptions in CLAUDE.md, " ++ "_helpers.lua, build.zig)."),
            },
            .{
                .kind = "text",
                .body = "2.4 Source and Compiler → sysdebug 2.4 " ++ "(C, Zig, Lua restrictions side by side).",
            },
            .{
                .kind = "text",
                .body = "2.5 Object Code and the Linker → sysdebug " ++ ("2.5 (the linker analogy: shmif is the runtime linker " ++ "for the whole system)."),
            },
            .{
                .kind = "text",
                .body = "2.6 Executable and Loading → sysdebug 2.6 " ++ "(arcan dynamic-by-necessity; seL4 the inversion).",
            },
            .{
                .kind = "text",
                .body = "2.7 Executing Software → sysdebug 2.7 " ++ ("(Asahi BUILD_PROFILE=release as the canonical " ++ "machine-limit case)."),
            },
            .{
                .kind = "text",
                .body = "2.8 OS and Process → sysdebug 2.8 (shmif " ++ ("segment + viz_bus as arcan-added abstractions; seL4 " ++ "replaces the OS abstraction)."),
            },
            .{
                .kind = "h2",
                .body = "Original Ch 3 → sysdebug Part I Ch 3",
            },
            .{
                .kind = "text",
                .body = "3.1 Why Analyze → sysdebug 3.1 (predicting " ++ "consequences; tickets-as-prediction).",
            },
            .{
                .kind = "text",
                .body = "3.2 Software System Analysis → sysdebug " ++ ("3.2 (static and dynamic; visibility rule as " ++ "corollary)."),
            },
            .{
                .kind = "text",
                .body = "3.3 System Views (the four-action core) → " ++ ("sysdebug 3.3 (Subdivide/Measure/Represent/Intervene " ++ "in hem verbs)."),
            },
            .{
                .kind = "text",
                .body = "3.4 Information Sources → sysdebug 3.4 " ++ "(pre/in/post-execution mapped to verb families).",
            },
            .{
                .kind = "text",
                .body = "3.5 The Conundrum → sysdebug 3.5 (auto-" ++ "arch round-as-snapshot; live compositor exempt).",
            },
            .{
                .kind = "text",
                .body = "3.6 Imperatives → sysdebug 3.6 (Fail " ++ ("Early/Often/Hard, with Fail Hard as the most " ++ "load-bearing of the three for arcan)."),
            },
            .{
                .kind = "h2",
                .body = "Original Ch 4 → sysdebug Part I Ch 4",
            },
            .{
                .kind = "text",
                .body = "4.1 Layout → sysdebug 4.1 (hem_dev " ++ "verb roll-call by family).",
            },
            .{
                .kind = "text",
                .body = "4.2 Debugger → sysdebug 4.2 (bugs show, " ++ ("engine introspect, cores info; ticket 0117 as the " ++ "open gap)."),
            },
            .{
                .kind = "text",
                .body = "4.3 Tracer → sysdebug 4.3 (monitor, " ++ "logwatch, time, bun poll-test).",
            },
            .{
                .kind = "text",
                .body = "4.4 Profiler → sysdebug 4.4 (metrics, " ++ "atlas, auto-arch fitness).",
            },
            .{
                .kind = "text",
                .body = "(no §4.5 in the original) → sysdebug 4.5 " ++ "Visualizer (new; senseye-applied substrate).",
            },
            .{
                .kind = "h2",
                .body = "Original Ch 0 (no analogue)",
            },
            .{
                .kind = "text",
                .body = "The original has no architecture chapter. sysdebug " ++ ("has Ch 0 because this codebase is too dense to land " ++ "in without a map."),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch0_architecture",
            },
            .{
                .kind = "h2",
                .body = "Parts II–V cross-refs",
            },
            .{
                .kind = "text",
                .body = "Each chapter agent writing one of Parts II–V " ++ ("owes an extension to this table: every original-book " ++ ("section their chapter mirrors, with the sysdebug " ++ ("section name. v2 of this page will autogenerate from " ++ "the chapters’ own metadata."))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/data/appl/sysdebug/OUTLINE.md",
                .note = "the master outline driving all cross-references",
            },
        },
        .cross_links = .{
            "00_foundations:refs",
            "00_foundations:tickets",
            "00_foundations:verbs",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 99,
            },
        },
    };
}
