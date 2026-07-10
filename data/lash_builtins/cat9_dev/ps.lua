-- ps [filter=value ...]
--
-- Process table from /proc, surfaced as a spread. Phase 1.1 of bug
-- 0118 (host-bash → cat9-native debug toolkit). Replaces:
--
--   pgrep -af '<exe>'
--   ps -ef | grep ...
--   awk '$3==1 {print $2}'   (orphan classification)
--
-- The bug 0116 hunt's first move was always "find which arcan/
-- afsrv_terminal is alive and which got reparented". This builtin
-- collapses that into one line:
--
--   ps                                  — all procs (filtered to my uid)
--   ps exe=*arcan*                      — substring match on exe path
--   ps exe=/home/x/next/arcan/zig-out/bin/afsrv_terminal
--   ps ppid=1                           — orphans (re-parented to init)
--   ps state=S                          — sleeping only
--   ps min_age=60                       — at least 60s old
--
-- Filter values match equality, except `exe=*pat*` does shell-style
-- substring (single * = wildcard). Multiple filters AND together.
--
-- Columns: PID, PPID, STATE, STARTED, THREADS, RSS_KB, EXE, CMD
--
-- Publishes on viz_bus when a row is opened (sensor=ps, key=pid),
-- so the inside agent can pipe a process row into procfs / cores /
-- engine-introspect just by clicking it.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.ps = "process table from /proc — bug 0118 phase 1.1"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*all")
    f:close()
    return data
end

local function read_link(path)
    -- /proc/PID/exe is a symlink. io.open doesn't follow nicely
    -- and we want the target, not the contents. Shell out to
    -- readlink via root:popen — small per-PID cost, acceptable.
    -- Falls back to nil on permission errors.
    local _, out, _, pid = root:popen({"/usr/bin/readlink", "readlink", "-f", path}, "re")
    if not pid then return nil end
    local line = out:read(true)
    out:close()
    return line
end

-- /proc/PID/stat: pid (comm) state ppid pgrp ... starttime ...
-- comm is in parens and can itself contain spaces and parens, so
-- we extract by finding the LAST ')' and slicing. Rest is
-- whitespace-split.
local function parse_stat(data)
    if not data then return nil end
    local lp = string.find(data, "%(")
    local rp
    -- find LAST ')'  — strrfind via reverse iteration
    local i = #data
    while i > 0 do
        if string.byte(data, i) == 41 then rp = i; break end
        i = i - 1
    end
    if not lp or not rp or rp <= lp then return nil end

    local pid = tonumber(string.sub(data, 1, lp - 2))
    local comm = string.sub(data, lp + 1, rp - 1)
    local rest = string.sub(data, rp + 2)
    local fields = {}
    for w in string.gmatch(rest, "%S+") do
        table.insert(fields, w)
    end
    -- After comm, /proc/PID/stat fields are 1-indexed from "state".
    -- state(1) ppid(2) pgrp(3) ... starttime(20).
    return {
        pid = pid,
        comm = comm,
        state = fields[1],
        ppid = tonumber(fields[2]),
        starttime = tonumber(fields[20]),
    }
end

-- /proc/PID/status: VmRSS:  N kB  / Threads:  N  / Uid: ...
local function parse_status(data)
    if not data then return nil end
    local rss = tonumber(string.match(data, "VmRSS:%s*(%d+)%s*kB") or "")
    local threads = tonumber(string.match(data, "Threads:%s*(%d+)") or "")
    local uid = tonumber(string.match(data, "Uid:%s*(%d+)") or "")
    return {rss = rss, threads = threads, uid = uid}
end

-- /proc/PID/cmdline is \0-separated argv. Replace \0 with space,
-- trim trailing.
local function parse_cmdline(data)
    if not data or data == "" then return "" end
    local s = string.gsub(data, "%z", " ")
    return (string.gsub(s, "%s+$", ""))
end

-- Boot time (from /proc/stat "btime N") so we can convert
-- starttime (clock ticks since boot) to absolute date. Cached
-- across rows in one builtin call.
local function boot_time()
    local s = read_file("/proc/stat")
    if not s then return nil end
    return tonumber(string.match(s, "btime%s+(%d+)"))
end

-- Clock ticks per second — _SC_CLK_TCK. Hardcoded 100 because
-- glibc uses USER_HZ=100 on every platform we ship to (verified
-- on aarch64-musl). If we ever switch to a target where this
-- differs, swap to /usr/bin/getconf CLK_TCK at builtin load.
local CLK_TCK = 100

local function format_started(starttime, btime)
    if not starttime or not btime then return "?" end
    local epoch = btime + math.floor(starttime / CLK_TCK)
    if os and os.date then
        return os.date("%H:%M:%S", epoch)
    end
    return tostring(epoch)
end

-- Wildcard match (single '*' in pattern == any chars). Empty
-- pattern matches anything.
local function wild_match(pattern, value)
    if not pattern or pattern == "" then return true end
    if not value then return false end
    -- Convert glob → Lua pattern.
    local pat = "^" .. string.gsub(
        H.lua_pattern_escape(pattern), "%%%*", ".*") .. "$"
    return string.match(value, pat) ~= nil
