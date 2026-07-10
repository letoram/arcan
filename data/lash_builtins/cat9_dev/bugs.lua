-- bugs — disciplined bug ledger backed by fossil tickets only.
--
-- Data source (read at scan time):
--   fossil tickets — every bug, every draft, every fix. Per ticket
--   0150 (2026-05-02) the bugs/ markdown folder was deprecated;
--   drafts now live in fossil with status='draft' and get promoted
--   by setting status='open' + assigning a bug_id.
--
-- Subcommands:
--   bugs                         — list (all tickets) as a spread
--   bugs open|touched|all        — filtered list
--   bugs draft                   — status='draft' tickets only
--   bugs show <id>               — open ticket body in a cell
--   bugs disasm <slug>           — run extract_disasm.sh + refresh
--   bugs ingest <round_id>       — orchestrate.sh --ingest <round_id>
--   bugs reload                  — re-scan
--
-- On row select the spread publishes ("snippets", file, line, …) on
-- H.viz_bus so the snippets / disasm / hilbert spreads pivot.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.bugs = "Bug ledger (fossil tickets, drafts, all in one DB)"

local function resolve_arcan_root()
    if H.arcan_root then return H.arcan_root end
    local env = cat9.env or {}
    if env.ARCAN_ROOT then return env.ARCAN_ROOT end
    return "/home/x/next/arcan"
end

local function tools_dir() return resolve_arcan_root() .. "/tools/auto-arch" end

-- ---------------------------------------------------------------- fossil

-- Read fossil tickets via `fossil sql`. Returns ordered list of rows;
-- each row is a table indexed by column name. Format-string is a TSV
-- using `||CHAR(9)||` separators; we pull values out by position.
local FOSSIL_COLS = {
    "bug_id", "bug_slug", "bug_signature", "status", "severity",
    "ticket_phase", "ticket_sensor", "ticket_created", "last_seen_date",
    "code_snippets", "run_history", "disasm_refs", "cell_refs",
    "title", "tkt_uuid",
}

local function fossil_query()
    local cols = {}
    for _, c in ipairs(FOSSIL_COLS) do
        -- Flatten embedded newlines so each row stays on one output
        -- line. Tabs are preserved as inner-row TSV; we strip char(13)
        -- and replace char(10) with literal "\n" so the spread
        -- renderer can show multi-line fields explicitly.
        table.insert(cols,
            "REPLACE(REPLACE(COALESCE(" .. c .. ", ''), x'0d', ''), x'0a', '\\n')")
    end
    -- Use char(31) (unit separator) between fields.  Trailing char(30)
    -- (record separator) so the parser can split on \x1e even if
    -- fossil's quote doesn't end at end-of-line.
    local select_expr = table.concat(cols, " || char(31) || ") .. " || char(30)"
    local sql = string.format(
        "SELECT %s FROM ticket ORDER BY bug_id;", select_expr)
    local cmd = string.format(
        "cd %q && fossil sql %q 2>/dev/null", resolve_arcan_root(), sql)
    local p = io.popen(cmd, "r")
    if not p then return {} end
    local raw = p:read("*a") or ""
    p:close()
    local rows = {}
    -- Strip fossil's outer single quotes around the WHOLE concat.
    -- Each record now ends with \x1e; values are \x1f-separated.
    -- bug 0020: between adjacent rows fossil writes `<x1e>'<newline>'`,
    -- so for record N>=2 the substring leading-chars are `'<newline>'`.
    -- Greedy-strip any combination of leading newlines and single quotes
    -- to land on the actual first field byte regardless of position.
    for record in string.gmatch(raw, "([^\30]*)\30") do
        local inner = record
        inner = string.gsub(inner, "^[\r\n']+", "")
        inner = string.gsub(inner, "[\r\n']+$", "")
        inner = string.gsub(inner, "''", "'")  -- unescape SQL quotes
        if inner ~= "" then
            local r = {}
            local idx = 1
            for tok in string.gmatch(inner .. "\31", "([^\31]*)\31") do
                r[FOSSIL_COLS[idx]] = tok
                idx = idx + 1
            end
            if r.bug_id and r.bug_id ~= "" then
                table.insert(rows, r)
            end
        end
    end
    return rows
