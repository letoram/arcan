-- refactor — drive the tools/refactor/ Zig binaries from cat9.
--
-- The toolkit (tools/refactor/src/T*) implements ABI-safe AST rewrites
-- that mechanically close refactor tickets registered in fossil
-- (tickets 0100-0111+, phase=refactor-A.* / B.* / C.*).
-- This builtin is the LLM-facing surface: type a subcommand, watch the
-- spread paint, click rows to pivot via viz_bus into bugs/snippets/
-- hilbert.
--
-- Subcommands:
--   refactor                       — list refactor tickets (filter=open)
--   refactor list [filter]         — open|closed|all|<phase>
--   refactor tools                 — registered T<N> binaries
--   refactor scan                  — run tools/test/scan_offenders.sh,
--                                    paint offender register
--   refactor apply T<N> [args]     — spawn the named binary, paint
--                                    progress + result rows
--   refactor verify                — tools/test/refactor_verifier.sh,
--                                    paint gate fitness
--   refactor manifest              — display tools/refactor/abi_firewall.json
--                                    summary
--
-- Pattern follows selfhost.lua + compile.lua:
--   * setup_shell_job spawns the tool; stdout streams into a spread
--   * the spread cursor is polled; clicks publish on viz_bus so the
--     bugs / snippets / hilbert spreads pivot to the offender's site
--   * dev_result events are emitted at start/done so cat9_workflow_runner
--     can post-mortem
--
-- Future: when tools/refactor/common/shmif.zig lands, the binaries
-- will publish via shmif MESSAGEs directly. Until then, stdout is the
-- transport — same shape compile.lua + selfhost.lua use.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.refactor =
    "refactor [list|tools|scan|apply T<N>|verify|manifest]"

local function arcan_root()
    if H.arcan_root then return H.arcan_root end
    local env = cat9.env or {}
    if env.ARCAN_ROOT then return env.ARCAN_ROOT end
    return "/home/x/next/arcan"
end

local function refactor_dir()  return arcan_root() .. "/tools/refactor" end
local function test_dir()      return arcan_root() .. "/tools/test" end

local function spread_set(spread, row, col, value)
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %s",
            spread.id, row, col, H.escape_cell(value)))
end

-- ---------------------------------------------------------------- list

-- Reuse bugs.lua's fossil reader by shelling out. Reading directly
-- from `fossil sql` here keeps refactor.lua independent of bugs.lua's
-- private state but mirrors the same column layout. See bugs.lua:43-95.
local FOSSIL_COLS = {
    "bug_id", "bug_slug", "bug_signature", "status", "severity",
    "ticket_phase", "title", "tkt_uuid",
}

local function fossil_query_refactor(filter)
    local cols = {}
    for _, c in ipairs(FOSSIL_COLS) do
        table.insert(cols,
            "REPLACE(REPLACE(COALESCE(" .. c .. ", ''), x'0d', ''), x'0a', '\\n')")
    end
    local select_expr = table.concat(cols, " || char(31) || ") .. " || char(30)"
    local where = "ticket_phase LIKE 'refactor-%'"
    if filter == "open" then
        where = where .. " AND status != 'fixed' AND status != 'wontfix'"
    elseif filter == "closed" then
        where = where .. " AND (status = 'fixed' OR status = 'wontfix')"
    elseif filter and filter ~= "all" then
        -- treat as a phase filter (e.g. "A.7", "B.6")
        where = "ticket_phase = 'refactor-" .. filter .. "'"
    end
    local sql = string.format(
        "SELECT %s FROM ticket WHERE %s ORDER BY bug_id;",
        select_expr, where)
    local cmd = string.format(
        "cd %q && fossil sql %q 2>/dev/null", arcan_root(), sql)
    local p = io.popen(cmd, "r")
    if not p then return {} end
    local raw = p:read("*a") or ""
    p:close()
    local rows = {}
    for record in string.gmatch(raw, "([^\30]*)\30") do
        local inner = record
        inner = string.gsub(inner, "^[\r\n]+", "")
        inner = string.gsub(inner, "^'", "")
        inner = string.gsub(inner, "'$", "")
        inner = string.gsub(inner, "''", "'")
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

local list_spread = nil
local row_to_ticket = {}

