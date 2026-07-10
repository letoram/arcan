-- procfs <pid> <view> [filter=value ...]
--
-- Typed /proc/<pid>/* accessor. Phase 1.2 of bug 0118. Replaces:
--
--   ls -la /proc/PID/fd/                       (fd view)
--   lsof -p PID                                (fd view + paths)
--   cat /proc/PID/task/*/{wchan,status}        (threads view)
--   cat /proc/PID/maps                         (maps view)
--   cat /proc/PID/status                       (status view)
--
-- Views:
--   procfs <pid>             — short summary (defaults to status)
--   procfs <pid> fd          — open file descriptors with target+flags
--   procfs <pid> threads     — per-thread state + wchan
--   procfs <pid> maps        — memory map (filter=heap, filter=memfd)
--   procfs <pid> status      — Name/State/PPid/VmRSS/Threads
--
-- The bug 0115/0116 hunt's lsof replacement — `procfs PID fd
-- target=*ttf` answers "is arcan still holding the deleted font fd?"
-- in one shmif-native call.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.procfs = "typed /proc/<pid>/* accessor — bug 0118 phase 1.2"

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*all")
    f:close()
    return data
end

-- readlink via root:popen so we resolve symlinks (and see the
-- "(deleted)" suffix on stale fd targets — load-bearing for
-- lsof-style diagnostics).
local function read_link(path)
    local _, out, _, pid = root:popen({"/usr/bin/readlink", "readlink", path}, "re")
    if not pid then return nil end
    local line = out:read(true)
    out:close()
    return line
end

-- ls /proc/PID/fd via fglob — each entry's "target" is what its
-- symlink points at, surfaced separately because the fd number
-- itself is also useful (sort by it, filter by it).
local function list_fd(pid_s, filter_target)
    local glob = "/proc/" .. pid_s .. "/fd/*"
    local ioh = root:fglob(glob)
    if not ioh then return nil, "fglob rejected " .. glob end
    ioh:lf_strip(true, "\0")
    local rows = {}
    local line, alive = ioh:read()
    while line do
        local fd = string.match(line, "/(%d+)$")
        if fd then
            local target = read_link(line) or "?"
            local deleted = string.find(target, " %(deleted%)$") ~= nil
            local clean = deleted
                and string.sub(target, 1, -11) or target
            -- target filter (substring/glob)
            local pass = true
            if filter_target and filter_target ~= "" then
                local pat = "^" .. string.gsub(
                    H.lua_pattern_escape(filter_target),
                    "%%%*", ".*") .. "$"
                pass = string.match(clean, pat) ~= nil
            end
            if pass then
                table.insert(rows, {
                    fd = tonumber(fd),
                    target = clean,
                    deleted = deleted,
                })
            end
        end
        line, alive = ioh:read()
        if not alive then break end
    end
    ioh:close()
    table.sort(rows, function(a, b) return a.fd < b.fd end)
    return rows
end

-- threads: walk /proc/PID/task/*, read each TID's wchan + status.
local function list_threads(pid_s)
    local glob = "/proc/" .. pid_s .. "/task/*"
    local ioh = root:fglob(glob)
    if not ioh then return nil, "fglob rejected " .. glob end
    ioh:lf_strip(true, "\0")
    local rows = {}
    local line, alive = ioh:read()
    while line do
        local tid = string.match(line, "/(%d+)$")
        if tid then
            local wchan = read_file(line .. "/wchan") or "?"
            wchan = string.gsub(wchan, "[\r\n%z]", "")
            local stat_status = read_file(line .. "/status") or ""
            local state = string.match(stat_status, "State:%s*(%S)") or "?"
            local name = string.match(stat_status, "Name:%s*([^\n]+)") or "?"
            table.insert(rows, {
                tid = tonumber(tid),
                state = state,
                wchan = wchan,
                name = name,
            })
        end
        line, alive = ioh:read()
        if not alive then break end
    end
    ioh:close()
    table.sort(rows, function(a, b) return a.tid < b.tid end)
    return rows
end

local function list_maps(pid_s, filter_substr)
    local data = read_file("/proc/" .. pid_s .. "/maps")
    if not data then return nil, "no /proc/" .. pid_s .. "/maps" end
    local rows = {}
    for line in string.gmatch(data, "[^\r\n]+") do
        if not filter_substr
            or filter_substr == ""
            or string.find(line, filter_substr, 1, true) then
            -- Format: addr_range perms offset dev inode [path]
            local addr, perms, off, dev, inode, path =
                string.match(line,
                    "^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
            if addr then
                table.insert(rows, {
                    addr = addr, perms = perms, off = off,
                    dev = dev, inode = inode, path = path or "",
                })
            end
        end
    end
    return rows
end

local function show_status(pid_s)
    local data = read_file("/proc/" .. pid_s .. "/status")
    if not data then return nil, "no /proc/" .. pid_s .. "/status" end
    local rows = {}
    for k in string.gmatch(data,
        "(Name:%s*[^\n]*)\n") do table.insert(rows, {"summary", k}) end
    -- Only the high-signal fields.
    local keep = {
        "Name", "State", "Tgid", "Pid", "PPid", "TracerPid",
        "Uid", "Gid", "FDSize", "Threads", "VmPeak", "VmSize",
        "VmRSS", "VmHWM", "VmStk", "VmExe", "VmLib",
        "voluntary_ctxt_switches", "nonvoluntary_ctxt_switches",
    }
    local set = {}
    for _, k in ipairs(keep) do set[k] = true end
    rows = {}
    for line in string.gmatch(data, "[^\r\n]+") do
        local k, v = string.match(line, "^(%w[%w_]*):%s*(.+)$")
        if k and set[k] then
            table.insert(rows, {k, v})
        end
    end
    return rows
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

function suggest.procfs(args, raw)
    if #args == 3 then
        -- view name
        cat9.readline:suggest(
            {"fd", "threads", "maps", "status"}, "word", args[3] or "")
    end
end

function builtins.procfs(pid_arg, view_arg, ...)
    if not pid_arg then
        cat9.add_message("procfs <pid> [fd|threads|maps|status] [filter=v]")
        return
    end
    local pid_s = tostring(pid_arg)
    if not string.match(pid_s, "^%d+$") then
        cat9.add_message("procfs: pid must be numeric, got " .. pid_s)
        return
    end

    -- Sanity-check that PID exists
    local check = read_file("/proc/" .. pid_s .. "/stat")
    if not check then
        cat9.add_message("procfs: no /proc/" .. pid_s .. " (process gone?)")
        H.emit_result("procfs:err:pid=" .. pid_s .. ":reason=enoent")
        return
    end

    local view = view_arg or "status"
    local filters = parse_filters({...})

    if view == "fd" then
        local rows, err = list_fd(pid_s, filters.target)
        if not rows then
            cat9.add_message("procfs fd: " .. err); return
        end
        local trows = {}
        for _, r in ipairs(rows) do
            table.insert(trows, {
                tostring(r.fd),
                r.deleted and "DEL" or "",
                r.target,
            })
        end
        H.make_spread("procfs " .. pid_s .. " fd",
            {"FD", "FLAG", "TARGET"}, trows)
        H.emit_result(string.format(
            "procfs:fd:pid=%s:rows=%d", pid_s, #rows))

    elseif view == "threads" then
        local rows, err = list_threads(pid_s)
        if not rows then
            cat9.add_message("procfs threads: " .. err); return
        end
        local trows = {}
        for _, r in ipairs(rows) do
            table.insert(trows, {
                tostring(r.tid), r.state, r.wchan, r.name,
            })
        end
        H.make_spread("procfs " .. pid_s .. " threads",
            {"TID", "STATE", "WCHAN", "NAME"}, trows)
        H.emit_result(string.format(
            "procfs:threads:pid=%s:rows=%d", pid_s, #rows))

    elseif view == "maps" then
        local rows, err = list_maps(pid_s, filters.grep or filters.filter)
        if not rows then
            cat9.add_message("procfs maps: " .. err); return
        end
        local trows = {}
        for _, r in ipairs(rows) do
            table.insert(trows, {
                r.addr, r.perms, r.off, r.dev, r.inode, r.path,
            })
        end
        H.make_spread("procfs " .. pid_s .. " maps",
            {"ADDR", "PERM", "OFF", "DEV", "INODE", "PATH"}, trows)
        H.emit_result(string.format(
            "procfs:maps:pid=%s:rows=%d", pid_s, #rows))

    elseif view == "status" then
        local rows, err = show_status(pid_s)
        if not rows then
            cat9.add_message("procfs status: " .. err); return
        end
        H.make_spread("procfs " .. pid_s .. " status",
            {"FIELD", "VALUE"}, rows)
        H.emit_result(string.format(
            "procfs:status:pid=%s", pid_s))
    else
        cat9.add_message("procfs: unknown view " .. view)
    end
end

end
