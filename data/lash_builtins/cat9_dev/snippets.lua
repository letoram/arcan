-- snippets [bug_id]
--
-- Persistent "bug snippets" spread. One row per code snippet from
-- the active bug. Subscribes to viz_bus payload.bug_id to refresh.
-- Click row → publishes (file, line) so other views (errors,
-- compile.units, disasm) drill to the snippet's location.
--
-- Snippet source: fossil ticket comment field (the migration of
-- 2026-05-02 / ticket 0150 stored each .md body verbatim under
-- comment, so the YAML frontmatter is still parseable from there).
-- The bugs/ folder no longer exists.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.snippets = "snippets [bug_id] — code snippets for active bug"

-- Repo root for fossil queries. lash's cwd can be anywhere; the
-- fossil checkout lives at the arcan repo root.
local arcan_repo = "/home/x/next/arcan"

local snippets_spread = nil
local snippets_current_bug = nil
local snippets_count = 0
local row_to_snippet = {}    -- spread row → {bug_id, idx, file, line}

local function ensure_snippets_spread()
    if snippets_spread and snippets_spread.id then return snippets_spread end
    snippets_spread = H.make_spread(
        "bug snippets",
        {"bug", "file", "range", "fn", "label"},
        {}
    )
    return snippets_spread
end

-- Repo handle → binary path (for DWARF lookup of enclosing fn).
-- The cat9 lashlibrary doesn't have a generic resolver yet, so this
-- is a small explicit table. Add new repos as they appear in fossil
-- ticket snippet metadata (`code_snippets` column or per-snippet
-- `repo:` YAML key in the ticket comment field).
local repo_to_bin = {
    ["zig-fork"] = "/home/x/.local/src/zig-0.15.2-fork/zig-out/bin/zig",
    ["arcan"]    = "/home/x/next/arcan/zig-out/bin/arcan",
}

-- Resolve the enclosing fn for a snippet (file:line) via
-- tools/auto-arch/snippet_fn.sh.  Returns "" if the helper isn't
-- available, the cache is cold, or the resolver has no answer.
local SNIPPET_FN_SH = "/home/x/next/arcan/tools/auto-arch/snippet_fn.sh"
local SNIPPET_FN_TIMEOUT = 6   -- seconds; first call may be cold
local fn_cache = {}            -- in-memory: bin|file|line → fn

local function resolve_fn(repo, file, line)
    if not (repo and file and line) then return "" end
    local bin = repo_to_bin[repo]
    if not bin then return "" end
    local base = string.match(file, "([^/]+)$") or file
    local key = bin .. "|" .. base .. "|" .. tostring(line)
    if fn_cache[key] then return fn_cache[key] end
    local cmd = string.format(
        "timeout %d %s %q %q %s 2>/dev/null",
        SNIPPET_FN_TIMEOUT, SNIPPET_FN_SH, bin, base, tostring(line))
    local p = io.popen(cmd, "r")
    if not p then return "" end
    local fn = p:read("*l") or ""
    p:close()
    fn_cache[key] = fn
    return fn
end

local function spread_clear(spread)
    if not (spread and spread.cells) then return end
    for r = #spread.cells, 2, -1 do spread.cells[r] = nil end
end

-- Fetch the comment field from fossil for a given bug id (numeric,
-- padded, or slug). Returns the comment as a single string, or nil.
-- The comment is the migrated .md body so it still has the YAML
-- frontmatter that parse_snippets walks.
local function fetch_bug_comment(bug_id)
    if not bug_id then return nil end
    local id_str = tostring(bug_id):gsub("^#", "")
    local num = tonumber(id_str, 10)
    local padded = num and string.format("%04d", num) or id_str
    -- escape single quotes for SQL
    local function esc(s) return tostring(s):gsub("'", "''") end
    -- Try bug_id (padded then raw) then bug_slug then "starts with id-"
    local sql = string.format(
        "SELECT comment FROM ticket WHERE bug_id IN ('%s','%s') OR bug_slug = '%s' OR bug_slug GLOB '%s-*' LIMIT 1",
        esc(padded), esc(id_str), esc(id_str), esc(padded))
    local cmd = string.format("cd %q && fossil sql %q 2>/dev/null", arcan_repo, sql)
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    -- fossil sql wraps text in single quotes. Strip the wrapper, undo \\ → \.
    if not out or out == "" then return nil end
    out = out:gsub("^'", ""):gsub("'\n*$", "")
    -- Fossil's text encoder emits \n as a literal backslash-n;
    -- convert back to newlines so frontmatter parsing works.
    out = out:gsub("\\n", "\n"):gsub("\\\\", "\\")
    return out
end

