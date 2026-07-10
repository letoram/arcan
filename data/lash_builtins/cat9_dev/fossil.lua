-- fossil [verb] [args ...]
--
-- Pure-Lua fossil wrappers that produce **clickable spreadsheet cells**
-- instead of plain text dumps. All popen-with-argv (no /bin/sh).
-- Mirror of cat9_dev/git.lua, talking to the in-tree .fossil DB.
-- Filed as bug 0025; even more valuable post-bugs/-removal (ticket
-- 0150, 2026-05-02) since fossil is now the single ticket store.
--
-- Verbs:
--   fossil                      → `fossil status` spreadsheet
--                                  (state, path)
--   fossil log [N]              → `fossil timeline -t ci -n N` spreadsheet
--                                  (sha, subject); N defaults to 50
--   fossil diff [<paths>]       → `fossil diff` hunk spreadsheet (op, line)
--   fossil tickets [<filter>]   → `fossil sql` over the ticket table
--                                  (bug_id, status, severity, slug, title)
--   fossil ticket-show <id-or-slug> → render full ticket comment
--   fossil ticket-history <id>  → run_history blob for a ticket
--   fossil ticket-set <slug> <field> <value>
--                               → wraps `fossil ticket change <uuid>`
--                                  (e.g. fossil ticket-set foo status fixed)
--
-- Emits `test:dev_result:fossil:<verb>:<status>:…` on each invocation.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.fossil =
    "fossil {status|log|diff|tickets|ticket-show|ticket-history|ticket-set}"

local fossilbin = "/usr/bin/fossil"
local srcdir = "/home/x/next/arcan"

-- Mirror of git.lua's read_all (same nbio:read(true) gotcha).
local function read_all(io_handle, max_lines)
    if not io_handle then return {} end
    max_lines = max_lines or 5000
    local buf = {}
    while true do
        local data, alive = io_handle:read(true)
        if data and data ~= "" then table.insert(buf, data) end
        if not alive then break end
        if #buf >= max_lines then break end
    end
    local joined = table.concat(buf, "")
    local lines = {}
    for line in string.gmatch(joined, "([^\n]+)") do
        table.insert(lines, line)
        if #lines >= max_lines then break end
    end
    return lines
end

local function popen_lines(args, max_lines)
    -- fossil supports -R <repo> for explicit-checkout invocation,
    -- but most subcommands need cwd inside the checkout. Use
    -- --chdir which fossil documents as the cwd-override flag.
    local argv = {fossilbin, "fossil"}
    for _, a in ipairs(args) do table.insert(argv, a) end
    -- ensure we run in the repo
    local _, out, _, pid = root:popen(argv, "re", nil, srcdir)
    if not out then return nil, "popen failed" end
    local lines = read_all(out, max_lines)
    out:close()
    return lines, nil
end

