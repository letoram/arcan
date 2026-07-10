
pub fn __init() void {
    return .{
        .title = "Introduction",
        .subtitle = "Part II · Ch 1 · The Self-Hosted Zig Fork",
        .part_id = 2,
        .chapter_id = 1,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The primal aim on the origin of anomalies is that " ++ ("each and every bug is simply an inconsideration on " ++ "behalf of the developer."),
                .cite = "Mellstrand & Ståhl 2012, p. 24",
            },
            .{
                .kind = "text",
                .body = "For years compiling a compiler has been a pastime nobody " ++ ("asked for, and yet here we are. The arcan project keeps a " ++ ("fork of zig — sh-zig — that compiles arcan with the " ++ ("self-hosted backend, no LLVM in the loop. The fork exists " ++ ("because the LLVM dependency is the single biggest piece of " ++ ("Rube-Goldbergness in the build, and a desktop that intends " ++ ("to outlive the next decade cannot be downstream of " ++ ("something that re-architects itself every two. Part II is " ++ ("the practitioner's chapter for the work that fork " ++ "actually causes.")))))))),
            },
            .{
                .kind = "h2",
                .body = "1.1  Demarcation",
            },
            .{
                .kind = "text",
                .body = "What is in scope here: codegen in sh-zig, the linker step " ++ ("that follows it, and the selfhost loop that compiles the " ++ ("next stage of sh-zig with the previous stage. Out of " ++ ("scope: the LLVM-zig codepath, which we keep building " ++ ("alongside the fork as a known-good comparison point — " ++ ("ticket dev-loop06 puts the two disasm streams side by " ++ ("side. Also out of scope: runtime arcan. When stage-3 " ++ ("arcan crashes, the panic belongs to Part III; the " ++ "miscompile that produced it belongs here."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "dev-loop06-disasm-llvm-vs-sh",
                .note = "the comparison stream that anchors this domain",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show dev-loop06-disasm-llvm-vs-sh",
                .note = "the side-by-side that decides what counts as a " ++ "sh-zig anomaly",
            },
            .{
                .kind = "bridge",
                .body = "The fork being software-intensive in its own right is the " ++ "next section's word.",
            },
            .{
                .kind = "h2",
                .body = "1.2  Software-intensive",
            },
            .{
                .kind = "epigraph",
                .body = "Software-intensive systems are composed of many " ++ ("different kinds of software, running on a variety " ++ ("of machines in close collaboration with other kinds " ++ "of devices and processes both mechanical and human.")),
                .cite = "Mellstrand & Ståhl 2012, p. 10",
            },
            .{
                .kind = "text",
                .body = "A compiler that compiles itself is a software-intensive " ++ ("system in miniature. There are three stages and each stage " ++ ("is its own piece of software: stage 0 is whichever zig " ++ ("binary the host shipped with; stage 1 is sh-zig built by " ++ ("stage 0; stage 2 is sh-zig built by stage 1; stage 3 is " ++ ("arcan built by stage 2. Each layer can drift independently " ++ ("of the others. A miscompile in stage 1 produces a stage-2 " ++ ("binary that miscompiles arcan in a way the stage-0 " ++ ("comparison cannot reproduce. The four-layer system is the " ++ ("smallest one this codebase has where the analyst " ++ "absolutely cannot keep all the moving parts in head."))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "the four layers in the build state, right now",
            },
            .{
                .kind = "bridge",
                .body = "The recursion is what makes cause-and-panic in this " ++ "domain its own particular kind of mess.",
            },
            .{
                .kind = "h2",
                .body = "1.3  Cause and panic",
            },
            .{
                .kind = "epigraph",
                .body = "A major part of software analysis and debugging is " ++ ("determining which factors involved caused a certain " ++ ("undesired effect to occur in order to feed this back " ++ ("into upcoming instances of the software, preferably " ++ "by changing some offline artifact like source code."))),
                .cite = "Mellstrand & Ståhl 2012, p. 18",
            },
            .{
                .kind = "text",
                .body = "Proximal cause for an arcan crash compiled with sh-zig is " ++ ("almost never in arcan. It is one stage upstream — " ++ ("the codegen that emitted the offending instruction — and " ++ ("the distal cause is two stages upstream, in whichever " ++ ("decision the previous selfhost round encoded. The auto-arch " ++ ("loop's job is to make this chain replayable: each round is " ++ ("a snapshot, the snapshot includes the source diff, the " ++ ("stage-1 binary, the stage-2 binary, the resulting arcan " ++ ("object files, and the panic line. When a regression appears " ++ ("we walk backwards through the snapshots until the first " ++ ("round that produces it, and the diff of that round is the " ++ "distal cause spelled out.")))))))))),
            },
            .{
                .kind = "text",
                .body = "What the original calls 'feeding the cause back into an " ++ ("offline artifact' is, in this domain, the panic-line " ++ ("auto-drafted ticket. When stage-3 arcan crashes with a " ++ ("trace ending in zig:13053, the auto-arch loop opens " ++ ("drafts/d001 with the body pre-filled. The draft becomes a " ++ ("real ticket the moment a human curates it. The drafts " ++ ("are how the loop's transient knowledge becomes part of " ++ "the codebase's memory.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "draft-d001-panic-select-zig-13053-body",
            },
            .{
                .kind = "ticketref",
                .id = "draft-d004-panic-select-zig-10124-body",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "every recent panic, bucketed",
            },
            .{
                .kind = "bridge",
                .body = "The book then asks where the anomalies come from. For " ++ "this domain there are four shapes.",
            },
            .{
                .kind = "h2",
                .body = "1.4  Origin of anomalies in codegen",
            },
            .{
                .kind = "text",
                .body = "The four ticket clusters that map this domain. Each is one " ++ ("kind of inconsideration the sh-zig developer makes more " ++ "often than they would like."),
            },
            .{
                .kind = "h3",
                .body = "Stack and frame",
            },
            .{
                .kind = "text",
                .body = "Ticket 0001 — sh-codegen emits a function prologue that " ++ ("underestimates the frame size for variadic Lua C-call " ++ ("shims and overflows the kernel-default 8KB stack at first " ++ ("invocation. Inconsideration: the AIR-to-MIR lowering for " ++ ("varargs forgot the spill area for the register save block. " ++ "Visible from a coredump on the very first lua_pushvalue.")))),
            },
            .{
                .kind = "ticketref",
                .id = "0001-sh-codegen-stack-overflow",
            },
            .{
                .kind = "h3",
                .body = "Signedness and integer width",
            },
            .{
                .kind = "text",
                .body = "Ticket 0002 — setSignedness fires an internal assert when " ++ ("given a sub-byte type. Ticket 0003 — pushevent's intcast " ++ ("from i32 to i16 truncates silently because the codegen " ++ ("lowered the truncation as a noop sign-extend. Both are " ++ ("the same shape: an integer-width assumption that is " ++ ("right in upstream zig and wrong in the fork because the " ++ "fork's MIR doesn't carry the signedness through the lowering."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0002-sh-setSignedness-small-size-assert",
            },
            .{
                .kind = "ticketref",
                .id = "0003-arcan-fsrv-pushevent-intcast-truncate",
            },
            .{
                .kind = "h3",
                .body = "Snapshot and miscompile",
            },
            .{
                .kind = "text",
                .body = "Ticket 0007 — statesnap's vcontext miscompiles the local " ++ ("stack array of segment ids; the compiled-down loop reads " ++ ("the wrong slot on iteration 2+. Symptom: durian's monitor " ++ ("view shows segment ids that monotonically grow then jump " ++ ("back, which is impossible in a working engine. The " ++ ("miscompile is in stage-2; reproducing in stage-0 (the " ++ "LLVM build) does not show it."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0007-statesnap-vcontext-stack-miscompile",
            },
            .{
                .kind = "h3",
                .body = "Alignment and panic paths",
            },
            .{
                .kind = "text",
                .body = "Ticket 0008 — lua_close panics with an alignment violation " ++ ("on aarch64-asahi only, because the fork's frame layout " ++ ("doesn't honour the 16-byte alignment Lua's gc thread " ++ ("expects from the pthread stack base. The same binary " ++ ("runs clean on x86_64, which is exactly the kind of fault " ++ ("the original frames as 'machine model breaking the " ++ "developer's assumption' (book §2.7)."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0008-lua-close-alignment-panic",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0001-sh-codegen-stack-overflow",
                .note = "the ticket trail for one cluster, in one spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs draft",
                .note = "all panic-line drafts the loop has produced",
            },
            .{
                .kind = "bridge",
                .body = "Which brings us to the only methodology this domain has " ++ "that is worth a name.",
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
                .body = "The auto-arch loop is the methodology. A round is a " ++ ("hypothesis: change one thing in the fork's source, " ++ ("rebuild stage-1, rebuild stage-2 with stage-1, rebuild " ++ ("arcan with stage-2, run the eval gate. The gate is the " ++ ("test: does arcan boot, does durian render, does the " ++ ("callgraph appl complete its loop without a panic. Pass " ++ ("becomes a fitness score; fitness above the previous best " ++ ("merges to the fossil branch. There is no science here. " ++ ("There is a feedback chain whose round time is short " ++ ("enough to leave it running overnight and whose snapshots " ++ "are cheap enough to walk backwards through afterwards."))))))))),
            },
            .{
                .kind = "text",
                .body = "The visibility-rule corollary for this domain: the loop " ++ ("publishes per-round events on viz_bus under sensors " ++ ("compile.units, compile.errors, selfhost.errors, and " ++ ("auto-arch.round. Any hem spread subscribed to those " ++ ("sensors gets the round telemetry live. We do not look at " ++ "the loop's logs after the fact; we watch it run.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| selfhost",
                .note = "start a selfhost round; the spread updates live",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "see the round in flight alongside everything else",
            },
            .{
                .kind = "bridge",
                .body = "And so the chapter ends where the original does, by " ++ "pointing at the next one.",
            },
            .{
                .kind = "h2",
                .body = "1.6  Concluding",
            },
            .{
                .kind = "text",
                .body = "Ch 2 walks the eight-stage pipeline that turns a sh-zig " ++ ("source change into a stage-3 arcan binary. Ch 3 takes " ++ ("the principal-debugging four actions and lands them on " ++ ("the live loop. Ch 4 is the verb roll-call: which hem " ++ ("verbs are this domain's debugger, tracer, profiler, " ++ "visualizer.")))),
            },
            .{
                .kind = "crosslink",
                .target = "02_zig_fork:ch2_software_demystified",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch3_principal_debugging",
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "02_zig_fork:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 2,
                .chapter = 1,
            },
        },
        .tickets = .{
            "0001-sh-codegen-stack-overflow",
            "0002-sh-setSignedness-small-size-assert",
            "0003-arcan-fsrv-pushevent-intcast-truncate",
            "0007-statesnap-vcontext-stack-miscompile",
            "0008-lua-close-alignment-panic",
            "draft-d001-panic-select-zig-13053-body",
            "draft-d004-panic-select-zig-10124-body",
            "dev-loop06-disasm-llvm-vs-sh",
        },
    };
}