-- Parse YAML front matter snippets list from the fossil comment text.
-- Looks for:
--   snippets:
--     - repo: ...
--       file: <path>
--       lines: "<range>"
--       note: <label>
-- and returns an array of {file, range, lines, note}.
local function parse_snippets_text(text)
    if not text then return {} end
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    local in_yaml = false
    local in_snippets = false
    local cur = nil
    local out = {}
    for _, line in ipairs(lines) do
        if line == "---" then
            if not in_yaml then
                in_yaml = true
            else
                break  -- end of front matter
            end
        elseif in_yaml then
            if string.match(line, "^snippets:") then
                in_snippets = true
            elseif in_snippets then
                if string.match(line, "^[a-zA-Z]") then
                    -- New top-level YAML key → snippets ended.
                    in_snippets = false
                    if cur then table.insert(out, cur); cur = nil end
                elseif string.match(line, "^%s+- ") then
                    if cur then table.insert(out, cur) end
                    cur = {}
                    -- The "- repo: foo" form puts the first field on the
                    -- same line as the dash.
                    local k, v = string.match(line, "^%s+- ([%w_]+):%s*(.+)$")
                    if k and v then cur[k] = v:gsub('^"(.*)"$', "%1") end
                elseif cur then
                    local k, v = string.match(line, "^%s+([%w_]+):%s*(.+)$")
                    if k and v then cur[k] = v:gsub('^"(.*)"$', "%1") end
                end
            end
        end
    end
    if cur then table.insert(out, cur) end
    return out
end

-- Pull the first numeric line from a "5143-5150" or "42" range.
local function first_line_of(range)
    if not range then return nil end
    local s = tostring(range)
    local n = tonumber(s)
    if n then return n end
    local lo = string.match(s, "^(%d+)")
    return lo and tonumber(lo) or nil
end

local function load_bug(bug_id)
    if not bug_id then return end
    local comment = fetch_bug_comment(bug_id)
    if not comment then
        H.emit_result(string.format("snippets:err:no_bug=%s", tostring(bug_id)))
        return
    end
    local snips = parse_snippets_text(comment)
    local spread = ensure_snippets_spread()
    if not spread then return end
    spread_clear(spread)
    row_to_snippet = {}
    snippets_count = 0
    snippets_current_bug = bug_id
    spread.short = "snippets " .. tostring(bug_id)

    for i, s in ipairs(snips) do
        snippets_count = snippets_count + 1
        local row = snippets_count + 1
        local first_ln = first_line_of(s.lines)
        local fn = ""
        if first_ln then
            fn = resolve_fn(s.repo, s.file, first_ln) or ""
        end
        -- Compress noisy zig-mangled prefix for display:
        --   codegen.aarch64.Select.Value.Index.setSignedness → setSignedness
        local fn_display = fn
        if #fn_display > 40 then
            fn_display = string.match(fn_display, "([^.]+)$") or fn_display
        end
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %s", spread.id, row, H.escape_cell(tostring(bug_id))))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 2 %s", spread.id, row, H.escape_cell(s.file or "")))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 3 %s", spread.id, row, H.escape_cell(s.lines or "")))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 4 %s", spread.id, row, H.escape_cell(fn_display)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 5 %s", spread.id, row, H.escape_cell(s.note or s.label or "")))
        row_to_snippet[row] = {
            bug_id = bug_id,
            idx = i,
            file = s.file,
            line = first_line_of(s.lines),
        }
    end
    H.emit_result(string.format("snippets:loaded:bug=%s:count=%d",
        tostring(bug_id), snippets_count))
    -- Broadcast: other views (bugs spread, units highlight, hilbert
    -- flash) re-render based on the active bug. Self-subscribe is
    -- guarded above (current_bug check), so we don't loop.
    H.viz_bus.publish("snippets", tostring(bug_id), 0, {
        bug_id = bug_id,
    })
end

-- Cursor poller: when the user clicks a snippet row, publish so
-- errors / units / disasm jump to the snippet's location.
local cursor_state = {row = 0, col = 0}
local function poll_snippets_cursor()
    if not (snippets_spread and snippets_spread.id and snippets_spread.cell_cursor) then
        return true
    end
    local cc = snippets_spread.cell_cursor
    local row, col = cc[2] or 0, cc[1] or 0
    if row ~= cursor_state.row or col ~= cursor_state.col then
        cursor_state.row, cursor_state.col = row, col
        local snip = row_to_snippet[row]
        if snip then
            local key = string.format("%s:%d", tostring(snip.bug_id), snip.idx)
            H.viz_bus.publish("snippets", key, row, {
                bug_id = snip.bug_id,
                snippet_id = key,
                file = snip.file,
                line = snip.line,
            })
        end
    end
    return true
end

local poll_installed = false
local function install_poller()
    if poll_installed then return end
    poll_installed = true
    if cat9.timers then table.insert(cat9.timers, poll_snippets_cursor) end
end

-- Subscribe to bus: any publish carrying payload.bug_id triggers a
-- reload (unless we're already showing that bug).
if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(_sensor, _key, _row, payload)
        if not (payload and payload.bug_id) then return end
        if payload.bug_id == snippets_current_bug then return end
        if not snippets_spread then return end  -- defer until user opens it
        load_bug(payload.bug_id)
    end)
end

function builtins.snippets(...)
    local args = {...}
    local bug_id = nil
    for _, v in ipairs(args) do
        if type(v) == "string" then bug_id = v; break end
    end
    ensure_snippets_spread()
    install_poller()
    if bug_id then
        load_bug(bug_id)
    elseif snippets_current_bug then
        load_bug(snippets_current_bug)
    else
        H.emit_result("snippets:opened:empty")
    end
end

function suggest.snippets(args, raw)
    -- Future: autocomplete bug ids via `fossil sql "SELECT bug_id, bug_slug FROM ticket"`.
end

end
