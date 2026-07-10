-- proc <subcommand> — process tree walker (Phase 1.1, bug 0118).
--
-- Subcommands:
--   proc ps [exe=<substr>] [parent=<pid>] [name=<substr>] [state=<X>]
--     List processes matching filters. Walks /proc/*/{stat,status,cmdline}.
--   proc kill <pid> [signal]
--     Send signal (default term) to a process. signal name as accepted by
--     root:psignal — "term","int","user1","hup","kill",...
--   proc info <pid>
--     Detailed info on a single process (per-key spread).
--   proc tree
--     ppid → pid forest as a flat spread (one row per pid, sorted by ppid).
--
-- Replaces host-bash `pgrep -af` / `kill` for cells driving lash workflows.
-- Pure-ish Lua: uses lash.root:fglob/fopen for /proc, lash.root:psignal for
-- signals.  No /bin/sh, no popen of pgrep.
--
-- Emits:
--   proc:ps:ok:rows=N
--   proc:kill:ok:pid=N:signal=S
--   proc:kill:err:pid=N:reason=...
--   proc:info:ok:pid=N
--   proc:info:err:pid=N:reason=no_such_pid
--   proc:tree:ok:rows=N
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.proc = "Process walker / killer (Phase 1.1, bug 0118)"

local function slurp(path)
    local f = root:fopen(path, "r")
    if not f then return nil end
    local out = ""
    local chunk, alive = f:read(true)
    while chunk do
        if #chunk == 0 then break end
        out = out .. chunk
        if not alive then break end
        chunk, alive = f:read(true)
    end
    f:close()
    return out
end

-- Synchronous variant kept for fallback paths; not the primary read.
local function list_proc_pids_sync()
    local pids = {}
    local entries = H.list_dir("/proc")
    if entries then
        for _, ent in ipairs(entries) do
            if ent.name:match("^%d+$") then
                table.insert(pids, ent.name)
            end
        end
    end
    return pids
end

-- /proc/PID/stat format: pid (comm) state ppid pgrp ...
-- comm can have spaces and parens; split on rightmost ')' to be safe.
local function parse_stat(s)
    if not s or #s == 0 then return nil end
    local rparen = nil
    for i = #s, 1, -1 do
        if s:sub(i, i) == ")" then rparen = i; break end
    end
    if not rparen then return nil end
    local lparen = s:find("%(")
    if not lparen or lparen >= rparen then return nil end
    local pid = tonumber(s:sub(1, lparen - 2):match("(%d+)"))
    local comm = s:sub(lparen + 1, rparen - 1)
    local rest = s:sub(rparen + 2)
    local fields = {}
    for tok in rest:gmatch("(%S+)") do
        table.insert(fields, tok)
    end
    return {
        pid = pid,
        comm = comm,
        state = fields[1] or "?",
        ppid = tonumber(fields[2]) or 0,
    }
end

local function parse_status(s)
    local out = {}
    if not s or #s == 0 then return out end
    for line in s:gmatch("[^\n]+") do
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then out[k] = v end
    end
    return out
end

local function gather(pid_str)
    local stat = parse_stat(slurp("/proc/" .. pid_str .. "/stat"))
    if not stat then return nil end
    local cmdline = slurp("/proc/" .. pid_str .. "/cmdline") or ""
    cmdline = cmdline:gsub("%z", " "):gsub("%s+$", "")
    local status = parse_status(slurp("/proc/" .. pid_str .. "/status") or "")
    -- exe path: prefer first cmdline arg (works across permission boundaries
    -- for same-uid processes; for cross-uid we'd need readlink which we
    -- don't have a primitive for yet).
    local exe = cmdline:match("^(%S+)") or ""
    return {
        pid = stat.pid,
        ppid = stat.ppid,
        state = stat.state,
        comm = stat.comm,
        exe = exe,
        cmdline = cmdline,
        rss = (status.VmRSS or ""):match("(%d+)") or "",
        threads = status.Threads or "1",
    }
end

local function parse_filters(args)
    local filt = {}
    for _, a in ipairs(args) do
        local k, v = a:match("^([^=]+)=(.*)$")
        if k and v then filt[k] = v end
    end
    return filt
end

local function row_matches(r, filt)
    if filt.exe then
        if not r.exe:find(filt.exe, 1, true)
           and not r.cmdline:find(filt.exe, 1, true) then
            return false
        end
    end
    if filt.parent and tostring(r.ppid) ~= filt.parent then return false end
    if filt.name and not r.comm:find(filt.name, 1, true) then return false end
    if filt.state and r.state ~= filt.state then return false end
    return true
end

-- Async enumeration via background job (zigbuild/build.lua pattern).
-- on_done(pids_table) runs once /bin/ls /proc finishes.
local function enumerate_pids_async(on_done)
    if not (root.popen and cat9.add_background_job) then
        on_done(list_proc_pids_sync())
        return
    end
    local _, outf, errf, pid = root:popen(
        {"/bin/ls", "/bin/ls", "/proc"}, "re"
    )
    if not pid then
        on_done(list_proc_pids_sync())
        return
    end
    local pids = {}
    local job = cat9.add_background_job(outf, pid,
        {lf_strip = true, err = errf},
        function(job, code)
            on_done(pids)
        end)
    table.insert(job.hooks.on_data, function(line)
        if line then
            local n = line:match("^%s*(%d+)%s*$")
            if n then table.insert(pids, n) end
        end
    end)
end

local function builtin_ps(...)
    local args = {...}
    local filt = parse_filters(args)
    enumerate_pids_async(function(all_pids)
        local rows = {}
        for _, pid_str in ipairs(all_pids) do
            local r = gather(pid_str)
            if r and row_matches(r, filt) then
                table.insert(rows, r)
            end
        end
        table.sort(rows, function(a, b) return (a.pid or 0) < (b.pid or 0) end)
        if #rows == 0 then
            cat9.add_message("proc ps: no matches (enumerated " .. #all_pids .. " pids)")
            H.emit_result(string.format("proc:ps:ok:rows=0:enum=%d", #all_pids))
            return
        end
        local cells = {}
        for _, r in ipairs(rows) do
            table.insert(cells, {
                tostring(r.pid), tostring(r.ppid), tostring(r.state or "?"),
                tostring(r.rss or ""), tostring(r.comm or ""),
                tostring(r.cmdline or ""):sub(1, 80),
            })
        end
        H.make_spread(
            "proc ps (" .. #rows .. ")",
            {"pid", "ppid", "state", "rss_kb", "comm", "cmdline"},
            cells
        )
        H.emit_result(string.format("proc:ps:ok:rows=%d", #rows))
    end)
end

local function builtin_kill(pid, sig)
    if not pid then
        cat9.add_message("proc kill <pid> [signal]")
        H.emit_result("proc:kill:err:reason=missing_args")
        return
    end
    sig = (sig or "term"):lower()
    local n = tonumber(pid)
    if not n then
        H.emit_result(string.format("proc:kill:err:pid=%s:reason=not_a_number", pid))
        return
    end
    if not root.psignal then
        H.emit_result("proc:kill:err:reason=psignal_unavailable")
        return
    end
    local ok, err = pcall(function() root:psignal(n, sig) end)
    if ok then
        H.emit_result(string.format("proc:kill:ok:pid=%d:signal=%s", n, sig))
    else
        H.emit_result(string.format("proc:kill:err:pid=%d:signal=%s:reason=%s",
            n, sig, tostring(err)))
    end
end

local function builtin_info(pid)
    if not pid then
        cat9.add_message("proc info <pid>")
        return
    end
    local r = gather(tostring(pid))
    if not r then
        cat9.add_message("proc info: no such pid " .. tostring(pid))
        H.emit_result(string.format("proc:info:err:pid=%s:reason=no_such_pid", pid))
        return
    end
    H.make_spread(
        "proc info " .. tostring(pid),
        {"key", "value"},
        {
            {"pid", tostring(r.pid)},
            {"ppid", tostring(r.ppid)},
            {"state", r.state},
            {"comm", r.comm},
            {"exe", r.exe},
            {"cmdline", r.cmdline},
            {"rss_kb", r.rss},
            {"threads", r.threads},
        }
    )
    H.emit_result(string.format("proc:info:ok:pid=%s", pid))
end

local function builtin_tree()
    enumerate_pids_async(function(all_pids)
        local rows = {}
        for _, pid_str in ipairs(all_pids) do
            local r = gather(pid_str)
            if r then table.insert(rows, r) end
        end
        if #rows == 0 then
            cat9.add_message("proc tree: no rows (enumerated " .. #all_pids .. " pids)")
            H.emit_result(string.format("proc:tree:ok:rows=0:enum=%d", #all_pids))
            return
        end
        table.sort(rows, function(a, b)
            if a.ppid == b.ppid then return (a.pid or 0) < (b.pid or 0) end
            return (a.ppid or 0) < (b.ppid or 0)
        end)
        local cells = {}
        for _, r in ipairs(rows) do
            table.insert(cells, {
                tostring(r.ppid), tostring(r.pid),
                tostring(r.comm or ""),
                tostring(r.cmdline or ""):sub(1, 60),
            })
        end
        H.make_spread(
            "proc tree (" .. #rows .. ")",
            {"ppid", "pid", "comm", "cmdline"},
            cells
        )
        H.emit_result(string.format("proc:tree:ok:rows=%d", #rows))
    end)
end

function suggest.proc(args, raw)
    if #args == 2 then
        cat9.readline:suggest({"ps", "kill", "info", "tree"}, "word", args[2])
    end
end

function builtins.proc(sub, ...)
    if not sub then
        cat9.add_message("proc <ps|kill|info|tree> [args]")
        return
    end
    if sub == "ps" then return builtin_ps(...) end
    if sub == "kill" then return builtin_kill(...) end
    if sub == "info" then return builtin_info(...) end
    if sub == "tree" then return builtin_tree(...) end
    cat9.add_message("proc: unknown subcommand " .. tostring(sub))
end

end
