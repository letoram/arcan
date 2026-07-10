-- metrics [pid|name]
--
-- Polls /proc/<pid>/{stat,status} at 1Hz and renders the result as a
-- persistent "live metrics" spread. Each metric is one row; the
-- sparkline column shows the last 16 samples as concatenated
-- block-fill glyphs (senseye-style time series, one cell per metric).
--
-- Senseye-applied step 3: this is the watchset / sparkline view. The
-- spread substrate gives us GPU rendering, persistence, click bus
-- subscription for free.
--
-- Default target: first process named "arcan" found in /proc.
-- Override: `metrics 1234` (pid) or `metrics durden` (substring of
-- /proc/<pid>/comm).
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.metrics = "metrics [pid|name] — live RSS/CPU/threads/fds"

local SAMPLE_WINDOW = 16
local SPARK_GLYPHS = {"▁","▂","▃","▄","▅","▆","▇","█"}

local metrics_spread = nil
local metric_rows = {}    -- name → row in spread
local metric_history = {} -- name → ring buffer (size SAMPLE_WINDOW)
local metric_count = 0
local target_pid = nil
local prev_cpu_ticks = nil
local poll_installed = false

local function ensure_metrics_spread()
    if metrics_spread and metrics_spread.id then return metrics_spread end
    metrics_spread = H.make_spread(
        "live metrics",
        {"metric", "value", "unit", "sparkline", "last"},
        {}
    )
    return metrics_spread
end

local function timestamp()
    if os and os.date then return os.date("%H:%M:%S") end
    return "?"
end

-- Push one sample into a metric's ring buffer + render the spark line.
local function push_sample(name, value, unit)
    local spread = ensure_metrics_spread()
    if not spread then return end
    local hist = metric_history[name]
    if not hist then
        hist = {head = 1, count = 0, samples = {}}
        for i = 1, SAMPLE_WINDOW do hist.samples[i] = 0 end
        metric_history[name] = hist
    end
    hist.samples[hist.head] = value
    hist.head = hist.head % SAMPLE_WINDOW + 1
    if hist.count < SAMPLE_WINDOW then hist.count = hist.count + 1 end

    -- Find min/max in the active window for normalization.
    local lo, hi = math.huge, -math.huge
    for i = 1, hist.count do
        local v = hist.samples[i]
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    local range = hi - lo
    if range <= 0 then range = 1 end

    -- Render samples in chronological order (oldest → newest).
    local spark = ""
    local order_start = hist.head
    if hist.count < SAMPLE_WINDOW then order_start = 1 end
    for i = 0, hist.count - 1 do
        local idx = ((order_start - 1 + i) % SAMPLE_WINDOW) + 1
        local v = hist.samples[idx]
        local norm = (v - lo) / range
        local g = math.floor(norm * 7 + 0.5) + 1
        if g < 1 then g = 1 end
        if g > 8 then g = 8 end
        spark = spark .. SPARK_GLYPHS[g]
    end

    local row = metric_rows[name]
    if not row then
        metric_count = metric_count + 1
        row = metric_count + 1
        metric_rows[name] = row
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %q",
                spread.id, row, name))
    end
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 2 %q",
            spread.id, row, tostring(value)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 3 %q",
            spread.id, row, unit or ""))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 4 %q",
            spread.id, row, spark))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 5 %q",
            spread.id, row, timestamp()))
end

local function read_first_line(path)
    local f = root:fopen(path, "r")
    if not f then return nil end
    local line = f:read(true)
    f:close()
    return line
end

local function read_all_lines(path)
    local f = root:fopen(path, "r")
    if not f then return nil end
    local out = {}
    local line, alive = f:read(true)
    while line do
        table.insert(out, line)
        line, alive = f:read(true)
        if not alive then break end
    end
    f:close()
    return out
end

