
pub fn __init() void {
    return .{
        .title = "Principal Debugging",
        .subtitle = "Part IV · Ch 3 · seL4 Bootstrapping in Zig",
        .part_id = 4,
        .chapter_id = 3,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The principal advantage of using an experimental " ++ ("approach is that one works with the actual behavior " ++ ("of the target system. This enables the analyst to " ++ ("establish a feedback chain where he or she measures " ++ "properties inside the system he or she manipulates."))),
                .cite = "Mellstrand & Ståhl 2012, p. 76",
            },
            .{
                .kind = "text",
                .body = "The four actions and three imperatives, applied to a " ++ ("target where 'measurement inside the system' is a " ++ "research problem, not a verb you type."),
            },
            .{
                .kind = "h2",
                .body = "3.1  Why analyse",
            },
            .{
                .kind = "text",
                .body = "Predicting whether a capability-derivation change will " ++ ("leave the rootserver unbootable. The cost of a bad " ++ ("prediction is high — the round time is a full qemu " ++ ("boot, far slower than auto-arch's compile rounds — so " ++ ("the analyst earns disproportionately from getting the " ++ "consequence right on the first try.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0143-tool-t0-invalid-input-sel4-kernel",
                .note = "the canonical case where consequence prediction failed",
            },
            .{
                .kind = "h2",
                .body = "3.2  Static and dynamic",
            },
            .{
                .kind = "text",
                .body = "Static side: src/sel4-zig/, the seL4 manual, the " ++ ("capability schema documented in the rootserver source. " ++ ("Dynamic side: serial console output, the (proposed) " ++ ("caps spread reading kernel state through a debug " ++ ("endpoint. The static side is more developed than usual " ++ ("for a domain in this appl, because the dynamic side is " ++ ("underdeveloped — when you cannot afford to inspect at " ++ "runtime, you over-invest in reading at design time.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/sel4-zig/kernel/main.zig",
                .note = "static: the source we own",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log",
                .note = "dynamic: serial console, today's only channel",
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
                .body = "Per kernel-object class. CNodes, TCBs, Pages, " ++ ("Endpoints, Notifications. Each class has a small set " ++ ("of failure modes; subdividing by class is more useful " ++ ("than subdividing by source file because the failure " ++ "almost always crosses files."))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep -r 'fn retype' /home/x/next/arcan/src/sel4-zig",
                .note = "subdivide by retype call",
            },
            .{
                .kind = "h3",
                .body = "Measure",
            },
            .{
                .kind = "text",
                .body = "Today: serial console (via logwatch), qemu monitor " ++ ("commands (via a TS wrapper that does not yet exist), " ++ ("gdb-stub via qemu's gdb-server. Tomorrow: a caps hem " ++ ("verb that pulls capability state through a debug " ++ ("endpoint and renders it as a spread, one row per cap. " ++ ("Agent C owes the ticket. The verbbox below is, " ++ ("literally, the missing-verb ticket as it would appear " ++ "to a reader.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| caps <pid>",
                .note = "TICKET-DRAFT: this verb does not exist; file " ++ "draft-d0NN-hem-caps-builtin.md per OUTLINE.md",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log",
                .note = "today's substitute",
            },
            .{
                .kind = "h3",
                .body = "Represent",
            },
            .{
                .kind = "text",
                .body = "Today: the serial console as raw text. Tomorrow: a " ++ ("boot-stage hilbert spread (where in the boot pipeline " ++ ("is the rootserver right now), a fault-event spread " ++ ("(every kernel response that was a refusal), a CSpace-" ++ ("tree senseye view (the cap tree as a spatial graph). " ++ "Three more tickets Agent C owes.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| boot-stage",
                .note = "TICKET-DRAFT: the boot-stage hilbert verb " ++ "(does not exist); file draft-d0NN-hem-boot-stage.md",
            },
            .{
                .kind = "h3",
                .body = "Intervene",
            },
            .{
                .kind = "text",
                .body = "Edit the rootserver source; rebuild; reboot qemu; " ++ ("replay. The intervention loop is closed today; it is " ++ ("just slow. The auto-arch round-as-snapshot model " ++ ("applies but the round is minutes, not seconds. The " ++ ("snapshots themselves are cheap — qemu state can be " ++ "saved — but no one has wired the hem builtin yet.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| edit /home/x/next/arcan/src/sel4-zig/kernel/main.zig FOO BAR",
                .note = "the intervention is the same verb as elsewhere",
            },
            .{
                .kind = "h2",
                .body = "3.4  Information sources",
            },
            .{
                .kind = "text",
                .body = "Pre-execution: source + capability schema + the seL4 " ++ ("reference manual. The schema is the strongest pre " ++ ("source any of the four parts have, because seL4 is " ++ "rigidly typed at the cap layer.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep -r capability /home/x/next/arcan/src/sel4-zig",
                .note = "pre: the schema as it appears in source",
            },
            .{
                .kind = "text",
                .body = "In-execution: serial console, qemu monitor. The " ++ ("monitor needs a TS wrapper to be hem-native; the " ++ "verbbox below is the missing-verb ticket."),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/qemu-monitor.ts",
                .note = "TICKET-DRAFT: this script does not exist; the " ++ "verbbox itself is the ticket",
            },
            .{
                .kind = "text",
                .body = "Post-execution: qemu coredump (saveable via the " ++ ("monitor), the kernel's last-line output before the " ++ ("fault, gdb-stub state at the moment of the fault. The " ++ ("tooling is conventional; the integration with hem " ++ "is not."))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| cores list",
                .note = "post: hem's existing core browser; will pick up " ++ "qemu cores once the wrapper is filed",
            },
            .{
                .kind = "h2",
                .body = "3.5  The conundrum",
            },
            .{
                .kind = "text",
                .body = "Each iteration is a full reboot. The auto-arch loop " ++ ("pattern (round-as-snapshot) applies but is much " ++ ("slower per round than in the compile or runtime " ++ ("domains. The discipline that compensates is to make " ++ ("the eval gate cheap — exit successful boot the moment " ++ ("the t0 task prints a known sentinel — and to defer the " ++ ("expensive verifications to a separate, less-frequent " ++ "round.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log fault",
                .note = "the cheap eval signal: did t0 fault",
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
                .body = "Compile-time capability typing. Zig comptime can " ++ ("encode a lot of the seL4 capability rules — the " ++ ("rootserver's CSpace layout can be a comptime structure " ++ ("the kernel-call sites are checked against. This is the " ++ ("highest-leverage Fail Early move available in the " ++ "domain and the part of the work that scales.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Often",
            },
            .{
                .kind = "text",
                .body = "A boot-test matrix: each commit re-runs t0 against a " ++ ("small grid of bootinfo configurations (different " ++ ("untyped sizes, different IRQ layouts, different " ++ ("rootserver CSpace depths). Today this matrix is " ++ ("manual; the auto-arch loop pattern would automate " ++ "it once the hem caps verb exists to score the result.")))),
            },
            .{
                .kind = "h3",
                .body = "Fail Hard",
            },
            .{
                .kind = "text",
                .body = "Panic on UB even at boot. The seL4 kernel does this " ++ ("natively; the zig rootserver should match. The " ++ ("temptation to soften a kernel-rejection into a warning " ++ ("and continue is the seL4-specific instance of the " ++ "no-panics-in-compositor-hot-paths rule. Same shape."))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log",
                .note = "the load-bearing kernel rejections are in here",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Five missing-verb tickets named in this chapter; one " ++ ("more in Ch 4. The reading-list quality of Part IV is " ++ ("deliberate — the domain is early, the verbs that would " ++ ("make it visible are work in progress, and the chapter " ++ "is honest about which is which."))),
            },
            .{
                .kind = "crosslink",
                .target = "04_sel4_zig:ch4_tools_of_the_trade",
            },
        },
        .cross_links = .{
            "04_sel4_zig:ch2_software_demystified",
            "04_sel4_zig:ch4_tools_of_the_trade",
            "00_foundations:ch3_principal_debugging",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 4,
                .chapter = 3,
            },
        },
        .tickets = .{
            "draft-d006-tool-t0-invalid-input-sel4-kernel",
            "draft-d012-tool-multi-sel4-kernel-parse-skip",
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
        },
    };
}
