
pub fn __init() void {
    return .{
        .title = "Glossary",
        .subtitle = "Front matter",
        .part_id = 1,
        .chapter_id = 0,
        .body = .{
            .{
                .kind = "text",
                .body = "The terms this book treats as known. Anything not on " ++ ("this page either lives in Ch 0 (Architecture) or in " ++ "the original book's index."),
            },
            .{
                .kind = "h3",
                .body = "shmif",
            },
            .{
                .kind = "text",
                .body = "Shared-memory interface. The single IPC arcan uses " ++ ("between the engine and every frameserver, every " ++ ("embedded TS module, every nested arcan instance. A " ++ ("shared memory page with a video buffer and an event " ++ "ring on it. See ch0 §0.3, ch2 §2.5."))),
            },
            .{
                .kind = "h3",
                .body = "segment",
            },
            .{
                .kind = "text",
                .body = "One shmif page, attached to one client. The unit of " ++ ("isolation between the engine and an arcan client. A " ++ ("frameserver is a process that holds at least one " ++ "segment; it can request additional ones (subsegments).")),
            },
            .{
                .kind = "h3",
                .body = "subsegment",
            },
            .{
                .kind = "text",
                .body = "A child segment requested by a primary segment for a " ++ ("specific purpose (a popup, a clipboard receiver, a " ++ ("debug surface). Currently disabled in afsrv_bun " ++ ("pending the durian SEGREQ→fetchfds fix " ++ "(bug 0036 phase 3l)."))),
            },
            .{
                .kind = "h3",
                .body = "frameserver",
            },
            .{
                .kind = "text",
                .body = "An out-of-process arcan client that produces or " ++ ("consumes a shmif segment. The eight built ones are " ++ ("afsrv_terminal, afsrv_decode, afsrv_encode, " ++ ("afsrv_net, afsrv_bun, afsrv_game, afsrv_probe, " ++ "afsrv_avfeed. Each lives at src/frameserver/<name>/."))),
            },
            .{
                .kind = "h3",
                .body = "afsrv_bun",
            },
            .{
                .kind = "text",
                .body = "The TypeScript-hosting frameserver. Bun-as-main, with " ++ ("a thin C glue, exposing globalThis.shmif and " ++ ("globalThis.durian to TS modules. Lives at " ++ ("src/frameserver/bun/ but is built under build_llvm/. " ++ "Bug 0036 is its design and migration history."))),
            },
            .{
                .kind = "h3",
                .body = "durian",
            },
            .{
                .kind = "text",
                .body = "The window manager appl. Lua. The default arcan boots " ++ ("to. Provides the menu tree (“/global/open/" ++ ("lash”, etc.), the IPC control socket at " ++ ("/run/user/1000/durian, the workspace and tile model. " ++ ("Reference upstream lives at reference/durian-upstream/" ++ ("durian/; the running snapshot lives at " ++ "zig-out/share/arcan/appl/durian/."))))),
            },
            .{
                .kind = "h3",
                .body = "lash",
            },
            .{
                .kind = "text",
                .body = "The shell host inside afsrv_terminal (or, soon, " ++ ("afsrv_bun). Provides the hem runtime its environment. " ++ "LASH_SHELL=cat9 is the canonical incantation."),
            },
            .{
                .kind = "h3",
                .body = "hem",
            },
            .{
                .kind = "text",
                .body = "The shell language and runtime lash hosts. Lua-based. " ++ ("Spread-oriented — every job is a cell, every cell can " ++ ("be inspected, edited, intervened on. The substrate the " ++ "visibility rule lives in.")),
            },
            .{
                .kind = "h3",
                .body = "hem_dev",
            },
            .{
                .kind = "text",
                .body = "The dev verb set, loaded into a hem cell with " ++ ("“builtin dev”. About fifty verbs " ++ ("covering inspection, build, code analysis, time/data, " ++ ("introspection, TS host. One Lua file per verb at " ++ "data/lash_builtins/hem_dev/."))),
            },
            .{
                .kind = "h3",
                .body = "spread",
            },
            .{
                .kind = "text",
                .body = "A hem rendering of tabular output — like " ++ ("a spreadsheet, but the rows and columns are clickable " ++ ("and tied back to viz_bus. find, grep, status, metrics, " ++ "cores list, dietree all render as spreads.")),
            },
            .{
                .kind = "h3",
                .body = "verbbox",
            },
            .{
                .kind = "text",
                .body = "A block kind in this appl. Renders a one-line hem " ++ ("chain with a `[N]` index. In v1 the user copies and " ++ ("pastes; in v2 the digit keys 1–9 will " ++ ("spawn the cell directly. The visibility rule is what " ++ "demands they exist."))),
            },
            .{
                .kind = "h3",
                .body = "viz_bus",
            },
            .{
                .kind = "text",
                .body = "The cross-cell event bus. hem cells subscribe and " ++ ("publish via shmif MESSAGE events with a payload key " ++ ("convention (sensor name + payload table). The " ++ ("_helpers.lua under hem_dev encodes the contract; " ++ "every published spread agrees on the shape."))),
            },
            .{
                .kind = "h3",
                .body = "sensor / payload key",
            },
            .{
                .kind = "text",
                .body = "A sensor is a name an emitter publishes under " ++ ("(“compile.errors”, " ++ ("“sysdebug.read”). A payload key " ++ ("is the schema of what gets emitted. Convention says " ++ ("sensors are dotted lowercase, keys are stable across " ++ "the lifetime of an appl.")))),
            },
            .{
                .kind = "h3",
                .body = "a12",
            },
            .{
                .kind = "text",
                .body = "arcan's network protocol. Carries shmif segments " ++ ("between machines. Implemented in src/a12/. Today " ++ ("shipped with arcan; tomorrow zig-native (gated by the " ++ ("posix_libc work). Production deployment is over " ++ "Tailscale."))),
            },
            .{
                .kind = "h3",
                .body = "ARCAN_CONNPATH",
            },
            .{
                .kind = "text",
                .body = "Environment variable telling an arcan client which " ++ ("appl socket to connect to. “durian” " ++ ("for normal use. Set automatically in lash cells; the " ++ "bun verb forces it for safety.")),
            },
            .{
                .kind = "h3",
                .body = "sh-zig",
            },
            .{
                .kind = "text",
                .body = "The self-hosted Zig fork. Compiles arcan and itself " ++ ("without LLVM. Part II's primary subject. The fork " ++ ("diverges from upstream zig in codegen, primarily " ++ "AArch64.")),
            },
            .{
                .kind = "h3",
                .body = "posix_libc shim",
            },
            .{
                .kind = "text",
                .body = "src/platform/posix/libc.zig. Hand-written Zig stand-in " ++ ("for the POSIX libc surface arcan needs (pthread, " ++ ("select, epoll, sockets). Replaces an @cImport path. " ++ "Tickets 0100–0111.")),
            },
            .{
                .kind = "h3",
                .body = "fossil",
            },
            .{
                .kind = "text",
                .body = "The VCS this repo uses (not git). Tickets live directly " ++ ("in fossil's ticket DB (`bugs show <slug>` or " ++ ("`fossil sql ...`); the legacy bugs/ folder was deleted " ++ ("2026-05-02 per ticket 0150. hem_dev has a fossil verb " ++ "for status, log, diff."))),
            },
            .{
                .kind = "h3",
                .body = "auto-arch loop",
            },
            .{
                .kind = "text",
                .body = "tools/auto-arch/. The orchestrator that runs " ++ ("selfhost rounds in fossil branches, scores them by " ++ ("fitness, merges or discards. Each round is a snapshot " ++ "in the original-book sense (Ch 3.5).")),
            },
            .{
                .kind = "h3",
                .body = "senseye / senseye-applied",
            },
            .{
                .kind = "text",
                .body = "Senseye is a separate project (~/next/senseye/) that " ++ ("produces visual representations of binary data. " ++ ("senseye-applied is the docs/hem_visual_agent/ plan " ++ ("for plugging senseye-style views into hem cells; " ++ ("layer 5 is the visualizer substrate this book's Ch 4 " ++ "§4.5 names.")))),
            },
            .{
                .kind = "h3",
                .body = "directory / .index / .monitor / .debug",
            },
            .{
                .kind = "text",
                .body = "a12 directory primitives. Directory mediates discovery " ++ ("between Sources and Sinks. .index, .monitor, .debug " ++ ("are reserved binary slots a directory may carry per " ++ "appl, surfaced in Part V.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
                .note = "the viz_bus contract in code form",
            },
        },
        .cross_links = .{
            "00_foundations:preface",
            "00_foundations:howto",
            "00_foundations:ch0_architecture",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = -1,
            },
        },
    };
}
