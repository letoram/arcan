
pub fn __init() void {
    return .{
        .title = "References",
        .subtitle = "Back matter",
        .part_id = 1,
        .chapter_id = 99,
        .body = .{
            .{
                .kind = "text",
                .body = "Five sources, one of them is this codebase itself.",
            },
            .{
                .kind = "h2",
                .body = "Primary text",
            },
            .{
                .kind = "text",
                .body = "Per Mellstrand and Björn Ståhl. " ++ ("*Systemic Software Debugging.* 2012. CC-BY 3.0. " ++ ("Available as a PDF at the root of this repo " ++ ("(systemic-software-debugging.pdf). The four chapters " ++ ("Part I mirrors are the four chapters of this work; " ++ ("every `epigraph` block in this appl cites a page " ++ "number from this PDF."))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/systemic-software-debugging.pdf",
                .note = "the canonical text",
            },
            .{
                .kind = "h2",
                .body = "arcan-fe.com posts",
            },
            .{
                .kind = "text",
                .body = "Björn Ståhl, https://arcan-fe.com/. " ++ ("The voice samples and several of the worked examples " ++ "come from these posts. Specifically:"),
            },
            .{
                .kind = "text",
                .body = "*A Spreadsheet and a Debugger walk into a Shell* " ++ ("(2024-09-16) — the gdb-and-spreadsheet " ++ "argument that anchors Ch 4 §4.5."),
            },
            .{
                .kind = "text",
                .body = "*A12 — Advancing Network Transparency on " ++ ("the Desktop* (2020-10-28) — background " ++ "for Part V."),
            },
            .{
                .kind = "text",
                .body = "*Whipping up a new Shell – Lash#Hem* " ++ "(2022-10-15) — background for hem itself.",
            },
            .{
                .kind = "text",
                .body = "*I wrote a Lua programmable display-server…* " ++ ("(2016-05-27) — background for arcan as a " ++ "whole."),
            },
            .{
                .kind = "text",
                .body = "*Next Experiment, Senseye* (2015-02-08) — " ++ "background for the visualizer substrate.",
            },
            .{
                .kind = "text",
                .body = "*Weaving a Different Web* (2026-01-26) — " ++ ("the controller-and-directory story for a12 over " ++ "Tailscale."),
            },
            .{
                .kind = "h2",
                .body = "Tickets",
            },
            .{
                .kind = "text",
                .body = "Tickets live in fossil at .fossil (the bugs/ folder was " ++ ("deleted 2026-05-02 per ticket 0150). Cite by slug; open " ++ ("with `bugs show <slug>`. The tickets entry of this back " ++ "matter has the full chapter↦ticket map.")),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:tickets",
            },
            .{
                .kind = "h2",
                .body = "The codebase",
            },
            .{
                .kind = "text",
                .body = "/home/x/next/arcan, in the state it is in when you " ++ ("are reading. The chapter prose names files by absolute " ++ ("path; the renderer turns them into filerefs. CLAUDE.md " ++ ("at the root is the canonical agent operating manual; " ++ ("_helpers.lua under hem_dev is the canonical viz_bus " ++ "contract.")))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/CLAUDE.md",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua",
            },
            .{
                .kind = "h2",
                .body = "Senseye (external)",
            },
            .{
                .kind = "text",
                .body = "https://github.com/letoram/senseye — the " ++ ("external project the visualizer substrate borrows " ++ ("from. Lives under ~/next/senseye/, outside this repo. " ++ ("The senseye-applied-plan under docs/hem_visual_agent/ " ++ "is the integration roadmap."))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/docs/hem_visual_agent/senseye-applied-plan.md",
                .note = "the integration plan",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| find /home/x/next/arcan/docs",
                .note = "all the long-form planning docs in one spread",
            },
        },
        .cross_links = .{
            "00_foundations:tickets",
            "00_foundations:verbs",
            "00_foundations:xref",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = 99,
            },
        },
    };
}
