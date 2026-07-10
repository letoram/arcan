
pub fn __init() void {
    return .{
        .title = "How to read this appl",
        .subtitle = "Front matter",
        .part_id = 1,
        .chapter_id = 0,
        .body = .{
            .{
                .kind = "text",
                .body = "Short page. Three things to know: how to navigate, " ++ ("what the block kinds mean, and what to do when a verb " ++ "the appl wants does not exist yet."),
            },
            .{
                .kind = "h2",
                .body = "Keys",
            },
            .{
                .kind = "text",
                .body = "From the index page, press a digit (1–9) to " ++ ("open the entry with that number. RETURN opens the " ++ ("first entry. Inside a chapter or article: h returns to " ++ ("the index. n / RIGHT moves to the next entry. p / " ++ ("LEFT moves to the previous. j or DOWN scrolls down; k " ++ ("or UP scrolls up. SPACE or PAGEDOWN scrolls a screen; " ++ "PAGEUP scrolls a screen back. ESC quits the appl."))))),
            },
            .{
                .kind = "h2",
                .body = "Block kinds",
            },
            .{
                .kind = "text",
                .body = "Most of what you see is `text` (prose) and `h2`/`h3` " ++ ("(section headings). Pull-quotes from the original book " ++ ("are `epigraph`. External quotes (arcan-fe.com posts, " ++ "tickets) are `quote`. Each gets a citation line.")),
            },
            .{
                .kind = "text",
                .body = "Three special kinds carry numbered references in the " ++ ("left margin. `verbbox` is the visibility-rule artefact " ++ ("— a runnable hem chain prefixed with " ++ ("[N]▶. `fileref` points at a path you can " ++ ("open in hem, prefixed [fN]→. `articleref` " ++ ("and `ticketref` link to other entries in this appl or " ++ ("to bug tickets, prefixed [aN]/[tN]→. In v1, " ++ ("the user copies and pastes the chain; in v2 the digit " ++ "keys will spawn the corresponding cell directly."))))))),
            },
            .{
                .kind = "text",
                .body = "If a chapter renders with a red MISSING-VERBBOX ribbon " ++ ("across the top, the chapter has failed its own " ++ ("discipline — a chapter that names a tool " ++ ("owes the reader a verb to run, and the renderer lints " ++ "for it. Send the chapter back to its agent."))),
            },
            .{
                .kind = "h2",
                .body = "How verbboxes spawn cells (the v2 plan)",
            },
            .{
                .kind = "text",
                .body = "A verbbox’s `chain` is exactly the string " ++ ("the spawning code passes to CAT9_INIT_CMD. Today the " ++ ("user copies that string into a fresh hem cell; " ++ ("tomorrow the appl will spawn the cell automatically " ++ ("via the same afsrv_terminal-with-CAT9_INIT_CMD " ++ ("incantation hem_dev's run verb already uses. The " ++ ("block kind is the same; the substrate underneath it " ++ "is what changes.")))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| status",
                .note = "an example verbbox — paste this " ++ ("into a fresh hem cell to see the spread it " ++ "names"),
            },
            .{
                .kind = "h2",
                .body = "Filing a missing verb",
            },
            .{
                .kind = "text",
                .body = "Some chapters — especially Part IV (seL4) " ++ ("and Part V (a12) — contain verbboxes for " ++ ("verbs that do not exist yet. These are intentional. " ++ ("The verbbox itself is a ticket — the chapter " ++ ("is documenting what the verb would do, and the writing " ++ ("of the chapter is what surfaces the gap. The procedure " ++ ("is: open a fresh fossil ticket via " ++ ("`tools/auto-arch/draft_ticket.sh \"missing:hem:<verb>\" " ++ ("sysdebug` (or `fossil ticket add ...` directly), with " ++ ("the chapter section as the motivating text. Then " ++ ("implement the " ++ ("verb under data/lash_builtins/hem_dev/<verb>.lua, " ++ ("using compile.lua as the template, and run zig build " ++ "install. The chapter does not change.")))))))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/data/lash_builtins/hem_dev/compile.lua",
                .note = "the canonical verb template",
            },
            .{
                .kind = "h2",
                .body = "If something looks wrong",
            },
            .{
                .kind = "text",
                .body = "If a citation does not match the page in the original, " ++ ("that is a bug in the chapter and worth filing. If a " ++ ("verbbox’s chain does not parse when you " ++ ("paste it into hem, that is a bug in the chapter (or " ++ ("in the verb it cites). If a chapter’s prose " ++ ("reads like a textbook — padded, generic, " ++ ("second-person, exclamatory — it has " ++ "violated STYLE.md, and that is also a bug.")))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/appl/sysdebug/STYLE.md",
                .note = "the voice rules the chapters are linted against",
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/data/appl/sysdebug/CONTRACT.md",
                .note = "the block-kind contract the renderer enforces",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:preface",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:glossary",
            },
        },
        .cross_links = .{
            "00_foundations:preface",
            "00_foundations:glossary",
            "00_foundations:ch0_architecture",
        },
        .bus_publish = .{
            .sensor = "sysdebug.read",
            .payload = .{
                .part = 1,
                .chapter = -1,
            },
        },
    };
}
