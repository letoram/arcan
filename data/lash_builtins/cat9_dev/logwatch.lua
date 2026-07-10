-- logwatch <file> [filter=regex] [emit=1] [tail=N]
--
-- Capture-and-classify reader for the arcan stderr log (or any
-- log file with embedded panic / trace markers). Phase 2.3 of
-- bug 0118. Replaces:
--
--   tail -N file | grep -E 'pattern'
--   grep -E 'RUNTIME PANIC|atlas miss' /tmp/arcan_panic.log
--
-- v1 is one-shot: scan a file, classify lines into known marker
-- buckets, emit a spread + shmon events. Follow-mode (true tail
-- -f shape) needs a background-worker primitive cat9 doesn't
-- expose to a sync builtin yet — left for v2.
--
-- Built-in marker buckets (priority order, first match wins):
--   PANIC     — RUNTIME PANIC | panic: | reached unreachable code
--   ATLAS     — [atlas miss], [atlas exhausted], [atlas init failed]
--   FONT      — [font race], [glyph extract], [font-cache]
--   ORPHAN    — [frameserver orphan]
--   FSRV      — frameserver_pushfd ... failed | platform_fsrv_*
--   SOCK      — sockpair_alloc | socketpoll
--   KBD       — EVTRACE feed: KBD
--
-- Each bucket gets emitted as a viz_bus event (sensor=log,
-- key=bucket) so other panes can react — atlas miss → atlas
-- pane blink, panic → memcloud red flash, etc.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.logwatch = "classify-and-emit log scanner — bug 0118 phase 2.3"

local BUCKETS = {
    {name = "PANIC",  pat = "RUNTIME%s+PANIC"},
    {name = "PANIC",  pat = "panic:"},
    {name = "PANIC",  pat = "reached unreachable code"},
    {name = "PANIC",  pat = "Trace/breakpoint trap"},
    {name = "ATLAS",  pat = "%[atlas miss%]"},
    {name = "ATLAS",  pat = "%[atlas exhausted%]"},
    {name = "ATLAS",  pat = "%[atlas init failed%]"},
    {name = "FONT",   pat = "%[font race%]"},
    {name = "FONT",   pat = "%[glyph extract%]"},
    {name = "FONT",   pat = "%[font%-cache%]"},
    {name = "ORPHAN", pat = "%[frameserver orphan%]"},
    {name = "FSRV",   pat = "frameserver_pushfd"},
    {name = "FSRV",   pat = "platform_fsrv_"},
    {name = "SOCK",   pat = "^sockpair_alloc"},
    {name = "SOCK",   pat = "^socketpoll"},
    {name = "KBD",    pat = "EVTRACE feed: KBD"},
}

local function classify(line)
    for _, b in ipairs(BUCKETS) do
        if string.find(line, b.pat) then return b.name end
    end
    return nil
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open " .. path end
    local lines = {}
    for l in f:lines() do
        table.insert(lines, l)
        if #lines >= H.MAX_LINES then break end
    end
    f:close()
    return lines
end

local function parse_args(args)
    local opts = {filter = nil, emit_each = false, tail = 0}
    local path = nil
    for _, a in ipairs(args) do
        if type(a) == "string" then
            local k, v = string.match(a, "^([%w_]+)=(.*)$")
            if k == "filter" then opts.filter = v
            elseif k == "emit" then opts.emit_each = (v == "1" or v == "true")
            elseif k == "tail" then opts.tail = tonumber(v) or 0
            elseif k then -- unknown
            else
                if not path then path = a end
            end
        end
    end
    return path, opts
end

function suggest.logwatch(args, raw)
    if #args == 2 then
        local last = args[2] or ""
        local argv, prefix, flt, offset =
            cat9.file_completion(last, cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    elseif #args >= 3 then
        local last = args[#args] or ""
        cat9.readline:suggest(
            {"filter=", "emit=1", "tail=200"}, "word", last)
    end
end

function builtins.logwatch(...)
    local path, opts = parse_args({...})
    if not path then
        cat9.add_message("logwatch <file> [filter=pat] [emit=1] [tail=N]")
        return
    end

    local lines, err = read_lines(path)
    if not lines then
        cat9.add_message("logwatch: " .. err)
        H.emit_result("logwatch:err:reason=open_failed:path=" .. path)
        return
    end

    -- Optional tail truncation.
    if opts.tail > 0 and #lines > opts.tail then
        local out = {}
        for i = #lines - opts.tail + 1, #lines do
            table.insert(out, lines[i])
        end
        lines = out
    end

    local rows = {}
    local counts = {}
    for line_no, line in ipairs(lines) do
        local bucket = classify(line)
        if bucket and (not opts.filter or string.find(line, opts.filter)) then
            counts[bucket] = (counts[bucket] or 0) + 1
            table.insert(rows, {
                tostring(line_no), bucket, line,
            })
            if opts.emit_each then
                H.emit_result(string.format(
                    "log:%s:line=%d", bucket, line_no))
            end
        end
    end

    local trows = {}
    for _, r in ipairs(rows) do
        table.insert(trows, r)
    end
    H.make_spread("logwatch " .. (path:match("([^/]+)$") or path),
        {"LINE", "BUCKET", "TEXT"}, trows)

    -- Summary line (and a viz_bus publish so subscribers see the
    -- bucket histogram).
    local summary_parts = {}
    for k, v in pairs(counts) do
        table.insert(summary_parts, string.format("%s=%d", k, v))
    end
    table.sort(summary_parts)
    local summary = table.concat(summary_parts, ":")
    if H.viz_bus and H.viz_bus.publish then
        H.viz_bus.publish("log", "summary", 0, {
            counts = counts,
            path = path,
            n_matched = #rows,
        })
    end
    H.emit_result(string.format(
        "logwatch:ok:path=%s:matched=%d:%s",
        path, #rows, summary ~= "" and summary or "empty"))

    if counts.PANIC and counts.PANIC > 0 then
        cat9.add_message(string.format(
            "logwatch: %d PANIC entries detected — pipe to "
            .. "`cores list since=-1h` to find the matching coredump.",
            counts.PANIC))
    end
end

end
