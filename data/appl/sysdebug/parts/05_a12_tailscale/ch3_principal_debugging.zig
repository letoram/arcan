
pub fn __init() void {
    return .{
        .title = "Principal Debugging",
        .subtitle = "Part V · Ch 3 · a12 over Tailscale",
        .part_id = 5,
        .chapter_id = 3,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "On realizing source code: large software systems " ++ ("are inherently too complex to understand by " ++ ("considering only source code and other static " ++ "sources.")),
                .cite = "Mellstrand & Ståhl 2012, p. 75",
            },
            .{
                .kind = "text",
                .body = "Especially true across a wire. The protocol source on " ++ ("this host tells you only what this host claims it does. " ++ ("What actually crosses the Tailnet is the only ground " ++ "truth, and capturing it is half the work.")),
            },
            .{
                .kind = "h2",
                .body = "3.1  Why analyse",
            },
            .{
                .kind = "text",
                .body = "Predicting whether a protocol change will break the " ++ ("other side. The other side may be running a version of " ++ ("arcan-net the analyst does not have a build of, may be " ++ ("owned by a different person, may not even be reachable " ++ ("from this Tailnet. The protocol's compatibility " ++ ("promises are the analyst's main lever; the test matrix " ++ ("(self-vs-self over loopback, self-vs-remote over the " ++ ("Tailnet, self-vs-stub for forced version drift) is " ++ "what makes the lever real."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "two endpoints when the loopback test is running",
            },
            .{
                .kind = "h2",
                .body = "3.2  Static and dynamic",
            },
            .{
                .kind = "text",
                .body = "Static side: src/a12/, the protocol spec embedded in " ++ ("those files' doc-comments, the manifest format. " ++ ("Dynamic side: anet_session captures (live, the " ++ ("anet_session-*.bin files at repo root are evidence " ++ ("the practice is established), procfs <pid> fd for " ++ ("the live socket state, the (proposed) .monitor stream " ++ ("for protocol-internal state. The static-dynamic gap is " ++ ("wider here than anywhere else in this appl: the " ++ ("static side is well-documented; the dynamic side is " ++ "research-grade.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan glob anet_session",
                .note = "the existing session captures, evidence the practice exists",
            },
            .{
                .kind = "h2",
                .body = "3.3  Four actions across the wire",
            },
            .{
                .kind = "h3",
                .body = "Subdivide",
            },
            .{
                .kind = "text",
                .body = "Per channel, per role. Local Source vs remote Sink vs " ++ ("Directory. Five subsystems on the typical session, " ++ ("and Subdivide here is mostly about which one to " ++ ("exclude — investigations that suspect the directory " ++ ("should not also be testing the wire. Mark each side " ++ "before debugging and rule out one at a time.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan-net",
                .note = "the local subsystems, in one spread",
            },
            .{
                .kind = "h3",
                .body = "Measure",
            },
            .{
                .kind = "text",
                .body = "Socket fd state via procfs <pid> fd. Frame timing via " ++ ("the time builtin bucketing the events from a session " ++ ("capture. The proposed .monitor stream — Agent D's " ++ ("ticket — would surface a12-internal state (version " ++ ("negotiated, frame counts per channel, error counters) " ++ ("as a spread. Until that ticket lands, the substitute " ++ "is reading the engine log filtered to the net bucket."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $(pidof arcan-net) fd",
                .note = "Measure: socket state per fd",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| time",
                .note = "Measure: frame timing as a time-bucketed spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs net",
                .note = "Measure: net-bucketed engine log",
            },
            .{
                .kind = "h3",
                .body = "Represent",
            },
            .{
                .kind = "text",
                .body = "The proposed anet_session capture browser as a spread: " ++ ("rows for frames, clickable for frame detail, with the " ++ ("channel and direction visible per row. Also Agent D's " ++ ("ticket. Today the captures are read with hexdump and " ++ ("the matching protocol struct from a12_types.zig kept " ++ "open in a sibling cell — slow, but it works.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/a12/a12_types.zig",
                .note = "the type definitions to read captures against",
            },
            .{
                .kind = "h3",
                .body = "Intervene",
            },
            .{
                .kind = "text",
                .body = "Tunnelled hem sessions over a12. Two analysts join " ++ ("the same directory with the same appl; both see the " ++ ("same spread; both can edit the same source. The pair-" ++ ("debug pattern is the highest-leverage form of " ++ ("intervention available on a multi-host fault — when " ++ ("one analyst is on each side of the partition, the " ++ "fault has nowhere to hide."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net somedir@ sysdebug",
                .note = "Intervene: pull this very appl from a directory",
            },
            .{
                .kind = "h2",
                .body = "3.4  Information sources",
            },
            .{
                .kind = "text",
                .body = "Pre-execution: ticket trail (ticket 0034 has the " ++ ("external-agent guide; the 2020 and 2023 arcan-fe.com " ++ ("a12 articles spell out the design rationale), source. " ++ "Pre answers what the protocol claims about itself.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0034-shmif-native-guide-for-external-agents",
                .note = "the protocol guide ticket",
            },
            .{
                .kind = "text",
                .body = "In-execution: .monitor stream (proposed) or its " ++ ("substitute, the procfs fd spread for the live socket. " ++ "In answers what is happening this session."),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $(pidof arcan-net) fd",
                .note = "in: live socket state",
            },
            .{
                .kind = "text",
                .body = "Post-execution: the .report slot, retrieved via " ++ ("arcan-net --get-file. The slot is reserved across the " ++ ("protocol for exactly this purpose: a sink that " ++ ("crashes leaves a Lua-replay script the source can " ++ ("fetch. Per the 'Weaving a Different Web' developer " ++ ("story, the script is replayable in the source's own " ++ ("session, so the post-execution evidence comes home " ++ "without anyone having to ssh into the failed sink.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net --get-file .report - somedir@",
                .note = "post: the .report slot from the most recent " ++ "session",
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
                .body = "A remote crash report comes back as a Lua replay. The " ++ ("analyst pulls the .report, opens it in hem, and runs " ++ ("the replay against a fresh local session. The replay " ++ ("is itself a tiny snapshot — every event the failed " ++ ("session received in order, plus the engine state at " ++ ("the moment of failure. Walking the replay end-to-end " ++ ("until the first event that diverges from the working " ++ "case is the chapter's worked example.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| arcan-net --replay .report",
                .note = "the conundrum's tooling: replay the failed " ++ "session locally",
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
                .body = "Key-pinning at first contact. The TOFU window is the " ++ ("earliest the analyst can fail the session — once a key " ++ ("is pinned, the cost of a wrong-key fault is " ++ ("low (immediate refusal); the cost of accepting an " ++ ("untrusted key is much higher (silent compromise). The " ++ ("discipline is to never bypass TOFU on a host that has " ++ "talked to the other side before."))))),
            },
            .{
                .kind = "h3",
                .body = "Fail Often",
            },
            .{
                .kind = "text",
                .body = "The appl_store hook can record every session — every " ++ ("push, every fetch, every LIST. Recording is cheap; " ++ ("auditing is the cheap-when-needed half. The matrix of " ++ ("publishers, sinks, and appl versions is the dataset " ++ ("the audit operates on, and it is essentially free if " ++ "the hook is in place.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Hard",
            },
            .{
                .kind = "text",
                .body = "A signature mismatch is fatal, not warned. The " ++ ("temptation to soften it — to render the appl with a " ++ ("warning ribbon and let the user decide — is the " ++ ("version of the no-soften-panic rule that applies " ++ ("across the wire. A bad signature means the source of " ++ ("truth is wrong; running anyway propagates the wrong " ++ "source of truth to the user's screen."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs net",
                .note = "the load-bearing rejections in the net log",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "The four actions, applied across the wire. Ch 4 names " ++ ("the verbs — including a closing recursive case where " ++ ("the appl reads itself from a remote sink, validating " ++ "the visibility rule survives transport.")),
            },
            .{
                .kind = "crosslink",
                .target = "05_a12_tailscale:ch4_tools_of_the_trade",
            },
        },
        .cross_links = .{
            "05_a12_tailscale:ch2_software_demystified",
            "05_a12_tailscale:ch4_tools_of_the_trade",
            "00_foundations:ch3_principal_debugging",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 5,
                .chapter = 3,
            },
        },
        .tickets = .{ "0034-shmif-native-guide-for-external-agents" },
    };
}