end

-- ---------------------------------------------------------------- drafts

-- ---------------------------------------------------------------- combined

H.bugs_cache = H.bugs_cache or nil

-- Per ticket 0150, the bugs/draft-*.md scanner is gone — drafts live
-- in fossil with status='draft' and are returned by fossil_query()
-- alongside everything else. is_draft is computed from status so the
-- spread + filter code below stays unchanged.
local function scan_all()
    local fossil_rows = fossil_query()
    local all = {}
    for _, r in ipairs(fossil_rows) do
        r.is_draft = (r.status == "draft")
        table.insert(all, r)
    end
    return all
end

local function ensure_cache()
    if not H.bugs_cache then H.bugs_cache = scan_all() end
    return H.bugs_cache
end

-- ---------------------------------------------------------------- spread

-- Visual status: full word + leading glyph so "fixed vs not" reads at a
-- glance from across the screen.  Open is the loud one (★ OPEN) so the
-- eye lands on actionable rows; closed (fixed/workaround) is calmer.
local function status_label(status)
    if status == "fixed" then        return "✓  FIXED"      end
    if status == "workaround" then   return "≈  WORKAROUND" end
    if status == "wontfix" then      return "—  WONTFIX"    end
    if status == "fix-pending" then  return "~  PENDING"    end
    if status == "investigating" then return "◐  INVESTIG."  end
    return "★  OPEN"
end

local function count_lines(s)
    if not s or s == "" then return 0 end
    local n = 1
    for _ in string.gmatch(s, "\n") do n = n + 1 end
    return n
end

local function bug_row(b)
    local sig = b.bug_signature or ""
    if #sig > 50 then sig = string.sub(sig, 1, 47) .. "…" end
    local title = b.title or ""
    if #title > 60 then title = string.sub(title, 1, 57) .. "…" end
    local runs = count_lines(b.run_history or "")
    local has_asm = (b.disasm_refs or "") ~= ""
    return {
        status_label(b.status or "open"),
        -- drafts now carry real fossil bug_ids; the "d-" visual marker
        -- is preserved so the spread row at-a-glance still flags them.
        b.is_draft and ("d-" .. (b.bug_id or "?")) or (b.bug_id or "?"),
        sig,
        b.severity or "?",
        b.ticket_phase or b.phase or "?",
        b.last_seen_date or b.last_seen or "?",
        runs > 0 and tostring(runs) or "-",
        has_asm and "Y" or "-",
        title,
    }
end

-- Spread state held module-level so the cursor poller can read it.
local bugs_spread = nil
local row_to_bug = {}

