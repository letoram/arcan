
pub fn __init() void {
    return .{
        .title = "Introduction",
        .subtitle = "Part I · Ch 1 · Foundations",
        .part_id = 1,
        .chapter_id = 1,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "We simply consider a bug to be unwanted system " ++ ("behavior (according to some actor) with the typical " ++ ("restriction that it's non-trivial to explain why the " ++ "system behaves as it does.")),
                .cite = "Mellstrand & Ståhl 2012, p. ix",
            },
            .{
                .kind = "text",
                .body = "This appl is not a textbook. The textbook already exists. " ++ ("It is sitting in a PDF at the root of this repo and four of " ++ ("its chapters anchor four of ours. What this appl is, " ++ ("instead, is a workshop manual: the same methodology, " ++ ("applied to one specific stack — the one whose source you " ++ ("are reading from inside. Where the original speaks well, " ++ ("we quote it and move on. Where the original is generic on " ++ "purpose, we are specific on purpose.")))))),
            },
            .{
                .kind = "text",
                .body = "The other thing this appl is, less obviously, is a bet. " ++ ("The bet is that the difference between a debugging book " ++ ("and a debugging tool is whether you can run the verb the " ++ ("moment you read about it. Every chapter ends in at least " ++ ("one verbbox. If a paragraph names a tool and there is no " ++ "verbbox under it, the chapter has failed itself.")))),
            },
            .{
                .kind = "h2",
                .body = "1.1  Demarcation",
            },
            .{
                .kind = "epigraph",
                .body = "The focus for this and coming chapters is primarily " ++ ("on dynamic analysis as a means for grasping and " ++ ("refining an understanding of the particulars of a " ++ ("given system, and, to a lesser degree, how we can " ++ ("manipulate software during all stages of " ++ "construction in order to ease future analysis.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 5",
            },
            .{
                .kind = "text",
                .body = "What is in scope here is what the original book is in " ++ ("scope for, narrowed to four sub-projects that happen to be " ++ ("the live work in this repo: the self-hosted Zig fork " ++ ("(Part II), the zig migration of arcan itself with " ++ ("afsrv_bun as the worked example (Part III), the " ++ ("seL4 bootstrap in zig (Part IV), and a12 over Tailscale " ++ ("(Part V). Out of scope: general debugging theory. The " ++ ("original handles that, and we will quote it where it " ++ "earns its keep."))))))),
            },
            .{
                .kind = "text",
                .body = "Also out of scope, deliberately: the rest of the desktop. " ++ ("durian lua, the hem shell internals, the auto-arch " ++ ("loop's full architecture — these are the substrate the " ++ ("four parts run on, but they are not what the parts are " ++ ("about. When a chapter needs them, it links sideways to " ++ ("the chapter or article that does cover them. Most often " ++ "that is Ch 0, which is the codebase map."))))),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch0_architecture",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "the rule that defines this scope",
            },
            .{
                .kind = "bridge",
                .body = "The reason a workshop manual works for this codebase and " ++ ("not for, say, an embedded compiler in isolation is that " ++ ("this codebase is software-intensive. That is the next " ++ "section's word.")),
            },
            .{
                .kind = "h2",
                .body = "1.2  Software-intensive systems",
            },
            .{
                .kind = "epigraph",
                .body = "We are now moving away from the realm of " ++ ("software-as-punch-cards and into software-intensive " ++ ("systems, where systems are composed of many " ++ ("different kinds of software, running on a variety " ++ ("of machines in close collaboration with other kinds " ++ "of devices and processes both mechanical and human.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 10",
            },
            .{
                .kind = "text",
                .body = "The arcan stack is exactly the kind of system the original " ++ ("is talking about. The engine is one binary. Around it sit " ++ ("eight frameservers, each its own process, each holding a " ++ ("shmif segment. The lua side runs durian (the window " ++ ("manager), lash (the shell host), hem (the shell), and an " ++ ("appl tree of lua programs the user can boot into — this " ++ ("one included. The TypeScript side runs inside afsrv_bun " ++ ("and reaches the engine through the same shmif. Add a12, " ++ ("the network protocol, and the system extends across the " ++ ("Tailnet to whatever sink the directory hands it to. Every " ++ ("boundary in that list is a place where two different " ++ ("kinds of software talk through one IPC, and every one is " ++ "a place an anomaly can hide."))))))))))),
            },
            .{
                .kind = "text",
                .body = "The book uses the 2003 Northeast blackout as its case " ++ ("study; we have our own. The afsrv_bun project (ticket " ++ ("0036) has spent ~18 months oscillating between three " ++ ("answers to one question — where does the TypeScript " ++ ("process live in arcan — and the reason it took that long " ++ ("is precisely that the answer crosses every boundary on " ++ ("the list above. There was no single subsystem to fix. The " ++ "fix was a discipline about how all of them are observed.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
                .note = "the case study",
            },
            .{
                .kind = "articleref",
                .slug = "visibility_rule",
                .title = "The visibility rule, why",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=afsrv",
                .note = "the boundaries, alive right now",
            },
            .{
                .kind = "bridge",
                .body = "When the system is this distributed, talking about the " ++ ("cause of a fault gets philosophical fast. The next " ++ "section is the original's framing for that."),
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
                .body = "The original distinguishes proximal and distal causes — " ++ ("the trigger that fires the Goldberg machine versus the " ++ ("thing that set the trigger up in the first place. In a " ++ ("single-process program with one thread the distinction is " ++ ("academic; in a system like this one it is most of the " ++ ("work. A segment_request hangs because durian's fetchfds " ++ ("expects an fd that afsrv_bun never sends, but afsrv_bun " ++ ("never sends it because Phase 3l of the migration disabled " ++ ("subsegment passthrough, and that was disabled because an " ++ ("earlier round in the auto-arch loop produced a stage-2 " ++ ("binary that crashed on retry. Each link is the " ++ ("proximal cause for the next one. The distal cause is the " ++ ("decision tree the auto-arch loop walked. The fix lives at " ++ "whichever link is cheapest to change.")))))))))))),
            },
            .{
                .kind = "text",
                .body = "What the book calls 'feeding the cause back into an " ++ ("offline artifact' has a very direct analogue here. " ++ ("Fossil tickets are that artifact. The auto-arch loop " ++ ("writes them; humans curate them; every fix that lands " ++ ("cites the ticket id in the commit message. The tickets " ++ ("are the codebase's memory of why a thing is the way it " ++ ("is. Without them the same proximal cause gets debugged " ++ "from scratch every quarter.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
                .note = "the canonical example: a rule, written down, " ++ "anchoring future work",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /home/x/.arcan/logs panic",
                .note = "see what an actual panic looks like in this " ++ "codebase",
            },
            .{
                .kind = "bridge",
                .body = "The book then asks where anomalies come from in the " ++ "first place. Our answer is in four shapes.",
            },
            .{
                .kind = "h2",
                .body = "1.4  The origin of anomalies",
            },
            .{
                .kind = "epigraph",
                .body = "The primal aim on the origin of anomalies is that " ++ ("each and every bug is simply an inconsideration on " ++ ("behalf of the developer. As a developer there are " ++ ("literally hundreds of protocols, conventions and " ++ ("interfaces within the machine, language and " ++ ("execution environment that, to a variety of " ++ "degrees, need to be followed."))))),
                .cite = "Mellstrand & Ståhl 2012, p. 24",
            },
            .{
                .kind = "text",
                .body = "The four parts of this appl each chase one shape of " ++ ("inconsideration. Part II hunts codegen miscompiles in " ++ ("the self-hosted Zig fork — the developer's " ++ ("inconsideration is most often about signedness, " ++ ("alignment, or the precise semantics of a panic path that " ++ ("differs from upstream. Part III hunts protocol races " ++ ("across shmif segments — the inconsideration is about who " ++ ("signals video first, or which side of the segment " ++ ("request sends the fd. Part IV hunts capability mistakes " ++ ("in the seL4 bootstrap — the inconsideration is about " ++ ("what was retyped from which untyped, and in which order. " ++ ("Part V hunts wire-side disagreements between the two " ++ ("ends of an a12 session — the inconsideration is about " ++ ("version drift, key trust, or clock skew across a " ++ "Tailnet."))))))))))))),
            },
            .{
                .kind = "text",
                .body = "Each of these is an inconsideration that the developer " ++ ("could have avoided by reading the relevant protocol more " ++ ("carefully, but the protocols are not short. The book's " ++ ("framing makes the size of the protocol surface explicit; " ++ ("ours adds an observation: when there are hundreds of " ++ ("protocols and you cannot read all of them, the next-best " ++ ("discipline is to make sure you can SEE which one is " ++ ("failing when it does. Visibility is the " ++ "inconsideration-correction primitive."))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0001-sh-codegen-stack-overflow",
            },
            .{
                .kind = "ticketref",
                .id = "0007-statesnap-vcontext-stack-miscompile",
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-afsrv-bun-frameserver",
                .note = "the trail of inconsiderations on one project",
            },
            .{
                .kind = "bridge",
                .body = "Which brings the chapter to where the original does: " ++ "the question of method.",
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
                .body = "The book is dry about debugging methods, and we are " ++ ("drier. There is no method here. There is one rule, and " ++ ("it is more of a discipline than a method: every claim a " ++ ("chapter makes about the system has to come with a verb " ++ ("the reader can run to see the claim themselves. If the " ++ ("claim cannot be made visible, the chapter has no " ++ "business making it."))))),
            },
            .{
                .kind = "text",
                .body = "This is not new. The original 3.3 (System Views and " ++ ("Analysis Actions) names the four moves any debugger " ++ ("makes — Subdivide, Measure, Represent, Intervene — and " ++ ("the visibility rule is what those four moves look like " ++ ("when the substrate is hem cells in durian. Subdivide is " ++ ("a new spread per subsystem. Measure is metrics, procfs, " ++ ("engine watch. Represent is the spread itself plus the " ++ ("senseye-applied layer-5 view. Intervene is edit, write, " ++ ("durian.send, hemSpawn. The point of writing the rule " ++ ("down separately is that without it those four moves " ++ ("happen invisibly, inside the harness, and the user " ++ "loses track of what was even attempted.")))))))))),
            },
            .{
                .kind = "articleref",
                .slug = "visibility_rule",
                .title = "The visibility rule, why",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "Subdivide: every subsystem at once",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| metrics",
                .note = "Measure: live resource use as a spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| dashboard",
                .note = "Represent: the composition",
            },
            .{
                .kind = "bridge",
                .body = "The original closes Ch 1 by asking what software actually " ++ "is. So do we; the answer is shorter.",
            },
            .{
                .kind = "h2",
                .body = "1.6  Concluding",
            },
            .{
                .kind = "epigraph",
                .body = "A major question still lingers however: what is " ++ "software?",
                .cite = "Mellstrand & Ståhl 2012, p. 36",
            },
            .{
                .kind = "text",
                .body = "For the next four parts, the operational answer is: " ++ ("software is what shmif passes between segments. " ++ ("Everything else — source code, object files, ELF " ++ ("binaries, lua tables, JSC strings, a12 frames — is " ++ ("scaffolding around that one fact. When a part of this " ++ ("system goes wrong, what we measure is what crosses " ++ ("shmif. When we intervene, we intervene on what crosses " ++ ("shmif. The next chapter walks the full pipeline that " ++ ("produces the binaries on either side of a shmif " ++ ("segment, and from chapter 3 onward we move into the live " ++ "system."))))))))),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch2_software_demystified",
            },
        },
        .cross_links = .{
            "00_foundations:ch0_architecture",
            "00_foundations:ch2_software_demystified",
            "00_foundations:visibility_rule_article",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 1,
            },
        },
        .tickets = .{
            "0036-visibility-rule",
            "0036-afsrv-bun-frameserver",
            "0001-sh-codegen-stack-overflow",
            "0007-statesnap-vcontext-stack-miscompile",
            "0100-refactor-posix-libc",
        },
    };
}
