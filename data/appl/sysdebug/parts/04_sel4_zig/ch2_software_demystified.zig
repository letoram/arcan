
pub fn __init() void {
    return .{
        .title = "Software Demystified",
        .subtitle = "Part IV · Ch 2 · seL4 Bootstrapping in Zig",
        .part_id = 4,
        .chapter_id = 2,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "Self-contained executable files which can be loaded " ++ ("and executed without any external dependencies are " ++ ("called static executables or statically linked " ++ ("binaries. This type of executable system has a " ++ ("very limited ability to communicate with its " ++ "environment.")))),
                .cite = "Mellstrand & Ståhl 2012, p. 55",
            },
            .{
                .kind = "text",
                .body = "The seL4 kernel is the static-by-design case the original " ++ ("describes, taken to its limit: it boots, hands the " ++ ("rootserver bootinfo, and from then on every interaction " ++ ("with its environment goes through capability-mediated " ++ ("IPC. The pipeline below walks from bootinfo to the first " ++ ("user task being installed. Each stage has its own way " ++ "of failing."))))),
            },
            .{
                .kind = "h2",
                .body = "2.1  Source",
            },
            .{
                .kind = "text",
                .body = "src/sel4-zig/kernel/*.zig is what we own — the seL4 " ++ ("kernel C source comes in via vendor/ as a build " ++ ("dependency. The zig side is a thin shim: kernel " ++ ("bootinfo parsing, the rootserver entry, the cap " ++ ("shuffling for the first task. Reading it cold takes " ++ ("an hour because it is small; the trick is recognising " ++ ("which symbols come from upstream seL4 versus from our " ++ "own zig.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/src/sel4-zig/kernel/main.zig",
                .note = "kernel entry on the zig side",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/src/sel4-zig",
                .note = "the full source surface",
            },
            .{
                .kind = "h2",
                .body = "2.2  Bootinfo",
            },
            .{
                .kind = "text",
                .body = "The page seL4 hands the rootserver. It contains the " ++ ("list of untypeds, the initial CSpace cap layout, the " ++ ("kernel's view of available IRQs and memory regions. " ++ ("Reading bootinfo correctly is the first thing the " ++ ("rootserver has to do, and getting it wrong fails t0 " ++ ("before its first instruction. Today we read it through " ++ ("the C kernel's serial-console dumps; tomorrow we want " ++ ("a hem caps verb that decodes the same data into a " ++ ("spread (this is the missing-verb ticket Agent C is " ++ "asked to file).")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| logwatch /tmp/sel4-serial.log",
                .note = "today: serial console dump as the bootinfo source",
            },
            .{
                .kind = "h2",
                .body = "2.3  Untyped",
            },
            .{
                .kind = "text",
                .body = "Raw memory pool. Each untyped has a base address and a " ++ ("size; the rootserver retypes pieces of it into specific " ++ ("kernel objects. The accounting matters — once retyped, " ++ ("an untyped chunk is consumed for the lifetime of the " ++ ("object. Untyped exhaustion at boot is one of the " ++ "shapes draft d006 takes.")))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep untyped /home/x/next/arcan/src/sel4-zig",
                .note = "every reference in the zig side",
            },
            .{
                .kind = "h2",
                .body = "2.4  Retype",
            },
            .{
                .kind = "text",
                .body = "The kernel call that turns untyped into a typed object: " ++ ("CNode, TCB, Page, Endpoint, Notification. Order matters " ++ ("and the dependency chain is real — a TCB needs a " ++ ("CSpace and a VSpace, which need CNodes and PageTables, " ++ ("which need their own pages. Build the chain bottom-up " ++ ("or the kernel rejects the next call. The retype " ++ ("sequence is the bulk of the rootserver's first half-" ++ "second of execution.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep retype /home/x/next/arcan/src/sel4-zig",
                .note = "every retype call site",
            },
            .{
                .kind = "h2",
                .body = "2.5  CSpace and VSpace construction",
            },
            .{
                .kind = "text",
                .body = "The rootserver's first job once it has untypeds and " ++ ("retypes is to build its own CSpace tree (where caps " ++ ("live) and its own VSpace (the page tables for its own " ++ ("address space). Both are recursive structures; both " ++ ("have to be self-consistent before the rootserver can " ++ ("install anything else. A misconfigured CSpace is " ++ "another shape draft d006 takes."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep -r CSpace /home/x/next/arcan/src/sel4-zig",
                .note = "the CSpace construction code",
            },
            .{
                .kind = "h2",
                .body = "2.6  ELF loading",
            },
            .{
                .kind = "text",
                .body = "The first user task is shipped as an ELF embedded in " ++ ("the rootserver binary. The rootserver parses it, " ++ ("retypes pages from untyped to back the loadable " ++ ("segments, maps them into the task's VSpace, and writes " ++ ("the entry point into the new TCB. Then it starts the " ++ ("TCB. If any of the maps are wrong, t0 takes a fault on " ++ ("its first instruction; the kernel returns to the " ++ ("rootserver's fault handler, which has nowhere useful " ++ "to send the trace except the serial console."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /path/to/rootserver.elf",
                .note = "today: post-link inspection of the rootserver binary",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /path/to/rootserver.elf",
                .note = "today: symbol table; pair with the load addresses from bootinfo",
            },
            .{
                .kind = "h2",
                .body = "2.7  IPC",
            },
            .{
                .kind = "text",
                .body = "seL4's synchronous fast path. A Send on an Endpoint " ++ ("blocks until a Receive completes; the kernel transfers " ++ ("registers and a small message buffer between sender " ++ ("and receiver. This is structurally different from " ++ ("shmif: shmif is asynchronous-and-shared, seL4 IPC is " ++ ("synchronous-and-rendezvous. The mental-model port for " ++ ("anyone arriving from Part III is the hardest single " ++ "step in this domain.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep IPC /home/x/next/arcan/src/sel4-zig",
                .note = "the IPC call sites",
            },
            .{
                .kind = "h2",
                .body = "2.8  Zig allocator and retype",
            },
            .{
                .kind = "text",
                .body = "The open question. Zig's allocator is a userspace " ++ ("abstraction; retype is a kernel call that consumes a " ++ ("specific untyped. The allocator-vs-retype impedance " ++ ("match is what the rootserver code has to bridge, and " ++ ("the bridge today is hand-written and fragile. The " ++ ("right shape is probably a custom allocator that takes " ++ ("an untyped pool as its backing store, but that has " ++ ("not been written yet. This is the largest open " ++ "design question in the domain."))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep -r Allocator /home/x/next/arcan/src/sel4-zig",
                .note = "every allocator-related touchpoint",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Eight stages from bootinfo to a running first task. Ch 3 " ++ ("applies the four-action spine and flags every place a " ++ "missing primitive blocks the visibility rule."),
            },
            .{
                .kind = "crosslink",
                .target = "04_sel4_zig:ch3_principal_debugging",
            },
        },
        .cross_links = .{
            "04_sel4_zig:ch1_introduction",
            "04_sel4_zig:ch3_principal_debugging",
            "00_foundations:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 4,
                .chapter = 2,
            },
        },
        .tickets = .{
            "draft-d006-tool-t0-invalid-input-sel4-kernel",
            "draft-d012-tool-multi-sel4-kernel-parse-skip",
        },
    };
}
