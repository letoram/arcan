-- time — time-bucket aggregator (C.1) + E.3 record-replay scaffold.
--
-- C.1 (NOW): bucket aggregator over `auto-arch.round` events.  Each
-- round becomes a row in the time spread (round_id × wall × decision
-- × fitness × gates_pass/total).  Drives the existing senseye-style
-- "rounds column" surface.
--
-- E.3 (LATER): time-replay over arcan_record/arcan_lwa.  Every tick
-- (auto-arch round, AIR inst, codegen step) emits a frame; the user
-- scrubs the timeline and atlas / memcloud / dietree rewind in
-- lockstep via subscribers to ("time", tick, frame_id, …).  Listed
-- as a TODO at the bottom — needs arcan_record plumbing that's
-- outside cat9's lash environment.
--
-- Payload contract (publishers MUST emit):
--   sensor:  "time"
--   key:     "round_<N>" | "tick_<N>"
--   row:     <bucket_idx>
--   payload: {
--     bucket_id = <int>,
--     round_id  = "round_<N>",
--     tick      = <int>,
--     decision  = "merge"|"parity"|"rejected",
--     fitness   = <int>,
--     gates_pass = <int>,
--     gates_total = <int>,
--     timestamp = <iso8601>,
--   }
--
-- Subcommands:
--   time              — open the spread; auto-loads existing rounds
--   time refresh      — re-scan tools/auto-arch/log/round_*
--   time replay <id>  — TODO (E.3): scrub to round/tick id
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.time = "Round timeline + time-bucket aggregator (C.1; E.3 stub)"

local time_spread = nil
local arcan_root = "/home/x/next/arcan"

local function ensure_spread()
    if time_spread and time_spread.id then return time_spread end
    time_spread = H.make_spread(
        "time",
        {"round", "decision", "fitness", "gates", "duration"},
        {})
    return time_spread
end

local function spread_clear(s)
    if not (s and s.cells) then return end
    for r = #s.cells, 2, -1 do s.cells[r] = nil end
end

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local l = f:read("*l")
    f:close()
    return l
end

local function read_all(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function ls_rounds()
    local out = {}
    local p = io.popen("ls -1 " .. arcan_root
        .. "/tools/auto-arch/log/ 2>/dev/null | sort", "r")
    if not p then return out end
    for n in p:lines() do
        if string.match(n, "^round_") then table.insert(out, n) end
    end
    p:close()
    return out
end

local function load_round(round_id)
    local base = arcan_root .. "/tools/auto-arch/log/" .. round_id
    local fitness = read_first_line(base .. "/fitness.txt") or "?"
    local decision = read_first_line(base .. "/decision.txt") or "?"
    -- Count gates: parse gate_results.tsv RESULT lines
    local gates_pass, gates_total, started, finished = 0, 0, "", ""
    local tsv = read_all(base .. "/gate_results.tsv")
    if tsv then
        for line in string.gmatch(tsv, "([^\n]+)") do
            if string.match(line, "^GATE\tRESULT\t") then
                gates_total = gates_total + 1
                if string.find(line, "\tpass\t", 1, true) then
                    gates_pass = gates_pass + 1
                end
            elseif string.match(line, "^GATE\tRUN\t") then
                started = string.match(line, "\t([^\t]+)$") or ""
            elseif string.match(line, "^GATE\tSUMMARY\t") then
                finished = string.match(line, "\t([^\t]+)$") or ""
            end
        end
    end
    return {
        round_id = round_id,
        fitness = fitness,
        decision = decision,
        gates_pass = gates_pass,
        gates_total = gates_total,
        started = started,
        finished = finished,
    }
end

local function paint_rounds(rounds)
    local s = ensure_spread()
    if not s then return end
    spread_clear(s)
    for i, r in ipairs(rounds) do
        local row = i + 1
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %s", s.id, row, H.escape_cell(r.round_id)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 2 %s", s.id, row, H.escape_cell(r.decision)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 3 %s", s.id, row, H.escape_cell(r.fitness)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 4 %s", s.id, row,
                H.escape_cell(string.format("%d/%d", r.gates_pass, r.gates_total))))
        local dur = "?"
        if r.started ~= "" and r.finished ~= "" then
            dur = string.match(r.finished, "T(%d+:%d+)") or r.finished
        end
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 5 %s", s.id, row, H.escape_cell(dur)))
        if H.viz_bus and H.viz_bus.publish then
            local fitness_n = tonumber(string.match(r.fitness, "^(%d+)") or "0") or 0
            H.viz_bus.publish("time", r.round_id, i, {
                bucket_id = i, round_id = r.round_id,
                decision = r.decision,
                fitness = fitness_n,
                gates_pass = r.gates_pass,
                gates_total = r.gates_total,
                timestamp = r.started,
            })
        end
    end
    H.emit_result(string.format("time:loaded:rounds=%d", #rounds))
end

local function refresh()
    local rounds = ls_rounds()
    local out = {}
    for _, rid in ipairs(rounds) do
        table.insert(out, load_round(rid))
    end
    paint_rounds(out)
end

-- E.3 placeholder.  When arcan_record + a per-step ("time", tick, …)
-- bus is wired, this will scrub atlas/memcloud/dietree subscribers
-- back to the requested point.  Today: no-op + emit a marker so the
-- harness can verify the contract surface.
local function replay(round_or_tick)
    cat9.add_message("time replay: arcan_record lockstep not yet wired"
        .. " — payload contract is final (see top-of-file).")
    H.emit_result("time:replay:not_implemented:target="
        .. tostring(round_or_tick or "?"))
end

local subcommands = {
    refresh = refresh,
    replay  = replay,
}

function suggest.time(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"refresh", "replay"}, args[2]),
            "word")
    end
end

function builtins.time(verb, ...)
    ensure_spread()
    if not verb then return refresh() end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("time {refresh|replay <round_id>}")
end

end
