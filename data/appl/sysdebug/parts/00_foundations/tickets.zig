
pub fn __init() void {
    return .{
        .title = "Tickets",
        .subtitle = "Back matter",
        .part_id = 1,
        .chapter_id = 99,
        .body = .{
            .{
                .kind = "text",
                .body = "Every ticket the chapters cite, in one place, with a " ++ ("one-line note about why it matters here. The tickets " ++ ("themselves live in fossil at .fossil — the legacy bugs/ " ++ ("folder was deleted 2026-05-02 per ticket 0150. Their " ++ ("state in fossil is authoritative; this page is a " ++ "curated index.")))),
            },
            .{
                .kind = "h2",
                .body = "Anchoring tickets (read these first)",
            },
            .{
                .kind = "ticketref",
                .id = "0036-visibility-rule",
                .note = "the rule that motivated the appl form. " ++ "Required reading before any chapter.",
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
                .note = "the worked example of the visibility rule, " ++ ("with five phases of design history. Part III " ++ "anchor."),
            },
            .{
                .kind = "ticketref",
                .id = "0034-shmif-native-guide-for-external-agents",
                .note = "the model an external agent has of shmif. " ++ ("Useful when reasoning about how a TS module " ++ "or a remote a12 sink sees the system."),
            },
            .{
                .kind = "h2",
                .body = "Part II (sh-zig)",
            },
            .{
                .kind = "ticketref",
                .id = "0001-sh-codegen-stack-overflow",
                .note = "stage-1 miscompile that still bites",
            },
            .{
                .kind = "ticketref",
                .id = "0007-statesnap-vcontext-stack-miscompile",
                .note = "AArch64-specific codegen anomaly",
            },
            .{
                .kind = "ticketref",
                .id = "0102-refactor-extern-fn",
                .note = "extern fn surface refactor; ABI assumptions",
            },
            .{
                .kind = "h2",
                .body = "Part III (zig-arcan, afsrv_bun)",
            },
            .{
                .kind = "ticketref",
                .id = "0036-afsrv-bun-frameserver",
                .note = "(re-cited; see anchoring tickets)",
            },
            .{
                .kind = "ticketref",
                .id = "0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach",
                .note = "the gap between hem and gdb — " ++ "the §4.2 ticket",
            },
            .{
                .kind = "ticketref",
                .id = "0118-epic-host-shell-debug-toolkit-to-hem-native-primitives",
                .note = "the epic that scopes the hem_dev migration of " ++ "host-shell debug primitives",
            },
            .{
                .kind = "h2",
                .body = "Part III (posix_libc shim)",
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
                .note = "the gating ticket for self-hosted shmif/a12/" ++ "keystore",
            },
            .{
                .kind = "h2",
                .body = "Part IV (seL4-zig) — mostly drafts",
            },
            .{
                .kind = "text",
                .body = "Part IV is intentionally early. Most of its tickets " ++ ("are draft-d* notes rather than full bugs. Agent C " ++ ("owes the chapter a list of drafts to file; the " ++ ("verbboxes for verbs that do not yet exist (caps, " ++ ("cspace, boot-stage hilbert) are themselves the " ++ "tickets.")))),
            },
            .{
                .kind = "h2",
                .body = "Part V (a12 over Tailscale)",
            },
            .{
                .kind = "ticketref",
                .id = "0100-refactor-posix-libc",
                .note = "(re-cited; the zig-a12 unblocker)",
            },
            .{
                .kind = "text",
                .body = "Agent D owes a draft for a `.monitor` hem builtin " ++ ("wrapping arcan-net's monitor stream. File via " ++ ("`tools/auto-arch/draft_ticket.sh` (writes status=draft " ++ "to fossil) or `fossil ticket add` directly.")),
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs all",
                .note = "the full ticket inventory — ~103 in fossil",
            },
            .{
                .kind = "verbbox",
                .chain = "builtin dev ||| bugs show 0138-visibility-rule",
                .note = "open the anchor ticket",
            },
        },
        .cross_links = .{
            "00_foundations:refs",
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
