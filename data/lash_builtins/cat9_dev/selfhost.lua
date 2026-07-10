-- selfhost — drive the zig SH-fork attempting to compile zig SH-fork.
--
-- Produces two live spreadsheets that update as the build emits stdout:
--   "selfhost steps"   — [N/M] step lines (idx, status, name)
--   "selfhost errors"  — file:line:col diagnostics + panic/SEGV lines
--                        from a crashed codegen worker thread.
--
-- The errors spread is created lazily on the first failure line so a
-- successful self-host run is silent.
--
-- Invocation from the cat9 prompt:
--   selfhost                      — run with default fork at
--                                    /home/x/.local/src/zig-0.15.2-fork
--   selfhost <fork-dir>           — point at a different fork checkout
--
-- The build command is fixed to:
--   <fork>/zig-out/bin/zig build install -p <fork>/selfhost-out \
--      -Duse-llvm=false -Doptimize=Debug -Dno-langref -Dno-lib
--
-- This is the zig-fork compiling its own source via the SH backend (no
-- LLVM, no LLD). Goal: byte-equivalent output to the LLVM-built zig.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.selfhost = "live spreadsheet of zig-SH-fork self-host build"

local default_fork = "/home/x/.local/src/zig-0.15.2-fork"

local function spread_set(spread, row, col, value)
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %s",
            spread.id, row, col, H.escape_cell(value)))
end

-- Match `error: thread NNN panic: ...` and `Segmentation fault at address 0x..`
-- patterns from a crashed codegen worker.
local function parse_panic_line(s)
    local thread, msg = string.match(s, "^error:%s+thread%s+(%d+)%s+panic:%s*(.*)$")
    if thread then
        return {kind = "panic", thread = tonumber(thread), message = msg}
    end
    local seg = string.match(s, "Segmentation fault at address (0x%x+)")
    if seg then
        return {kind = "segv", address = seg, message = "SIGSEGV at " .. seg}
    end
    return nil
end

-- Module-level so the cursor poller can see them.
local steps_spread = nil
local errors_spread = nil
local row_to_step = {}     -- spread row → {idx, name, status}
local row_to_error = {}    -- spread row → {file, line, kind, message}

