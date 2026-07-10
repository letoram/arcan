
pub fn __init() void {
    return .{
        .title = "Introduction",
        .subtitle = "Part III · Ch 1 · Zig-based arcan (afsrv_bun + shim)",
        .part_id = 3,
        .chapter_id = 1,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "We are now moving away from the realm of " ++ ("software-as-punch-cards and into software-intensive " ++ ("systems, where systems are composed of many " ++ ("different kinds of software, running on a variety " ++ ("of machines in close collaboration with other " ++ ("kinds of devices and processes both mechanical and " ++ "human."))))),
                .cite = "Mellstrand & Ståhl 2012, p. 10",
            },
            .{
                .kind = "text",
                .body = "Arcan is being moved to zig piece by piece. The active " ++ ("wedge is afsrv_bun, a frameserver that runs Bun (and so " ++ ("TypeScript) as a first-class shmif client. The project " ++ ("is bug 0036, multi-phase, mostly landed. The structural " ++ ("enabler underneath it is the posix_libc shim work " ++ ("(0100–0111) which removes the @cImport dependency from " ++ ("shmif and a12 so the zig self-host backend can compile " ++ ("them. Part III walks both: the live frameserver as the " ++ ("worked example, and the shim as the structural reason " ++ "the example was even possible to attempt.")))))))),
            },
            .{
                .kind = "h2",
                .body = "1.1  Demarcation",
            },
            .{
                .kind = "text",
                .body = "What's in scope: afsrv_bun, the posix_libc shim, the " ++ ("engine's gradual zig migration. Out of scope: durian " ++ ("lua (still lua, not migrating); upstream arcan (mirrored " ++ ("in vendor/, not authored); the hem shell (the substrate " ++ ("we run inside, covered in passing in Part I Ch 0). " ++ ("Out of scope but worth flagging: the full Phase 3l " ++ ("ghostty embed in afsrv_bun is not built; today's claude " ++ ("integration is sibling-spawn from a TS host into a " ++ ("separate afsrv_terminal tile, not in-process. The " ++ "ticket trail for that decision is in 0036's phase log.")))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
                .note = "the multi-phase ticket; sections 3i.5 and 3l set the scope",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-afsrv-bun-frameserver",
                .note = "open the master ticket; phase log defines what is in",
            },
            .{
                .kind = "bridge",
                .body = "The system the worked example sits inside is " ++ "software-intensive in the original's exact sense.",
            },
            .{
                .kind = "h2",
                .body = "1.2  Software-intensive",
            },
            .{
                .kind = "text",
                .body = "Shmif is the IPC fabric. Engine on one side, frameservers " ++ ("on the other, each in its own process, each holding its " ++ ("segment. afsrv_bun is one frameserver in that constellation " ++ ("but a peculiar one: it does not just consume shmif, it " ++ ("exposes shmif primitives back into a TypeScript runtime so " ++ ("any .ts file run via `bun foo.ts` is itself a small shmif " ++ ("client. The intensiveness is recursive. Engine + " ++ ("frameservers + appls + TS modules all couple through one " ++ ("page-table-shared ring buffer, and an anomaly anywhere in " ++ ("that chain ends up in the same place: a wait that doesn't " ++ ("wake or a signal that doesn't carry the data the receiver " ++ "expected.")))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "the live frameserver constellation, one row each",
            },
            .{
                .kind = "bridge",
                .body = "Cause and panic in this domain split visibly into two " ++ "shapes.",
            },
            .{
                .kind = "h2",
                .body = "1.3  Cause and panic",
            },
            .{
                .kind = "epigraph",
                .body = "A major part of software analysis and debugging is " ++ ("determining which factors involved caused a certain " ++ ("undesired effect to occur in order to feed this " ++ ("back into upcoming instances of the software, " ++ ("preferably by changing some offline artifact like " ++ "source code.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 18",
            },
            .{
                .kind = "text",
                .body = "User-visible faults: the Bun window never opens, the " ++ ("compositor flickers, a paint demo writes outside its " ++ ("canvas. These are easy to investigate because the user " ++ ("is the live oracle. Hidden faults: a SEGREQ that arcan " ++ ("issues and durian never fetches the fd for, an event " ++ ("that gets queued past the ring's wrap point and " ++ ("silently drops, a TS exception that gets swallowed " ++ ("because the JSC strict-`<` ASSERT in the FreeList code " ++ ("fires first on Asahi's 16K-page system. Hidden faults " ++ ("are the chapter's whole reason for existing. The user " ++ ("feels them only as 'something didn't happen' and there " ++ ("is no signal to attach a hypothesis to. The visibility " ++ ("rule was filed because hidden faults are unactionable " ++ "without a forced surface for them.")))))))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
                .note = "the rule, written down",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "the methodological rule that anchors this part",
            },
            .{
                .kind = "bridge",
                .body = "The shapes the anomalies in this domain take are " ++ "particular.",
            },
            .{
                .kind = "h2",
                .body = "1.4  Origin of anomalies",
            },
            .{
                .kind = "epigraph",
                .body = "The primal aim on the origin of anomalies is that " ++ ("each and every bug is simply an inconsideration on " ++ "behalf of the developer."),
                .cite = "Mellstrand & Ståhl 2012, p. 24",
            },
            .{
                .kind = "h3",
                .body = "Protocol races",
            },
            .{
                .kind = "text",
                .body = "shmif's signal/wait dance has a wait side that may sleep " ++ ("indefinitely if it raced ahead of the signaller. The " ++ ("signaller is supposed to commit before signalling, the " ++ ("waiter is supposed to recheck the predicate after waking; " ++ ("any drift in either invariant produces a hang the user " ++ ("experiences as 'frozen window'. Phase 3g of bug 0036 ate " ++ ("weeks because the TS-side host bindings did not " ++ "implement the signal-after-commit ordering correctly.")))))),
            },
            .{
                .kind = "h3",
                .body = "Assumption mismatches",
            },
            .{
                .kind = "text",
                .body = "durian's fetchfds path expects a SEGID_APPLICATION " ++ ("subsegment SEGREQ to come with an fd in the ancillary " ++ ("data. afsrv_bun's TS-side openSubSegment binding does " ++ ("the request but the C glue never attaches the fd. " ++ ("durian waits forever; afsrv_bun thinks the request " ++ ("succeeded. The phase log calls it Phase 3i.5; the " ++ ("binding has been disabled until the C glue carries the " ++ "fd through, see 0036's ticket body for the trace.")))))),
            },
            .{
                .kind = "h3",
                .body = "Build profile mistakes",
            },
            .{
                .kind = "text",
                .body = "On Asahi's 16KB-page kernel, building afsrv_bun in debug " ++ ("profile fires a JSC strict-`<` ASSERT in the FreeList " ++ ("code on first allocation. Release profile bypasses the " ++ ("ASSERT and runs cleanly. The ASSERT is correct in spirit " ++ ("(the developer asserted a condition that holds on 4KB " ++ ("pages), wrong in extent (the condition does not hold on " ++ ("16KB pages, where the same arithmetic produces an " ++ ("off-by-one). This is exactly the original §1.1 framing " ++ "of 'machine model breaking the developer's assumption'."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
            },
            .{
                .kind = "ticketref",
                .id = "0034-shmif-native-guide-for-external-agents",
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
                .note = "the structural enabler under all of this",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0100-refactor-posix-libc",
                .note = "the posix_libc cluster, all 12 tickets",
            },
            .{
                .kind = "bridge",
                .body = "And the methodology is not new — it is the rule, again.",
            },
            .{
                .kind = "h2",
                .body = "1.5  Methodology",
            },
            .{
                .kind = "epigraph",
                .body = "More often than not, there is some claim of " ++ ("scientific value in these methods, but given a " ++ ("closer examination the methods seem empty, " ++ "irrelevant or trivial.")),
                .cite = "Mellstrand & Ståhl 2012, p. 36",
            },
            .{
                .kind = "text",
                .body = "The visibility rule, again, in this chapter's words: " ++ ("every claim about a frameserver, a segment, a TS " ++ ("binding, an event, has to come with a verb that opens " ++ ("the live state of that thing in a hem cell. If the " ++ ("claim cannot be made visible, it is unmakable in this " ++ ("appl. The rule is what 'methodology' reduces to here, " ++ ("because the system itself does not afford " ++ ("stop-the-world inspection — the engine's event loop " ++ ("stops only when something has gone irrecoverably wrong, " ++ "by which time the question is post-mortem.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "the methodology, verbatim",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "everything visible at once, the rule applied",
            },
            .{
                .kind = "h2",
                .body = "1.6  Concluding",
            },
            .{
                .kind = "text",
                .body = "Ch 2 walks the shmif/frameserver/TS pipeline end to end. " ++ ("Ch 3 lands the four principal-debugging actions on the " ++ ("live engine. Ch 4 names the verbs that make the rule " ++ "actually doable in practice.")),
            },
            .{
                .kind = "crosslink",
                .target = "03_zig_arcan:ch2_software_demystified",
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "03_zig_arcan:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 3,
                .chapter = 1,
            },
        },
        .tickets = .{
            "0036-afsrv-bun-frameserver",
            "0036-visibility-rule",
            "0034-shmif-native-guide-for-external-agents",
            "0100-refactor-posix-libc",
            "0035-bun-shmif-native-plugin",
            "0033-claude-code-shmif-bridge-in-afsrv-terminal",
        },
    };
}
