
pub fn __init() void {
    return .{
        .title = "Architecture",
        .subtitle = "Part I · Ch 0 · Foundations",
        .part_id = 1,
        .chapter_id = 0,
        .body = .{
            .{
                .kind = "h2",
                .body = "0.1  Demarcation: what is in this repo",
            },
            .{
                .kind = "text",
                .body = "Walking into /home/x/next/arcan cold is a bit like walking " ++ ("into someone's workshop after they've gone to bed. There " ++ ("is a lot, much of it dusty, none of it labelled. Ten " ++ ("directories at the root and you cannot tell which two you " ++ ("can ignore. This chapter is the map. Read once; come back " ++ "whenever you have forgotten where something lives.")))),
            },
            .{
                .kind = "text",
                .body = "The ten that matter: src/ (engine + frameservers + shmif), " ++ ("data/ (lua appls, lash shell, hem verbs), build_llvm/ " ++ ("(the LLVM-tainted half kept apart so the self-hosted " ++ ("backend does not have to see it), .fossil (single ticket " ++ ("DB; ~103 tickets — the legacy bugs/ folder was deleted " ++ ("2026-05-02 per ticket 0150), docs/ (the few long-form " ++ ("planning files), " ++ ("tools/ (the auto-arch loop and friends), reference/ " ++ ("(upstream durian, mirrored not modified), build.zig and " ++ ("build.zig.zon at the root, CLAUDE.md (the project rules), " ++ "zig-out/ (everything builds into here)."))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/CLAUDE.md",
                .note = "the project rules — visibility, BUILD_PROFILE, what not to delete",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build.zig",
                .note = "what gets built and how",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/docs/selfhost_plan.md",
                .note = "the medium-term plan",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "see what's happening in the repo right now",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/CLAUDE.md",
                .note = "the rules in their actual form",
            },
            .{
                .kind = "bridge",
                .body = "The two halves — engine in src/, lua in data/ — are " ++ "connected by shmif. That is the next section.",
            },
            .{
                .kind = "h2",
                .body = "0.2  The engine",
            },
            .{
                .kind = "text",
                .body = "arcan is one binary, src/engine/arcan_main.zig, that does " ++ ("compositing, drives a Lua VM, and pumps events to and from " ++ ("frameservers. It is not a microkernel; the engine is the " ++ ("trusted core, and everything else (frameservers, lua, the " ++ "user's appls) talks to it through one IPC: shmif."))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/engine/arcan_main.zig",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/engine/arcan_event.zig",
                .note = "the event pump",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/engine/arcan_lua.zig",
                .note = "the Lua FFI layer",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/engine/arcan_main.zig",
                .note = "the entry point",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan name=main",
                .note = "find the symbol's offset; useful when correlating coredumps",
            },
            .{
                .kind = "bridge",
                .body = "shmif is what the engine and " ++ "everything else talk through.",
            },
            .{
                .kind = "h2",
                .body = "0.3  shmif",
            },
            .{
                .kind = "text",
                .body = "shmif is a shared memory page with an event ring on it. " ++ ("One side writes pixels; the other side composites. Either " ++ ("side can post events. There is no other IPC in this " ++ ("codebase that matters — every frameserver, every embedded " ++ ("TS module, every nested arcan instance, all talk through " ++ ("shmif. If you want to debug a frameserver you debug what " ++ ("it puts on shmif. If you want to profile arcan you profile " ++ "what crosses shmif.")))))),
            },
            .{
                .kind = "epigraph",
                .body = "In a modern tool chain the linker is the only tool " ++ "that considers the entire system at once.",
                .cite = "Mellstrand & Ståhl 2012, p. 51 (our analogue: " ++ "shmif sees every frameserver at once)",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the C ABI header — read this once, end-to-end",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/shmif/shmif_types.zig",
                .note = "the Zig wrappers",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/shmif/arcan_shmif_sub.zig",
                .note = "subsegments — partly disabled, see the visibility-rule article",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the canonical surface",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a",
                .note = "what the linker actually emitted",
            },
            .{
                .kind = "bridge",
                .body = "Every frameserver is a shmif client. There are eight of them.",
            },
            .{
                .kind = "h2",
                .body = "0.4  The frameservers",
            },
            .{
                .kind = "text",
                .body = "src/frameserver/{terminal,decode,encode,net,bun,game,probe,avfeed}/. " ++ ("Each has a default/ directory (the frameserver itself) and " ++ ("embed/ (a thin variant for in-durian bootstrapping). The " ++ ("terminal one hosts shells and editors and hem — this is " ++ ("what you are running in right now, in the v2 era. decode " ++ ("hosts ffmpeg. encode hosts streaming and recording. net " ++ ("hosts a12. bun hosts Bun (TypeScript), but it is a partial " ++ "story — see the article when it lands.")))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/frameserver/terminal/",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/frameserver/bun/",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/frameserver/net/",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/frameserver",
                .note = "the inventory",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "which ones are alive right now",
            },
            .{
                .kind = "articleref",
                .slug = "afsrv_bun_in_five_phases",
                .title = "afsrv_bun, in five phases (forthcoming)",
            },
            .{
                .kind = "bridge",
                .body = "a12 is the network protocol the net frameserver speaks. " ++ "It is important enough to get its own section.",
            },
            .{
                .kind = "h2",
                .body = "0.5  a12",
            },
            .{
                .kind = "text",
                .body = "a12 is arcan's network protocol. It carries shmif segments " ++ ("over the wire. It is in src/a12/ and is in the middle of a " ++ ("zig migration. The medium-term goal is 'every device the " ++ ("user owns runs an a12 endpoint, and a directory mediates " ++ ("discovery'; the short-term goal is 'the current C path " ++ ("keeps working while the zig path is built around it.' For " ++ ("the full arc see the 2026-01-26 'Weaving a Different Web' " ++ ("post on arcan-fe.com; for now, know it exists and where " ++ "it lives."))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/a12/a12.zig",
                .note = "handshake, stream mux",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/a12/a12_encode.zig",
                .note = "payload packing",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/a12/a12_decode.zig",
                .note = "parse",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/a12",
                .note = "the inventory",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan-net",
                .note = "the CLI's symbol table; the API surface in one place",
            },
            .{
                .kind = "bridge",
                .body = "That is the engine half. The other half is in data/.",
            },
            .{
                .kind = "h2",
                .body = "0.6  The Lua side",
            },
            .{
                .kind = "text",
                .body = "data/ holds three things. data/appl/ — the bundled appls " ++ ("(welcome, console, callgraph, texttest, vktest, sysdebug — " ++ ("the last one is what you are reading). data/lash/ — the " ++ ("lash shell. data/lash_builtins/hem_dev/ — hem's dev " ++ ("verbs (about fifty of them). The reference durian lives " ++ ("separately at reference/durian-upstream/durian/ but only " ++ ("as upstream mirror; the actual running durian is built and " ++ "installed to zig-out/share/arcan/appl/durian/.")))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/appl/welcome/welcome.lua",
                .note = "the simplest possible appl — read it",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
                .note = "viz_bus and the canonical payload-key contract",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/reference/durian-upstream/durian/durian.lua",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/data/lash_builtins/hem_dev '*.lua'",
                .note = "list every hem_dev verb",
            },
            .{
                .kind = "bridge",
                .body = "Those fifty verbs are what makes the visibility rule " ++ "possible. The next section is the cheat-sheet.",
            },
            .{
                .kind = "h2",
                .body = "0.7  hem_dev verbs (the cheat-sheet)",
            },
            .{
                .kind = "text",
                .body = "Six families. system/debug: status, ps, procfs, proc, " ++ ("cores, metrics, engine. files/search: read, edit, write, " ++ ("find, grep, glob, head, tail, wc, fs, hash. build/compile: " ++ ("compile, zigbuild, atlas, refactor, selfhost. code analysis: " ++ ("disasm, dwarf, dietree, diegraph, sym, snippet. time/data: " ++ ("time, hilbert, memcloud, snippets. introspection: git, " ++ ("fossil, bugs, logwatch, sheet, paste, screenshot, dashboard, " ++ ("run. And TS host: bun, claude. One file per verb at " ++ ("data/lash_builtins/hem_dev/<verb>.lua. To add one, copy " ++ ("the simplest existing verb (compile.lua is a fair template) " ++ "and zig build install."))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/status.lua",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/bugs.lua",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/hilbert.lua",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| hilbert",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
            },
            .{
                .kind = "bridge",
                .body = "How all of this is built and installed is one section away.",
            },
            .{
                .kind = "h2",
                .body = "0.8  Build, install, run",
            },
            .{
                .kind = "text",
                .body = "build.zig at the root is the main build. build_llvm/build.zig " ++ ("is the side project for LLVM-tainted targets — qtarcan, " ++ ("gamescope, llama-cli, afsrv_bun. They are kept apart so " ++ ("the self-hosted backend does not have to see them; one " ++ ("consequence is that afsrv_bun is invisible to a top-level " ++ ("zig build. On Asahi, BUILD_PROFILE=release is forced (a " ++ ("JSC strict-< ASSERT bug on 16K-page systems). zig build " ++ ("install lays everything into zig-out/. The running durian " ++ ("is at zig-out/share/arcan/appl/durian/; if you edit a hem " ++ ("verb under data/lash_builtins/hem_dev/, you have to rerun " ++ ("zig build install to see the change. Persistent durian " ++ ("state lives in ~/.arcan/arcan.sqlite — do not delete; the " ++ ("first-run wizard fires if you do, and you lose every " ++ "tweak you have ever made.")))))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build.zig",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build_llvm/build.zig",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build_llvm/tools/link-afsrv-bun.sh",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "start a build, watch the live error spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build.zig",
                .note = "the actual build script",
            },
            .{
                .kind = "bridge",
                .body = "That is the map. The next chapter is the Introduction to " ++ ("the original-book material; it picks up where this chapter " ++ "leaves off."),
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "00_foundations:visibility_rule_article",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 0,
            },
        },
        .tickets = .{
            "0036-visibility-rule",
            "0036-afsrv-bun-frameserver",
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
            "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
        },
    };
}