-- ---------------------------------------------------------------- status
local function fossil_status()
    local lines, err = popen_lines({"changes", "--differ"})
    if not lines then
        cat9.add_message("fossil status: " .. tostring(err))
        H.emit_result("fossil:status:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        -- format: "STATE       path/to/file"
        local state, path = string.match(l, "^(%S+)%s+(.+)$")
        if state and path then
            table.insert(rows, {state, path})
        end
    end
    H.make_spread(
        string.format("fossil status (%d)", #rows),
        {"state", "path"},
        rows
    )
    H.emit_result(string.format("fossil:status:ok:rows=%d", #rows))
end

-- ------------------------------------------------------------------- log
local function fossil_log(n_arg)
    local n = tonumber(n_arg) or 50
    local lines, err = popen_lines({
        "timeline", "-t", "ci", "-n", tostring(n), "--format", "%H %c",
    })
    if not lines then
        cat9.add_message("fossil log: " .. tostring(err))
        H.emit_result("fossil:log:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local sha, subj = string.match(l, "^(%w+)%s+(.*)$")
        if sha and #sha >= 10 then
            -- short SHA + first line of message
            table.insert(rows, {sha:sub(1, 12), (subj or ""):sub(1, 200)})
        end
    end
    H.make_spread(
        string.format("fossil log (%d)", #rows),
        {"sha", "subject"},
        rows
    )
    H.emit_result(string.format("fossil:log:ok:rows=%d", #rows))
end

-- ------------------------------------------------------------------ diff
local function fossil_diff(...)
    local rest = {...}
    local args = {"diff"}
    for _, v in ipairs(rest) do
        if type(v) == "string" and string.sub(v, 1, 1) ~= "#" then
            table.insert(args, v)
        end
    end
    local lines, err = popen_lines(args, 20000)
    if not lines then
        cat9.add_message("fossil diff: " .. tostring(err))
        H.emit_result("fossil:diff:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local first = string.sub(l, 1, 1)
        local op
        if first == "+" then op = "+"
        elseif first == "-" then op = "-"
        elseif first == "@" then op = "@"
        elseif first == "I" or first == "=" then op = "h"
        else op = " "
        end
        table.insert(rows, {op, l})
    end
    H.make_spread(
        string.format("fossil diff (%d lines)", #rows),
        {"op", "line"},
        rows
    )
    H.emit_result(string.format("fossil:diff:ok:lines=%d", #rows))
end

-- ----------------------------------------------------------- ticket helpers
-- All ticket-* subcommands route through `fossil sql` so we get
-- clean structured output without depending on `fossil ticket
-- show`'s report-format quirks.
local function ticket_sql(query, max_lines)
    return popen_lines({"sql", query}, max_lines)
end

-- Strip fossil sql's wrapping quotes + collapse \n-as-literal to
-- a real newline. Mirrors snippets.lua's fetch_bug_comment helper.
local function unquote(s)
    if not s then return "" end
    s = s:gsub("^'", ""):gsub("'$", "")
    s = s:gsub("\\n", "\n"):gsub("\\\\", "\\")
    return s
end

-- ------------------------------------------------------------- tickets list
local function fossil_tickets(filter)
    local where = "1=1"
    if filter == "open" then
        where = "status NOT IN ('fixed','closed','wontfix')"
    elseif filter == "fixed" then
        where = "status='fixed'"
    elseif filter == "blocker" then
        where = "severity='blocker' AND status NOT IN ('fixed','closed','wontfix')"
    elseif filter and filter ~= "" then
        -- treat as a slug substring filter
        local esc = tostring(filter):gsub("'", "''")
        where = "bug_slug LIKE '%" .. esc .. "%'"
    end
    local q = string.format([[
        SELECT REPLACE(REPLACE(COALESCE(bug_id,'?'),x'09',' '),x'0a',' ')
            ||x'09'||REPLACE(REPLACE(COALESCE(status,'?'),x'09',' '),x'0a',' ')
            ||x'09'||REPLACE(REPLACE(COALESCE(severity,'?'),x'09',' '),x'0a',' ')
            ||x'09'||REPLACE(REPLACE(COALESCE(bug_slug,'?'),x'09',' '),x'0a',' ')
            ||x'09'||REPLACE(REPLACE(COALESCE(SUBSTR(title,1,90),'?'),x'09',' '),x'0a',' ')
        FROM ticket WHERE %s
        ORDER BY CASE severity WHEN 'blocker' THEN 1 WHEN 'major' THEN 2
                               WHEN 'minor' THEN 3 ELSE 4 END,
                 CAST(bug_id AS INTEGER) DESC
        LIMIT 100
    ]], where)
    local lines, err = ticket_sql(q)
    if not lines then
        cat9.add_message("fossil tickets: " .. tostring(err))
        H.emit_result("fossil:tickets:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local id, status, sev, slug, title = string.match(unquote(l),
            "^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if id then
            table.insert(rows, {id, status, sev, slug, title})
        end
    end
    H.make_spread(
        string.format("fossil tickets %s (%d)",
            filter or "all", #rows),
        {"id", "status", "severity", "slug", "title"},
        rows
    )
    H.emit_result(string.format("fossil:tickets:ok:filter=%s:rows=%d",
        filter or "all", #rows))
end

-- ----------------------------------------------------------- ticket-show
local function fossil_ticket_show(id_or_slug)
    if not id_or_slug then
        cat9.add_message("fossil ticket-show >id-or-slug<")
        return
    end
    local esc = tostring(id_or_slug):gsub("'", "''")
    -- Match against bug_id (as-is or zero-padded) OR bug_slug
    local idnum = tonumber(esc)
    local padded = idnum and string.format("%04d", idnum) or esc
    local q = string.format(
        "SELECT comment FROM ticket WHERE bug_id IN ('%s','%s') OR bug_slug='%s' OR bug_slug GLOB '%s-*' LIMIT 1",
        padded, esc, esc, padded)
    local lines, err = ticket_sql(q)
    if not lines or #lines == 0 then
        cat9.add_message("fossil ticket-show: not found")
        H.emit_result("fossil:ticket-show:err:id=" .. esc)
        return
    end
    local body = unquote(table.concat(lines, "\n"))
    -- Render as line-spread for scrollable inspection
    local rows = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(rows, {line})
    end
    H.make_spread(
        string.format("ticket %s (%d lines)", id_or_slug, #rows),
        {"line"},
        rows
    )
    H.emit_result(string.format("fossil:ticket-show:ok:id=%s:lines=%d",
        id_or_slug, #rows))
end

-- ----------------------------------------------------------- ticket-history
local function fossil_ticket_history(id_or_slug)
    if not id_or_slug then
        cat9.add_message("fossil ticket-history >id-or-slug<")
        return
    end
    local esc = tostring(id_or_slug):gsub("'", "''")
    local idnum = tonumber(esc)
    local padded = idnum and string.format("%04d", idnum) or esc
    local q = string.format(
        "SELECT COALESCE(run_history,'(empty)') FROM ticket WHERE bug_id IN ('%s','%s') OR bug_slug='%s' LIMIT 1",
        padded, esc, esc)
    local lines, err = ticket_sql(q)
    local body = (lines and #lines > 0) and unquote(table.concat(lines, "\n")) or "(no ticket)"
    local rows = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(rows, {line})
    end
    H.make_spread(
        string.format("ticket %s history", id_or_slug),
        {"line"},
        rows
    )
    H.emit_result(string.format("fossil:ticket-history:ok:id=%s:lines=%d",
        id_or_slug, #rows))
end

-- ----------------------------------------------------------- ticket-set
-- Wraps `fossil ticket change <uuid> <field> <value>`. Looks up the
-- uuid by slug-or-id first.
local function fossil_ticket_set(slug, field, value, ...)
    if not slug or not field or value == nil then
        cat9.add_message("fossil ticket-set >slug-or-id< >field< >value<")
        return
    end
    local esc = tostring(slug):gsub("'", "''")
    local idnum = tonumber(esc)
    local padded = idnum and string.format("%04d", idnum) or esc
    local q = string.format(
        "SELECT tkt_uuid FROM ticket WHERE bug_id IN ('%s','%s') OR bug_slug='%s' LIMIT 1",
        padded, esc, esc)
    local lines, _ = ticket_sql(q)
    if not lines or #lines == 0 then
        cat9.add_message("fossil ticket-set: not found: " .. slug)
        H.emit_result("fossil:ticket-set:err:notfound:slug=" .. slug)
        return
    end
    local uuid = unquote(lines[1])
    -- value may have spaces — concatenate any extra positional args
    local val_parts = {tostring(value)}
    for _, v in ipairs({...}) do
        table.insert(val_parts, tostring(v))
    end
    local val = table.concat(val_parts, " ")
    local out, err = popen_lines({
        "ticket", "change", uuid, field, val,
    }, 50)
    if err then
        cat9.add_message("fossil ticket-set: " .. tostring(err))
        H.emit_result("fossil:ticket-set:err:reason=" .. tostring(err))
        return
    end
    cat9.add_message(string.format(
        "fossil ticket-set %s %s = %s (uuid %s)",
        slug, field, val, uuid:sub(1, 10)))
    H.emit_result(string.format(
        "fossil:ticket-set:ok:slug=%s:field=%s", slug, field))
end

-- ----------------------------------------------------------- dispatch
function builtins.fossil(verb, ...)
    if not verb then
        return fossil_status()
    elseif verb == "status" then
        return fossil_status()
    elseif verb == "log" then
        return fossil_log(...)
    elseif verb == "diff" then
        return fossil_diff(...)
    elseif verb == "tickets" then
        return fossil_tickets(...)
    elseif verb == "ticket-show" or verb == "show" then
        return fossil_ticket_show(...)
    elseif verb == "ticket-history" or verb == "history" then
        return fossil_ticket_history(...)
    elseif verb == "ticket-set" or verb == "set" then
        return fossil_ticket_set(...)
    else
        cat9.add_message("fossil: unknown verb '" .. tostring(verb) ..
            "' (status|log|diff|tickets|ticket-show|ticket-history|ticket-set)")
    end
end

end
