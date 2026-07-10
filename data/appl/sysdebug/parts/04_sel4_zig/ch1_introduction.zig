
pub fn __init() void {
    return .{
        .title = "Introduction",
        .subtitle = "Part IV · Ch 1 · seL4 Bootstrapping in Zig",
        .part_id = 4,
        .chapter_id = 1,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "We simply consider a bug to be unwanted system " ++ ("behavior (according to some actor) with the typical " ++ ("restriction that it's non-trivial to explain why " ++ "the system behaves as it does.")),
                .cite = "Mellstrand & Ståhl 2012, p. ix",
            },
            .{
                .kind = "text",
                .body = "The medium-term bet is that the arcan desktop boots " ++ ("directly on seL4 with a zig rootserver. Today that means " ++ ("src/sel4-zig/kernel/*.zig plus a handful of draft " ++ ("tickets capturing the early failures — t0 input " ++ ("validation, the multi-kernel parse skip, two more in " ++ ("the queue. Part IV documents what exists, the framing " ++ ("the canonical book offers for a capability system, and " ++ ("what hem_dev verbs would have to be filed to bring " ++ "this domain into the visibility rule."))))))),
            },
            .{
                .kind = "h2",
                .body = "1.1  Demarcation",
            },
            .{
                .kind = "text",
                .body = "What is in scope: the kernel build, the rootserver, the " ++ ("first user task and its IPC to the rootserver. Out of " ++ ("scope: full arcan-on-seL4. That is years away; the " ++ ("engine has too many posix dependencies left, and the " ++ "shim work (Part III) is the precondition."))),
            },
            .{
                .kind = "ticketref",
                .id = "draft-d006-tool-t0-invalid-input-sel4-kernel",
            },
            .{
                .kind = "ticketref",
                .id = "draft-d012-tool-multi-sel4-kernel-parse-skip",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0143-tool-t0-invalid-input-sel4-kernel",
                .note = "the t0 ticket; it is the canonical 'first failure' for this domain",
            },
            .{
                .kind = "bridge",
                .body = "What software-intensive looks like inside a microkernel " ++ "is the next section's word.",
            },
            .{
                .kind = "h2",
                .body = "1.2  Software-intensive in a microkernel",
            },
            .{
                .kind = "epigraph",
                .body = "We are now moving away from the realm of " ++ ("software-as-punch-cards and into software-intensive " ++ ("systems, where systems are composed of many " ++ ("different kinds of software, running on a variety " ++ ("of machines in close collaboration with other " ++ ("kinds of devices and processes both mechanical and " ++ "human."))))),
                .cite = "Mellstrand & Ståhl 2012, p. 10",
            },
            .{
                .kind = "text",
                .body = "The intuition the original sets up — that a software-" ++ ("intensive system is intensive because of how many " ++ ("subsystems it crosses — inverts on a microkernel. The " ++ ("kernel itself does almost nothing: schedule, switch " ++ ("context, route IPC. Everything else is in user mode. " ++ ("There is no shim story; there is a great deal of " ++ ("explicit capability passing. Each subsystem matters " ++ ("more, not less, because there is no kernel-side hidden " ++ "machinery to fall back on."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/sel4-zig",
                .note = "the source surface for what we own",
            },
            .{
                .kind = "bridge",
                .body = "Cause and panic on a capability system is structurally " ++ "different from cause and panic on linux.",
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
                .body = "Every fault in seL4 land is a missing or miscast " ++ ("capability. There is no SIGSEGV in the linux sense; " ++ ("there is a kernel response saying 'you do not have the " ++ ("right to do that' or 'you sent the wrong type of " ++ ("endpoint cap'. Draft d006 is the canonical case: t0 — " ++ ("the very first user task — is rejected by the kernel " ++ ("with InvalidInput before its first instruction. Walking " ++ ("back from the trace tells us which capability was " ++ ("wrong, but the trace itself comes from a serial console " ++ ("we have to capture out-of-band, because there is no " ++ "kernel-side syslog yet."))))))))),
            },
            .{
                .kind = "ticketref",
                .id = "draft-d006-tool-t0-invalid-input-sel4-kernel",
                .note = "the InvalidInput trace; the canonical first-failure",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0143-tool-t0-invalid-input-sel4-kernel",
                .note = "the trace, captured",
            },
            .{
                .kind = "bridge",
                .body = "Origin of anomalies on a microkernel has only a few " ++ "shapes, and they recur.",
            },
            .{
                .kind = "h2",
                .body = "1.4  Origin of anomalies",
            },
            .{
                .kind = "h3",
                .body = "Capability derivation mistakes",
            },
            .{
                .kind = "text",
                .body = "A capability is derived from another by retype. Get the " ++ ("derivation order wrong and you have a CNode pointing " ++ ("at memory that another CNode also points at, and the " ++ ("kernel notices on the next operation. This is the " ++ "shape draft d006 takes."))),
            },
            .{
                .kind = "h3",
                .body = "Rootserver bringup ordering",
            },
            .{
                .kind = "text",
                .body = "The rootserver has to set up its own CSpace and VSpace " ++ ("before it can install the first user task. Get the " ++ ("ordering wrong — install a task whose endpoint cap " ++ ("lives in a CNode that has not been mapped yet — and " ++ ("the task is unbootable. Draft d012's multi-kernel " ++ ("parse skip is upstream of this in the build (we cannot " ++ ("even produce the binary), but the same ordering " ++ "discipline applies.")))))),
            },
            .{
                .kind = "h3",
                .body = "Missing untyped retypes",
            },
            .{
                .kind = "text",
                .body = "The bootinfo page lists untypeds the rootserver may " ++ ("consume. Forget to retype one before referencing " ++ ("memory that requires it, and the same InvalidInput " ++ "kernel response. The shape repeats.")),
            },
            .{
                .kind = "ticketref",
                .id = "draft-d012-tool-multi-sel4-kernel-parse-skip",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs draft",
                .note = "every seL4 draft ticket",
            },
            .{
                .kind = "bridge",
                .body = "Methodology in this domain is the same four actions, " ++ "structurally constrained.",
            },
            .{
                .kind = "h2",
                .body = "1.5  Methodology",
            },
            .{
                .kind = "text",
                .body = "Subdivide / Measure / Represent / Intervene. Subdivide " ++ ("and Intervene work as elsewhere — per kernel-object " ++ ("class, per source file, per ticket. Measure is the " ++ ("step the domain constrains: there is no procfs, no " ++ ("metrics, no engine watch. We measure by reading " ++ ("capability state at known IPC boundaries — at the " ++ ("kernel-rootserver boundary on boot, at " ++ ("rootserver-task boundaries thereafter. Today that means " ++ ("serial console; tomorrow it means a caps hem verb " ++ "this chapter owes the reader.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/sel4-zig/kernel/main.zig",
                .note = "the kernel entry, today's measurement substrate",
            },
            .{
                .kind = "h2",
                .body = "1.6  Concluding",
            },
            .{
                .kind = "text",
                .body = "Ch 2 sketches the boot pipeline from bootinfo to first " ++ ("task. Ch 3 lands the four actions and flags every " ++ ("primitive that has to be filed before this domain is " ++ ("fully under the visibility rule. Ch 4 is the verb roll-" ++ ("call divided into 'today' and 'tomorrow' — the " ++ "tomorrow column is also the ticket queue.")))),
            },
            .{
                .kind = "crosslink",
                .target = "04_sel4_zig:ch2_software_demystified",
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "04_sel4_zig:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 4,
                .chapter = 1,
            },
        },
        .tickets = .{
            "draft-d006-tool-t0-invalid-input-sel4-kernel",
            "draft-d012-tool-multi-sel4-kernel-parse-skip",
            "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
        },
    };
}
