
pub fn __init() void {
    return .{
        .title = "Software Demystified",
        .subtitle = "Part III · Ch 2 · Zig-based arcan",
        .part_id = 3,
        .chapter_id = 2,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "In a modern tool chain the linker is the only tool " ++ "that considers the entire system at once.",
                .cite = "Mellstrand & Ståhl 2012, p. 51",
            },
            .{
                .kind = "text",
                .body = "The original walks compile, link, load, execute. We walk " ++ ("the analogous arcan pipeline: source, shmif page, " ++ ("frameserver lifecycle, segment request, the TS layer, the " ++ ("C glue, the posix_libc shim, the engine-Lua loop. Where " ++ ("the original's linker is the global lens, ours is shmif: " ++ "the only thing that sees every frameserver at once.")))),
            },
            .{
                .kind = "h2",
                .body = "2.1  Source",
            },
            .{
                .kind = "text",
                .body = "src/engine/ holds the engine; src/frameserver/ holds the " ++ ("frameserver subprojects (terminal, decode, encode, net, " ++ ("bun, game, probe, avfeed); src/shmif/ holds the shared " ++ ("library both sides link against; src/a12/ holds the " ++ ("network protocol. Each subdirectory is its own zig " ++ ("package; the top-level build.zig wires them together. " ++ ("afsrv_bun is the outlier — it lives under build_llvm/ " ++ ("because Bun's build pulls in LLVM, and we keep that " ++ "dependency out of the main project."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src zig",
                .note = "every zig source under src/",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/build_llvm",
                .note = "the LLVM-implicating split",
            },
            .{
                .kind = "h2",
                .body = "2.2  The shmif page",
            },
            .{
                .kind = "text",
                .body = "Shared memory between engine and frameserver. One page, " ++ ("fixed layout: header with version + state, ring buffers " ++ ("for events in each direction, audio and video buffers " ++ ("with their own semaphores. Signal/wait coordinate access. " ++ ("The header version is checked on attach; mismatched " ++ ("versions abort the segment immediately, which is what " ++ ("Fail Hard looks like at the protocol layer. The TS-side " ++ ("binding exposes the page as an ArrayBuffer so a script " ++ ("can read state directly when the visible-window paint " ++ "primitives are not enough.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the C header that defines the layout, both sides see this",
            },
            .{
                .kind = "h2",
                .body = "2.3  Frameserver lifecycle",
            },
            .{
                .kind = "text",
                .body = "Spawn, preroll, activate. Spawn forks the frameserver " ++ ("binary with the shmif page descriptor in env. Preroll " ++ ("is the negotiation window: the frameserver declares its " ++ ("type, the engine resizes the segment to the requested " ++ ("dimensions, both sides confirm. Activate is the " ++ ("signal-after-commit dance for the first frame, and from " ++ ("then on the segment is in steady state until shutdown " ++ ("or crash. Crashes during preroll are particularly nasty " ++ ("— the segment never reached steady state, so it shows " ++ "up as an orphan in the watchdog log (ticket 0114).")))))))),
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
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "the live constellation; preroll vs activate state per row",
            },
            .{
                .kind = "h2",
                .body = "2.4  Segment request",
            },
            .{
                .kind = "text",
                .body = "A frameserver that wants a second window asks the engine " ++ ("via SEGREQ. The engine asks durian via the control " ++ ("socket; durian decides yes or no and (if yes) issues a " ++ ("fetchfds against the new segment's descriptor. The fd " ++ ("comes back to the frameserver as ancillary data on the " ++ ("shmif socket. This is the path Phase 3l of bug 0036 " ++ ("tried to extend with SEGID_APPLICATION subsegments and " ++ ("where the C glue currently does not attach the fd, " ++ ("stalling durian's fetchfds. Until the glue is fixed, " ++ "openSubSegment is registered in C but disabled in TS.")))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
                .note = "phase 3l caveat lives in the master ticket",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the SEGREQ event structure, including the fd field",
            },
            .{
                .kind = "h2",
                .body = "2.5  The TS layer",
            },
            .{
                .kind = "text",
                .body = "When the hem user runs `bun foo.ts`, the bun verb " ++ ("resolves to /home/x/next/arcan/zig-out/bin/afsrv_bun " ++ ("foo.ts. afsrv_bun starts as a normal frameserver — its " ++ ("shmif segment is what hem sees as the new tile — then " ++ ("loads foo.ts in JSC. Before user code runs, the host " ++ ("bindings are installed on globalThis: shmif.* for the " ++ ("page primitives, durian.* for the IPC socket, host.* " ++ ("for utility round-trips. Every primitive is a JSC " ++ ("function backed by a public C wrapper that a future " ++ ("auto-arch round can replace with a zig-native " ++ "implementation once the posix_libc shim is complete."))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build_llvm/examples/arcan-shmif.ts",
                .note = "the TS surface; helpers and AsyncIterable wrappers",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/echo.ts",
                .note = "the smallest end-to-end: TS calls host.echo, gets a round-trip",
            },
            .{
                .kind = "h2",
                .body = "2.6  The C glue",
            },
            .{
                .kind = "text",
                .body = "src/frameserver/bun/embed/arcan_afsrv_bun_init.c is the " ++ ("entry point. It opens the shmif segment, then hands the " ++ ("fd-equivalent over to a C++ host-bindings module that " ++ ("registers the JSC functions and starts JSC. The split " ++ ("exists because shmif is C-only and JSC is C++; the seam " ++ ("is the JSC_DEFINE_HOST_FUNCTION boundary, where each " ++ ("binding's C++ function calls one public C wrapper that " ++ ("knows about the shmif page. The pattern is documented " ++ ("in the afsrv_bun_jsc_bindings memory note; it is the " ++ "recipe new bindings have to follow.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/frameserver/bun",
                .note = "the C glue tree",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/afsrv_bun",
                .note = "the linked binary; JSC_DEFINE_HOST_FUNCTION symbols visible",
            },
            .{
                .kind = "h2",
                .body = "2.7  The posix_libc shim",
            },
            .{
                .kind = "text",
                .body = "src/platform/posix/libc.zig holds the shim. It exists " ++ ("because the zig self-host backend cannot @cImport — and " ++ ("every shmif/a12/keystore consumer that wants to be " ++ ("self-host-built has to drop @cImport in favour of " ++ ("explicit zig externs. The 12-ticket cluster (0100–0111) " ++ ("walks each of the consumers in turn: 0102 extern fn " ++ ("shape; 0103 build heredoc plumbing; 0104 the addShmif" ++ ("ZigSource family; 0105 the createBootPayload call site; " ++ ("0106 cstr plumbing; 0107 a getopt clone; 0108 the " ++ ("sprintf path; 0109 a test-size table; 0110 strarr " ++ ("collection; 0111 the force-synch dummy. 0100 is the " ++ ("epic; 0101 is the re-export gateway. Reading the cluster " ++ "in order is reading the entire migration plan."))))))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
            },
            .{
                .kind = "ticketref",
                .id = "0102-refactor-extern-fn",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0100-refactor-posix-libc",
                .note = "every ticket in the shim cluster",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/platform/posix/libc.zig",
                .note = "the shim itself, hand-written",
            },
            .{
                .kind = "h2",
                .body = "2.8  Engine and Lua",
            },
            .{
                .kind = "text",
                .body = "The engine's main loop walks Lua callbacks. A Lua " ++ ("valid_vid() call from durian ultimately reaches the " ++ ("engine's vobj table; an engine signal_video() call " ++ ("from afsrv_bun reaches the same table from the other " ++ ("side. The two sides meet at the shmif segment for the " ++ ("frameserver. When the path from the Lua call to the " ++ ("shmif buffer signal goes wrong — a missing decref, a " ++ ("stale vobj — the symptom is the engine's panic on " ++ ("invalid state, not a soft warning. Per the " ++ ("no-panics-in-compositor-hot-paths rule, the panic IS " ++ "the diagnostic; softening it would propagate corruption."))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "engine panics, bucketed; the diagnostic of last resort",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Eight stages from source to a Lua callback firing on a " ++ ("buffer signal. Ch 3 lands the four-action spine on the " ++ ("live engine; Ch 4 names the hem verbs that make each " ++ "action operational.")),
            },
            .{
                .kind = "crosslink",
                .target = "03_zig_arcan:ch3_principal_debugging",
            },
        },
        .cross_links = .{
            "03_zig_arcan:ch1_introduction",
            "03_zig_arcan:ch3_principal_debugging",
            "00_foundations:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 3,
                .chapter = 2,
            },
        },
        .tickets = .{
            "0036-afsrv-bun-frameserver",
            "0100-refactor-posix-libc",
            "0102-refactor-extern-fn",
            "0113-frameserver-orphan-survives-arcan-crash",
            "0114-watchdog-false-orphan-on-external-shmif-clients",
        },
    };
}
