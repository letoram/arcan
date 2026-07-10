return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

-- Emit a shmif-native MESSAGE event (visible to autorun.lua's
-- extevh wrap → shmon.log) carrying a builtin's result. Use for
-- shmif-native verification by the harness — avoids post-mortem
-- /tmp text-file reads.
--
-- ALSO mirrors to a sidecar log file so the harness has a feedback
-- channel even when arcan was started without ARCAN_SHMIF_MONITOR
-- (the common case during normal user sessions, where the autorun
-- extevh wrap is dormant). The sidecar path is settable via the
-- CAT9_EMIT_LOG env var; default below is the persistent staging
-- directory the dev workflow already uses.
H.EMIT_LOG_PATH = (cat9.env and cat9.env.CAT9_EMIT_LOG)
    or os.getenv("CAT9_EMIT_LOG")
    or "/home/x/.local/share/zig-sh-testing/cat9_emits.log"

function H.emit_result(tag)
    pcall(function()
        root:message("test:dev_result:" .. tostring(tag))
        root:refresh()
    end)
    pcall(function()
        local f = root:fopen(H.EMIT_LOG_PATH, "a")
        if not f then return end
        local ts = "?"
        if os and os.date then ts = os.date("%Y-%m-%dT%H:%M:%S") end
        f:write(string.format("%s %s\n", ts, tostring(tag)))
        f:flush(-1)
        f:close()
    end)
end

-- Cross-view selection bus — senseye's "cursor in hex highlights the
-- pointcloud cluster" pattern, generalized over our spread substrate.
-- Any view (translator) publishes (sensor, key) when its user-cursor
-- moves to a new row. Any view subscribes via H.viz_bus.subscribe(fn)
-- and receives (sensor, key, row, payload) on every publish; it then
-- decides what to do — typically: scan its own rows for matches and
-- mark them with a leading ► glyph in column 1.
--
-- ## Canonical payload keys (the contract)
--
-- Publishers MUST use these keys for these meanings; subscribers MAY
-- match on any combination. Without a contract, every cross-view
-- linkage needs ad-hoc field-name agreements between publisher and
-- subscriber. With this contract, any view can be added to either
-- side without touching the others.
--
-- | key            | type        | meaning                            |
-- |----------------|-------------|------------------------------------|
-- | name           | string      | step name / compile unit identifier|
-- | file           | string      | source file path (absolute pref)   |
-- | line           | number      | source line number                 |
-- | column         | number      | source column number               |
-- | severity       | string      | "error" / "warning" / "note"       |
-- | bug_id         | string      | fossil ticket UUID or bug_id e.g. 0001 |
-- | snippet_id     | string      | "<bug_id>:<idx>" (e.g. "0001:2")   |
-- | addr_range     | {start,end} | hex address range, integers        |
-- | disasm_target  | string      | absolute path to .o for disasm     |
-- | disasm_func    | string      | symbol name within target          |
-- | hilbert_xy     | {x,y}       | hilbert grid coordinates           |
-- | bucket_id      | number      | time-view bucket id                |
-- | round_id       | number      | auto-arch round id                 |
-- | fitness        | number      | auto-arch round fitness 0..N       |
--
-- Sensors (the `sensor` arg to publish) follow `<source>.<view>`:
-- `compile.units`, `compile.errors`, `selfhost.errors`, `bugs`,
-- `snippets`, `hilbert`, `time`, `metrics`, `auto-arch.round`.
H.viz_bus = H.viz_bus or {
    selection = {sensor = nil, key = nil, row = 0, payload = nil},
    subscribers = {},
}

