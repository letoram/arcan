
pub fn __init() void {
    return .{
        .title = "Software Demystified",
        .subtitle = "Part I · Ch 2 · Foundations",
        .part_id = 1,
        .chapter_id = 2,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "To determine the behavior a particular piece of " ++ ("software will present when executing, one must have " ++ "an extensive knowledge about the system at hand."),
                .cite = "Mellstrand & Ståhl 2012, p. 40",
            },
            .{
                .kind = "text",
                .body = "The original chapter walks one program (a small C " ++ ("program with deliberate bugs) all the way from source to " ++ ("the CPU. We do not repeat that walk; we point at it. " ++ ("What we walk instead is the same pipeline at four " ++ ("different scales — the four hello-worlds that anchor " ++ ("Parts II through V. Each one breaks differently, and " ++ "each break maps to one of the original's eight sections."))))),
            },
            .{
                .kind = "h2",
                .body = "2.1  Hello, world",
            },
            .{
                .kind = "text",
                .body = "Four hello worlds, one per part. Part II's is `zig " ++ ("build` — the self-hosted fork compiling itself, then " ++ ("compiling arcan, then compiling hem. Part III's is " ++ ("`arcan welcome`, which boots the engine into the " ++ ("smallest non-trivial appl and exits. Part IV's is the " ++ ("seL4 root task that prints over the serial console " ++ ("before handing off to anything userspace. Part V's is " ++ ("`arcan-net <directory>@ explain`, which performs an a12 " ++ ("handshake against a directory and prints what it saw. " ++ ("All four should succeed. When one of them stops " ++ "succeeding, that part has a chapter of work to do."))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| zigbuild",
                .note = "Part II's hello world — start a build, watch the " ++ "live error spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| run /home/x/next/arcan/zig-out/bin/arcan welcome",
                .note = "Part III's hello world (run the engine into the " ++ "smallest appl)",
            },
            .{
                .kind = "bridge",
                .body = "Each of those four hello worlds is the output of a tool " ++ "chain. The next section is the chain itself.",
            },
            .{
                .kind = "h2",
                .body = "2.2  Source to binary",
            },
            .{
                .kind = "epigraph",
                .body = "The key principle for a toolchain is that a series " ++ ("of tools is to be applied where the output from one " ++ "tool is the input to the next."),
                .cite = "Mellstrand & Ståhl 2012, p. 43",
            },
            .{
                .kind = "text",
                .body = "We have four tool chains in this repo, decoupled enough " ++ ("to walk separately. The Zig chain (Part II): zig source " ++ ("→ tokens → AST → AIR → MIR → object → ELF, no LLVM. The " ++ ("C-and-Zig chain that builds arcan and frameservers (Part " ++ ("III): mixed C and zig, llvm-zig backend, dynamic linking " ++ ("for shmif consumers. The seL4 chain (Part IV): zig " ++ ("source for the rootserver, statically linked, the " ++ ("kernel itself coming from upstream seL4 sources. The a12 " ++ ("chain (Part V): a sub-tree of the C-and-zig chain whose " ++ ("output is arcan-net rather than arcan. Each chapter of " ++ "each part takes one stage of one chain and walks it."))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build.zig",
                .note = "the top-level chain",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build_llvm/build.zig",
                .note = "the LLVM-tainted side chain (afsrv_bun lives here)",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build.zig",
                .note = "the actual chain, not a sketch of it",
            },
            .{
                .kind = "bridge",
                .body = "The chain has a developer at one end. That developer's " ++ "assumptions are part of the system.",
            },
            .{
                .kind = "h2",
                .body = "2.3  The developer",
            },
            .{
                .kind = "epigraph",
                .body = "There is no automated way to transform an informal " ++ ("description of a system into a formal description, " ++ ("and to do this task a developer must make a number " ++ "of assumptions, generalizations and simplifications.")),
                .cite = "Mellstrand & Ståhl 2012, p. 44",
            },
            .{
                .kind = "text",
                .body = "The developer's assumptions on this codebase are not " ++ ("implicit. They are written down. CLAUDE.md at the repo " ++ ("root is the largest such artefact: forty-odd rules about " ++ ("what is built where, which paths are stable, what should " ++ ("never be deleted, which are the visible inspection " ++ ("primitives. _helpers.lua under hem_dev encodes the " ++ ("viz_bus contract — payload key shapes, sensor naming, " ++ ("the cross-cell event names the spreads agree on. The " ++ ("build.zig comments encode the trickier ones: why " ++ ("afsrv_bun is in build_llvm, why BUILD_PROFILE=release on " ++ "Asahi, what useC and useLlvmForSource gate."))))))))),
            },
            .{
                .kind = "text",
                .body = "When something breaks in a way that surprises the " ++ ("developer who wrote those assumptions down, the " ++ ("assumption is the first place to look. Half of the " ++ ("fossil tickets start by quoting the line in CLAUDE.md " ++ "or _helpers.lua that turned out to be load-bearing."))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/CLAUDE.md",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
                .note = "the viz_bus contract",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/CLAUDE.md",
                .note = "the assumptions, in their actual form",
            },
            .{
                .kind = "bridge",
                .body = "The compiler is the next thing in the chain after the " ++ "developer.",
            },
            .{
                .kind = "h2",
                .body = "2.4  Source and the compiler",
            },
            .{
                .kind = "epigraph",
                .body = "No high-level language allows for unrestricted " ++ ("communication between its principal entities or " ++ ("communication as free as the actual machine code " ++ ("allows. Understanding the restrictions placed on " ++ ("high-level languages is essential when hijacking " ++ ("execution, which is a key to tracing and debugging " ++ "complex software systems."))))),
                .cite = "Mellstrand & Ståhl 2012, p. 46",
            },
            .{
                .kind = "text",
                .body = "Three high-level languages cross this codebase, each " ++ ("with its own restrictions to know about. C is loose " ++ ("about types and memory, strict about ABI; the engine's " ++ ("older code lives there. Zig is strict about types and " ++ ("memory ownership, gives the developer comptime as a " ++ ("first-class restriction-loosener for the cases C would " ++ ("have used a macro for, and exposes its own calling " ++ ("convention story when it talks to C. Lua is loose about " ++ ("types and ABI, strict about nothing — which is " ++ ("deliberate; the durian side gets to be loose because the " ++ ("engine is strict on its behalf. Each of the four parts " ++ ("spends time on the restrictions of its primary " ++ ("language; the inconsiderations the original calls bugs " ++ "are most often violations of those restrictions.")))))))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/engine/arcan_lua.zig",
                .note = "where Lua and the engine talk; the bridge between " ++ "two restriction systems",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan name=lua",
                .note = "all the lua_* symbols the engine binds",
            },
            .{
                .kind = "bridge",
                .body = "The compiler emits object files. The linker is the next " ++ "section, and it is the one that earns its own analogy.",
            },
            .{
                .kind = "h2",
                .body = "2.5  Object code and the linker",
            },
            .{
                .kind = "epigraph",
                .body = "In a modern tool chain the linker is the only tool " ++ "that considers the entire system at once.",
                .cite = "Mellstrand & Ståhl 2012, p. 51",
            },
            .{
                .kind = "text",
                .body = "This is the line we keep coming back to. The original " ++ ("is talking about the link step in a single binary's " ++ ("build. We have an analogue at runtime: shmif is the only " ++ ("thing that sees every frameserver at once. The compiler " ++ ("sees one source file. The linker sees one binary. The " ++ ("engine sees one shmif page per client. shmif itself — " ++ ("the protocol, the page layout, the event ring — is the " ++ ("whole-system view. If you want to debug something " ++ ("across two frameservers, you measure what shmif passes " ++ "between them. Anything else is local reasoning.")))))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the contract every link in the chain agrees on",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a",
                .note = "the linker's output for the contract itself",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan",
                .note = "every symbol the engine ended up with after link",
            },
            .{
                .kind = "bridge",
                .body = "Once linked, the binary still has to be loaded. The " ++ "next section is what happens at load time.",
            },
            .{
                .kind = "h2",
                .body = "2.6  Executable and loading",
            },
            .{
                .kind = "epigraph",
                .body = "Self-contained executable files which can be loaded " ++ ("and executed without any external dependencies are " ++ ("called static executables or statically linked " ++ ("binaries. This type of executable system has a very " ++ "limited ability to communicate with its environment."))),
                .cite = "Mellstrand & Ståhl 2012, p. 55",
            },
            .{
                .kind = "text",
                .body = "arcan is dynamic by necessity. A static arcan would be a " ++ ("compositor that cannot accept new clients — and the " ++ ("whole point of the engine is that frameservers and " ++ ("shmif consumers come and go at runtime. afsrv_bun loads " ++ ("a TypeScript module the user picked, half a second " ++ ("before it actually runs. arcan-net pulls an appl bundle " ++ ("from a Tailscale peer and hands it to a sub-arcan to " ++ "run. None of that is possible with a static binary.")))))),
            },
            .{
                .kind = "text",
                .body = "Part IV inverts this. A seL4 rootserver wants to be as " ++ ("static as it can; the loader is the kernel, not glibc, " ++ ("and the only dependencies are capabilities derived from " ++ ("untyped memory at boot. The same paragraph in the " ++ ("original about static executables is, for Part IV, the " ++ ("ideal — and that is itself a debugging story, because " ++ "anything dynamic that creeps in is an inconsideration."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $$ maps",
                .note = "what the loader did for this very cell — the " ++ ("list of mapped libraries is the dynamic side, " ++ "alive"),
            },
            .{
                .kind = "bridge",
                .body = "Once loaded, the binary executes. This is where the " ++ "machine itself starts to matter.",
            },
            .{
                .kind = "h2",
                .body = "2.7  Executing software and the machine",
            },
            .{
                .kind = "epigraph",
                .body = "Even though in the turing-complete world of " ++ ("computers every computation is theoretically " ++ ("possible with any turing-complete system, the " ++ ("efficiency and actual implementability depends on " ++ "the underlying computational model."))),
                .cite = "Mellstrand & Ståhl 2012, p. 58",
            },
            .{
                .kind = "text",
                .body = "The Asahi case is the original's paragraph applied " ++ ("directly. The 16K-page MMU on Apple Silicon is part of " ++ ("the underlying computational model, and JavaScriptCore's " ++ ("FreeList code path has a strict-`<` ASSERT that fires on " ++ ("16K pages where it would not on 4K. The developer's " ++ ("implementability assumption (`<` works the same " ++ ("everywhere) was wrong, and the workaround — " ++ ("BUILD_PROFILE=release, which makes the assertion " ++ ("compile out — is the same workaround the book is " ++ ("describing. The machine constrains; the developer trades " ++ "off; the build script remembers the trade-off."))))))))),
            },
            .{
                .kind = "text",
                .body = "There is a sister case in Part II. The self-hosted Zig " ++ ("fork has known miscompiles where the AArch64 instruction " ++ ("encoding diverges from the upstream LLVM path; tickets " ++ ("0001 (codegen stack overflow) and 0007 (statesnap " ++ ("vcontext miscompile) live there. The machine is the " ++ ("same; the model the compiler has of the machine is " ++ "different."))))),
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
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build_llvm/tools/link-afsrv-bun.sh",
                .note = "the BUILD_PROFILE=release rule, written down",
            },
            .{
                .kind = "bridge",
                .body = "Above the machine is the OS. That is the chapter's last " ++ "section, and it sets up Ch 3.",
            },
            .{
                .kind = "h2",
                .body = "2.8  OS and process",
            },
            .{
                .kind = "epigraph",
                .body = "When the operating system loads a program into " ++ ("memory as a new process, it constructs a virtual " ++ ("address space in which that process is supposed to " ++ "operate.")),
                .cite = "Mellstrand & Ståhl 2012, p. 65",
            },
            .{
                .kind = "text",
                .body = "Linux gives us process, fd, signal, virtual address " ++ ("space — the standard set. arcan adds two abstractions on " ++ ("top: the shmif segment (a per-client shared page), and " ++ ("the viz_bus event (a structured message bus the hem " ++ ("spreads agree on). Neither is an OS primitive; both are " ++ ("load-bearing for everything that follows. When Part III " ++ ("talks about a frameserver crash, it really means the " ++ ("shmif segment went away; when Part III talks about a " ++ ("missing event, it means the viz_bus did not see one " ++ "where it expected.")))))))),
            },
            .{
                .kind = "text",
                .body = "Part IV replaces the OS abstraction wholesale. Process " ++ ("becomes thread-control-block plus capability set; fd " ++ ("becomes endpoint capability; signal becomes IPC. The " ++ ("primitives are different and so the failure modes are " ++ ("different — that is the chapter's whole point. Part V " ++ ("is in the opposite position: it has a normal Linux OS " ++ ("on each end, but the wire between them is the new " ++ "abstraction, and the wire is the place faults sit.")))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/src/shmif/arcan_shmif.h",
                .note = "the segment as primitive",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
                .note = "the viz_bus as primitive (search for viz_bus " ++ "and payload key)",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| ps name=arcan",
                .note = "the OS view of arcan; one process",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| engine introspect",
                .note = "the arcan view of itself; many segments",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch3_principal_debugging",
            },
            .{
                .kind = "bridge",
                .body = "The chapter has walked the pipeline once. The next " ++ ("chapter is what to do when something on it has gone " ++ "wrong."),
            },
        },
        .cross_links = .{
            "00_foundations:ch1_introduction",
            "00_foundations:ch3_principal_debugging",
            "00_foundations:ch0_architecture",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 2,
            },
        },
        .tickets = .{
            "0001-sh-codegen-stack-overflow",
            "0007-statesnap-vcontext-stack-miscompile",
            "0036-afsrv-bun-frameserver",
            "0100-refactor-posix-libc",
        },
    };
}