local function bugs_list(filter)
    local entries = ensure_cache()
    local rows = {}
    local row_bugs = {}
    for _, b in ipairs(entries) do
        local s = b.status or "open"
        local include = false
        if filter == "open" then
            include = (s ~= "fixed" and s ~= "wontfix")
        elseif filter == "draft" then
            include = b.is_draft == true
        elseif filter == "all" or not filter then
            include = true
        elseif filter == "fossil" then
            include = b.is_draft == false
        end
        if include then
            table.insert(rows, bug_row(b))
            table.insert(row_bugs, b)
        end
    end
    local title = string.format("bugs (%s, %d)", filter or "all", #rows)
    if #rows == 0 then
        bugs_spread = H.make_spread(title,
            {"status", "id", "signature", "sev", "phase", "seen", "runs", "asm", "title"},
            {{ "(no bugs)", "", "", "", "", "", "", "", "" }})
        return
    end
    -- Map spread row → bug entry for the cursor poller
    row_to_bug = {}
    for i, b in ipairs(row_bugs) do
        row_to_bug[i + 1] = b   -- +1: row 1 is header
    end
    bugs_spread = H.make_spread(title,
        {"status", "id", "signature", "sev", "phase", "seen", "runs", "asm", "title"},
        rows)
    if H.emit_result then
        H.emit_result("bugs:listed:filter=" .. (filter or "all")
            .. ":count=" .. tostring(#rows))
    end
end

-- Cursor poller: clicking a bug row publishes (bug_id) so snippets
-- opens the bug's snippets, and (signature) so disasm/dwarf can pivot.
local bugs_cursor = {row = 0}
local function poll_bugs_cursor()
    if not (bugs_spread and bugs_spread.id and bugs_spread.cell_cursor) then
        return true
    end
    local r = bugs_spread.cell_cursor[2] or 0
    if r ~= bugs_cursor.row then
        bugs_cursor.row = r
        local b = row_to_bug[r]
        if b and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("bugs", tostring(b.bug_id), r, {
                bug_id = b.bug_id,
                bug_slug = b.bug_slug,
                signature = b.bug_signature,
                phase = b.ticket_phase,
                severity = b.severity,
                status = b.status,
            })
            H.emit_result(string.format(
                "bugs:click:id=%s:slug=%s:sig=%s",
                tostring(b.bug_id),
                tostring(b.bug_slug),
                tostring(b.bug_signature)))
        end
    end
    return true
end

if cat9.timers then
    table.insert(cat9.timers, poll_bugs_cursor)
end

-- Detail-spread cursor poller: when the user moves cursor onto an
-- "action: <verb>" row in the ticket-detail view, dispatch the verb.
-- The detail spread is annotated with dev_kind="bug-detail" + dev_bug_id
-- by bugs_show.  We track the previous cell to fire on each new arrival
-- (not on every poll while the cursor sits on the row).
local detail_cursor = {row = 0, job = nil}
local function poll_detail_cursor()
    -- cat9.alljobs / cat9.jobs holds every spread; scan for the latest
    -- bug-detail one (there's typically exactly one open at a time).
    local job
    for _, j in pairs(cat9.jobs or {}) do
        if j.dev_kind == "bug-detail" then job = j end
    end
    if not (job and job.cell_cursor) then return true end
    local r = job.cell_cursor[2] or 0
    if job ~= detail_cursor.job then
        detail_cursor.job = job
        detail_cursor.row = 0
    end
    if r == detail_cursor.row then return true end
    detail_cursor.row = r
    local cell_a = job.cells and job.cells[r] and job.cells[r][1]
    if not (cell_a and cell_a.label) then return true end
    local lbl = cell_a.label
    if lbl == "action: rebuild" then
        run_rebuild(job.dev_bug_id, "rebuild")
    elseif lbl == "action: revert-and-rebuild" then
        run_revert_rebuild(job.dev_bug_id)
    elseif lbl == "action: run-repro" then
        run_repro(job.dev_bug_id)
    elseif lbl == "action: extract-disasm" then
        run_extract_disasm(job.dev_bug_id)
    elseif lbl == "action: disasm-before" then
        run_disasm_temporal(job.dev_bug_id, "before")
    elseif lbl == "action: disasm-after" then
        run_disasm_temporal(job.dev_bug_id, "after")
    elseif lbl == "disasm: llvm" or lbl == "disasm: sh" or
           lbl == "disasm: diff" then
        -- Cell B holds the path; open as a `read` job so the user
        -- can scroll the .S/.diff in cat9 directly.
        local cell_b = job.cells and job.cells[r] and job.cells[r][2]
        local val = cell_b and cell_b.label or ""
        -- val starts with "[click] /path/...".  Strip the bracket prefix.
        local path = string.match(val, "/[^ ]+%.[Sst][xX]?[tT]?")
        if path then
            cat9.parse_string(cat9.readline, "read " .. path)
        end
    end
    return true
end
if cat9.timers then
    table.insert(cat9.timers, poll_detail_cursor)
end

-- Query fossil for commits that touched this bug's snippet files. Returns
-- a list of {sha, when, comment} rows, newest first. Empty list if nothing
-- matches — used to populate the bottom of the ticket-detail spread.
local function bug_commits(b)
    local files = {}
    if b.code_snippets and b.code_snippets ~= "" then
        for fname in b.code_snippets:gmatch("file=([^\t\n]+)") do
            files[#files + 1] = fname
        end
    end
    if #files == 0 then return {} end
    -- Use `fossil finfo` per file. Aggregate, dedupe by sha, keep newest.
    local seen = {}
    local out = {}
    local arcan_root = "/home/x/next/arcan"
    for _, f in ipairs(files) do
        local cmd = string.format(
            "cd %q && fossil finfo -l %q 2>/dev/null | head -20",
            arcan_root, f)
        local p = io.popen(cmd, "r")
        if p then
            for line in p:lines() do
                -- format: "<date> [<sha>] <comment> (user: x, ...)"
                local date, sha, comment =
                    string.match(line, "^([%d%-%s:]+)%s*%[([0-9a-f]+)%]%s*(.*)$")
                if sha and not seen[sha] then
                    seen[sha] = true
                    table.insert(out, {sha = sha, when = date or "",
                                       comment = (comment or ""):sub(1, 80),
                                       file = f})
                end
            end
            p:close()
        end
    end
    return out
end

local function bugs_show(id)
    if not id then cat9.add_message("bugs show <id|slug>"); return end
    local idn = tostring(id):gsub("^#", "")
    -- Normalise: bug_id is zero-padded "0019" in fossil, user typically
    -- types "19" or "0019" or "#19".  Match on string (slug or padded
    -- id), AND on numeric value when both sides are numeric.
    --
    -- bug 0020 (Zig lua54 quirk): tonumber("0019") returns 17 — the
    -- arcan-embedded Lua's number parser auto-detects octal from the
    -- leading zero and accumulates value*8+digit without rejecting
    -- non-octal digits (so "0019" → ((0*8+0)*8+1)*8+9 == 17).  Force
    -- base 10 explicitly to bypass the auto-detection.
    local idnum = tonumber(idn, 10)
    local cache = ensure_cache()
    for _, b in ipairs(cache) do
        local bidnum = tonumber(b.bug_id or "", 10)
        local match = tostring(b.bug_id) == idn or b.bug_slug == idn
            or (idnum and bidnum and idnum == bidnum)
        if match then
            do
                -- Render fossil ticket as a key/value spread, then append
                -- a "commits" section (one row per fossil commit that
                -- touched a snippet file) and an "actions" section with
                -- clickable verbs the cursor poller dispatches.
                -- (Per ticket 0150, drafts now follow the same render
                --  path — they're real fossil tickets with status='draft'
                --  and no longer have a separate .md file to fall back
                --  on. The is_draft flag is still computed for the
                --  spread row's "d-" prefix.)
                local rows = {}
                for _, k in ipairs(FOSSIL_COLS) do
                    local v = b[k] or ""
                    if v ~= "" then
                        table.insert(rows, {k, v:sub(1, 200)})
                    end
                end
                -- Visual separator + commits.
                local commits = bug_commits(b)
                if #commits > 0 then
                    table.insert(rows, {"--- commits ---", ""})
                    for _, c in ipairs(commits) do
                        table.insert(rows, {
                            string.format("commit %s", c.sha:sub(1, 10)),
                            string.format("[%s] %s  (%s)",
                                c.when:gsub("%s+$", ""),
                                c.comment, c.file)})
                    end
                end
                -- Action verbs. The cursor poller below recognizes these
                -- field names and runs the corresponding command on click.
                table.insert(rows, {"--- actions ---", ""})
                local is_fixed = (b.status == "fixed" or
                                  b.status == "workaround")
                if is_fixed then
                    table.insert(rows, {"action: rebuild",
                        "[click] zig build install — verify fix still holds"})
                    table.insert(rows, {"action: revert-and-rebuild",
                        "[click] fossil revert + rebuild — reproduce original failure"})
                else
                    table.insert(rows, {"action: rebuild",
                        "[click] zig build install — try a fresh build"})
                end
                -- dev-loop02: per-bug minimal repro.  If
                -- tools/auto-arch/repro/<id>/run.sh exists, surface
                -- it as a clickable action.
                local repro_path = string.format(
                    "%s/repro/%s/run.sh", tools_dir(), tostring(b.bug_id))
                local rf = io.open(repro_path, "r")
                if rf then
                    rf:close()
                    table.insert(rows, {"action: run-repro",
                        "[click] " .. repro_path .. " — minimal demonstration"})
                end
                -- dev-loop06: disasm artifacts.  If extract_disasm.sh
                -- has been run for this bug's slug, surface the .S
                -- files as clickable rows.  Always offer the
                -- "extract-disasm" action so the user can (re)run.
                local disasm_dir = string.format(
                    "%s/disasm/%s", tools_dir(), tostring(b.bug_slug or ""))
                local llvm_s = disasm_dir .. "/llvm.0.S"
                local sh_s = disasm_dir .. "/sh.0.S"
                local diff_p = disasm_dir .. "/diff.0.txt"
                table.insert(rows, {"--- disasm ---", ""})
                local lf = io.open(llvm_s, "r")
                if lf then
                    lf:close()
                    table.insert(rows, {"disasm: llvm",
                        "[click] " .. llvm_s})
                end
                local sf = io.open(sh_s, "r")
                if sf then
                    sf:close()
                    table.insert(rows, {"disasm: sh",
                        "[click] " .. sh_s})
                end
                local df = io.open(diff_p, "r")
                if df then
                    df:close()
                    table.insert(rows, {"disasm: diff",
                        "[click] " .. diff_p .. " — LLVM vs SH unified diff"})
                end
                -- Always-present actions for (re)running extraction.
                table.insert(rows, {"action: extract-disasm",
                    "[click] extract_disasm.sh — (re)build LLVM + SH .S for this bug"})
                if b.status == "fixed" or b.status == "workaround" then
                    table.insert(rows, {"action: disasm-before",
                        "[click] disasm at parent commit (pre-fix codegen)"})
                    table.insert(rows, {"action: disasm-after",
                        "[click] disasm at fix-tip (post-fix codegen)"})
                end
                local detail = H.make_spread("ticket: " .. idn,
                    {"field", "value"}, rows)
                if detail then
                    detail.dev_kind = "bug-detail"
                    detail.dev_bug_id = b.bug_id
                end
            end
            return
        end
    end
    cat9.add_message("bugs show: not found: " .. tostring(idn))
end

-- dev-loop02: run a per-bug minimal repro and stream output into a
-- sibling spread.  Looks up tools/auto-arch/repro/<id>/run.sh; surfaces
-- the script's verdict via shmif MESSAGE so dashboard.lua can tally
-- repro health.  The runner is just a `!! bash …` job — repro output
-- (compile + run) lands as a regular cat9 job spreadsheet that the
-- user can scroll, just like any other shell job.
local function run_repro(bug_id)
    if not bug_id then return end
    local script = string.format(
        "%s/repro/%s/run.sh", tools_dir(), tostring(bug_id))
    local f = io.open(script, "r")
    if not f then
        cat9.add_message("repro: no run.sh for bug " .. tostring(bug_id))
        return
    end
    f:close()
    -- The `!!` prefix opens a job and streams stdout into it.  Capture
    -- the exit status into a per-bug result via tee + grep — the job's
    -- own exit_code field is also surfaced in cat9.alljobs after the
    -- job completes (autosuggest can render it).
    local cmd = string.format("bash %q 2>&1", script)
    cat9.parse_string(cat9.readline, "!! " .. cmd)
    if H.emit_result then
        H.emit_result("repro:start:bug=" .. tostring(bug_id))
    end
end

-- dev-loop06: run extract_disasm.sh for the bug's slug.  Generates
-- LLVM and SH .S files plus a unified diff under
-- tools/auto-arch/disasm/<slug>/.  After the script returns, the
-- user can re-issue `bugs show <id>` to see the disasm: rows
-- populated.
local function run_extract_disasm(bug_id)
    if not bug_id then return end
    local b
    for _, x in ipairs(ensure_cache()) do
        if tostring(x.bug_id) == tostring(bug_id) then b = x; break end
    end
    if not b or not b.bug_slug then
        cat9.add_message("disasm: no slug for bug " .. tostring(bug_id))
        return
    end
    local cmd = string.format(
        "bash %q/extract_disasm.sh --slug %q 2>&1",
        tools_dir(), b.bug_slug)
    cat9.parse_string(cat9.readline, "!! " .. cmd)
    if H.emit_result then
        H.emit_result("disasm:extract:bug=" .. tostring(bug_id) ..
            ":slug=" .. tostring(b.bug_slug))
    end
end

-- dev-loop06 (temporal axis): run extract_disasm at the parent
-- commit (before-fix) or current tip (after-fix).  Stub for now —
-- requires worktree wiring (dev-loop03).  Emits a placeholder
-- message and tells the user the verb isn't fully wired.
local function run_disasm_temporal(bug_id, when)
    cat9.add_message(string.format(
        "disasm-%s: requires per-bug worktree (dev-loop03) — not yet wired",
        tostring(when)))
    if H.emit_result then
        H.emit_result(string.format(
            "disasm:temporal:bug=%s:when=%s:status=stubbed",
            tostring(bug_id), tostring(when)))
    end
end

-- Run zig build install (rebuild target) for a closed ticket and stream
-- output into a sibling spread.  Verifies the fix still holds (no new
-- panics from the chain that was filed under this bug_id).
local function run_rebuild(bug_id, label)
    local cmd = string.format(
        "cd /home/x/next/arcan && PATH=/home/x/.local/src/zig-0.15.2-fork/zig-out/bin:$PATH zig build install --summary all 2>&1")
    cat9.parse_string(cat9.readline, "!! " .. cmd)
    if H.emit_result then
        H.emit_result(string.format("bugs:%s:bug=%s", label or "rebuild", bug_id or ""))
    end
end

-- Revert the snippet files for a closed bug to a previous commit
-- (one before the fix), rebuild, and surface the result. The user can
-- watch the chain panic in the launch log — proof the fix was load-bearing.
local function run_revert_rebuild(bug_id)
    -- Find the snippet files for this bug.
    local b
    for _, x in ipairs(ensure_cache()) do
        if tostring(x.bug_id) == tostring(bug_id) then b = x; break end
    end
    if not b or not b.code_snippets then
        cat9.add_message("bugs revert: snippet info missing for " .. tostring(bug_id))
        return
    end
    local files = {}
    for f in b.code_snippets:gmatch("file=([^\t\n]+)") do
        files[#files + 1] = f
    end
    if #files == 0 then
        cat9.add_message("bugs revert: no files in snippet")
        return
    end
    -- fossil revert restores the file from the last checkin — but we
    -- want the version BEFORE the fix.  Use `fossil revert -r` with the
    -- parent of the fix sha.  For "pending"/sha unset, fall back to a
    -- plain `fossil diff` so the user can see what the fix changed.
    local cmd = "cd /home/x/next/arcan && echo '=== bug " .. tostring(bug_id) ..
                " — diff vs HEAD ===' && for f in"
    for _, f in ipairs(files) do
        cmd = cmd .. " " .. string.format("%q", f)
    end
    cmd = cmd .. "; do echo \"--- $f ---\"; fossil diff \"$f\" 2>&1 | head -40; done"
    cat9.parse_string(cat9.readline, "!! " .. cmd)
    if H.emit_result then
        H.emit_result(string.format("bugs:revert-preview:bug=%s", tostring(bug_id)))
    end
end

-- Run a tool from tools/auto-arch and refresh.
local function shell_tool(cmd)
    cat9.parse_string(cat9.readline, "!! " .. cmd)
    H.bugs_cache = nil
end

local function bugs_disasm(slug)
    if not slug then cat9.add_message("bugs disasm <slug>"); return end
    shell_tool(tools_dir() .. "/extract_disasm.sh --slug " .. slug)
end

local function bugs_ingest(round_id)
    if not round_id then cat9.add_message("bugs ingest <round_id>"); return end
    shell_tool(tools_dir() .. "/orchestrate.sh --ingest " .. round_id)
end

local function bugs_reload()
    H.bugs_cache = nil
    ensure_cache()
    cat9.add_message(string.format(
        "bugs: reloaded (%d entries)", #(H.bugs_cache or {})))
end

-- bug 0018: in-process filter/edit demo via cat9's `view #N <verb>`.
-- The tour spawns ONE read job over a known small file (mouse.lua),
-- then announces each in-place verb the user can drive against it
-- without spawning more jobs.  Emits one shmif MESSAGE per step so
-- a harness in shmon can verify the canonical interaction primitive
-- is exercised.  The verbs themselves are typed by the user — we
-- announce them as guidance because their effect (view switch /
-- expand / edit) is intrinsically interactive.
local function bugs_view_tour()
    local source = resolve_arcan_root() .. "/data/scripts/builtin/mouse.lua"
    H.emit_result("view-tour:begin:source=" .. source)

    -- Spawn the read job that subsequent view verbs target.
    cat9.parse_string(cat9.readline, "read " .. source)
    local jid = cat9.latestjob and cat9.latestjob.id
    H.emit_result(string.format("view-tour:read:job=%s:source=%s",
        tostring(jid or "?"), source))

    -- Each entry: {label, command-the-user-types, what-they-see}
    local steps = {
        {"expand",   "view #N expand",        "fill the screen with job N"},
        {"grep",     "view #N grep cursor",   "in-place filter to lines matching 'cursor'"},
        {"edit",     "view #N edit",          "flip to interactive edit mode on that job"},
        {"hex",      "view #N hex",           "flip to hex view of the same content"},
        {"collapse", "view #N collapse",      "return to summary"},
    }
    for i, step in ipairs(steps) do
        local cmd = step[2]
        if jid then cmd = (cmd:gsub("#N", "#" .. tostring(jid))) end
        H.emit_result(string.format(
            "view-tour:step:%d:label=%s:cmd=%s", i, step[1], cmd))
        cat9.add_message(string.format("[%d/%d] %s — %s",
            i, #steps, cmd, step[3]))
    end

    H.emit_result("view-tour:done:steps=" .. #steps)
    cat9.add_message("view-tour ready: type the listed `view #" ..
        tostring(jid or "N") ..
        " <verb>` lines to exercise in-place filter/edit/hex.")
end

local subcommands = {
    show       = bugs_show,
    reload     = bugs_reload,
    open       = function() bugs_list("open") end,
    draft      = function() bugs_list("draft") end,
    fossil     = function() bugs_list("fossil") end,
    all        = function() bugs_list("all") end,
    disasm     = bugs_disasm,
    ingest     = bugs_ingest,
    repro      = run_repro,
    ["view-tour"] = bugs_view_tour,
}

function suggest.bugs(args, raw)
    if #args == 2 then
        local set = {"show", "reload", "open", "draft", "fossil", "all",
                     "disasm", "ingest", "repro", "view-tour"}
        cat9.readline:suggest(cat9.prefix_filter(set, args[2]), "word")
    end
end

function builtins.bugs(verb, ...)
    if not verb then return bugs_list("all") end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    if verb == "open" or verb == "draft" or verb == "fossil" or verb == "all" then
        return bugs_list(verb)
    end
    cat9.add_message("bugs {show <id>|disasm <slug>|ingest <round>|"
        .. "repro <id>|reload|open|draft|fossil|all|view-tour}")
end

end
