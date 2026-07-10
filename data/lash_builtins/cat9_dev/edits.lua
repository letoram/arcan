-- edits
--
-- Open the **edited-files spreadsheet**: rows are files modified by
-- write/edit/disasm/etc. since the kid started, with columns
-- [file, action, last_op_at]. Sourced from cat9.dev_helpers.edits
-- (which the other builtins populate via H.register_edit).
--
-- This is a snapshot, not a live view — reopen the cell to refresh.
-- (Live update would need to keep the spreadsheet handle around and
-- patch rows from the registering builtins.)
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers
H.edits = H.edits or {}

builtins.hint.edits = "Show files touched by write/edit (snapshot, spreadsheet)"

function builtins.edits(...)
    -- Snapshot the registry into rows
    local rows = {}
    for path, ent in pairs(H.edits) do
        table.insert(rows, {ent.path, ent.action, ent.last_op_at or "—"})
    end

    -- Sort by most recent first if last_op_ts is available
    table.sort(rows, function(a, b)
        local ea = H.edits[a[1]]
        local eb = H.edits[b[1]]
        return (ea and ea.last_op_ts or 0) > (eb and eb.last_op_ts or 0)
    end)

    if #rows == 0 then
        -- Still create the spreadsheet so the agent gets a visible
        -- "no edits yet" cell rather than a silent no-op.
        H.make_spread("edits (none)", {"file", "action", "last_op"}, {{
            "(no edits yet — use write/edit to populate)", "", ""
        }})
        return
    end

    H.make_spread(
        string.format("edits (%d)", #rows),
        {"file", "action", "last_op"},
        rows
    )
end

end
