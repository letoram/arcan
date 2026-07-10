-- memcloud — live mapping point cloud (E.2).
--
-- TUI fallback for the GPU memory cloud: a live point cloud over
-- /proc/<pid>/maps + /proc/<pid>/smaps_rollup, rendered through
-- senseye's pcloud/trigram shader on the GPU side.  This builtin
-- hosts the data sampler + payload publisher; the arcan_vk consumer
-- is the same contract.
--
-- Payload contract:
--   sensor:  "memcloud"
--   key:     <region_name>      e.g. "[heap]" or "/lib/.../foo.so"
--   row:     <region_idx>
--   payload: {
--     addr_range = {start_int, end_int},
--     perms = "rwxp",
--     pgsz  = <bytes>,
--     rss   = <bytes>,
--     name  = <region_name>,
--   }
--
-- Subcommands:
--   memcloud               — open the spread for $(pgrep arcan)
--   memcloud pid <N>       — sample a different pid
--   memcloud refresh       — re-poll
--   memcloud gpu           — open arcan_vk + trigram shader (TODO)
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.memcloud = "Memory map cloud (TUI fallback for E.2)"

local memcloud_spread = nil
local current_pid = nil
local row_to_region = {}

-- bug 0027: temporal blink — when an edit lands on a source file or
-- fossil reports a dirty file, light up the memcloud region whose
-- name matches.  Mapping is heuristic (substring/basename match;
-- without DWARF index we can only approximate "this region holds
-- code derived from this source file").
local blink_rows = {}        -- spread row → ticks remaining
local BLINK_TICKS = 4

local function ensure_spread()
    if memcloud_spread and memcloud_spread.id then return memcloud_spread end
    memcloud_spread = H.make_spread(
        "memcloud",
        {"region", "perms", "size", "rss", "addr"},
        {})
    return memcloud_spread
end

local function spread_clear(s)
    if not (s and s.cells) then return end
    for r = #s.cells, 2, -1 do s.cells[r] = nil end
end

local function find_arcan_pid()
    local p = io.popen("pgrep -x arcan 2>/dev/null | head -1", "r")
    if not p then return nil end
    local pid = p:read("*l")
    p:close()
    return pid and tonumber(pid) or nil
end

local function parse_size_kb(line)
    local n = tonumber(string.match(line or "", "(%d+)%s*kB"))
    return n or 0
end

local function read_smaps_rollup(pid)
    local out = {rss = 0, pss = 0, swap = 0}
    local f = io.open("/proc/" .. tostring(pid) .. "/smaps_rollup", "r")
    if not f then return out end
    for line in f:lines() do
        if string.match(line, "^Rss:") then out.rss = parse_size_kb(line) end
        if string.match(line, "^Pss:") then out.pss = parse_size_kb(line) end
        if string.match(line, "^Swap:") then out.swap = parse_size_kb(line) end
    end
    f:close()
    return out
end

local function read_maps(pid)
    local rows = {}
    local f = io.open("/proc/" .. tostring(pid) .. "/maps", "r")
    if not f then return rows end
    local idx = 0
    for line in f:lines() do
        local lo_hex, hi_hex, perms, _, _, _, name =
            string.match(line, "^(%x+)%-(%x+) (%S+) (%S+) (%S+) (%S+)%s*(.*)$")
        if lo_hex and hi_hex and perms then
            idx = idx + 1
            local lo = tonumber(lo_hex, 16) or 0
            local hi = tonumber(hi_hex, 16) or 0
            local sz = hi - lo
            table.insert(rows, {
                idx = idx, name = (name == "" and "[anon]" or name),
                perms = perms,
                size = sz,
                addr_range = {lo, hi},
            })
        end
    end
    f:close()
    return rows
end

local function paint(rows)
    local s = ensure_spread()
    if not s then return end
    spread_clear(s)
    row_to_region = {}
    -- bug 0027: any blink_rows referring to a row index that no
    -- longer exists after spread_clear must be discarded so they
    -- don't ghost-paint a wrong region next refresh.
    blink_rows = {}
    for _, r in ipairs(rows) do
        local row = #s.cells + 1
        row_to_region[row] = r
        local short_name = r.name
        if #short_name > 50 then short_name = "…" .. string.sub(short_name, -49) end
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %s", s.id, row, H.escape_cell(short_name)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 2 %s", s.id, row, H.escape_cell(r.perms)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 3 %d", s.id, row, r.size))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 4 %s", s.id, row, "?"))   -- per-region rss is opt-in via /proc/pid/smaps (heavy)
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 5 %s", s.id, row,
                H.escape_cell(string.format("0x%x", r.addr_range[1]))))
        if H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("memcloud", r.name, r.idx, {
                name = r.name,
                addr_range = r.addr_range,
                perms = r.perms,
                pgsz = r.size,
            })
        end
    end