-- Runtime introspection — code can iterate this to discover the
-- canonical key set without re-reading the comment block.
--
-- bug 0029: keys are organised by family.  When a publisher emits
-- under a sensor (e.g. `build.atlas`, `fossil`, `edit`, `ticket`),
-- subscribers know which key set to look at.  Adding a new family
-- means: append keys here, update the publisher, update at least
-- one subscriber's match logic (status spread parse_emit and the
-- relevant viz pane).
H.viz_bus.PAYLOAD_KEYS = {
    -- core (existing)
    name           = "step name / compile unit identifier",
    file           = "source file path",
    line           = "source line number",
    column         = "source column number",
    severity       = "error / warning / note",
    bug_id         = "fossil ticket UUID or bug_id like 0001",
    snippet_id     = "<bug_id>:<idx>",
    addr_range     = "{start, end} hex addr ints",
    disasm_target  = "absolute path to .o for disasm",
    disasm_func    = "symbol name within target",
    hilbert_xy     = "{x, y} hilbert grid coords",
    bucket_id      = "time-view bucket id",
    round_id       = "auto-arch round id",
    fitness        = "auto-arch round fitness",

    -- build family (bug 0023 publisher: zigbuild.lua;
    -- subscribers: atlas long-line, hilbert, status spread)
    build_unit         = "compile unit name (target / .o)",
    build_state        = "queued|cached|running|building|ok|built|err|fail",
    build_exit         = "process exit code on err (0 otherwise)",
    build_dur_ms       = "duration ms when known",
    build_target       = "top-level zig build target",
    build_steps_total  = "total step count for the build",
    build_errors_n     = "diagnostic count at end-of-build",

    -- fossil family (bug 0025 publisher: fossil builtin;
    -- subscribers: hilbert/memcloud blink, status spread)
    fossil_sha         = "short SHA of commit",
    fossil_path        = "path of dirty/changed file",
    fossil_dirty       = "boolean — file is dirty",
    fossil_added       = "lines added (numstat)",
    fossil_removed     = "lines removed (numstat)",
    fossil_msg         = "commit message (one-line)",

    -- edit family (cat9 view edit / edit builtin emits;
    -- subscribers: hilbert/memcloud blink, status spread, source pane)
    edit_pat           = "substitution pattern (lua-pattern form)",
    edit_changes       = "int — applied substitution count",
    edit_path          = "path of file edited",

    -- ticket family (bug 0030 publisher: ticket flips via fossil;
    -- subscribers: bug spread, status spread)
    ticket_uuid        = "fossil ticket uuid",
    ticket_status_from = "prior status",
    ticket_status_to   = "new status",
    ticket_bug_id      = "fossil bug_slug e.g. 0036-foo",
}

function H.viz_bus.subscribe(fn)
    table.insert(H.viz_bus.subscribers, fn)
end

-- Autoexec hook: if CAT9_DEV_AUTOEXEC env var is set, fire that command
-- once on the first timer tick after dev/ builtins have finished loading.
-- Lets a remote driver (like the parent process spawning this lash) hand
-- the user a window already showing the bugs spread / dashboard / etc.
do
    local autoexec = (cat9.env and cat9.env.CAT9_DEV_AUTOEXEC) or
                     os.getenv("CAT9_DEV_AUTOEXEC")
    if autoexec and autoexec ~= "" and not H.autoexec_fired then
        local fired = false
        local function autoexec_tick()
            if fired then return false end -- remove self after firing
            -- Wait for readline to be available — cat9 sets it during
            -- setup_window after the first refresh.
            if not (cat9.readline and cat9.parse_string) then
                return true
            end
            fired = true
            H.autoexec_fired = true
            cat9.parse_string(cat9.readline, autoexec)
            H.emit_result("dev:autoexec:cmd=" .. autoexec)
            return false -- one-shot
        end
        cat9.timers = cat9.timers or {}
        table.insert(cat9.timers, autoexec_tick)
    end
end

function H.viz_bus.publish(sensor, key, row, payload)
    H.viz_bus.selection.sensor = sensor
    H.viz_bus.selection.key = key
    H.viz_bus.selection.row = row or 0
    H.viz_bus.selection.payload = payload
    -- Mirror to shmif MESSAGE so the harness can verify and so future
    -- frameservers driven via shmif (e.g. afsrv_trigram, afsrv_disasm)
    -- can subscribe through the autorun extevh hook the same way.
    H.emit_result(string.format("viz:select:sensor=%s:row=%d:key=%s",
        tostring(sensor or "?"), row or 0, tostring(key or "")))
    for _, fn in ipairs(H.viz_bus.subscribers) do
        pcall(fn, sensor, key, row, payload)
    end
end

H.MAX_LINES = 10000
H.MAX_FILES = 5000

local function escape_cell(v)
    local s = tostring(v)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "[\r\n]", " ")
    return string.format('"%s"', s)
end
H.escape_cell = escape_cell