function builtins.selfhost(...)
    local args = {...}
    local fork = default_fork
    if type(args[1]) == "string" and args[1] ~= "" then
        fork = args[1]
    end
    local zigbin = fork .. "/zig-out/bin/zig"

    local argv = {
        zigbin, "zig",
        "build", "install",
        "-p", fork .. "/selfhost-out",
        "-Duse-llvm=false",
        "-Doptimize=Debug",
        "-Dno-langref",
        "-Dno-lib",
    }

    if steps_spread and steps_spread.id then
        -- Reuse existing spread; clear non-header rows so the run is
        -- visible in-place rather than spawning fresh windows.
        for r = #steps_spread.cells, 2, -1 do steps_spread.cells[r] = nil end
    else
        steps_spread = H.make_spread(
            "selfhost steps",
            {"idx", "total", "status", "name"},
            {}
        )
    end
    if not steps_spread then
        cat9.add_message("selfhost: spreadsheet unavailable")
        return
    end

    local errors_count = 0
    local steps_seen = {}
    row_to_step = {}
    row_to_error = {}

    H.emit_result(string.format("selfhost:start:fork=%s",
        string.match(fork, "[^/]+$") or fork))

    local function ensure_errors_spread()
        if errors_spread then return end
        errors_spread = H.make_spread(
            "selfhost errors",
            {"id", "kind", "file", "line", "col", "severity", "message"},
            {}
        )
    end

    local function append_error(rec)
        ensure_errors_spread()
        if not errors_spread then return end
        errors_count = errors_count + 1
        local row = errors_count + 1
        spread_set(errors_spread, row, 1, tostring(errors_count))
        spread_set(errors_spread, row, 2, rec.kind or "diag")
        spread_set(errors_spread, row, 3, rec.file or "-")
        spread_set(errors_spread, row, 4, rec.line and tostring(rec.line) or "-")
        spread_set(errors_spread, row, 5, rec.col and tostring(rec.col) or "-")
        spread_set(errors_spread, row, 6, rec.severity or "error")
        spread_set(errors_spread, row, 7, rec.message or "")
        row_to_error[row] = {
            file = rec.file, line = tonumber(rec.line),
            kind = rec.kind or "diag", message = rec.message,
        }
        if H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("selfhost.errors",
                (rec.file or "?") .. ":" .. tostring(rec.line or 0),
                row,
                {
                    file = rec.file, line = tonumber(rec.line),
                    severity = rec.severity or "error",
                    kind = rec.kind or "diag",
                })
        end
        H.emit_result(string.format(
            "selfhost:errors:count=%d:file=%s:line=%s:kind=%s",
            errors_count, rec.file or "-", tostring(rec.line or "-"),
            rec.kind or "diag"))
    end

    local env = cat9.table_copy_shallow(cat9.env)
    local old_dir = root:chdir()
    root:chdir(fork)

    local job = cat9.setup_shell_job(
        argv, "re", env,
        "selfhost " .. fork,
        {close = true}
    )
    root:chdir(old_dir)

    if not job then
        cat9.add_message("selfhost: setup_shell_job failed")
        return
    end
    job.short = "selfhost"

    if job.out and job.out.data_handler then
        job.out:data_handler(function()
            local line, alive = job.out:read(true)
            while line do
                local step = H.parse_zig_step_line(line)
                local diag = H.parse_zig_diag_line(line)
                local crash = parse_panic_line(line)
                if step then
                    local row = steps_seen[step.idx]
                    if not row then
                        row = #steps_seen + 2
                        steps_seen[step.idx] = row
                        spread_set(steps_spread, row, 1, tostring(step.idx))
                        spread_set(steps_spread, row, 2, tostring(step.total))
                        spread_set(steps_spread, row, 3, "running")
                        spread_set(steps_spread, row, 4, step.name)
                        row_to_step[row] = {
                            idx = step.idx, name = step.name, status = "running"
                        }
                        if H.viz_bus and H.viz_bus.publish then
                            H.viz_bus.publish("selfhost.steps",
                                step.name, row,
                                {name = step.name, status = "running"})
                        end
                    else
                        spread_set(steps_spread, row, 3, "running")
                    end
                elseif diag then
                    append_error(diag)
                elseif crash then
                    append_error(crash)
                end
                line, alive = job.out:read(true)
                if not alive then break end
            end
        end)
    end

    table.insert(job.hooks.on_finish, function()
        for _, row in pairs(steps_seen) do
            spread_set(steps_spread, row, 3, "ok")
            if row_to_step[row] then row_to_step[row].status = "ok" end
        end
        cat9.add_message(string.format(
            "selfhost: build OK (%d errors observed)", errors_count))
        H.emit_result(string.format(
            "selfhost:ok:steps=%d:errors=%d", #steps_seen, errors_count))
    end)
    table.insert(job.hooks.on_fail, function()
        for _, row in pairs(steps_seen) do
            spread_set(steps_spread, row, 3, "fail")
            if row_to_step[row] then row_to_step[row].status = "fail" end
        end
        cat9.add_message(string.format(
            "selfhost: build failed (%d errors)", errors_count))
        H.emit_result(string.format(
            "selfhost:fail:steps=%d:errors=%d", #steps_seen, errors_count))
    end)
end

-- Click handlers for the two spreads.  Polls cell_cursor; on row
-- change publishes a payload that snippets / disasm / dwarf / units
-- subscribers all pick up (file+line are the canonical keys).
local steps_cursor = {row = 0}
local errors_cursor = {row = 0}

local function poll_steps_cursor()
    if not (steps_spread and steps_spread.id and steps_spread.cell_cursor) then
        return true
    end
    local r = steps_spread.cell_cursor[2] or 0
    if r ~= steps_cursor.row then
        steps_cursor.row = r
        local s = row_to_step[r]
        if s and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("selfhost.steps", s.name, r, {
                name = s.name, status = s.status,
            })
            H.emit_result(string.format(
                "selfhost:click:step:name=%s:status=%s",
                s.name, s.status))
        end
    end
    return true
end

local function poll_errors_cursor()
    if not (errors_spread and errors_spread.id and errors_spread.cell_cursor) then
        return true
    end
    local r = errors_spread.cell_cursor[2] or 0
    if r ~= errors_cursor.row then
        errors_cursor.row = r
        local e = row_to_error[r]
        if e and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("selfhost.errors",
                (e.file or "?") .. ":" .. tostring(e.line or 0),
                r,
                {
                    file = e.file, line = e.line,
                    severity = "error", kind = e.kind,
                })
            H.emit_result(string.format(
                "selfhost:click:error:file=%s:line=%s",
                e.file or "-", tostring(e.line or "-")))
        end
    end
    return true
end

if cat9.timers then
    table.insert(cat9.timers, poll_steps_cursor)
    table.insert(cat9.timers, poll_errors_cursor)
end

end
