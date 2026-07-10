
pub fn __init() void {
    return .{
        .title = "Software Demystified",
        .subtitle = "Part II · Ch 2 · The Self-Hosted Zig Fork",
        .part_id = 2,
        .chapter_id = 2,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "The key principle for a toolchain is that a series " ++ ("of tools is to be applied where the output from one " ++ "tool is the input to the next."),
                .cite = "Mellstrand & Ståhl 2012, p. 43",
            },
            .{
                .kind = "text",
                .body = "The original walks the canonical compile-link-load pipeline " ++ ("for a C program on linux. We walk the same pipeline for a " ++ ("compiler that compiles itself, and the difference is that " ++ ("the output of stage N is the input to stage N+1 in a " ++ ("literal sense — the binary IS the next step's tool. Eight " ++ ("stages, each one with a place where its assumptions can " ++ "drift from the previous."))))),
            },
            .{
                .kind = "h2",
                .body = "2.1  Source",
            },
            .{
                .kind = "text",
                .body = "The fork's source tree mirrors upstream zig with a small " ++ ("set of patches concentrated in src/codegen/aarch64 and " ++ ("src/Sema. The patches are not fork-specific features; they " ++ ("are upstream patches the maintainers haven't merged yet, " ++ ("back-ported and held here so the selfhost loop can run " ++ ("ahead of upstream. The diff against upstream is small " ++ ("enough to read in one sitting and is the first thing to " ++ "look at when a regression appears.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/build_llvm/vendor/sh-zig/src",
                .note = "the fork's tree; diff against upstream lives in fossil",
            },
            .{
                .kind = "h2",
                .body = "2.2  Tokens and AST",
            },
            .{
                .kind = "text",
                .body = "Tokenisation and AST construction match upstream byte for " ++ ("byte. There has never been a fork-introduced bug at this " ++ ("stage. Mentioned only so the next sections' first " ++ ("divergence has a clear baseline. If a sh-zig binary " ++ ("produces a different AST for the same input than an " ++ ("LLVM-zig binary, something is corrupt at the binary level " ++ ("before the stage even starts; investigate stage-1 " ++ "integrity first, not the parser.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/build_llvm/vendor/sh-zig/zig name=Ast",
                .note = "AST symbols in the stage-1 binary",
            },
            .{
                .kind = "h2",
                .body = "2.3  AIR",
            },
            .{
                .kind = "text",
                .body = "Analyzed Intermediate Representation. This is the first " ++ ("stage where divergences between sh-zig and LLVM-zig output " ++ ("actually appear, and they are usually intentional — Sema " ++ ("patches that propagate signedness or alignment information " ++ ("the upstream Sema discards. AIR is also where the " ++ ("auto-arch loop's instrumentation lives; round telemetry " ++ "is emitted from the AIR-walker entry points."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0002-sh-setSignedness-small-size-assert",
                .note = "the canonical Sema patch motivator",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep AIR /home/x/next/arcan/build_llvm/vendor/sh-zig/src",
                .note = "the AIR-walker entry points",
            },
            .{
                .kind = "h2",
                .body = "2.4  MIR",
            },
            .{
                .kind = "text",
                .body = "Machine Intermediate Representation. The codegen wedge: " ++ ("this is where AIR becomes target-specific and where most " ++ ("of the fork's bugs live. The aarch64 backend is the one " ++ ("we care about — Asahi is the development host — and the " ++ ("x86_64 backend is the comparison case. When a regression " ++ ("appears on aarch64 and not on x86_64, the diff between " ++ ("the two backends' MIR for the offending function is the " ++ "first thing to read.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "0001-sh-codegen-stack-overflow",
                .note = "MIR varargs prologue, missing spill area",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| grep aarch64 /home/x/next/arcan/build_llvm/vendor/sh-zig/src/codegen",
                .note = "the aarch64 codegen tree",
            },
            .{
                .kind = "h2",
                .body = "2.5  Object",
            },
            .{
                .kind = "text",
                .body = "ELF emission. Where intcast-truncate (0003) lives — the " ++ ("fork's elf-writer assumes the bit-width of an immediate " ++ ("is the type-system bit-width, but the AIR-to-MIR lowering " ++ ("may have widened the immediate without updating the " ++ ("metadata, so the wrong relocation flavour ends up in the " ++ ("object. Visible at link time as 'truncated to fit', or " ++ ("at runtime as silently wrong arithmetic. The disasm " ++ "spread is the workhorse here.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "0003-arcan-fsrv-pushevent-intcast-truncate",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a",
                .note = "object code from a stage-3 build, source-cross-referenced",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan name=pushevent",
                .note = "symbol locations for the pushevent family",
            },
            .{
                .kind = "h2",
                .body = "2.6  Linker",
            },
            .{
                .kind = "text",
                .body = "sh-zig's own linker (zld for aarch64, lld-stripped for " ++ ("x86_64) handles the link step. The alignment story " ++ ("(0008) is here: the linker honours the alignment of the " ++ ("input sections but not the alignment of the data inside " ++ ("them, so a struct field that the codegen happened to " ++ ("place at offset 0xc in its own object ends up at " ++ ("offset 0xc within the linked output too — and that is " ++ ("off-by-4 from the 16-byte alignment Lua wants. Same " ++ ("object, x86_64 build: the field happens to land at 0x10. " ++ "The bug is the linker; the symptom is in lua_close.")))))))),
            },
            .{
                .kind = "ticketref",
                .id = "0008-lua-close-alignment-panic",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/arcan",
                .note = "the linked binary, alignment visible at offset",
            },
            .{
                .kind = "h2",
                .body = "2.7  Loaded binary",
            },
            .{
                .kind = "text",
                .body = "Stage-2 sh-zig — the binary that compiles arcan. Loading " ++ ("it is what an `selfhost` round does. The selfhost binary " ++ ("is the recursive case the original §2.6 calls out: a " ++ ("static-by-design executable whose only IO is reading " ++ ("source and writing object files. Its assumptions are " ++ ("frozen at the moment stage-1 emitted it; you cannot patch " ++ "stage-2 except by re-running stage-1 with new source."))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| procfs $(pidof zig) maps",
                .note = "the loaded layout while a stage-2 build runs",
            },
            .{
                .kind = "h2",
                .body = "2.8  Comparison",
            },
            .{
                .kind = "text",
                .body = "The dev-loop06 spread puts the LLVM-zig and sh-zig " ++ ("disasm streams of the same arcan function side by side. " ++ ("Three columns: source, LLVM-zig output, sh-zig output. " ++ ("Differences highlight; the spread tracks them by " ++ ("function, builds a diff bucket per function, and a " ++ ("regression-by-round timeline. The spread is how a " ++ ("miscompile gets pinned to a specific MIR change in " ++ "fewer than five clicks.")))))),
            },
            .{
                .kind = "ticketref",
                .id = "dev-loop06-disasm-llvm-vs-sh",
                .note = "the comparison spread",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show dev-loop06-disasm-llvm-vs-sh",
                .note = "open the spread description",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/arcan",
                .note = "open one half; the other half is the LLVM build's bin",
            },
            .{
                .kind = "h2",
                .body = "Closing",
            },
            .{
                .kind = "text",
                .body = "Eight stages; one feedback loop. Ch 3 walks the four " ++ ("principal-debugging actions over this same pipeline and " ++ "shows what each one looks like with hem cells under it."),
            },
            .{
                .kind = "crosslink",
                .target = "02_zig_fork:ch3_principal_debugging",
            },
        },
        .cross_links = .{
            "02_zig_fork:ch1_introduction",
            "02_zig_fork:ch3_principal_debugging",
            "00_foundations:ch2_software_demystified",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 2,
                .chapter = 2,
            },
        },
        .tickets = .{
            "0001-sh-codegen-stack-overflow",
            "0002-sh-setSignedness-small-size-assert",
            "0003-arcan-fsrv-pushevent-intcast-truncate",
            "0008-lua-close-alignment-panic",
            "dev-loop06-disasm-llvm-vs-sh",
        },
    };
}
