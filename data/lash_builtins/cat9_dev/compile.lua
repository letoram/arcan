-- compile <target> [-Dopt=val ...]
--
-- User-facing wrapper for `zig build` that produces two clickable
-- spreadsheets — Steps (row per zig step, status updates as zig
-- prints `[N/M]` progress lines) and Errors (row per diagnostic,
-- created lazily on the first error).
--
-- Stage A1 (this file): regex-parse zig stdout/stderr.
-- Stage A2 (deferred): consume `BUILD\tSTEP\t…` tagged stderr from
--   the patched fork (lib/std/Build/ShmifProgress.zig).
-- Stage A3 (deferred): consume EVENT_TARGET_MESSAGE shmif events
--   from the fork's pure-Zig Shmif.zig client.
--
-- Auto-detection picks the latest available stage; for now it's just
-- A1. Emits `test:dev_result:compile:{ok|fail}:target=…` on finish.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.compile = "compile <target> — live Steps + Errors spreadsheets"

local srcdir = "/home/x/next/arcan"
local zigbin = "/home/x/.local/src/zig-0.15.2-fork/zig-out/bin/zig"

local function spread_set(spread, row, col, value)
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %s",
            spread.id, row, col, H.escape_cell(value)))
end

-- Senseye-spirited cell glyphs: shape conveys kind, length conveys
-- magnitude. The eye scans patterns first and reads text second.
local function status_glyph(s)
    if s == "running" or s == "start" then return "▶" end
    if s == "ok" then return "✓" end
    if s == "fail" then return "✗" end
    if s == "skip" then return "~" end
    return "?"
end

-- Step-name kind → left-edge prefix glyph. Build graphs are mostly
-- WriteFile noise punctuated by compile/link bursts; the prefix lets
-- you skim the column for the burst.
local function name_glyph(name)
    if not name or name == "" then return "  " end
    if name == "WriteFile" or string.sub(name, 1, 10) == "WriteFile " then
        return "□ "
    end
    if string.sub(name, 1, 12) == "compile obj " then return "■ " end
    if string.sub(name, 1, 12) == "compile exe " then return "▣ " end
    if string.sub(name, 1, 12) == "compile lib " then return "▦ " end
    if string.sub(name, 1, 8) == "install " then return "◆ " end
    return "· "
end

-- Log-scaled horizontal block-fill bar. Each whole `█` is ~1.33
-- decades (1 → ▏, 10 → ▊, 100 → █▌, 1000 → ██▏, 10000 → ███).
-- Capped at 32 eighths so the column doesn't blow up — the
-- spreadsheet auto-clips, click the column header to expand.
local function bar_only(n)
    if not n or n <= 0 then return "" end
    local eighths = math.floor((math.log(n) / math.log(10)) * 6)
    if eighths < 1 then eighths = 1 end
    if eighths > 32 then eighths = 32 end
    local full = math.floor(eighths / 8)
    local rem  = eighths - full * 8
    local part = ({"", "▏", "▎", "▍", "▌", "▋", "▊", "▉"})[rem + 1] or ""
    return string.rep("█", full) .. part
end

local function dur_bar(ms)
    if not ms or ms <= 0 then return "—" end
    return string.format("%s %dms", bar_only(ms), ms)
end

local function count_bar(n)
    if not n or n <= 0 then return "—" end
    return string.format("%s %d", bar_only(n), n)
end

-- The spread IS the build system. One global `compile units` spread
-- accumulates every compilation unit ever seen across every target
-- and every invocation. Rows survive across builds — re-running a
-- compile mutates known rows (status, dur, seen-count) and only
-- inserts new ones for genuinely new step names. Untouched rows
-- stick around as the historical record of what's been built.
local units_spread = nil
local units_by_name = {}     -- step name → row in spread
local units_count = 0        -- total rows ever inserted
local units_seen_count = {}  -- row → total times seen across all builds
local units_last_gen = {}    -- row → most recent build gen that touched it
local units_status = {}      -- row → latest status string (for foreign views)
local units_build_gen = 0    -- monotonic counter; bumped per `compile`

-- Reverse maps for selection bus + foreign views. Declared up here
-- so H.units_state below closes over the right upvalues.
local row_to_unit_name = {}    -- units row → step name
local row_to_diag_key  = {}    -- errors row → diag key

