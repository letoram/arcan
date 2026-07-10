
pub fn __init() void {
    return .{
        .title = "Preface",
        .subtitle = "Front matter",
        .part_id = 1,
        .chapter_id = 0,
        .body = .{
            .{
                .kind = "epigraph",
                .body = "We dedicate this work to all ambitious requirement " ++ ("specification engineers and system architects who " ++ ("manage to keep up the good faith despite the fact " ++ ("that software produced with their work as input " ++ ("never ever functions as specified, intended or " ++ "expected.")))),
                .cite = "Mellstrand & Ståhl 2012, dedication",
            },
            .{
                .kind = "text",
                .body = "The book this appl is a companion to is Per Mellstrand " ++ ("and Björn Ståhl's *Systemic Software " ++ ("Debugging* (2012). It is at the repo root as a PDF, and " ++ ("it is licensed CC-BY 3.0, which is the legal reason " ++ ("this appl can quote it as freely as it does. Where the " ++ ("original speaks for itself we quote it; where the " ++ ("original is generic on purpose, we are specific on " ++ ("purpose; where the original could not have written a " ++ ("section because the substrate did not yet exist, we " ++ "have added one (see Ch 4 §4.5).")))))))),
            },
            .{
                .kind = "text",
                .body = "Why an appl rather than another PDF: the original " ++ ("describes verbs the analyst should run. A PDF can only " ++ ("describe them. An appl can also run them. Every " ++ ("section in this book that names a tool is followed by " ++ ("a verbbox — a one-line hem chain that, when you click " ++ ("it (or copy and paste it, in v1), spawns a sibling " ++ ("cell that does the thing the section just talked about. " ++ ("If you cannot make a thing visible, you cannot claim " ++ "to understand it; the appl form is what enforces this."))))))),
            },
            .{
                .kind = "text",
                .body = "Who this is for: one person, building this stack. The " ++ ("voice is direct, dry, and occasionally self-deprecating " ++ ("(the source samples for that voice are Ståhl's " ++ ("posts on arcan-fe.com, and the book itself, by the " ++ ("same author). It is not a generic textbook; it is a " ++ ("workshop manual for a specific workshop. If a stranger " ++ ("wandered in and could not tell whether a paragraph was " ++ ("written by us or by the book — except by " ++ "topic — the voice was kept."))))))),
            },
            .{
                .kind = "text",
                .body = "How to read it: Front matter (preface, glossary, " ++ ("howto) is short and to be skimmed. Part I (Foundations: " ++ ("five chapters, including a Ch 0 Architecture map " ++ ("specific to this codebase) is what you read first. " ++ ("Parts II through V each take one of the four live " ++ ("sub-projects (the self-hosted Zig fork, the zig " ++ ("migration of arcan, the seL4 bootstrap, a12 over " ++ ("Tailscale) and walk it through the methodology. Each " ++ ("of those parts is owned by a separate writing agent; " ++ "the coordinator owns Part I.")))))))),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| read /home/x/next/arcan/CLAUDE.md",
                .note = "the project's own rules; cited many times",
            },
            .{
                .kind = "bridge",
                .body = "An appl is an honest book. A PDF could only describe " ++ "these verbs; here you can run them.",
            },
            .{ .kind = "rule" },
            .{
                .kind = "text",
                .body = "Attribution: epigraph and pull-quote material from " ++ ("*Systemic Software Debugging* (Mellstrand & Ståhl, " ++ ("2012, CC-BY 3.0). Block quotes from arcan-fe.com posts " ++ ("are cited inline. Tickets cited by their slug; live in " ++ ("the fossil DB at .fossil — open via `bugs show <slug>` " ++ "from any hem cell.")))),
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:glossary",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:howto",
            },
            .{
                .kind = "crosslink",
                .target = "00_foundations:ch0_architecture",
            },
        },
        .cross_links = .{
            "00_foundations:glossary",
            "00_foundations:howto",
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
