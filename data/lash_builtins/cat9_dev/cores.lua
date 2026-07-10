-- cores [list|info|debug|bt] [pid=N|since=-Nmin|exe=...]
--
-- Coredump browser. Phase 1.3 of bug 0118. Replaces:
--
--   coredumpctl list --since=-Nmin
--   coredumpctl info <pid>
--   coredumpctl debug <pid> --debugger-arguments='-batch -ex bt'
--
-- The bug 0114 / 0116 hunt's path was: spot a SIGTRAP, extract the
-- panic message from the dump's preserved stderr, walk the
-- backtrace to identify the panic site. Currently those are three
-- separate shell invocations that need parsing.
--
-- Subcommands:
--   cores                          — list recent (last 5 min)
--   cores list since=-1h exe=*arcan*
--   cores info <pid>               — header + signal + top frames
--   cores bt <pid>                 — full symbolized backtrace
--   cores debug <pid>              — alias for bt
--
-- Publishes on viz_bus when a frame is focused (sensor=cores,
-- key=frame), so disasm.lua can pick up the function name and
-- jump to its disassembly automatically.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.cores = "coredump browser — bug 0118 phase 1.3"

local function popen_lines(argv)
    local _, out, _, pid = root:popen(argv, "re")
    if not pid then return nil, "spawn failed: " .. argv[1] end
    local lines = {}
    local line, alive = out:read(true)
    while line do
        table.insert(lines, line)
        if #lines >= H.MAX_LINES then break end
        line, alive = out:read(true)
        if not alive then break end
    end
    out:close()
    return lines
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

