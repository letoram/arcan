-- bun <script.ts> [args...]
--
-- Spawn afsrv_bun (Bun-as-shmif-frameserver) running the given TS
-- module. afsrv_bun connects back to durden via ARCAN_CONNPATH, so a
-- new arcan window appears next to this cat9 cell — that's the bun
-- process's primary segment. The TS module sees globalThis.shmif.*
-- and globalThis.durden.send for IPC; bug 0036 phase 3i.
--
-- The cat9 cell itself is the popen-attached job — its body shows the
-- TS module's stderr output (console.log lands there). Use this when
-- you want a TS-driven action visible in BOTH places: the cell text
-- (logs) and the new arcan window (whatever shmif primitives the TS
-- code paints).
--
-- Resolution order for the binary:
--   1. $ARCAN_AFSRV_BUN env override (full path to binary)
--   2. <project>/zig-out/bin/afsrv_bun (the canonical install path)
--   3. ~/.local/share/arcan/bun-build/src/build/release/afsrv_bun
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.bun = "Run a TS file via afsrv_bun (Bun + shmif)"

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function resolve_bin()
    local env = cat9.env or {}
    local override = env.ARCAN_AFSRV_BUN or os.getenv("ARCAN_AFSRV_BUN")
    if override and override ~= "" and file_exists(override) then
        return override
    end
    local cands = {
        "/home/x/next/arcan/zig-out/bin/afsrv_bun",
        (env.HOME or os.getenv("HOME") or "")
            .. "/.local/share/arcan/bun-build/src/build/release/afsrv_bun",
    }
    for _, p in ipairs(cands) do
        if file_exists(p) then return p end
    end
    return nil
end

function suggest.bun(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.bun(...)
    local args = {...}
    if #args < 1 then
        cat9.add_message("bun <script.ts> [args...]")
        return
    end

    local script = nil
    local extra = {}
    for _, v in ipairs(args) do
        if type(v) == "string" then
            if not script then script = v
            else table.insert(extra, v) end
        end
    end
    if not script then
        cat9.add_message("bun: no script argument")
        return
    end

    local bin = resolve_bin()
    if not bin then
        cat9.add_message(
            "bun: afsrv_bun not found. " ..
            "Set $ARCAN_AFSRV_BUN or install at zig-out/bin/afsrv_bun.")
        return
    end

    local env = cat9.table_copy_shallow(cat9.env)
    -- Ensure the spawned process can talk to durden. The user's session
    -- normally has this set; force it for safety so `bun` always works
    -- from anywhere — including environments scrubbed by shells.
    env.ARCAN_CONNPATH = env.ARCAN_CONNPATH or "durden"

    -- setup_shell_job(argv, "re", env, line, opts) — "re" = raw exec.
    -- argv[1] is the binary; argv[2] is conventional argv[0] (program
    -- name visible to the spawned process). We pass "afsrv_bun" so its
    -- own stderr `[afsrv_bun] ...` prefixes look right.
    local final_argv = {bin, "afsrv_bun", script}
    for _, a in ipairs(extra) do table.insert(final_argv, a) end

    local short = "bun " .. (string.match(script, "([^/]+)$") or script)
    local job = cat9.setup_shell_job(
        final_argv, "re", env,
        "bun " .. script, {close = true})
    if not job then return end
    job.short = short

    H.emit_result(string.format("bun:spawn:script=%s", script))

    -- ── Parent-control channel ────────────────────────────────────────
    -- Lines on STDOUT starting with `\x01@cat9 ` (SOH + tag) are control
    -- directives FROM the spawned afsrv_bun TO this cat9 cell. We strip
    -- the prefix and dispatch the remainder via cat9.parse_string —
    -- same entry point cat9 uses for keyboard-typed verbs. Other lines
    -- pass through and render normally as job-body output.
    --
    -- The hook rides job.hooks.on_data because cat9.flush_job reads
    -- job.out/err directly via `:read(false, buffer)` — bypassing any
    -- data_handler callbacks. on_data fires per-line inside
    -- data_buffered/data_unbuffered (jobctl.lua:68/207), which IS the
    -- code path flush_job runs through after each read tick. Setting
    -- `job.block_buffer = true` from the hook keeps the matched line
    -- out of the cell body; non-prefix lines render normally with
    -- block_buffer left at its default (false).
    --
    -- Stderr has no equivalent hook (jobctl.lua:282-291 reads err with
    -- no callbacks fired), so the protocol must ride stdout. TS-side
    -- `cat9Parent.send` wraps console.log accordingly.
    local CTRL_PREFIX = "\1@cat9 "
    local plen = #CTRL_PREFIX

    table.insert(job.hooks.on_data, function(line, buffered, eof)
        if type(line) ~= "string" then return end
        if string.sub(line, 1, plen) == CTRL_PREFIX then
            local verb = string.sub(line, plen + 1)
            if verb ~= "" then
                H.emit_result(string.format("bun:ctrl:%s", verb))
                -- Dispatch verb in the parent's readline context.
                pcall(cat9.parse_string, cat9.readline, verb)
            end
            -- Suppress this line from the cell body so the user sees
            -- only the EFFECT of the verb (the spawned jobs), not the
            -- raw control-prefix lines.
            job.block_buffer = true
        else
            -- Restore default so subsequent non-control lines render.
            job.block_buffer = false
        end
    end)
    H.emit_result("bun:ctrl:installed-on-data-hook")

    if job.closure then
        local prev = job.closure
        job.closure = function(...)
            H.emit_result(string.format("bun:exit:script=%s", script))
            return prev(...)
        end
    else
        job.closure = function()
            H.emit_result(string.format("bun:exit:script=%s", script))
        end
    end
end

end
