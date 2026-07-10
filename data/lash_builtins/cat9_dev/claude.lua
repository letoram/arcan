-- claude [args...]
--
-- Spawn afsrv_terminal hosting Claude Code as a SIBLING shmif client
-- (separate durden tile). Uses afsrv_terminal's ARCAN_ARG="exec=…"
-- pathway to run the claude binary directly inside ghostty's
-- terminal renderer — same auth (Claude.ai OAuth) as the outer
-- session, no API key needed.
--
-- Companion to the system `p!claude` form which runs claude INLINE
-- in the current lash cell via cat9's PTY mode. Use `claude` here
-- when you want a full new tile; use `p!claude` for in-cell.
--
-- Resolution order for the binary:
--   1. $CLAUDE_BIN env override
--   2. ~/.local/bin/claude (the standard install path)
--   3. PATH lookup via /usr/bin/env claude
--
-- Visible: a fresh durden tile appears with claude running, ready
-- for input. The cat9 cell that ran this verb shows a single job
-- entry (the spawned afsrv_terminal pid) and is otherwise free.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.claude = "Spawn Claude Code in a new durden tile (no API key)"

local function file_exists(path)
    if not path or path == "" then return false end
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function resolve_claude_bin()
    local env = cat9.env or {}
    local override = env.CLAUDE_BIN or os.getenv("CLAUDE_BIN")
    if file_exists(override) then return override end
    local home = env.HOME or os.getenv("HOME") or ""
    local candidate = home .. "/.local/bin/claude"
    if file_exists(candidate) then return candidate end
    -- Last resort: /usr/bin/env will resolve PATH at exec time.
    return "claude"
end

local function resolve_afsrv_terminal()
    local p = "/home/x/next/arcan/zig-out/bin/afsrv_terminal"
    if file_exists(p) then return p end
    return "/usr/bin/afsrv_terminal"
end

function suggest.claude(args, raw)
    -- The first arg position takes claude's own subcommand / flag, not
    -- a path. claude's CLI surface is rich; we intentionally don't
    -- pre-populate suggestions to avoid stale completions. Tab still
    -- triggers cat9's default file-completion if the user wants it.
end

function builtins.claude(...)
    local args = {...}

    local extras = {}
    for _, v in ipairs(args) do
        if type(v) == "string" then table.insert(extras, v) end
    end

    local bin = resolve_claude_bin()
    local term = resolve_afsrv_terminal()

    local env = cat9.table_copy_shallow(cat9.env)
    env.ARCAN_CONNPATH = env.ARCAN_CONNPATH or "durden"
    -- afsrv_terminal forks the binary in its PTY child via ARCAN_ARG
    -- exec=. ARCAN_TERMINAL_ARGV (NUL-separated) carries argv beyond
    -- argv[0] (which is set to `bin` itself by build_argv).
    env.ARCAN_ARG = "exec=" .. bin
    if #extras > 0 then
        env.ARCAN_TERMINAL_ARGV = table.concat(extras, "\0")
    else
        env.ARCAN_TERMINAL_ARGV = nil
    end

    -- setup_shell_job in raw-exec mode. argv[2] is the conventional
    -- argv[0] visible to the spawned process; "afsrv_terminal" keeps
    -- its self-identification consistent.
    local argv = {term, "afsrv_terminal"}

    local short = "claude"
    if #extras > 0 then
        short = "claude " .. extras[1]
    end

    local line = "claude" .. (short ~= "claude" and (" " .. extras[1]) or "")
    local job = cat9.setup_shell_job(argv, "re", env, line, {close = true})
    if not job then
        cat9.add_message("claude: setup_shell_job failed")
        return
    end
    job.short = short

    H.emit_result(string.format("claude:spawn:bin=%s", bin))

    if job.closure then
        local prev = job.closure
        job.closure = function(...)
            H.emit_result("claude:exit")
            return prev(...)
        end
    else
        job.closure = function() H.emit_result("claude:exit") end
    end
end

end