-- Parse the header table coredumpctl emits. Format (since systemd
-- 250-ish):
--   TIME                       PID    UID  GID SIG     COREFILE EXE                    SIZE
--   Thu 2026-04-30 19:51:30 -05 302504 1000 1000 SIGTRAP present  /home/x/.../arcan    7M
local function parse_list(lines)
    local rows = {}
    for i, line in ipairs(lines) do
        if i > 1 and line and line ~= "" then
            -- TIME is 27 chars (Day YYYY-MM-DD HH:MM:SS ±HH); after
            -- that we can split on whitespace.
            local time_s = string.sub(line, 1, 27)
            local rest = string.sub(line, 28)
            local fields = {}
            for w in string.gmatch(rest, "%S+") do
                table.insert(fields, w)
            end
            -- fields: PID UID GID SIG COREFILE EXE SIZE
            if #fields >= 7 then
                table.insert(rows, {
                    time = string.gsub(time_s, "^%s+", ""),
                    pid = tonumber(fields[1]),
                    uid = tonumber(fields[2]),
                    sig = fields[4],
                    state = fields[5],
                    exe = fields[6],
                    size = fields[#fields],
                })
            end
        end
    end
    return rows
end

local function wild_match(pattern, value)
    if not pattern or pattern == "" then return true end
    if not value then return false end
    local pat = "^" .. string.gsub(
        H.lua_pattern_escape(pattern), "%%%*", ".*") .. "$"
    return string.match(value, pat) ~= nil
end

local function do_list(filters)
    local since = filters.since or "-5min"
    local argv = {
        "/usr/bin/coredumpctl", "coredumpctl",
        "list", "--no-pager", "--since=" .. since,
    }
    local lines, err = popen_lines(argv)
    if not lines then
        cat9.add_message("cores list: " .. err); return
    end
    local rows = parse_list(lines)
    -- post-filter on exe / sig / pid
    local kept = {}
    for _, r in ipairs(rows) do
        if filters.exe and not wild_match(filters.exe, r.exe) then
        elseif filters.sig and r.sig ~= filters.sig then
        elseif filters.pid and tonumber(filters.pid) ~= r.pid then
        else
            table.insert(kept, r)
        end
    end
    if #kept == 0 then
        cat9.add_message("cores list: no cores matching")
        H.emit_result("cores:list:empty")
        return
    end
    local trows = {}
    for _, r in ipairs(kept) do
        table.insert(trows, {
            r.time, tostring(r.pid), r.sig, r.size, r.exe,
        })
    end
    H.make_spread("cores",
        {"TIME", "PID", "SIG", "SIZE", "EXE"}, trows)
    H.emit_result(string.format("cores:list:rows=%d", #kept))
end

-- Info: header + the systemd-coredump preserved-stderr block (which
-- holds the panic message) + first ~12 backtrace frames.
local function extract_panic(info_lines)
    -- Look for "RUNTIME PANIC" / "panic:" / "Trace/breakpoint trap"
    -- in the embedded message body. coredumpctl info wraps these in
    -- the "Message:" section after the headers.
    local msg = nil
    local in_message = false
    for _, l in ipairs(info_lines) do
        if string.find(l, "^%s*Message:") then in_message = true end
        if in_message then
            local pm = string.match(l, "(panic:%s*[^\n]+)")
            local rp = string.match(l, "(RUNTIME%s+PANIC[^\n]+)")
            if pm and not msg then msg = pm end
            if rp and not msg then msg = rp end
        end
    end
    return msg
end

local function extract_top_frames(info_lines, limit)
    -- coredumpctl info dumps `Stack trace of thread N:` blocks; we
    -- want the first thread's frames.
    local frames = {}
    local in_block = false
    for _, l in ipairs(info_lines) do
        if string.find(l, "Stack trace of thread") then
            if in_block then break end -- only the first block
            in_block = true
        elseif in_block then
            -- "                #0  0xADDR symbol (...)"
            local n, sym = string.match(l, "#(%d+)%s+0x%x+%s+(.+)$")
            if n and sym then
                table.insert(frames, {n = tonumber(n), sym = sym})
                if #frames >= (limit or 12) then break end
            end
        end
    end
    return frames
end

local function do_info(pid_s)
    local argv = {
        "/usr/bin/coredumpctl", "coredumpctl",
        "info", "--no-pager", pid_s,
    }
    local lines, err = popen_lines(argv)
    if not lines then
        cat9.add_message("cores info: " .. err); return
    end
    local panic = extract_panic(lines)
    local frames = extract_top_frames(lines, 16)

    local trows = {}
    if panic then
        table.insert(trows, {"PANIC", panic})
    end
    for _, f in ipairs(frames) do
        table.insert(trows, {string.format("#%d", f.n), f.sym})
    end
    if #trows == 0 then
        -- fallback: dump the first 30 lines so the user sees raw
        for i = 1, math.min(30, #lines) do
            table.insert(trows, {tostring(i), lines[i]})
        end
    end
    H.make_spread("cores info " .. pid_s,
        {"FRAME", "SYMBOL/MSG"}, trows)
    H.emit_result(string.format(
        "cores:info:pid=%s:panic=%s",
        pid_s, panic and "yes" or "no"))
end

-- Full symbolized backtrace via gdb -batch.
local function do_bt(pid_s)
    local argv = {
        "/usr/bin/coredumpctl", "coredumpctl",
        "debug", pid_s,
        "--debugger-arguments=" ..
            "-batch -ex 'set pagination off' -ex 'thread 1' -ex 'bt 32' -ex quit",
    }
    local lines, err = popen_lines(argv)
    if not lines then
        cat9.add_message("cores bt: " .. err); return
    end
    local frames = {}
    for _, l in ipairs(lines) do
        local n, addr, sym = string.match(l, "^#(%d+)%s+(0x%x+)%s+in%s+(.+)$")
        if n then
            table.insert(frames, {
                n = tonumber(n), addr = addr, sym = sym,
            })
        end
    end
    if #frames == 0 then
        cat9.add_message("cores bt: gdb produced no frames")
        H.emit_result("cores:bt:empty")
        return
    end
    -- Dedupe consecutive identical frames (defaultPanic shows up
    -- twice under simple_panic).
    local clean = {}
    for i, f in ipairs(frames) do
        if i == 1 or frames[i - 1].sym ~= f.sym then
            table.insert(clean, f)
        end
    end
    local trows = {}
    for _, f in ipairs(clean) do
        table.insert(trows, {
            string.format("#%d", f.n), f.addr, f.sym,
        })
    end
    local spread = H.make_spread(
        "cores bt " .. pid_s,
        {"FRAME", "PC", "SYMBOL"}, trows)

    -- Cross-view: clicking a frame publishes the symbol so disasm
    -- can jump to it.
    if spread and H.viz_bus and H.viz_bus.publish then
        spread.on_row_focus = function(row_idx)
            local f = clean[row_idx - 1]
            if not f then return end
            H.viz_bus.publish("cores", "frame", row_idx, {
                disasm_func = f.sym,
                addr_range = {tonumber(f.addr) or 0,
                              tonumber(f.addr) or 0},
            })
        end
    end

    H.emit_result(string.format(
        "cores:bt:pid=%s:frames=%d", pid_s, #clean))
end

function suggest.cores(args, raw)
    if #args == 3 then
        cat9.readline:suggest(
            {"list", "info", "bt", "debug"}, "word", args[3] or "")
    end
end

function builtins.cores(sub, ...)
    sub = sub or "list"
    if sub == "list" then
        do_list(parse_filters({...}))
    elseif sub == "info" then
        local pid_arg = ...
        if not pid_arg then
            cat9.add_message("cores info <pid>"); return
        end
        do_info(tostring(pid_arg))
    elseif sub == "bt" or sub == "debug" then
        local pid_arg = ...
        if not pid_arg then
            cat9.add_message("cores bt <pid>"); return
        end
        do_bt(tostring(pid_arg))
    else
        -- treat first arg as a since= shorthand or PID
        if string.match(sub, "^%d+$") then
            do_info(sub)
        else
            do_list(parse_filters({sub, ...}))
        end
    end
end

end