end

local function parse_filters(args)
    local f = {}
    for _, a in ipairs(args) do
        if type(a) == "string" then
            local k, v = string.match(a, "^([%w_]+)=(.*)$")
            if k and v then f[k] = v end
        end
    end
    return f
end

local function row_passes(row, filters, btime, my_uid)
    -- Default scope: same uid. Override with uid=any or uid=N.
    if filters.uid then
        if filters.uid ~= "any" then
            local want = tonumber(filters.uid)
            if want and row.uid ~= want then return false end
        end
    else
        if row.uid ~= my_uid then return false end
    end

    if filters.pid and tonumber(filters.pid) ~= row.pid then return false end
    if filters.ppid and tonumber(filters.ppid) ~= row.ppid then return false end
    if filters.state and filters.state ~= row.state then return false end
    if filters.exe and not wild_match(filters.exe, row.exe) then return false end
    if filters.comm and not wild_match(filters.comm, row.comm) then return false end
    if filters.cmd and not wild_match(filters.cmd, row.cmd) then return false end

    if filters.min_age then
        local want = tonumber(filters.min_age)
        if want and btime and row.starttime then
            local epoch = btime + math.floor(row.starttime / CLK_TCK)
            if (os.time() - epoch) < want then return false end
        end
    end
    return true
end

function suggest.ps(args, raw)
    -- Suggest filter-key prefixes when the cursor is mid-arg.
    local prefixes = {
        "exe=", "comm=", "cmd=", "ppid=", "pid=",
        "state=", "uid=", "min_age=",
    }
    local last = args[#args] or ""
    local set = {}
    for _, p in ipairs(prefixes) do
        if last == "" or string.sub(p, 1, #last) == last then
            table.insert(set, p)
        end
    end
    cat9.readline:suggest(set, "word", last)
end

function builtins.ps(...)
    local args = {...}
    local filters = parse_filters(args)
    local btime = boot_time()
    local my_uid = nil
    do
        local s = read_file("/proc/self/status")
        if s then my_uid = tonumber(string.match(s, "Uid:%s*(%d+)") or "") end
    end

    -- Walk /proc looking for numeric entries (PIDs).
    local ioh = root:fglob("/proc/*")
    if not ioh then
        cat9.add_message("ps: fglob /proc rejected")
        H.emit_result("ps:err:reason=fglob_rejected")
        return
    end
    ioh:lf_strip(true, "\0")

    local rows = {}
    local line, alive = ioh:read()
    while line do
        local pid_s = string.match(line, "/proc/(%d+)$")
        if pid_s then
            local pid = tonumber(pid_s)
            local stat = parse_stat(read_file(line .. "/stat"))
            local stat_status = parse_status(read_file(line .. "/status"))
            if stat then
                local row = {
                    pid = pid,
                    ppid = stat.ppid,
                    state = stat.state,
                    comm = stat.comm,
                    starttime = stat.starttime,
                    threads = stat_status and stat_status.threads or 0,
                    rss = stat_status and stat_status.rss or 0,
                    uid = stat_status and stat_status.uid or -1,
                    exe = read_link(line .. "/exe") or "",
                    cmd = parse_cmdline(read_file(line .. "/cmdline")),
                }
                if row_passes(row, filters, btime, my_uid) then
                    table.insert(rows, row)
                    if #rows >= H.MAX_FILES then break end
                end
            end
        end
        line, alive = ioh:read()
        if not alive then break end
    end
    ioh:close()

    -- Sort by PID for stable ordering.
    table.sort(rows, function(a, b) return a.pid < b.pid end)

    if #rows == 0 then
        cat9.add_message("ps: no matching processes")
        H.emit_result("ps:empty")
        return
    end

    local table_rows = {}
    for _, r in ipairs(rows) do
        table.insert(table_rows, {
            tostring(r.pid),
            tostring(r.ppid),
            r.state,
            format_started(r.starttime, btime),
            tostring(r.threads),
            tostring(r.rss),
            r.exe,
            r.cmd ~= "" and r.cmd or ("[" .. r.comm .. "]"),
        })
    end

    local spread = H.make_spread(
        "ps",
        {"PID", "PPID", "STATE", "STARTED", "THR", "RSS_KB", "EXE", "CMD"},
        table_rows)

    -- Cross-view: when a row is selected, publish the PID so other
    -- views (procfs, cores) can pipe into it.
    if spread and H.viz_bus and H.viz_bus.publish then
        spread.on_row_focus = function(row_idx)
            local row = rows[row_idx - 1] -- header takes row 1
            if not row then return end
            H.viz_bus.publish("ps", "pid", row_idx, {
                pid = row.pid,
                ppid = row.ppid,
                exe = row.exe,
                comm = row.comm,
            })
        end
    end

    H.emit_result(string.format("ps:ok:rows=%d", #rows))
end

end
