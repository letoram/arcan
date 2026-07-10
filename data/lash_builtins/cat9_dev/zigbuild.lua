-- zigbuild [target] [-Dopt=val ...]
--
-- Like cat9/dev/build.lua's `build` builtin, but **parses zig stdout
-- into live spreadsheet cells**: a Steps spreadsheet that updates as
-- `[N/M] step` lines appear, and an Errors spreadsheet that
-- materializes only if zig emits a diagnostic.
--
-- Phase 2: regex-parse the existing stdout/stderr text. Phase 3
-- (deferred to a follow-up session) patches the zig fork to emit
-- shmif EVENT_TARGET_MESSAGE per step/diag — at which point this
-- builtin's parser becomes a thin EVENT consumer instead of regexes.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.zigbuild = "zig build with live Steps + Errors spreadsheets"

local srcdir = "/home/x/next/arcan"
local zigbin = "/home/x/.local/src/zig-0.15.2-fork/zig-out/bin/zig"

function suggest.zigbuild(args, raw)
    -- Trivial: completion would need to run `zig build --help` and
    -- parse Steps section. Skip for now.
end

local function spread_set(spread, row, col, value)
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %s",
            spread.id, row, col, H.escape_cell(value)))
end

function builtins.zigbuild(...)
    local raw_args = {...}
    local targets = {}
    for _, v in ipairs(raw_args) do
        if type(v) == "string" then table.insert(targets, v) end
    end

    -- Build argv. zigbin's argv[0] is "zig" by convention.
    local argv = {zigbin, "zig", "build"}
    for _, t in ipairs(targets) do table.insert(argv, t) end

    -- Steps spreadsheet (always created, populated lazily as parse
    -- events fire).
    local steps_spread = H.make_spread(
        "zigbuild steps " .. table.concat(targets, " "),
        {"idx", "status", "name", "duration"},
        {}
    )
    if not steps_spread then
        cat9.add_message("zigbuild: spreadsheet unavailable")
        return
    end

    -- Errors spreadsheet — created lazily on first diagnostic.
    local errors_spread = nil
    local errors_count = 0
    local steps_seen = {}    -- idx → row in steps spread (1-indexed beyond header)
    local steps_meta = {}    -- idx → {name, state, total} for build:done summary
    local build_total = 0    -- last seen [N/M] total
    local build_target = targets[1] or "default"

    local env = cat9.table_copy_shallow(cat9.env)
    local old_dir = root:chdir()
    root:chdir(srcdir)

    local job = cat9.setup_shell_job(
        argv, "re", env,
        "zigbuild " .. table.concat(targets, " "),
        {close = true}
    )
    root:chdir(old_dir)

    if not job then
        cat9.add_message("zigbuild: setup_shell_job failed")
        return
    end
    job.short = "zigbuild " .. (targets[1] or "default")

    -- bug 0023: helpers that mirror a step / done event onto shmif so
    -- viz subscribers (atlas long-line, hilbert, status spread) can
    -- paint live.  Two channels per emit:
    --   1. H.emit_result()  → shmif MESSAGE `test:dev_result:build:…`
    --      consumed by autorun.lua → shmon.log; visible to harness.
    --   2. H.viz_bus.publish() → in-process subscribers (atlas etc).
    local function emit_step(idx, total, name, state, dur_ms, exit_code)
        local tag = string.format(
            "build:step:idx=%d:total=%d:unit=%s:state=%s:dur_ms=%d:exit=%d",
            idx, total or 0, tostring(name or ""),
            tostring(state), dur_ms or 0, exit_code or 0)
        H.emit_result(tag)
        if H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("build.atlas", tostring(idx), idx, {
                build_unit  = name,
                build_state = state,
                build_exit  = exit_code or 0,
                name        = name,
            })
        end
    end

    local function emit_done(status, steps, errs, exit_code)
        local tag = string.format(
            "build:done:target=%s:steps=%d:errors=%d:status=%s:exit=%d",
            tostring(build_target), steps or 0, errs or 0,
            tostring(status), exit_code or 0)
        H.emit_result(tag)
        if H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("build.atlas", "done", steps or 0, {
                build_unit  = build_target,
                build_state = status,
                build_exit  = exit_code or 0,
            })
        end
    end

    -- Hook a per-line parser onto stdout's data_handler. The builtin
    -- itself returns immediately; rows materialize as zig prints.
    if job.out and job.out.data_handler then
        job.out:data_handler(function()
            local line, alive = job.out:read(true)
            while line do
                -- Tagged stream wins when present (patched zig fork).
                local tagged = H.parse_zig_tagged_line(line)
                local step = (not tagged) and H.parse_zig_step_line(line) or nil
                local diag = (not tagged) and H.parse_zig_diag_line(line) or nil
                if tagged and tagged.kind == "step" then
                    local row = steps_seen[tagged.idx]
                    if not row then
                        row = #steps_seen + 2
                        steps_seen[tagged.idx] = row
                        spread_set(steps_spread, row, 1, tostring(tagged.idx))
                        spread_set(steps_spread, row, 3, tagged.name)
                    end
                    spread_set(steps_spread, row, 2, tagged.status)
                    spread_set(steps_spread, row, 4,
                        string.format("%dms", tagged.dur_ms or 0))
                    steps_meta[tagged.idx] = {
                        name = tagged.name, state = tagged.status,
                        total = tagged.total,
                    }
                    build_total = tagged.total or build_total
                    emit_step(tagged.idx, tagged.total,
                        tagged.name, tagged.status, tagged.dur_ms, 0)
                elseif tagged and tagged.kind == "diag" then
                    if not errors_spread then
                        errors_spread = H.make_spread(
                            "zigbuild errors",
                            {"severity", "file", "line", "col", "message"},
                            {}
                        )
                    end
                    if errors_spread then
                        errors_count = errors_count + 1
                        local row = errors_count + 1
                        spread_set(errors_spread, row, 1, tagged.severity)
                        spread_set(errors_spread, row, 2, tagged.file)
                        spread_set(errors_spread, row, 3, tostring(tagged.line))
                        spread_set(errors_spread, row, 4, tostring(tagged.col))
                        spread_set(errors_spread, row, 5, tagged.message)
                    end
                elseif tagged and tagged.kind == "build" then
                    -- Final summary line from patched fork.  Mirror via
                    -- emit_done so subscribers see a single canonical
                    -- closer; on_finish/on_fail will not double-emit
                    -- when the tagged closer has already fired.
                    local exit_code = (tagged.status == "ok") and 0 or 1
                    emit_done(tagged.status, tagged.steps,
                        tagged.errors, exit_code)
                    job._build_done_emitted = true
                elseif step then
                    local row = steps_seen[step.idx]
                    if not row then
                        row = #steps_seen + 2
                        steps_seen[step.idx] = row
                        spread_set(steps_spread, row, 1, tostring(step.idx))
                        spread_set(steps_spread, row, 2, "running")
                        spread_set(steps_spread, row, 3, step.name)
                        spread_set(steps_spread, row, 4, "—")
                    else
                        spread_set(steps_spread, row, 2, "running")
                    end
                    steps_meta[step.idx] = {
                        name = step.name, state = "running",
                        total = step.total,
                    }
                    build_total = step.total or build_total
                    emit_step(step.idx, step.total, step.name,
                        "running", 0, 0)
                elseif diag then
                    if not errors_spread then
                        errors_spread = H.make_spread(
                            "zigbuild errors",
                            {"severity", "file", "line", "col", "message"},
                            {}
                        )
                    end
                    if errors_spread then
                        errors_count = errors_count + 1
                        local row = errors_count + 1
                        spread_set(errors_spread, row, 1, diag.severity)
                        spread_set(errors_spread, row, 2, diag.file)
                        spread_set(errors_spread, row, 3, tostring(diag.line))
                        spread_set(errors_spread, row, 4, tostring(diag.col))
                        spread_set(errors_spread, row, 5, diag.message)
                    end
                end
                line, alive = job.out:read(true)
                if not alive then break end
            end
        end)
    end

    -- on_finish: mark all running steps as ok (best-effort; zig
    -- doesn't always emit a per-step done line).
    table.insert(job.hooks.on_finish, function()
        for idx, row in pairs(steps_seen) do
            spread_set(steps_spread, row, 2, "ok")
            local meta = steps_meta[idx]
            if meta and meta.state == "running" then
                emit_step(idx, build_total, meta.name, "ok", 0, 0)
                meta.state = "ok"
            end
        end
        if not job._build_done_emitted then
            local steps_count = 0
            for _ in pairs(steps_seen) do steps_count = steps_count + 1 end
            emit_done("ok", steps_count, errors_count, 0)
            job._build_done_emitted = true
        end
    end)
    table.insert(job.hooks.on_fail, function()
        for idx, row in pairs(steps_seen) do
            spread_set(steps_spread, row, 2, "fail")
            local meta = steps_meta[idx]
            if meta and meta.state == "running" then
                emit_step(idx, build_total, meta.name, "err", 0, 1)
                meta.state = "err"
            end
        end
        cat9.add_message(string.format(
            "zigbuild: failed (%d errors)", errors_count))
        if not job._build_done_emitted then
            local steps_count = 0
            for _ in pairs(steps_seen) do steps_count = steps_count + 1 end
            emit_done("fail", steps_count, errors_count, 1)
            job._build_done_emitted = true
        end
    end)
end

end
