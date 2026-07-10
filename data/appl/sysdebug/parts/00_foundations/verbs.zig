
pub fn __init() void {
    return .{
        .title = "Verbs",
        .subtitle = "Back matter",
        .part_id = 1,
        .chapter_id = 99,
        .body = .{
            .{
                .kind = "text",
                .body = "Every verbbox the appl publishes, grouped by what it " ++ ("does. Click any of these in v2; copy any of them in " ++ "v1."),
            },
            .{
                .kind = "h2",
                .body = "Subdivide",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "every active subsystem at once",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan",
                .note = "the arcan process tree",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "every alive frameserver",
            },
            .{
                .kind = "h2",
                .body = "Measure",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "live resource use",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| engine introspect",
                .note = "the engine's view of its own state",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $$ maps",
                .note = "the loader's output for this very cell",
            },
            .{
                .kind = "h2",
                .body = "Represent (visualizer substrate)",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
                .note = "build graph as spatial map",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dietree",
                .note = "DWARF DIE forest",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "every spread composed in one workspace",
            },
            .{
                .kind = "h2",
                .body = "Intervene",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| edits",
                .note = "every recent edit in flight",
            },
            .{
                .kind = "h2",
                .body = "Pre-execution information sources",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan",
                .note = "the symbol table the linker emitted",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a",
                .note = "the linker's output for the shmif library",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/CLAUDE.md",
                .note = "the project's rules",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build.zig",
                .note = "the build script in its actual form",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep panic /home/x/next/arcan/src",
                .note = "every panic site in the engine",
            },
            .{
                .kind = "h2",
                .body = "In-execution information sources",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| monitor CLIENT",
                .note = "durian's view of every shmif client",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs",
                .note = "bucketed engine log",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "panics, only",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/poll-test.ts",
                .note = "shmif events from inside an afsrv_bun segment",
            },
            .{
                .kind = "h2",
                .body = "Post-execution information sources",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores list",
                .note = "every recent crash, browseable",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| fossil log",
                .note = "every recent auto-arch round, branched",
            },
            .{
                .kind = "h2",
                .body = "Build and toolchain",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "start a build, watch the live error spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| atlas",
                .note = "build-time long-line tracker",
            },
            .{
                .kind = "h2",
                .body = "Tickets and tickets-as-debuggers",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "the anchor ticket",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-afsrv-bun-frameserver",
                .note = "the worked example",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0117",
                .note = "the gdb-attach equivalent ticket",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs all",
                .note = "the full ticket inventory (fossil)",
            },
            .{
                .kind = "h2",
                .body = "Inventory",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/data/lash_builtins/hem_dev '*.lua'",
                .note = "every hem_dev verb",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/frameserver",
                .note = "every frameserver",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/a12",
                .note = "the a12 sources",
            },
        },
        .cross_links = .{
            "00_foundations:refs",
            "00_foundations:tickets",
            "00_foundations:xref",
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