-- Public reader for views (hilbert, future translators) that want the
-- current units state without going through the spread cells.
H.units_state = function()
    return {
        count = units_count,
        status_at = function(row) return units_status[row] end,
        name_at = function(row) return row_to_unit_name[row] end,
    }
end

local function ensure_units_spread()
    if units_spread and units_spread.id then return units_spread end
    units_spread = H.make_spread(
        "compile units",
        {"#", "status", "name", "duration", "seen", "last"},
        {}
    )
    return units_spread
end

local function timestamp()
    if os and os.date then return os.date("%H:%M:%S") end
    return "?"
end

-- Errors are also persistent and cross-build. Keyed by
-- "<file>:<line>:<col>:<severity>:<msg-hash>" so the same diagnostic
-- across builds occupies one row that pops every time the compiler
-- still emits it. Touched-this-build → bright; not seen this build →
-- the row's status flips to "stale" and the cell fades from the eye
-- until either re-seen (returns to bright) or the user clears it.
-- That's the spread doing its tracker job: the cell IS the bug, and
-- the cell stays until either the diagnostic goes away (build clean)
-- or the user explicitly clears it.
local errors_spread = nil
local errors_by_key = {}    -- diag-key → row
local errors_count = 0
local errors_last_gen = {}  -- row → most recent build gen that re-saw it
local errors_seen_count = {}

local function ensure_errors_spread()
    if errors_spread and errors_spread.id then return errors_spread end
    errors_spread = H.make_spread(
        "compile errors",
        {"status", "severity", "file", "line", "col", "message", "seen", "last"},
        {}
    )
    return errors_spread
end

local function diag_key(d)
    return string.format("%s:%d:%d:%s:%s",
        d.file or "?", d.line or 0, d.col or 0,
        d.severity or "?", d.message or "")
end

-- Time-view spread (senseye-applied step 2). Rows = 1-minute buckets,
-- columns = event-kind counts rendered as log-scaled block-fill bars.
-- "This minute saw a burst of 50 steps and 2 errors; the next was
-- quiet" pops without the user reading any number. Buckets accumulate
-- across all `compile` invocations — same persistence pattern as
-- units/errors.
local time_spread = nil
local time_bucket_secs = 60
local time_buckets = {}        -- bucket_id → {steps, diags, ok, fail}
local time_bucket_to_row = {}  -- bucket_id → row in spread
local time_buckets_count = 0

local function ensure_time_spread()
    if time_spread and time_spread.id then return time_spread end
    time_spread = H.make_spread(
        "compile timeline",
        {"time", "steps", "diags", "ok", "fail", "total"},
        {}
    )
    return time_spread
end

local function bucket_for_now()
    if not (os and os.time) then return 0 end
    return math.floor(os.time() / time_bucket_secs)
end

local function bucket_label(bid)
    if not (os and os.date) then return tostring(bid) end
    return os.date("%H:%M", bid * time_bucket_secs)
end

local function time_record(kind)
    local spread = ensure_time_spread()
    if not spread then return end
    local bid = bucket_for_now()
    local row = time_bucket_to_row[bid]
    local b = time_buckets[bid]
    if not b then
        b = {steps = 0, diags = 0, ok = 0, fail = 0}
        time_buckets[bid] = b
        time_buckets_count = time_buckets_count + 1
        row = time_buckets_count + 1
        time_bucket_to_row[bid] = row
        spread_set(spread, row, 1, bucket_label(bid))
    end
    b[kind] = (b[kind] or 0) + 1
    spread_set(spread, row, 2, count_bar(b.steps))
    spread_set(spread, row, 3, count_bar(b.diags))
    spread_set(spread, row, 4, count_bar(b.ok))
    spread_set(spread, row, 5, count_bar(b.fail))
    spread_set(spread, row, 6, count_bar(b.steps + b.diags + b.ok + b.fail))
end

-- Selection-bus publisher. Per-spread polling on cat9.timers picks
-- up cell_cursor changes and broadcasts (sensor, key, row, payload).
-- Subscribers (cross-spread highlighters, future shmif translators)
-- pattern-match on the payload to decide what to highlight.
local cursor_state = {
    units = {col = 0, row = 0},
    errors = {col = 0, row = 0},
}