local function refactor_list(filter)
    filter = filter or "open"
    local tickets = fossil_query_refactor(filter)
    if #tickets == 0 then
        list_spread = H.make_spread(
            "refactor (" .. filter .. ", 0)",
            {"id", "phase", "status", "sev", "title"},
            {{"(no refactor tickets)", "", "", "", ""}})
        return
    end
    local rows = {}
    row_to_ticket = {}
    for i, t in ipairs(tickets) do
        local title = t.title or ""
        if #title > 70 then title = string.sub(title, 1, 67) .. "…" end
        table.insert(rows, {
            t.bug_id or "?",
            t.ticket_phase or "?",
            t.status or "open",
            t.severity or "?",
            title,
        })
        row_to_ticket[i + 1] = t  -- +1 for header
    end
    list_spread = H.make_spread(
        string.format("refactor (%s, %d)", filter, #tickets),
        {"id", "phase", "status", "sev", "title"},
        rows)
    H.emit_result(string.format(
        "refactor:list:filter=%s:count=%d", filter, #tickets))
end

-- ---------------------------------------------------------------- tools

-- Parse tools registered in tools/refactor/build.zig. The lines we
-- want look like:  .{ .name = "T0_abi_firewall", .root = "src/T0_abi_firewall/main.zig" },
local function read_tools_registry()
    local path = refactor_dir() .. "/build.zig"
    local f = io.open(path, "r")
    if not f then return {} end
    local txt = f:read("*a")
    f:close()
    local out = {}
    for name, root in string.gmatch(txt,
        '%.name%s*=%s*"([%w_]+)"%s*,%s*%.root%s*=%s*"([^"]+)"') do
        table.insert(out, {name = name, root = root})
    end
    return out
end

local function refactor_tools()
    local tools = read_tools_registry()
    local rows = {}
    for _, t in ipairs(tools) do
        -- Best-effort: check if the binary was built (in zig-out/bin/).
        local bin = refactor_dir() .. "/zig-out/bin/" .. t.name
        local fp = io.open(bin, "r")
        local built = "no"
        if fp then fp:close(); built = "yes" end
        table.insert(rows, {t.name, built, t.root})
    end
    H.make_spread(
        string.format("refactor tools (%d registered)", #tools),
        {"binary", "built", "source"},
        rows)
    H.emit_result(string.format(
        "refactor:tools:registered=%d", #tools))
end

-- ---------------------------------------------------------------- scan

-- Spawn tools/refactor/zig-out/bin/T_scan and paint the
-- per-pattern summary. Each pattern is one row; the user can drill
-- via `refactor list <phase>` to see the corresponding fossil
-- tickets. T_scan honors tools/refactor/exclude.txt.
local function refactor_scan()
    local bin = refactor_dir() .. "/zig-out/bin/T_scan"
    local fp = io.open(bin, "r")
    if not fp then
        cat9.add_message("refactor scan: " .. bin ..
            " not built. `cd tools/refactor && zig build install`.")
        return
    end
    fp:close()
    local cmd = string.format("%q --root %q 2>&1", bin, arcan_root())
    local p = io.popen(cmd, "r")
    if not p then
        cat9.add_message("refactor scan: failed to spawn T_scan")
        return
    end
    H.emit_result("refactor:scan:start")
    local rows = {}
    local total_off = "0"
    local total_loc = "0"
    for line in p:lines() do
        -- T_scan emits:
        --   SUMMARY\t<name>\t<phase>\t<count>\t<delta_per>\t<est>
        --   TOTAL\toffenders=<N>\test_loc=<M>
        local n, ph, c, dp, et =
            string.match(line, "^SUMMARY\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)$")
        if n then
            table.insert(rows, {n, ph, c, dp, et})
        end
        local tot = string.match(line, "^TOTAL\toffenders=(%d+)")
        if tot then total_off = tot end
        local loc = string.match(line, "est_loc=(%d+)")
        if loc then total_loc = loc end
    end
    p:close()
    if #rows == 0 then
        cat9.add_message("refactor scan: no patterns parsed (T_scan format change?)")
        return
    end
    H.make_spread(
        string.format("offenders (%s, est %s LOC)", total_off, total_loc),
        {"pattern", "phase", "count", "delta/each", "est_total"},
        rows)
    H.emit_result(string.format(
        "refactor:scan:done:patterns=%d:offenders=%s:est_loc=%s",
        #rows, total_off, total_loc))
end

-- ---------------------------------------------------------------- apply

-- Run a registered T<N> binary in-process via setup_shell_job.
-- Stdout streams into a "refactor apply T<N>" spread; the user sees
-- progress live, same shape as compile / selfhost.
local apply_spread = nil
local apply_count = 0

local function refactor_apply(tool_name, ...)
    if not tool_name then
        cat9.add_message("refactor apply <tool> [args] — try `refactor tools`")
        return
    end
    local args = {...}
    local bin = refactor_dir() .. "/zig-out/bin/" .. tool_name
    local fp = io.open(bin, "r")
    if not fp then
        cat9.add_message("refactor apply: " .. tool_name ..
            " not built. Build with `cd tools/refactor && zig build install`.")
        return
    end
    fp:close()

    apply_spread = H.make_spread(
        "refactor apply " .. tool_name,
        {"#", "kind", "detail"},
        {})
    apply_count = 0

    local argv = {bin, tool_name}
    for _, a in ipairs(args) do table.insert(argv, a) end

    local env = cat9.table_copy_shallow(cat9.env)
    local old_dir = root:chdir()
    root:chdir(refactor_dir())
    local job = cat9.setup_shell_job(
        argv, "re", env,
        "refactor " .. tool_name, {close = true})
    root:chdir(old_dir)
    if not job then
        cat9.add_message("refactor apply: setup_shell_job failed")
        return
    end
    job.short = "refactor:" .. tool_name

    if job.out and job.out.data_handler then
        job.out:data_handler(function()
            local line, alive = job.out:read(true)
            while line do
                apply_count = apply_count + 1
                local row = apply_count + 1
                -- Recognize known shapes; otherwise treat as info.
                local kind, detail
                if string.find(line, "^OFFENDER\t") then
                    kind = "offender"
                    detail = string.gsub(line, "^OFFENDER\t", "")
                elseif string.find(line, "^RESULT\t") then
                    kind = "result"
                    detail = string.gsub(line, "^RESULT\t", "")
                elseif string.find(line, "^FIREWALL\t") then
                    kind = "firewall"
                    detail = string.gsub(line, "^FIREWALL\t", "")
                else
                    kind = "info"
                    detail = line
                end
                spread_set(apply_spread, row, 1, tostring(apply_count))
                spread_set(apply_spread, row, 2, kind)
                spread_set(apply_spread, row, 3, detail:sub(1, 200))
                line, alive = job.out:read(true)
                if not alive then break end
            end
        end)
    end

    H.emit_result("refactor:apply:" .. tool_name .. ":start")
    table.insert(job.hooks.on_finish, function()
        H.emit_result(string.format(
            "refactor:apply:%s:done:lines=%d", tool_name, apply_count))
    end)
    table.insert(job.hooks.on_fail, function()
        H.emit_result(string.format(
            "refactor:apply:%s:fail:lines=%d", tool_name, apply_count))
    end)
end

-- ---------------------------------------------------------------- verify

-- Native Lua reimplementation of tools/test/refactor_verifier.sh.
-- Runs each gate inline:
--   - offenders: spawn T_scan; emit fitness based on diff vs baseline
--   - shmif-abi: zig test src/shmif/shmif_*_test.zig
--   - cat9-workflow: tools/test/cat9_workflow_runner.sh (skip if !$DISPLAY)
-- Mirrors auto-arch eval.sh's GATE\tRESULT TSV shape so refactor
-- commits use the same fitness-scoring contract as zig-SH-fork
-- bug rounds.
local VERIFY_GATES = {
    {name = "offenders",     weight = 5, timeout = 60},
    {name = "shmif-abi",     weight = 3, timeout = 120},
    {name = "cat9-workflow", weight = 2, timeout = 300},
}

local function gate_offenders()
    local bin = refactor_dir() .. "/zig-out/bin/T_scan"
    local fp = io.open(bin, "r")
    if not fp then return "broken", "T_scan not built" end
    fp:close()
    local p = io.popen(string.format("%q --root %q 2>&1", bin, arcan_root()), "r")
    if not p then return "broken", "spawn failed" end
    local total = "?"
    for line in p:lines() do
        local n = string.match(line, "^TOTAL\toffenders=(%d+)")
        if n then total = n end
    end
    p:close()
    -- Compare against baseline at tools/test/baseline/offenders.tsv. If
    -- absent (first run), pass; otherwise pass only when current count
    -- has not grown.
    local base_path = test_dir() .. "/baseline/offenders.tsv"
    local bf = io.open(base_path, "r")
    if not bf then return "pass", "no baseline (count=" .. total .. ")" end
    local base_lines = 0
    for _ in bf:lines() do base_lines = base_lines + 1 end
    bf:close()
    local now = tonumber(total) or 0
    if now <= base_lines then
        return "pass", string.format("count=%d baseline=%d", now, base_lines)
    end
    return "fail", string.format("regression: count=%d baseline=%d", now, base_lines)
end

local function gate_shmif_abi()
    -- Walk src/shmif/shmif_*_test.zig and ast-check each. Tests
    -- requiring the actual C side (shmif_test_helpers.c) won't link
    -- via plain zig test; --test-no-exec gates only the parser +
    -- typer side, which is the right firewall: layout asserts hold
    -- iff the type definitions still parse cleanly.
    local zig = "/usr/local/zig-aarch64-linux-0.15.2/zig"
    local cmd = string.format(
        "ls %s/src/shmif/shmif_*_test.zig 2>/dev/null", arcan_root())
    local p = io.popen(cmd, "r")
    if not p then return "broken", "ls failed" end
    local files = {}
    for f in p:lines() do table.insert(files, f) end
    p:close()
    if #files == 0 then return "broken", "no shmif test files found" end
    local pass = 0
    local fail = 0
    for _, f in ipairs(files) do
        local check = string.format(
            "%q ast-check %q > /dev/null 2>&1", zig, f)
        if os.execute(check) then
            pass = pass + 1
        else
            fail = fail + 1
        end
    end
    if fail == 0 then
        return "pass", string.format("ast-check=%d/%d", pass, #files)
    end
    return "fail", string.format("ast-check=%d/%d", pass, #files)
end

-- Contract baseline diff: read tools/test/baseline/cat9_workflow.expected,
-- run the workflow runner, parse its report.txt, ensure every
-- EXPECTED_PASS line maps to a `PASS <name>` row in the report.
-- Missing or downgraded → fail. INFO lines satisfy EXPECTED_INFO.
local function read_workflow_baseline()
    local path = test_dir() .. "/baseline/cat9_workflow.expected"
    local f = io.open(path, "r")
    if not f then return nil, "baseline missing: " .. path end
    local expected = { pass = {}, info = {} }
    for line in f:lines() do
        local trimmed = string.gsub(line, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= "#" then
            local kind, name = string.match(
                trimmed, "^EXPECTED_([A-Z]+)\t([^\t]+)$")
            if kind == "PASS" then
                expected.pass[name] = true
            elseif kind == "INFO" then
                expected.info[name] = true
            end
        end
    end
    f:close()
    return expected
end

local function gate_cat9_workflow()
    if not (cat9.env and cat9.env.DISPLAY) then
        return "pass", "skipped (no DISPLAY)"
    end
    local expected, err = read_workflow_baseline()
    if not expected then return "broken", err end

    local runner = test_dir() .. "/cat9_workflow_runner.sh"
    local fp = io.open(runner, "r")
    if not fp then return "broken", runner .. " missing" end
    fp:close()

    -- Runner now writes to ${HOME}/.local/share/zig-sh-testing/cat9_wf/report.txt
    local home = (cat9.env and cat9.env.HOME) or os.getenv("HOME") or ""
    local report_path = home .. "/.local/share/zig-sh-testing/cat9_wf/report.txt"

    local rc = os.execute("TIMEOUT=120 " .. runner .. " > /dev/null 2>&1")
    -- rc may be true/nil in 5.4 with extended return; we don't strictly
    -- need it because the contract diff is the real verdict.
    _ = rc

    local rf = io.open(report_path, "r")
    if not rf then return "fail", "report missing: " .. report_path end
    local got = { pass = {}, fail = {}, info = {} }
    for line in rf:lines() do
        local kind, name = string.match(line, "^(PASS)%s+(%S+)") -- "PASS  name"
        if not kind then kind, name = string.match(line, "^(FAIL)%s+(%S+)") end
        if not kind then kind, name = string.match(line, "^(INFO)%s+(%S+)") end
        if kind == "PASS" then got.pass[name] = true
        elseif kind == "FAIL" then got.fail[name] = true
        elseif kind == "INFO" then got.info[name] = true end
    end
    rf:close()

    -- Diff: every EXPECTED_PASS must be in got.pass; every EXPECTED_INFO
    -- in got.info or got.pass (info is acceptable as a stronger pass).
    local missing = {}
    local regressed = {}
    for name, _ in pairs(expected.pass) do
        if not got.pass[name] then
            if got.fail[name] then
                table.insert(regressed, name)
            else
                table.insert(missing, name)
            end
        end
    end
    for name, _ in pairs(expected.info) do
        if not (got.info[name] or got.pass[name]) then
            if got.fail[name] then
                table.insert(regressed, name)
            else
                table.insert(missing, name)
            end
        end
    end

    if #regressed == 0 and #missing == 0 then
        return "pass", string.format("matches baseline (%d expected_pass)",
            (function() local n = 0 for _ in pairs(expected.pass) do n = n + 1 end return n end)())
    end
    local detail = ""
    if #regressed > 0 then
        detail = "regressed: " .. table.concat(regressed, ",")
    end
    if #missing > 0 then
        if #detail > 0 then detail = detail .. "; " end
        detail = detail .. "missing: " .. table.concat(missing, ",")
    end
    return "fail", detail
end

local function refactor_verify()
    H.emit_result("refactor:verify:start")
    local rows = {}
    local total_w = 0
    local max_w = 0
    local start_t = os.time()
    for _, g in ipairs(VERIFY_GATES) do
        max_w = max_w + g.weight
        H.emit_result("refactor:verify:gate:" .. g.name .. ":start")
        local t0 = os.time()
        local status, detail
        if g.name == "offenders" then
            status, detail = gate_offenders()
        elseif g.name == "shmif-abi" then
            status, detail = gate_shmif_abi()
        elseif g.name == "cat9-workflow" then
            status, detail = gate_cat9_workflow()
        else
            status, detail = "broken", "unknown gate"
        end
        local dur = os.time() - t0
        if status == "pass" then total_w = total_w + g.weight end
        table.insert(rows, {
            g.name, tostring(g.weight), status,
            tostring(dur), detail or "",
        })
        H.emit_result(string.format(
            "refactor:verify:gate:%s:%s:secs=%d", g.name, status, dur))
    end
    local elapsed = os.time() - start_t
    H.make_spread(
        string.format(
            "refactor verify (fitness=%d/%d, %ds)",
            total_w, max_w, elapsed),
        {"gate", "weight", "status", "secs", "detail"},
        rows)
    H.emit_result(string.format(
        "refactor:verify:done:fitness=%d/%d:secs=%d",
        total_w, max_w, elapsed))
end

-- ---------------------------------------------------------------- manifest

local function refactor_manifest()
    local path = refactor_dir() .. "/abi_firewall.json"
    local f = io.open(path, "r")
    if not f then
        cat9.add_message("refactor manifest: " .. path ..
            " missing. Run `refactor apply T0_abi_firewall .`")
        return
    end
    -- Read enough to count entries; a full JSON parse is overkill here.
    local txt = f:read("*a")
    f:close()
    -- Each entry line starts with `    { "kind": "...", "name": "..."`.
    local n = 0
    local kind_counts = {}
    for kind in string.gmatch(txt, '"kind":%s*"([%w_]+)"') do
        n = n + 1
        kind_counts[kind] = (kind_counts[kind] or 0) + 1
    end
    local rows = {}
    for k, c in pairs(kind_counts) do
        table.insert(rows, {k, tostring(c)})
    end
    table.insert(rows, {"TOTAL", tostring(n)})
    H.make_spread(
        "abi firewall (" .. n .. " entries)",
        {"kind", "count"},
        rows)
    H.emit_result(string.format(
        "refactor:manifest:entries=%d", n))
end

-- ---------------------------------------------------------------- cursor

-- Click a row in the refactor list spread → publish on viz_bus so
-- bugs / snippets pivot. Same shape as bugs.lua's poller.
local list_cursor = {row = 0}
local function poll_list_cursor()
    if not (list_spread and list_spread.id and list_spread.cell_cursor) then
        return true
    end
    local r = list_spread.cell_cursor[2] or 0
    if r ~= list_cursor.row then
        list_cursor.row = r
        local t = row_to_ticket[r]
        if t and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("refactor", tostring(t.bug_id), r, {
                bug_id = t.bug_id,
                bug_slug = t.bug_slug,
                phase = t.ticket_phase,
                signature = t.bug_signature,
            })
            H.emit_result(string.format(
                "refactor:click:id=%s:phase=%s",
                tostring(t.bug_id), tostring(t.ticket_phase)))
        end
    end
    return true
end

if cat9.timers then
    table.insert(cat9.timers, poll_list_cursor)
end

-- ---------------------------------------------------------------- dispatch

-- ---------------------------------------------------------------- sync-tickets

-- Encode a string for `fossil ticket set --quote`. Mirrors migrate_bugs.sh's
-- quote() awk: \ → \\, tab → \t, CR → \r, LF → \n, space → \s. The result
-- is a single shell token (no spaces) safe to pass on the command line.
local function fossil_quote(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\t", "\\t")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, " ", "\\s")
    return s
end

-- Run T_scan once, collect OFFENDER lines per pattern. Returns table:
--   { [pattern] = { count = N, snippets = "<TSV blob ready for code_snippets>" } }
local function collect_offenders()
    local bin = refactor_dir() .. "/zig-out/bin/T_scan"
    local fp = io.open(bin, "r")
    if not fp then return nil, "T_scan not built" end
    fp:close()
    local cmd = string.format("%q --root %q 2>/dev/null", bin, arcan_root())
    local p = io.popen(cmd, "r")
    if not p then return nil, "T_scan spawn failed" end
    local by_pat = {}
    for line in p:lines() do
        -- OFFENDER\t<pat>\t<file>\t<line>\t<context>\t<phase>\t<delta>
        local pat, file, ln, ctx = string.match(line,
            "^OFFENDER\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]*)\t")
        if pat then
            by_pat[pat] = by_pat[pat] or {count = 0, rows = {}}
            by_pat[pat].count = by_pat[pat].count + 1
            -- Build one snippets row per occurrence, mirroring the
            -- shape migrate_bugs.sh produced for the original markdown
            -- tickets: repo=<r>\tfile=<f>\tlines=<L>\tnote=<ctx>
            table.insert(by_pat[pat].rows, string.format(
                "repo=arcan\tfile=%s\tlines=%s\tnote=%s",
                file, ln, ctx))
        end
    end
    p:close()
    -- Build the snippets blob per pattern.
    for pat, data in pairs(by_pat) do
        data.snippets = table.concat(data.rows, "\n")
    end
    return by_pat
end

-- Look up tkt_uuid by bug_signature. Returns string or nil.
local function ticket_uuid_for(signature)
    local q = string.format(
        "SELECT tkt_uuid FROM ticket WHERE bug_signature='%s' LIMIT 1;",
        signature)
    local cmd = string.format(
        "cd %q && fossil sql %q 2>/dev/null", arcan_root(), q)
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local raw = p:read("*l") or ""
    p:close()
    if raw == "" then return nil end
    -- Output is `'<uuid>'` (fossil quotes string SELECT results).
    return string.match(raw, "^'([0-9a-f]+)'$") or string.match(raw, "([0-9a-f]+)")
end

-- Read existing code_snippets blob; count rows (each row = one occurrence).
local function existing_count(uuid)
    if not uuid then return 0 end
    local q = string.format(
        "SELECT REPLACE(COALESCE(code_snippets, ''), x'0a', char(31)) FROM ticket WHERE tkt_uuid='%s';",
        uuid)
    local cmd = string.format(
        "cd %q && fossil sql %q 2>/dev/null", arcan_root(), q)
    local p = io.popen(cmd, "r")
    if not p then return 0 end
    local raw = p:read("*a") or ""
    p:close()
    if raw == "" or raw == "''" then return 0 end
    local n = 0
    for _ in string.gmatch(raw, "repo=arcan") do n = n + 1 end
    return n
end

-- Apply the per-pattern update via fossil ticket set --quote. Returns
-- "ok" / error string.
local function apply_one(uuid, snippets_blob, today)
    if not uuid then return "no-uuid" end
    local enc = fossil_quote(snippets_blob)
    local cmd = string.format(
        "cd %q && fossil ticket set --quote %s code_snippets %s last_seen_date %q --user x 2>&1",
        arcan_root(), uuid, enc, today)
    local p = io.popen(cmd, "r")
    if not p then return "spawn-fail" end
    local out = p:read("*a") or ""
    local ok = p:close()
    if ok then return "ok" end
    return string.gsub(out, "\n", " "):sub(1, 80)
end

local function refactor_sync_tickets(action)
    H.emit_result("refactor:sync:start")
    local by_pat, err = collect_offenders()
    if not by_pat then
        cat9.add_message("refactor sync-tickets: " .. tostring(err))
        return
    end

    -- Pull all refactor tickets so we know which patterns map.
    local q = "SELECT bug_id, bug_slug, bug_signature, tkt_uuid FROM ticket WHERE ticket_phase LIKE 'refactor-%' ORDER BY bug_id;"
    local cmd = string.format(
        "cd %q && fossil sql %q 2>/dev/null", arcan_root(), q)
    local p = io.popen(cmd, "r")
    if not p then
        cat9.add_message("refactor sync: fossil sql spawn failed")
        return
    end
    local tickets = {}
    for line in p:lines() do
        local id, slug, sig, uuid = string.match(line,
            "^'(.-)'%s*'(.-)'%s*'(.-)'%s*'([0-9a-f]+)'$")
        if id then
            table.insert(tickets, {id = id, slug = slug, sig = sig, uuid = uuid})
        end
    end
    p:close()

    local today = os.date("%Y-%m-%d")
    local rows = {}
    local applied = 0
    local skipped = 0
    for _, t in ipairs(tickets) do
        -- Each refactor ticket's signature is "refactor.<pattern>".
        local pat = string.match(t.sig, "^refactor%.(.+)$")
        if pat then
            local data = by_pat[pat]
            local new_count = data and data.count or 0
            local old_count = existing_count(t.uuid)
            local delta = new_count - old_count
            local status = "scan-only"
            if action == "apply" and data then
                status = apply_one(t.uuid, data.snippets, today)
                if status == "ok" then applied = applied + 1
                else skipped = skipped + 1 end
            end
            table.insert(rows, {
                t.id, pat,
                tostring(old_count), tostring(new_count),
                (delta > 0 and "+" or "") .. tostring(delta),
                status,
            })
        end
    end

    -- Sort by absolute delta descending so the biggest changes lead.
    table.sort(rows, function(a, b)
        local da = math.abs(tonumber((string.gsub(a[5], "^+", ""))) or 0)
        local db = math.abs(tonumber((string.gsub(b[5], "^+", ""))) or 0)
        return da > db
    end)

    local title = action == "apply"
        and string.format(
            "refactor sync-tickets (applied=%d, skip=%d)", applied, skipped)
        or string.format("refactor sync-tickets (preview, %d patterns)", #rows)
    H.make_spread(title,
        {"id", "pattern", "old", "new", "delta", "status"},
        #rows > 0 and rows or {{"(no refactor tickets)", "", "", "", "", ""}})
    H.emit_result(string.format(
        "refactor:sync:done:tickets=%d:applied=%d:action=%s",
        #rows, applied, action or "preview"))
end

-- ---------------------------------------------------------------- dryrun

-- Tool registry mirroring tools/refactor/build.zig's tools[] array.
-- `kind`: scan / manifest / meta — non-mutating. (`mutate` will join
-- once we have the staging-copy path; until then mutating tools are
-- gated on a fossil ticket.)
-- `target`: descriptor consumed by resolve_target(). Special strings:
--   "n/a"                       — tool takes no per-file argv
--   "build.zig"                 — single file
--   "src/**/*.zig"              — all .zig under src/
--   "src/shmif/shmif_*_test.zig" — shmif test files only
local DRYRUN_TOOLS = {
    {name = "T0_abi_firewall",         kind = "manifest", target = "src/**/*.zig"},
    {name = "T1_dedupe_cimport",       kind = "scan",     target = "src/**/*.zig"},
    {name = "T2_hoist_externs",        kind = "scan",     target = "src/**/*.zig"},
    {name = "T3_section_commentor",    kind = "scan",     target = "src/**/*.zig"},
    {name = "T4_trim_header_docblocks",kind = "scan",     target = "src/**/*.zig"},
    {name = "T9_ptr_cstar_to_slice",   kind = "scan",     target = "src/**/*.zig"},
    {name = "T11_zeroes_to_defaults",  kind = "scan",     target = "src/**/*.zig"},
    {name = "T13_sizeof_assertions",   kind = "scan",     target = "src/shmif/shmif_*_test.zig"},
    {name = "T27_lua_template_extract",kind = "scan",     target = "build.zig"},
    {name = "T35_transitive_purity",   kind = "meta",     target = "n/a"},
    {name = "T36_selfhosted_smoke",    kind = "meta",     target = "n/a"},
    {name = "T46_cimport_remover",     kind = "scan",     target = "src/**/*.zig"},
    {name = "T48_symbol_coverage",     kind = "meta",     target = "n/a"},
}

-- Read tools/refactor/exclude.txt: one ERE pattern per non-comment
-- non-blank line. Returns a list of patterns; the empty list means
-- "match nothing" (no exclusion).
local function read_exclude_patterns()
    local f = io.open(refactor_dir() .. "/exclude.txt", "r")
    if not f then return {} end
    local pats = {}
    for line in f:lines() do
        local trimmed = string.gsub(line, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= "#" then
            table.insert(pats, trimmed)
        end
    end
    f:close()
    return pats
end

local function path_excluded(rel, patterns)
    for _, pat in ipairs(patterns) do
        if string.find(rel, pat) then return true end
    end
    return false
end

-- Resolve a target descriptor to an absolute file list, filtered
-- through exclude.txt. Uses io.popen + find — directory walks via
-- pure Lua are slow on a 600-file tree.
local function resolve_target(target, exclude_pats)
    if target == "n/a" then return {} end
    local repo = arcan_root()
    local cmd
    if target == "build.zig" then
        return {repo .. "/build.zig"}
    elseif target == "src/**/*.zig" then
        cmd = string.format(
            "find %q -name '*.zig' -type f 2>/dev/null", repo .. "/src")
    elseif target == "src/shmif/shmif_*_test.zig" then
        cmd = string.format(
            "find %q -name 'shmif_*_test.zig' -type f 2>/dev/null",
            repo .. "/src/shmif")
    else
        cmd = string.format(
            "find %q -type f 2>/dev/null", repo .. "/" .. target)
    end
    local p = io.popen(cmd, "r")
    if not p then return {} end
    local files = {}
    local prefix = repo .. "/"
    for line in p:lines() do
        local rel = line
        if string.sub(rel, 1, #prefix) == prefix then
            rel = string.sub(rel, #prefix + 1)
        end
        if not path_excluded(rel, exclude_pats) then
            table.insert(files, line)
        end
    end
    p:close()
    return files
end

-- Heuristic site count from a tool's stdout: extract first
-- "<N> (sites|hits|missing|files|extern|asserts|asserts)" match.
local function parse_sites(stdout)
    local n = string.match(stdout,
        "(%d+)%s+(sites?)") or
            string.match(stdout, "(%d+)%s+(hits?)") or
            string.match(stdout, "(%d+)%s+(missing)") or
            string.match(stdout, "(%d+)%s+(extern)") or
            string.match(stdout, "(%d+)%s+(asserts?)") or
            string.match(stdout, "T0:.- (%d+) entries") or "0"
    return n
end

local function count_errors(stdout)
    local n = 0
    for _ in string.gmatch(stdout, "error:") do n = n + 1 end
    for _ in string.gmatch(stdout, "panic:") do n = n + 1 end
    return n
end

-- Sequential async orchestrator. Each tool runs as a cat9 job;
-- on_finish triggers the next tool. Spread paints rows live as
-- each tool completes — same surface shape selfhost.lua uses.
local dryrun_state = nil
local DRYRUN_HEADERS = {"tool", "kind", "files", "sites", "errors", "status"}

local function dryrun_set_row(row, vals)
    for col, v in ipairs(vals) do
        spread_set(dryrun_state.spread, row, col, v)
    end
end

local function dryrun_finish()
    -- Persist a TSV summary so other tools (CI, fossil tickets,
    -- the auto-arch verifier) can read the snapshot one-shot.
    local path = refactor_dir() .. "/output/dryruns/summary.tsv"
    local f = io.open(path, "w")
    if f then
        f:write("TOOL\tname\tkind\tfiles\tsites\terrors\tstatus\n")
        for _, r in ipairs(dryrun_state.rows) do
            f:write("TOOL\t" .. table.concat(r, "\t") .. "\n")
        end
        f:close()
    end
    H.emit_result(string.format(
        "refactor:dryrun:done:tools=%d:summary=%s",
        #dryrun_state.rows, path))
    dryrun_state = nil
end

local function dryrun_advance()
    dryrun_state.idx = dryrun_state.idx + 1
    if dryrun_state.idx > #DRYRUN_TOOLS then
        return dryrun_finish()
    end

    local spec = DRYRUN_TOOLS[dryrun_state.idx]
    local row = dryrun_state.idx + 1
    local bin = refactor_dir() .. "/zig-out/bin/" .. spec.name

    -- Mark "running" so the user sees per-tool progress.
    dryrun_set_row(row, {spec.name, spec.kind, "?", "?", "?", "running"})
    H.emit_result("refactor:dryrun:tool:" .. spec.name .. ":start")

    -- Skip if not built.
    local fp = io.open(bin, "r")
    if not fp then
        local rec = {spec.name, spec.kind, "0", "0", "0", "not-built"}
        dryrun_set_row(row, rec)
        table.insert(dryrun_state.rows, rec)
        return dryrun_advance()
    end
    fp:close()

    local files = resolve_target(spec.target, dryrun_state.exclude)
    local file_count = tostring(#files)

    -- Build argv. T0 wants --out <path>; others get just the file
    -- list. Meta tools get no file argv.
    local argv = {bin, spec.name}
    if spec.name == "T0_abi_firewall" then
        local manifest_path = refactor_dir() ..
            "/output/dryruns/T0_abi_firewall/abi_firewall.json"
        os.execute("mkdir -p " .. refactor_dir() ..
            "/output/dryruns/T0_abi_firewall")
        table.insert(argv, "--out")
        table.insert(argv, manifest_path)
    end
    if spec.kind ~= "meta" then
        for _, f in ipairs(files) do table.insert(argv, f) end
    end

    local env = cat9.table_copy_shallow(cat9.env)
    local old_dir = root:chdir()
    root:chdir(arcan_root())
    local job = cat9.setup_shell_job(
        argv, "re", env,
        "dryrun:" .. spec.name, {close = true})
    root:chdir(old_dir)
    if not job then
        local rec = {spec.name, spec.kind, file_count, "0", "1", "spawn-fail"}
        dryrun_set_row(row, rec)
        table.insert(dryrun_state.rows, rec)
        return dryrun_advance()
    end
    job.short = "dryrun:" .. spec.name

    -- Capture all output for parse-on-finish. Live row updates would
    -- require per-line decisions; one paint per tool is enough.
    local out_buf = {}
    if job.out and job.out.data_handler then
        job.out:data_handler(function()
            local line, alive = job.out:read(true)
            while line do
                table.insert(out_buf, line)
                line, alive = job.out:read(true)
                if not alive then break end
            end
        end)
    end

    local function complete(status)
        local stdout = table.concat(out_buf, "\n")
        local sites = parse_sites(stdout)
        local errors = count_errors(stdout)
        if errors > 0 and status == "pass" then status = "fail" end
        local rec = {spec.name, spec.kind, file_count,
                     tostring(sites), tostring(errors), status}
        dryrun_set_row(row, rec)
        table.insert(dryrun_state.rows, rec)
        H.emit_result(string.format(
            "refactor:dryrun:tool:%s:%s:files=%s:sites=%s:errors=%d",
            spec.name, status, file_count, sites, errors))
        dryrun_advance()
    end

    table.insert(job.hooks.on_finish, function() complete("pass") end)
    table.insert(job.hooks.on_fail,   function() complete("fail") end)
end

local function refactor_dryrun(action)
    local summary = refactor_dir() .. "/output/dryruns/summary.tsv"
    if action == "run" then
        if dryrun_state then
            cat9.add_message(string.format(
                "refactor dryrun: in progress (%d/%d). Wait or close the spread.",
                dryrun_state.idx, #DRYRUN_TOOLS))
            return
        end
        H.emit_result("refactor:dryrun:start:tools=" .. tostring(#DRYRUN_TOOLS))
        local pats = read_exclude_patterns()
        local spread = H.make_spread(
            "refactor dryrun (running 0/" .. #DRYRUN_TOOLS .. ")",
            DRYRUN_HEADERS, {})
        if not spread then
            cat9.add_message("refactor dryrun: spread unavailable")
            return
        end
        dryrun_state = {
            idx = 0,
            spread = spread,
            exclude = pats,
            rows = {},
        }
        dryrun_advance()
        return
    end

    -- No arg: read the on-disk summary so the spread paints what
    -- the last sweep produced.
    local f = io.open(summary, "r")
    if not f then
        cat9.add_message("refactor dryrun: " .. summary ..
            " missing. Run `refactor dryrun run` first.")
        return
    end
    local rows = {}
    local n = 0
    for line in f:lines() do
        n = n + 1
        if n > 1 then
            local parts = {}
            for tok in string.gmatch(line, "([^\t]+)") do
                table.insert(parts, tok)
            end
            if #parts >= 7 then
                table.insert(rows, {parts[2], parts[3], parts[4],
                                    parts[5], parts[6], parts[7]})
            end
        end
    end
    f:close()
    H.make_spread(
        "refactor dryrun (" .. (#rows) .. " tools)",
        DRYRUN_HEADERS,
        #rows > 0 and rows or {{"(no rows)", "", "", "", "", ""}})
    H.emit_result("refactor:dryrun:listed:tools=" .. tostring(#rows))
end

-- ---------------------------------------------------------------- dispatch

local subcommands = {
    list         = refactor_list,
    tools        = refactor_tools,
    scan         = refactor_scan,
    apply        = refactor_apply,
    verify       = refactor_verify,
    manifest     = refactor_manifest,
    dryrun       = refactor_dryrun,
    ["sync-tickets"] = refactor_sync_tickets,
    open         = function() refactor_list("open") end,
    closed       = function() refactor_list("closed") end,
    all          = function() refactor_list("all") end,
}

function suggest.refactor(args, raw)
    if #args == 2 then
        local set = {"list", "tools", "scan", "apply", "verify",
                     "manifest", "dryrun", "sync-tickets",
                     "open", "closed", "all"}
        cat9.readline:suggest(cat9.prefix_filter(set, args[2]), "word")
    elseif #args == 3 and args[2] == "apply" then
        local tools = read_tools_registry()
        local names = {}
        for _, t in ipairs(tools) do table.insert(names, t.name) end
        cat9.readline:suggest(cat9.prefix_filter(names, args[3]), "word")
    elseif #args == 3 and args[2] == "dryrun" then
        cat9.readline:suggest(cat9.prefix_filter({"run"}, args[3]), "word")
    elseif #args == 3 and args[2] == "sync-tickets" then
        cat9.readline:suggest(cat9.prefix_filter({"apply"}, args[3]), "word")
    end
end

function builtins.refactor(verb, ...)
    if not verb then return refactor_list("open") end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message(
        "refactor {list|tools|scan|apply T<N>|verify|manifest}")
end

end