end

local function refresh()
    local pid = current_pid or find_arcan_pid()
    if not pid then
        cat9.add_message("memcloud: no arcan PID found and none specified")
        H.emit_result("memcloud:err:no_pid")
        return
    end
    current_pid = pid
    local rows = read_maps(pid)
    paint(rows)
    local roll = read_smaps_rollup(pid)
    H.emit_result(string.format(
        "memcloud:refresh:pid=%d:regions=%d:rss_kb=%d", pid, #rows, roll.rss))
end

local function set_pid(p)
    local n = tonumber(p)
    if not n then cat9.add_message("memcloud pid <N>"); return end
    current_pid = n
    refresh()
end

local function gpu_stub()
    cat9.add_message("memcloud gpu: arcan_vk + senseye/shaders/pcloud/trigram"
        .. " binding not yet wired — payload contract (top-of-file) is final.")
    H.emit_result("memcloud:gpu:not_implemented")
end

-- Cursor poller: click a region → publish (addr_range) so dwarf
-- resolves the start address to file:line:fn (via H.viz_bus).
local mem_cursor = {row = 0}
local function poll_mem_cursor()
    if not (memcloud_spread and memcloud_spread.id and memcloud_spread.cell_cursor) then
        return true
    end
    local r = memcloud_spread.cell_cursor[2] or 0
    if r ~= mem_cursor.row then
        mem_cursor.row = r
        local reg = row_to_region[r]
        if reg and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("memcloud", reg.name, r, {
                name = reg.name,
                addr_range = reg.addr_range,
                perms = reg.perms,
                pgsz = reg.size,
                bin = reg.name,    -- for dwarf.lua addr2line lookup
            })
            H.emit_result(string.format(
                "memcloud:click:region=%s:addr=0x%x:perms=%s",
                reg.name, reg.addr_range[1], reg.perms))
        end
    end
    return true
end

-- bug 0027: blink-decay timer.  Repaints the perms cell of each
-- blinking region with an inverted glyph; on each tick we decrement
-- the counter and restore the underlying perms when it hits 0.
local function poll_mem_blink()
    if not (memcloud_spread and memcloud_spread.id) then return true end
    if next(blink_rows) == nil then return true end
    local expired = {}
    for row, ticks in pairs(blink_rows) do
        local reg = row_to_region[row]
        if reg then
            if ticks > 0 then
                cat9.parse_string(cat9.readline,
                    string.format("set #%d %d 2 %s",
                        memcloud_spread.id, row,
                        H.escape_cell("◉" .. string.sub(reg.perms or "", 1, 3))))
                blink_rows[row] = ticks - 1
            else
                cat9.parse_string(cat9.readline,
                    string.format("set #%d %d 2 %s",
                        memcloud_spread.id, row, H.escape_cell(reg.perms or "")))
                table.insert(expired, row)
            end
        else
            table.insert(expired, row)
        end
    end
    for _, row in ipairs(expired) do blink_rows[row] = nil end
    return true
end

local function blink_region_by_path(path)
    if not path or path == "" then return end
    local base = string.match(path, "([^/]+)$") or path
    local stem = string.match(base, "(.+)%.[^.]+$") or base
    for row, reg in pairs(row_to_region) do
        local rname = reg.name or ""
        if rname ~= "" then
            if string.find(rname, base, 1, true)
               or string.find(rname, stem, 1, true) then
                blink_rows[row] = BLINK_TICKS
            end
        end
    end
end

local function blink_region_by_unit(unit)
    if not unit or unit == "" then return end
    for row, reg in pairs(row_to_region) do
        local rname = reg.name or ""
        if rname ~= "" then
            if string.find(rname, unit, 1, true)
               or string.find(unit, rname, 1, true) then
                blink_rows[row] = BLINK_TICKS
            end
        end
    end
end

if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(_sensor, _key, _row, payload)
        if not payload then return end
        if payload.edit_path then blink_region_by_path(payload.edit_path) end
        if payload.fossil_path then blink_region_by_path(payload.fossil_path) end
        if payload.build_unit then blink_region_by_unit(payload.build_unit) end
    end)
end

if cat9.timers then
    table.insert(cat9.timers, poll_mem_cursor)
    table.insert(cat9.timers, poll_mem_blink)
end

local subcommands = {
    refresh = refresh,
    pid     = set_pid,
    gpu     = gpu_stub,
}

function suggest.memcloud(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"refresh", "pid", "gpu"}, args[2]),
            "word")
    end
end

function builtins.memcloud(verb, ...)
    ensure_spread()
    if not verb then return refresh() end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("memcloud {refresh|pid <N>|gpu}")
end

end