-- Cross-view highlight state. When the bus fires, each owned spread
-- looks for rows whose name/file column contains the key as a
-- substring and prefixes column 1 with `►`. Previously-highlighted
-- rows get the prefix cleared. Substring match is loose on purpose:
-- click "compile obj utf8" in units → errors rows mentioning utf8
-- pop; click an error in src/shmif/foo.zig → units rows whose name
-- contains "shmif" pop. The senseye gestalt move, generalized.
local highlighted_unit_rows = {}    -- set: row → true (currently highlighted)
local highlighted_error_rows = {}

local function units_clear_highlight()
    if not units_spread then return end
    for row in pairs(highlighted_unit_rows) do
        -- Restore the original # cell content (the row index).
        spread_set(units_spread, row, 1, tostring(row - 1))
    end
    highlighted_unit_rows = {}
end

local function units_apply_highlight(key)
    if not units_spread or not key or key == "" then return end
    units_clear_highlight()
    for name, row in pairs(units_by_name) do
        if string.find(name, key, 1, true) then
            spread_set(units_spread, row, 1, "► " .. tostring(row - 1))
            highlighted_unit_rows[row] = true
        end
    end
end

local function errors_clear_highlight()
    if not errors_spread then return end
    for row in pairs(highlighted_error_rows) do
        -- Recompute the proper status cell: existing row carries it
        -- in the units_status equivalent, but errors store status as
        -- glyph+word. Re-derive by inspecting the diag-key.
        local key = row_to_diag_key[row]
        local cur = errors_last_gen[row] == units_build_gen
        local status_cell = cur and "✗ active" or "~ cleared"
        if key then
            local sev = string.match(key, ":[^:]*:[^:]*:([^:]+):") or "?"
            local glyph = (sev == "error" and "✗")
                or (sev == "warning" and "!")
                or (sev == "note" and "·")
                or "?"
            status_cell = glyph .. (cur and " active" or " cleared")
        end
        spread_set(errors_spread, row, 1, status_cell)
    end
    highlighted_error_rows = {}
end

local function errors_apply_highlight(key, payload)
    if not errors_spread or not key or key == "" then return end
    errors_clear_highlight()
    -- Match against the file column (col 3) since errors carry file
    -- paths and the key from a units publish is a step name. Loose
    -- substring works both directions.
    for diag_key_str, row in pairs(errors_by_key) do
        local file = string.match(diag_key_str, "^([^:]+):") or ""
        local hit =
            string.find(diag_key_str, key, 1, true)
            or (payload and payload.file
                and string.find(payload.file, file, 1, true))
            or string.find(file, key, 1, true)
        if hit then
            local existing = "►"
            spread_set(errors_spread, row, 1, existing)
            highlighted_error_rows[row] = true
        end
    end
end

-- Single subscriber that applies cross-view highlights regardless of
-- which view published. Self-publishes don't loop because the
-- substring scan is bounded and idempotent under same key.
local highlights_installed = false
local function install_highlight_subscriber()
    if highlights_installed then return end
    highlights_installed = true
    if H.viz_bus and H.viz_bus.subscribe then
        H.viz_bus.subscribe(function(_sensor, key, _row, payload)
            units_apply_highlight(key)
            errors_apply_highlight(key, payload)
        end)
    end
end

local function poll_units_cursor()
    if not (units_spread and units_spread.id and units_spread.cell_cursor) then
        return true
    end
    local cc = units_spread.cell_cursor
    local row, col = cc[2] or 0, cc[1] or 0
    local prev = cursor_state.units
    if row ~= prev.row or col ~= prev.col then
        prev.row, prev.col = row, col
        local name = row_to_unit_name[row]
        if name then
            H.viz_bus.publish("compile.units", name, row, {name = name})
        end
    end
    return true
end

local function poll_errors_cursor()
    if not (errors_spread and errors_spread.id and errors_spread.cell_cursor) then
        return true
    end
    local cc = errors_spread.cell_cursor
    local row, col = cc[2] or 0, cc[1] or 0
    local prev = cursor_state.errors
    if row ~= prev.row or col ~= prev.col then
        prev.row, prev.col = row, col
        local key = row_to_diag_key[row]
        if key then
            -- Parse <file>:<line>:<col>:<sev>:<msg> back into
            -- structured payload so subscribers can match on file
            -- alone, line alone, etc.
            local file, line, c2, sev = string.match(key,
                "^(.-):(%d+):(%d+):([^:]+):")
            H.viz_bus.publish("compile.errors", key, row, {
                file = file, line = tonumber(line),
                col = tonumber(c2), severity = sev,
            })
        end
    end
    return true
