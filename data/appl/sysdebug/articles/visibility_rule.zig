
pub fn __init() void {
    return .{
        .title = "The visibility rule, why",
        .subtitle = "Article  ·  2026-05-01",
        .date = "2026-05-01",
        .part_id = 0,
        .chapter_id = 0,
        .body = .{
            .{
                .kind = "text",
                .body = "For a year and a half, by my honest count, this project has " ++ ("bounced between three answers to the same question: where " ++ "does Claude live in arcan?"),
            },
            .{
                .kind = "text",
                .body = "The question matters because the tool only helps when you " ++ ("can see what it is doing. A coding assistant that runs in " ++ ("a window you cannot watch is not an assistant; it is a " ++ ("vendor pitch. And yet most of the time, that is exactly " ++ "what you get."))),
            },
            .{
                .kind = "text",
                .body = "The first answer was the obvious one: run Claude on the " ++ ("public web at claude.ai, in a browser of its own, and have " ++ ("me copy and paste between it and a terminal. That was the " ++ ("v1 era. It worked in the sense that something happened. It " ++ ("did not work in any other sense. I ended every session " ++ ("with twelve open browser tabs and no idea what had been " ++ ("changed, what had been read, or which file was next to be " ++ "edited.")))))),
            },
            .{
                .kind = "text",
                .body = "The second answer was Claude Code in afsrv_terminal — the " ++ ("v2 era, which is what you are reading this in. This is " ++ ("much better. The CLI is in a tile; I can see its log. I " ++ ("can scroll back. I can swap workspaces and the conversation " ++ "persists. It is a real assistant."))),
            },
            .{
                .kind = "text",
                .body = "But there is a hole in this story. The harness primitives — " ++ ("Read, Edit, Bash, Grep, Glob — execute inside the Claude " ++ ("Code process. I do not see them. The tile shows me what " ++ ("the assistant says about what it did, not what it actually " ++ ("did. When the assistant writes 'Reading X', that text is " ++ ("the only evidence I get; the file system call itself is " ++ ("invisible. Worse, when the assistant writes 'Reading X' " ++ ("and then describes the contents, the description IS the " ++ ("only evidence. There is no second copy. If the description " ++ ("is wrong — paraphrased, hallucinated, half-remembered from " ++ "a paste two turns ago — I have no way to notice."))))))))),
            },
            .{
                .kind = "text",
                .body = "The fix is not to teach the assistant to be more careful. " ++ ("The assistant is a probabilistic model. The fix is to push " ++ ("the read OUT of the harness and INTO a window. If the " ++ ("assistant calls hem's read verb instead of the harness " ++ ("Read, the file appears as a job cell. I see the cell. I " ++ ("see the actual file. I can scroll it. I can compare it to " ++ ("what the assistant says. Now the assistant's description " ++ "is checkable.")))))),
            },
            .{
                .kind = "text",
                .body = "This is the visibility rule. It is the load-bearing " ++ "principle of how this codebase wants to be worked in.",
            },
            .{
                .kind = "h3",
                .body = "Tangent — the in-terminal claude bridge that came before",
            },
            .{
                .kind = "text",
                .body = "There was a previous attempt to solve this, recorded in " ++ ("retired ticket 0033 (claude-code-shmif-bridge in " ++ ("afsrv_terminal). The idea was to instrument the running " ++ ("Claude Code CLI from outside, intercept its tool calls, and " ++ ("mirror them to the hem cell that hosted it. Half-shim, " ++ ("half-trap. It worked, kind of, for the simple primitives. " ++ ("It did not work for the ones that mattered. The bridge was " ++ "never going to scale to the full surface of the harness.")))))),
            },
            .{
                .kind = "text",
                .body = "The lesson from that attempt was: do not try to peek into " ++ ("the assistant's process. Convince the assistant to use " ++ ("verbs that are already visible, and the visibility takes " ++ "care of itself. That is what the rule encodes.")),
            },
            .{
                .kind = "ticketref",
                .id = "0033-claude-code-shmif-bridge-in-afsrv-terminal",
                .note = "the retired predecessor; read the post-mortem",
            },
            .{
                .kind = "h3",
                .body = "What the rule actually says",
            },
            .{
                .kind = "text",
                .body = "Ticket 0036-visibility-rule is two paragraphs. The first " ++ ("says: every Read, every Edit, every Find, every Grep that " ++ ("the assistant does should route through hem verbs that " ++ ("render to user-visible cells. The second says: the harness " ++ ("primitives still work, but they are emergency-only — for " ++ ("when hem lacks the verb, in which case the assistant " ++ ("files a missing-verb ticket so the visibility surface " ++ "grows.")))))),
            },
            .{
                .kind = "text",
                .body = "That is it. There is no enforcement layer. There is no " ++ ("syscall sandbox. There is a written rule and an assistant " ++ "that has been asked to follow it."),
            },
            .{
                .kind = "text",
                .body = "This works better than it has any right to. It works " ++ ("because the assistant has been told why; because every " ++ ("CLAUDE.md it loads carries the rule; because every hem " ++ ("verb's existence is itself a nudge toward using that verb " ++ ("instead of the equivalent harness one. It works because " ++ ("the visibility surface is now wide — fifty hem_dev verbs " ++ "and counting — and the assistant rarely has to fall back."))))),
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
                .note = "the rule itself; two paragraphs",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0036-visibility-rule",
                .note = "read it now",
            },
            .{
                .kind = "h3",
                .body = "Where it is honored, where it is not",
            },
            .{
                .kind = "text",
                .body = "The rule is honored well for files (read / edit / write), " ++ ("for searches (find / grep / glob), for builds (zigbuild / " ++ ("compile), for tickets (bugs show), for diffs (fossil " ++ ("diff), for crash inspection (cores). It is honored " ++ ("partially for process inspection (procfs covers about a " ++ ("third of what ps -elf would show). It is not honored at " ++ ("all for HTTP requests, for arbitrary network calls, for " ++ "mkdir, for rm — because no hem verb covers those yet.")))))),
            },
            .{
                .kind = "text",
                .body = "Each gap is itself a ticket waiting to be filed. Most of " ++ ("0118 (epic — host shell debug toolkit to hem-native " ++ "primitives) is exactly the sweep that closes them."),
            },
            .{
                .kind = "ticketref",
                .id = "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
                .note = "the sweep that closes the remaining gaps",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
                .note = "read the sweep plan",
            },
            .{
                .kind = "h3",
                .body = "Tangent — Phase 3i.5 and the parent control channel",
            },
            .{
                .kind = "text",
                .body = "There is also a quieter version of the rule, inside the " ++ ("hem stack itself: when a child cell wants to send " ++ ("structured directives back to its parent cell, it does so " ++ ("through a SOH-prefixed line on stdout (the " ++ ("hemParent.send mechanism in 0036 Phase 3i.5). The " ++ ("receiving parent's data_handler is supposed to parse those " ++ "lines and dispatch them."))))),
            },
            .{
                .kind = "text",
                .body = "The receiving handler does not currently dispatch. The " ++ ("directives are emitted; the parent ignores them. This is " ++ ("filed; it is not fixed. But the model is right: visibility " ++ ("means the protocol is a stream the user can also see, not " ++ ("a private socket. Even when the channel breaks, you can " ++ ("grep stdout and find the SOH-prefixed line and know what " ++ "was sent. The rule survives the failure."))))),
            },
            .{
                .kind = "fileref",
                .path = "/home/x/next/arcan/build_llvm/examples/bun-drives-parent.ts",
                .note = "the demo of the SOH-prefix protocol; known-broken end-to-end",
            },
            .{
                .kind = "h3",
                .body = "Why this had to be an appl",
            },
            .{
                .kind = "text",
                .body = "A document about the visibility rule could be a PDF. It " ++ ("would be honest about the rule and dishonest about itself " ++ ("— a static slab in a viewer where every paragraph claiming " ++ ("'you can see this verb' is unaccompanied by an actual verb " ++ "you can run."))),
            },
            .{
                .kind = "text",
                .body = "So this is an appl. The fileref a few paragraphs up is a " ++ ("real link; press its number key and you open ticket " ++ ("0036-visibility-rule in a sibling hem cell. The verbboxes " ++ ("throughout the chapters are real verbs; they spawn hem " ++ ("cells with the chain pre-loaded. The rule applies to " ++ "itself. Anything less would be embarrassing.")))),
            },
            .{ .kind = "rule" },
            .{
                .kind = "h3",
                .body = "who am i  ·  what is this  ·  where am i",
            },
            .{
                .kind = "text",
                .body = "who am i — an assistant that is, today, writing about " ++ "itself. That is fine; this is an honest book.",
            },
            .{
                .kind = "text",
                .body = "what is this — sysdebug — a canonical companion to " ++ ("Mellstrand & Ståhl's Systemic Software Debugging " ++ ("(2012, CC-BY 3.0), applied to the arcan / hem / zig " ++ ("stack. The bones are at /home/x/next/arcan/data/appl/" ++ "sysdebug/."))),
            },
            .{
                .kind = "text",
                .body = "where am i — in a workspace tile, hopefully. If not — if " ++ ("you are reading this in your terminal scrollback — the " ++ ("appl is not running. Try the launch command in the " ++ "appl's README, or ask the assistant to spawn it.")),
            },
        },
        .cross_links = .{ "00_foundations:ch0_architecture" },
        .tickets = .{
            "0036-visibility-rule",
            "0036-afsrv-bun-frameserver",
            "0033-claude-code-shmif-bridge-in-afsrv-terminal",
            "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
        },
    };
}
