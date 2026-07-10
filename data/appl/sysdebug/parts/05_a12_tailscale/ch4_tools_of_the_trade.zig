
pub fn __init() void {
    return .{
        .title = "Tools of the Trade",
        .subtitle = "Part V · Ch 4 · a12 over Tailscale",
        .part_id = 5,
        .chapter_id = 4,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The developer, just like other craftsmen, has an " ++ "extensive array of tools at his disposal.",
                .cite = "Mellstrand & Ståhl 2012, p. 119",
            },
            .{
                .kind = "text",
                .body = "For the network the array is heavier on CLI verbs and " ++ ("lighter on spreads than the other parts. arcan-net is " ++ ("the canonical CLI; the spread side is where the " ++ "missing-verb tickets live.")),
            },
            .{
                .kind = "h2",
                .body = "4.1  Roll-call",
            },
            .{
                .kind = "text",
                .body = "arcan-net's CLI: the directory verbs (LIST, " ++ ("--push-appl, --get-file, keystore), the session verbs " ++ ("(--replay, --sign-tag), the diagnostic verbs (verbose " ++ ("modes via env vars). The directory side: config.lua " ++ ("hooks (appl_load, appl_store), the reserved binary " ++ ("slots (.monitor, .debug, .index, .report). The " ++ ("(proposed) hem-side: a .monitor builtin wrapping " ++ ("arcan-net's monitor stream, plus an anet_session " ++ "browser. Agent D's tickets."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net keystore",
                .note = "the keystore CLI verb",
            },
            .{
                .kind = "h2",
                .body = "4.2  Debugger",
            },
            .{
                .kind = "text",
                .body = "arcan-net itself is the canonical debugger CLI: it " ++ ("knows the protocol, can issue any verb, can stand in " ++ ("as either side of a session for testing. The open " ++ (".monitor verb proposal turns it into a live debugger — " ++ ("spawn arcan-net in monitor mode against a remote " ++ ("endpoint, get a stream of protocol-internal events, " ++ ("render them as a spread. Until that ticket lands, the " ++ ("debugger is arcan-net + a session capture + manual " ++ ("cross-reference, which is what most network protocol " ++ "debugging looks like everywhere.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net keystore",
                .note = "the debugger's first verb: what does this host trust",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "every live arcan-net, with its CLI args visible",
            },
            .{
                .kind = "h2",
                .body = "4.3  Tracer",
            },
            .{
                .kind = "text",
                .body = "anet_session captures are the trace. Each capture is a " ++ ("binary file recording every frame in both directions, " ++ ("with timestamps. The time builtin buckets a capture " ++ ("into per-100ms windows, which is the natural " ++ ("granularity for spotting bursty congestion or " ++ ("missed-deadline patterns. logwatch with the net " ++ ("bucket is the engine-side analogue: every line in the " ++ ("engine log that came from a12 code, in time order, " ++ "filtered live."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| time",
                .note = "bucket a session capture into 100ms windows",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs net",
                .note = "engine-side trace, net-bucketed",
            },
            .{
                .kind = "h2",
                .body = "4.4  Profiler",
            },
            .{
                .kind = "text",
                .body = "Per-frame timing for the wire: how long from frame " ++ ("encode-start to ack-back. Bandwidth per channel " ++ ("(video / audio / event / blob) for the session. " ++ ("Directory-side queue depths: how many requests are " ++ ("waiting for an appl_load hook to complete. The " ++ ("profiler answers the question 'where is the wall-" ++ ("clock going on a slow session', and the answer " ++ ("almost always points at one specific channel or one " ++ "specific hook, not at the protocol as a whole."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| time",
                .note = "the profile, distilled from the trace",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "queue depths visible per process",
            },
            .{
                .kind = "h2",
                .body = "4.5  Visualizer (NEW)",
            },
            .{
                .kind = "text",
                .body = "The proposed .index browser as a spread: rows for " ++ ("every appl the directory advertises, with a per-row " ++ ("preview pane. Per-session frame heatmaps via shmif " ++ ("fillRect: each pixel is one frame, colour encodes the " ++ ("channel and direction, the heatmap shows the session's " ++ ("shape over time. The recursive case: this very appl, " ++ ("sysdebug, packaged and pushed to a directory, then " ++ ("pulled from a second sink. The act of running the " ++ ("appl over the protocol it documents IS the visibility " ++ ("rule's transport-survival test. If it reads correctly " ++ ("from the remote side, the rule has held across the " ++ ("wire; if not, the rule has a wire-side blind spot the " ++ "next ticket has to address."))))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net --sign-tag dev --push-appl sysdebug somedir@",
                .note = "publish this very appl to a directory",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net somedir@ sysdebug",
                .note = "read this very appl from the remote sink, the " ++ "recursive case",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs net",
                .note = "watch the recursive case from the source side",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Five families, three of them well-covered, two of them " ++ ("with open tickets. Part V closes the four-part arc; " ++ ("the back matter (refs, tickets, verbs, xref) is the " ++ ("appl's index. From here the natural next chapter is " ++ ("the one the user writes by running the verbs above " ++ "and filing the next round of tickets.")))),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:refs",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:verbs",
            },
        },
        .cross_links = .{
            "05_a12_tailscale:ch3_principal_debugging",
            "00_foundations:ch4_tools_of_the_trade",
            "00_foundations:verbs",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 5,
                .chapter = 4,
            },
        },
        .tickets = .{ "0034-shmif-native-guide-for-external-agents" },
    };
}