end

local viz_pollers_installed = false
local function install_viz_pollers()
    if viz_pollers_installed then return end
    viz_pollers_installed = true
    if cat9.timers then
        table.insert(cat9.timers, poll_units_cursor)
        table.insert(cat9.timers, poll_errors_cursor)
    end
end

function suggest.compile(args, raw)
    -- A future enhancement could parse `zig build --help` Steps.
end

function builtins.compile(...)
    local raw_args = {...}
    local targets = {}
    local extra = {}
    for _, v in ipairs(raw_args) do
        if type(v) == "string" then
            if string.sub(v, 1, 2) == "-D" or string.sub(v, 1, 2) == "-f" then
                table.insert(extra, v)
            else
                table.insert(targets, v)
            end
        end
    end
    if #targets == 0 then
        cat9.add_message("compile <target> [-Dopt=val ...]")
        H.emit_result("compile:err:reason=no_target")
        return
    end

    local target = targets[1]
    -- Stage-B: ask the patched fork to emit `BUILD\t…` tagged stderr
    -- lines. The flag is silently rejected by stock zig, so we set it
    -- only when the fork's binary is in use (it is, by construction
    -- on this build — zigbin points at it).
    local argv = {zigbin, "zig", "build", "--shmif-tagged-progress", target}
    for _, t in ipairs(targets) do
        if t ~= target then table.insert(argv, t) end
    end
    for _, e in ipairs(extra) do table.insert(argv, e) end

    -- The persistent units spread — created on first compile, reused
    -- on every subsequent invocation. Each `compile <target>` bumps
    -- the build gen and mutates rows for units it touches, leaving
    -- the rest as historical record.
    local steps = ensure_units_spread()
    if not steps then
        cat9.add_message("compile: spreadsheet unavailable")
        H.emit_result(string.format("compile:err:target=%s:reason=spreadsheet_unavailable",
            target))
        return
    end
    -- Make the errors + timeline spreads visible up front too —
    -- even a clean build should show the errors view (with all rows
    -- `cleared`) and the timeline view, so the user can see
    -- "everything passed at HH:MM:SS" / build cadence.
    ensure_errors_spread()
    ensure_time_spread()
    -- Install the cell_cursor → selection-bus pollers once both
    -- spreads exist, and the cross-view highlight subscriber. Both
    -- idempotent.
    install_viz_pollers()
    install_highlight_subscriber()
    units_build_gen = units_build_gen + 1
    local this_gen = units_build_gen
    local touched_this_build = 0
    local errors_touched_this_build = 0

    local env = cat9.table_copy_shallow(cat9.env)
    local old_dir = root:chdir()
    root:chdir(srcdir)

    local job = cat9.setup_shell_job(
        argv, "re", env,
        "compile " .. target,
        {close = true}
    )
    root:chdir(old_dir)

    if not job then
        cat9.add_message("compile: setup_shell_job failed")
        H.emit_result(string.format("compile:err:target=%s:reason=setup_shell_job",
            target))
        return
    end
    job.short = "compile " .. target

    H.emit_result(string.format("compile:start:target=%s:steps_spread=%d:gen=%d",
        target, steps.id, this_gen))

    local function add_step_row(_idx, name, status, dur)
        if not name or name == "" then return end
        -- Key by step name, not the build-local idx. Generic
        -- "WriteFile" steps without a target name share one row;
        -- specific "WriteFile a12.h" gets its own. That's a feature:
        -- anonymous noise concentrates into one churn-indicator
        -- cell, named outputs each become their own historical row.
        local key = name
        local row = units_by_name[key]
        local status_cell = status_glyph(status) .. " " .. (status or "")
        local name_cell   = name_glyph(name) .. name
        local dur_cell    = dur_bar(dur)
        local first_touch_this_build = (units_last_gen[row or 0] ~= this_gen)
        if not row then
            units_count = units_count + 1
            row = units_count + 1
            units_by_name[key] = row
            row_to_unit_name[row] = name
            spread_set(steps, row, 1, tostring(units_count))
            spread_set(steps, row, 3, name_cell)
        end
        spread_set(steps, row, 2, status_cell)
        if dur then spread_set(steps, row, 4, dur_cell) end
        local seen = (units_seen_count[row] or 0) + 1
        units_seen_count[row] = seen
        spread_set(steps, row, 5, tostring(seen))
        spread_set(steps, row, 6, timestamp())
        units_last_gen[row] = this_gen
        units_status[row] = status
        if first_touch_this_build then
            touched_this_build = touched_this_build + 1
        end
        time_record("steps")
    end

    local function add_diag_row(diag)
        local errors = ensure_errors_spread()
        if not errors then return end
        local key = diag_key(diag)
        local row = errors_by_key[key]
        local first_touch_this_build = (errors_last_gen[row or 0] ~= this_gen)
        local sev_glyph = (diag.severity == "error" and "✗")
            or (diag.severity == "warning" and "!")
            or (diag.severity == "note" and "·")
            or "?"
        local status_cell = sev_glyph .. " active"
        if not row then
            errors_count = errors_count + 1
            row = errors_count + 1
            errors_by_key[key] = row
            row_to_diag_key[row] = key
            spread_set(errors, row, 2, diag.severity or "")
            spread_set(errors, row, 3, diag.file or "")
            spread_set(errors, row, 4, tostring(diag.line or 0))
            spread_set(errors, row, 5, tostring(diag.col or 0))
            spread_set(errors, row, 6, diag.message or "")
        end
        spread_set(errors, row, 1, status_cell)
        local seen = (errors_seen_count[row] or 0) + 1
        errors_seen_count[row] = seen
        spread_set(errors, row, 7, tostring(seen))
        spread_set(errors, row, 8, timestamp())
        errors_last_gen[row] = this_gen
        if first_touch_this_build then
            errors_touched_this_build = errors_touched_this_build + 1
        end
        time_record("diags")
    end

    -- Mark errors not touched this build as `stale`. The cell stays
    -- in the spread (history matters), but its status flips so the
    -- eye can scan past. The `last` column carries the timestamp of
    -- the build that cleared it — so the row literally shows "last
    -- passed at HH:MM:SS". A subsequent re-emit of the diag flips
    -- it back to `active` automatically.
    local function fade_stale_errors()
        if not errors_spread then return end
        local now = timestamp()
        for _key, row in pairs(errors_by_key) do
            if errors_last_gen[row] ~= this_gen then
                spread_set(errors_spread, row, 1, "~ cleared")
                spread_set(errors_spread, row, 8, now)
            end
        end
    end

    -- Per-line dispatch: prefer the tagged Stage-B stream when
    -- present, fall back to the legacy `[N/M]` regex parser
    -- (`zigbuild` lineage). Stock zig with no fork patch emits
    -- only legacy lines and `--shmif-tagged-progress` as an
    -- unknown-flag error → we'd never reach here. With the fork,
    -- both paths can coexist if zig also emits the legacy form.
    local function dispatch(line)
        local tag = H.parse_zig_tagged_line(line)
        if tag then
            if tag.kind == "step" then
                local s = tag.status
                local row_status = (s == "start") and "running" or s
                add_step_row(tag.idx, tag.name, row_status,
                    s == "start" and nil or tag.dur_ms)
            elseif tag.kind == "diag" then
                add_diag_row(tag)
            end
            return
        end
        local step = H.parse_zig_step_line(line)
        if step then
            add_step_row(step.idx, step.name, "running", nil)
            return
        end
        local diag = H.parse_zig_diag_line(line)
        if diag then add_diag_row(diag) end
    end

    local function consume(io)
        if not io or not io.read then return end
        local line, alive = io:read(true)
        while line do
            -- A non-buffered chunk may contain multiple newline-
            -- separated records.
            for one in string.gmatch(line, "([^\n]+)") do
                dispatch(one)
            end
            line, alive = io:read(true)
            if not alive then break end
        end
    end

    if job.out and job.out.data_handler then
        job.out:data_handler(function() consume(job.out) end)
    end
    if job.err and job.err.data_handler then
        job.err:data_handler(function() consume(job.err) end)
    end

    table.insert(job.hooks.on_finish, function()
        fade_stale_errors()
        time_record("ok")
        H.emit_result(string.format(
            "compile:ok:target=%s:steps=%d:errors=%d",
            target, touched_this_build, errors_touched_this_build))
    end)
    table.insert(job.hooks.on_fail, function()
        fade_stale_errors()
        time_record("fail")
        H.emit_result(string.format(
            "compile:fail:target=%s:steps=%d:errors=%d",
            target, touched_this_build, errors_touched_this_build))
    end)
end

end