-- Find a process by exact comm match or substring. Returns pid or nil.
-- Tries /proc enumeration via H.list_dir first; fossil-restricted
-- fglob may not enumerate /proc on some platforms, so fall back to
-- pgrep via root:popen.
local function find_pid_by_name(name)
    local entries = H.list_dir("/proc")
    if entries then
        for _, ent in ipairs(entries) do
            local pid = tonumber(ent.name)
            if pid then
                local comm = read_first_line("/proc/" .. pid .. "/comm")
                if comm then
                    comm = comm:gsub("[\r\n]", "")
                    if comm == name or string.find(comm, name, 1, true) then
                        return pid
                    end
                end
            end
        end
    end
    -- Fallback: pgrep -x <name>
    local _, out, _, pid = root:popen({"/usr/bin/pgrep", "pgrep", "-x", name}, "re")
    if pid and out then
        local line = out:read(true)
        out:close()
        if line then
            local n = tonumber(line:gsub("[\r\n%s]", ""))
            if n then return n end
        end
    end
    -- Last-ditch: pgrep -f <name> (substring match across full cmdline)
    local _, out2, _, pid2 = root:popen({"/usr/bin/pgrep", "pgrep", "-f", name}, "re")
    if pid2 and out2 then
        local line = out2:read(true)
        out2:close()
        if line then
            local n = tonumber(line:gsub("[\r\n%s]", ""))
            if n then return n end
        end
    end
    return nil
end

-- /proc/<pid>/stat field 14 = utime (clock ticks), field 15 = stime.
-- Field 20 = num_threads. Field 23 = vsize. Field 24 = rss (pages).
local function parse_stat(line)
    -- comm field can contain spaces and parens; skip past the closing ').
    local close = string.find(line, ") ", 1, true)
    if not close then return nil end
    local rest = string.sub(line, close + 2)
    local fields = {}
    for tok in string.gmatch(rest, "%S+") do
        table.insert(fields, tok)
    end
    -- Index 1 in `fields` corresponds to field 3 in the original
    -- /proc/<pid>/stat layout (state). utime is field 14 → fields[12].
    return {
        utime = tonumber(fields[12]) or 0,
        stime = tonumber(fields[13]) or 0,
        threads = tonumber(fields[18]) or 0,
    }
end

local function parse_status_field(lines, key)
    for _, line in ipairs(lines) do
        local v = string.match(line, "^" .. key .. ":%s*(%d+)")
        if v then return tonumber(v) end
    end
    return nil
end

local function count_fds(pid)
    local entries = H.list_dir("/proc/" .. pid .. "/fd")
    return entries and #entries or 0
end

local function poll_once()
    if not target_pid then return true end
    local stat_line = read_first_line("/proc/" .. target_pid .. "/stat")
    if not stat_line then
        target_pid = nil
        return true
    end
    local stat = parse_stat(stat_line)
    local status = read_all_lines("/proc/" .. target_pid .. "/status")
    if not (stat and status) then return true end

    local rss_kb = parse_status_field(status, "VmRSS") or 0
    local rss_mb = math.floor(rss_kb / 1024 + 0.5)
    push_sample("RSS", rss_mb, "MB")

    push_sample("threads", stat.threads, "")

    push_sample("fds", count_fds(target_pid), "")

    local total_ticks = stat.utime + stat.stime
    if prev_cpu_ticks then
        -- 1Hz tick on a USER_HZ=100 system → 100 ticks = 100% CPU.
        local pct = total_ticks - prev_cpu_ticks
        push_sample("cpu", pct, "%")
    end
    prev_cpu_ticks = total_ticks

    return true  -- keep polling
end

local function install_poll_timer()
    if poll_installed then return end
    poll_installed = true
    if cat9.timers then table.insert(cat9.timers, poll_once) end
end

function suggest.metrics(args, raw)
    -- A future enhancement could autocomplete process names from /proc.
end

function builtins.metrics(...)
    local args = {...}
    local arg = nil
    for _, v in ipairs(args) do
        if type(v) == "string" then arg = v; break end
    end
    if arg then
        local n = tonumber(arg)
        if n then
            target_pid = n
        else
            target_pid = find_pid_by_name(arg)
            if not target_pid then
                cat9.add_message("metrics: no process matching '" .. arg .. "'")
                H.emit_result("metrics:err:no_match=" .. arg)
                return
            end
        end
    else
        target_pid = find_pid_by_name("arcan")
        if not target_pid then
            cat9.add_message("metrics: no arcan process found (pass pid or name)")
            H.emit_result("metrics:err:no_arcan")
            return
        end
    end
    ensure_metrics_spread()
    install_poll_timer()
    -- Take an immediate sample so the spread isn't empty until first tick.
    poll_once()
    H.emit_result(string.format("metrics:start:pid=%d", target_pid))
end

end