function H.lua_pattern_escape(s)
    return (string.gsub(s, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

function H.make_spread(title, headers, rows)
    local prev_builtin = cat9.builtin_name
    cat9.builtins["builtin"]("spreadsheet")
    cat9.parse_string(cat9.readline, "new")
    local spread = cat9.latestjob
    if not spread then
        cat9.add_message("dev: spreadsheet builtin not available")
        cat9.builtins["builtin"](prev_builtin)
        return nil
    end
    spread.short = title or "spread"

    if headers and #headers > 0 then
        local hp = {}
        for _, h in ipairs(headers) do
            table.insert(hp, escape_cell(h))
        end
        cat9.parse_string(cat9.readline,
            string.format("insert #%d 1 %s", spread.id, table.concat(hp, " ")))
    end

    if rows then
        for i, row in ipairs(rows) do
            local parts = {}
            for _, v in ipairs(row) do
                table.insert(parts, escape_cell(v))
            end
            cat9.parse_string(cat9.readline,
                string.format("insert #%d %d %s",
                    spread.id, i + 1, table.concat(parts, " ")))
        end
    end

    -- Auto-size columns to longest cell content (header or any row).
    -- Mirrors the spreadsheet builtin's get_window_col_width logic but
    -- is called proactively after population, so the user doesn't have
    -- to click each column header to expand. Caps at MAX_AUTO_COL so
    -- one runaway cell doesn't push everything off screen — beyond that
    -- the user can still hand-toggle via column-header click.
    local MIN_COL = 6   -- mirrors builtin_cfg.min_col_width default
    local MAX_AUTO = 48
    spread.column_sizes = spread.column_sizes or {}
    if spread.cells and root and root.utf8_len then
        local ncols = headers and #headers or 0
        for col = 1, ncols do
            local cw = MIN_COL
            for row = 1, (#rows or 0) + 1 do
                local cell = spread.cells[row] and spread.cells[row][col]
                if cell and cell.label then
                    local w = root:utf8_len(cell.label)
                    if w > cw then cw = w end
                end
            end
            if cw > MIN_COL then
                if cw > MAX_AUTO then cw = MAX_AUTO end
                spread.column_sizes[col] = cw + 1
            end
        end
        if cat9.flag_dirty then cat9.flag_dirty(spread) end
    end

    cat9.builtins["builtin"](prev_builtin)
    return spread
end

function H.read_file_lines(path, max_lines)
    max_lines = max_lines or H.MAX_LINES
    local f = root:fopen(path, "r")
    if not f then
        return nil, "couldn't open " .. tostring(path)
    end
    -- root:fopen "r" + f:read(true) on this build returns *all* the
    -- file contents in one call (or arbitrary chunk boundaries on
    -- larger files), not one line per call.  Buffer chunks and split
    -- on "\n" ourselves so callers (wc/grep/tail/read) get a real
    -- line table instead of a single-element giant-string table.
    local lines = {}
    local pending = ""
    local truncated = false

    local function emit(s)
        table.insert(lines, s)
        if #lines >= max_lines then
            table.insert(lines, "(truncated at " .. max_lines .. " lines)")
            truncated = true
        end
    end

    local chunk, alive = f:read(true)
    while chunk and not truncated do
        if #chunk == 0 then break end
        pending = pending .. chunk
        local start = 1
        while true do
            local nl = pending:find("\n", start, true)
            if not nl then break end
            emit(pending:sub(start, nl - 1))
            if truncated then break end
            start = nl + 1
        end
        pending = pending:sub(start)
        if not alive then break end
        chunk, alive = f:read(true)
    end
    f:close()
    if truncated then return lines, "truncated" end
    if #pending > 0 then emit(pending) end
    return lines, nil
end

function H.write_file(path, content)
    local f = root:fopen(path, "w")
    if not f then
        return nil, "couldn't open " .. tostring(path) .. " for write"
    end
    local bytes
    if type(content) == "table" then
        local out = {}
        for _, line in ipairs(content) do
            table.insert(out, line)
            if not line:find("\n$") then
                table.insert(out, "\n")
            end
        end
        local s = table.concat(out, "")
        bytes = #s
        f:write(s)
    else
        local s = tostring(content)
        if not s:find("\n$") then s = s .. "\n" end
        bytes = #s
        f:write(s)
    end
    f:flush(-1)
    f:close()
    return bytes, nil
end

function H.list_dir(path)
    local glob_pat = path
    if not glob_pat:find("/$") then glob_pat = glob_pat .. "/" end
    glob_pat = glob_pat .. "*"

    local ioh = root:fglob(glob_pat)
    if not ioh then
        return nil, "fglob: rejected " .. tostring(path)
    end
    ioh:lf_strip(true, "\0")

    local out = {}
    local line, alive = ioh:read()
    while line do
        if line ~= "" then
            local name = string.match(line, "([^/]+)$") or line
            table.insert(out, {full = line, name = name})
            if #out >= H.MAX_FILES then
                ioh:close()
                return out, "truncated"
            end
        end
        line, alive = ioh:read()
        if not alive then break end
    end
    ioh:close()
    return out, nil
end

function H.walk_dir(path, opts, cb)
    opts = opts or {}
    local max_depth = opts.max_depth or 10
    local count = 0

    local function recurse(dir, depth)
        if depth > max_depth or count >= H.MAX_FILES then return end
        local entries = H.list_dir(dir)
        if not entries then return end
        for _, ent in ipairs(entries) do
            local st = root.fstatus and root:fstatus(ent.full) or {}
            ent.is_dir = st.kind == "directory" or st.dir
            ent.size = st.size
            ent.mtime = st.mtime
            cb(ent)
            count = count + 1
            if ent.is_dir then
                recurse(ent.full, depth + 1)
            end
            if count >= H.MAX_FILES then return end
        end
    end

    recurse(path, 0)
    return count
end

function H.parse_zig_step_line(s)
    local idx, total, name = string.match(s, "^%[(%d+)/(%d+)%]%s+(.+)$")
    if idx then
        return {idx = tonumber(idx), total = tonumber(total), name = name}
    end
    return nil
end

function H.parse_zig_diag_line(s)
    local file, line, col, sev, msg =
        string.match(s, "^([^:]+):(%d+):(%d+):%s*(%w+):%s*(.*)$")
    if file and (sev == "error" or sev == "warning" or sev == "note") then
        return {
            file = file,
            line = tonumber(line),
            col = tonumber(col),
            severity = sev,
            message = msg,
        }
    end
    return nil
end

-- Stage-B parser: `BUILD\tSTEP\t<idx>\t<total>\t<name>\t<status>\t<dur_ms>`
-- and `BUILD\tDIAG\t<sev>\t<file>\t<line>\t<col>\t<msg>` and
-- `BUILD\tBUILD\t<status>\t<steps>\t<errors>` lines emitted by the
-- patched fork's lib/std/Build/ShmifProgress.zig when zig is invoked
-- with `--shmif-tagged-progress`. Returns one of:
--   {kind="step",  idx, total, name, status, dur_ms}
--   {kind="diag",  severity, file, line, col, message}
--   {kind="build", status, steps, errors}
--   nil on no match
function H.parse_zig_tagged_line(s)
    if not s or string.sub(s, 1, 6) ~= "BUILD\t" then return nil end
    -- Tab-split into ≤8 fields
    local parts = {}
    local idx = 1
    local prev = 7  -- index after first "BUILD\t"
    while idx <= 8 do
        local nxt = string.find(s, "\t", prev, true)
        if not nxt then
            table.insert(parts, string.sub(s, prev))
            break
        end
        table.insert(parts, string.sub(s, prev, nxt - 1))
        prev = nxt + 1
        idx = idx + 1
    end
    local kind = parts[1]
    if kind == "STEP" and #parts >= 6 then
        return {
            kind = "step",
            idx = tonumber(parts[2]),
            total = tonumber(parts[3]),
            name = parts[4] or "",
            status = parts[5] or "",
            dur_ms = tonumber(parts[6]) or 0,
        }
    elseif kind == "DIAG" and #parts >= 6 then
        return {
            kind = "diag",
            severity = parts[2] or "",
            file = parts[3] or "",
            line = tonumber(parts[4]) or 0,
            col = tonumber(parts[5]) or 0,
            message = parts[6] or "",
        }
    elseif kind == "BUILD" and #parts >= 4 then
        return {
            kind = "build",
            status = parts[2] or "",
            steps = tonumber(parts[3]) or 0,
            errors = tonumber(parts[4]) or 0,
        }
    end
    return nil
end

function H.parse_objdump_line(s)
    local addr_hex, fname = string.match(s, "^([0-9a-fA-F]+)%s+<([^>]+)>:%s*$")
    if addr_hex then
        return {kind = "func", name = fname, addr = "0x" .. addr_hex}
    end

    local a, b, c = string.match(s, "^%s*([0-9a-fA-F]+):%s+([0-9a-fA-F][0-9a-fA-F %s]-)%s%s+(.+)$")
    if a then
        return {
            kind = "addr",
            addr = "0x" .. a,
            bytes = string.gsub(b or "", "%s+$", ""),
            asm = c,
        }
    end

    local sf, sl = string.match(s, "^(/[^:]+):(%d+)%s*$")
    if sf then
        return {kind = "src", file = sf, line = tonumber(sl), content = ""}
    end

    return nil
end

H.edits = H.edits or {}
function H.register_edit(path, action)
    local now_str = "now"
    if os and os.date then now_str = os.date("%H:%M:%S") end
    local now_ts = 0
    if os and os.time then now_ts = os.time() end
    H.edits[path] = {
        path = path,
        action = action,
        last_op_at = now_str,
        last_op_ts = now_ts,
    }
    -- Auto-fossil-commit when running inside an auto-arch round.
    -- Orchestrator sets H.in_round_context = "round_<N>" before
    -- spawning the agent; we leave it nil during normal sessions.
    if H.in_round_context then
        H.fossil_commit(path, action)
    end
end

-- ============================================================================
-- Fossil ledger helpers
-- ============================================================================
--
-- During an auto-arch round, every cat9 native edit is committed
-- onto the round's fossil branch. The branch lives until the
-- verifier accepts (merge into trunk) or rejects (close branch).
-- Outside a round, we no-op — commits during normal development
-- shouldn't be auto-fired by every edit.
--
-- Repo handle map. Mirror of docs/repo-handles.md but reachable from Lua.
H.fossil_repos = H.fossil_repos or {
    arcan    = "/home/x/next/arcan",
    ["zig-fork"] = "/home/x/.local/src/zig-0.15.2-fork",
}

-- Resolve a path to the (repo_root, repo_name, relative_path) tuple,
-- or nil if the path doesn't fall under any tracked repo.
function H.fossil_repo_for(path)
    if not path then return nil end
    -- Always resolve to absolute path for prefix matching.
    local abs = path
    if string.sub(abs, 1, 1) ~= "/" then
        abs = (H.fossil_repos.arcan or "") .. "/" .. abs
    end
    local best_name, best_root = nil, nil
    for name, root in pairs(H.fossil_repos) do
        if string.sub(abs, 1, #root + 1) == root .. "/" then
            if not best_root or #root > #best_root then
                best_name, best_root = name, root
            end
        end
    end
    if not best_root then return nil end
    return {
        repo  = best_name,
        root  = best_root,
        rel   = string.sub(abs, #best_root + 2),
        abs   = abs,
    }
end

H.fossil_commits = H.fossil_commits or {}

-- Run `fossil commit -m '…' <rel-path>` inside the appropriate repo.
-- Honors H.in_round_context (sets AUTO_ARCH_ROUND env so the
-- pre-commit sandbox hook fires) and H.current_bug (for the
-- commit-message template). On failure, records the error in
-- H.fossil_commits but does not raise — fossil-commit failure
-- shouldn't break the user's edit.
function H.fossil_commit(path, action)
    local info = H.fossil_repo_for(path)
    if not info then
        H.emit_result(string.format("fossil:err:path=%s:reason=not_in_known_repo", tostring(path)))
        return false, "not in a known repo"
    end
    local round = H.in_round_context or "manual"
    local bug = H.current_bug or "none"
    local msg = string.format(
        "round %s: bug %s: %s %s",
        round, tostring(bug), action or "edit", info.rel)
    -- Shell-escape single quotes by ending the quoted string,
    -- inserting an escaped quote, and resuming.
    local esc_msg = string.gsub(msg, "'", "'\\''")
    local esc_path = string.gsub(info.rel, "'", "'\\''")
    local cmd = string.format(
        "AUTO_ARCH_ROUND='%s' cd '%s' && fossil commit --no-warnings -m '%s' '%s' 2>&1",
        round, info.root, esc_msg, esc_path)
    local p = io.popen(cmd, "r")
    if not p then
        H.emit_result("fossil:err:reason=popen_failed")
        return false, "popen failed"
    end
    local out = p:read("*a") or ""
    local ok, _, ec = p:close()
    table.insert(H.fossil_commits, {
        round = round, bug = bug, repo = info.repo,
        path = info.rel, action = action, ts = os.time and os.time() or 0,
        ok = ok and true or false, exit_code = ec, stdout = out,
    })
    if ok then
        H.emit_result(string.format(
            "fossil:commit:ok:repo=%s:path=%s:round=%s:bug=%s",
            info.repo, info.rel, round, bug))
        return true
    end
    H.emit_result(string.format(
        "fossil:commit:fail:repo=%s:path=%s:exit=%s",
        info.repo, info.rel, tostring(ec)))
    return false, out
end

-- Begin / end a round context. The orchestrator (or a manual driver)
-- calls these around an edit-heavy session. Inside `enter_round`:
--   * H.in_round_context is the round id
--   * H.fossil_commit auto-fires on every register_edit
-- Outside, behavior reverts to plain register_edit (no commits).
function H.enter_round(round_id, bug_id)
    H.in_round_context = round_id
    H.current_bug = bug_id
    H.emit_result(string.format("round:enter:id=%s:bug=%s",
        tostring(round_id), tostring(bug_id)))
end

function H.exit_round()
    local prev = H.in_round_context
    H.in_round_context = nil
    H.current_bug = nil
    H.emit_result(string.format("round:exit:id=%s", tostring(prev)))
end

end
