-- atlas — build atlas (E.1).
--
-- TUI fallback for the GPU build atlas: a 3D scene where each .o
-- output is a tile in (x = compile-unit Hilbert idx, y = file size,
-- z = LLVM-vs-SH byte-diff count).  The arcan_vk segment that lifts
-- this onto a Vulkan shader subscribes to the same payload contract,
-- so no atlas-spread API changes are needed when the GPU surface
-- lands.
--
-- Payload contract (publishers MUST emit these fields):
--   sensor:  "atlas"
--   key:     <unit_name>      e.g. "Select.zig"
--   row:     <unit_idx>       e.g. 47
--   payload: {
--     name = <unit_name>,
--     hilbert_xy = {x, y},     existing canonical key
--     file_size = <bytes>,
--     diff_bytes = <0..N>,     LLVM-vs-SH .o byte-diff
--     status = "pass"|"fail"|"diff",
--   }
--
-- Subscribers:
--   - This file's TUI spread (atlas-table view)
--   - Future arcan_vk segment (atlas-3D, init stub at the bottom)
--   - hilbert.lua already subscribes to ("atlas", name, …) for
--     bidirectional cell hover.
--
-- Subcommands:
--   atlas               — open the table spread
--   atlas refresh       — re-poll the source data
--   atlas live          — open a long-line panorama spread; live-paint
--                        from `build.atlas` viz_bus emits (bug 0024)
--   atlas gpu           — try to open the arcan_vk surface (TODO)
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.atlas = "Build atlas — .o size × diff-bytes table (TUI fallback for E.1)"

local atlas_spread = nil
local last_rows = {}
local row_to_unit = {}    -- spread row → unit row (for cursor poller)

-- bug 0024: live-paint atlas — a second spread fed by `build.atlas`
-- viz_bus emits from zigbuild.lua.  One row per build unit, repainted
-- on every state transition so the user can see units flow
-- queued → building → ok|err in real time.  Status glyph palette
-- mirrors the bug-0024 acceptance criteria.
local atlas_live_spread = nil
local atlas_live_state = {
    rows = {},        -- spread row → {unit_idx, name, state, dur_ms}
    by_idx = {},      -- build_idx → spread row
    by_unit = {},     -- unit name → spread row (for fallback lookup)
    cursor = {row = 0},
    subscribed = false,
}

local STATE_GLYPH = {
    queued   = "·",
    cached   = "░",
    running  = "▒",
    building = "▒",   -- alias from zigbuild emit
    ok       = "▓",
    built    = "▓",
    err      = "█",
    fail     = "█",
}

local function ensure_spread()
    if atlas_spread and atlas_spread.id then return atlas_spread end
    atlas_spread = H.make_spread(
        "build atlas",
        {"unit", "idx", "size", "diff", "status"},
        {})
    return atlas_spread
end

local function spread_clear(s)
    if not (s and s.cells) then return end
    for r = #s.cells, 2, -1 do s.cells[r] = nil end
end

-- Source: tools/auto-arch/log/round_<latest>/diff-vs-llvm.log
-- emits TSV-like lines:  DIFF\tPASS\t<ref>\tllvm=N\tsh=N
--                        DIFF\tFAIL\t<ref>\tllvm=N\tsh=N\tdiff_bytes=K
local function read_latest_diff_log()
    local cmd = [[ls -1t /home/x/next/arcan/tools/auto-arch/log/round_*/diff-vs-llvm.log 2>/dev/null | head -1]]
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local path = p:read("*l")
    p:close()
    if not path or path == "" then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local rows = {}
    local idx = 0
    for line in f:lines() do
        local kind, status, ref, rest =
            string.match(line, "^DIFF\t(%w+)\t([%w%-_/.]+)\t(.*)$")
        -- Hmm — eat the leading "DIFF\t" then split:
        local _, status2, ref2, rest2 =
            string.match(line, "^(DIFF)\t(%w+)\t([^\t]+)\t(.*)$")
        if status2 and ref2 then
            local llvm = tonumber(string.match(rest2 or "", "llvm=(%d+)") or "0") or 0
            local sh   = tonumber(string.match(rest2 or "", "sh=(%d+)")   or "0") or 0
            local diff = tonumber(string.match(rest2 or "", "diff_bytes=(%d+)") or "0") or 0
            idx = idx + 1
            table.insert(rows, {
                idx = idx, name = ref2, size = llvm, sh = sh,
                diff = diff, status = string.lower(status2)
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
    row_to_unit = {}
    for _, r in ipairs(rows) do
        local row = #s.cells + 1
        row_to_unit[row] = r
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %s", s.id, row, H.escape_cell(r.name)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 2 %d", s.id, row, r.idx))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 3 %d", s.id, row, r.size))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 4 %d", s.id, row, r.diff))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 5 %s", s.id, row, H.escape_cell(r.status)))
        if H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("atlas", r.name, r.idx, {
                name = r.name,
                file_size = r.size,
                diff_bytes = r.diff,
                status = r.status,
            })
        end
    end
end

local function atlas_refresh()
    local rows = read_latest_diff_log() or {}
    last_rows = rows
    paint(rows)
    H.emit_result(string.format("atlas:refresh:rows=%d", #rows))
end

-- bug 0024: live-paint atlas (long-line panorama).
local function atlas_live_paint_unit(unit_idx, name, state, dur_ms, exit_code)
    if not atlas_live_spread then return end
    local row = atlas_live_state.by_idx[unit_idx]
    if not row and name then row = atlas_live_state.by_unit[name] end
    if not row then
        row = #atlas_live_state.rows + 2  -- header is row 1
        atlas_live_state.rows[row - 1] = {
            unit_idx = unit_idx, name = name,
            state = state, dur_ms = dur_ms or 0,
        }
        atlas_live_state.by_idx[unit_idx] = row
        if name then atlas_live_state.by_unit[name] = row end
    else
        local rec = atlas_live_state.rows[row - 1]
        if rec then
            rec.state = state
            rec.dur_ms = dur_ms or rec.dur_ms or 0
            rec.name = name or rec.name
        end
    end
    local glyph = STATE_GLYPH[state] or "?"
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 1 %s",
            atlas_live_spread.id, row, H.escape_cell(glyph)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 2 %d",
            atlas_live_spread.id, row, unit_idx or 0))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 3 %s",
            atlas_live_spread.id, row, H.escape_cell(name or "?")))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 4 %s",
            atlas_live_spread.id, row, H.escape_cell(state)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 5 %s",
            atlas_live_spread.id, row,
            H.escape_cell(string.format("%dms", dur_ms or 0))))
end

local function atlas_live_paint_done(target, steps, errors_n, status, exit_code)
    if not atlas_live_spread then return end
    local row = #atlas_live_state.rows + 2
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 1 %s",
            atlas_live_spread.id, row,
            H.escape_cell(STATE_GLYPH[status] or "·")))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 2 %s",
            atlas_live_spread.id, row, H.escape_cell("Σ")))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 3 %s",
            atlas_live_spread.id, row,
            H.escape_cell("done:" .. tostring(target or "?"))))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 4 %s",
            atlas_live_spread.id, row, H.escape_cell(status or "?")))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 5 %s",
            atlas_live_spread.id, row,
            H.escape_cell(string.format(
                "%d steps / %d err / exit=%d",
                steps or 0, errors_n or 0, exit_code or 0))))
end

local function atlas_live_subscribe()
    if atlas_live_state.subscribed then return end
    if not (H.viz_bus and H.viz_bus.subscribe) then return end
    H.viz_bus.subscribe(function(sensor, key, row, payload)
        if sensor ~= "build.atlas" then return end
        if not atlas_live_spread then return end
        if not payload then return end
        if key == "done" then
            atlas_live_paint_done(
                payload.build_unit, row,
                payload.errors_n or 0,
                payload.build_state, payload.build_exit)
            return
        end
        atlas_live_paint_unit(
            row, payload.build_unit or payload.name,
            payload.build_state or "queued",
            payload.dur_ms or 0,
            payload.build_exit or 0)
    end)
    atlas_live_state.subscribed = true
end

local function atlas_live()
    if not atlas_live_spread then
        atlas_live_spread = H.make_spread(
            "build atlas (live)",
            {"●", "idx", "unit", "state", "dur"},
            {})
    end
    atlas_live_subscribe()
    H.emit_result("atlas:live:opened")
end

-- Cursor poller for the live spread — clicking a row publishes the
-- unit on viz_bus so source/hilbert pivot.
local function poll_atlas_live_cursor()
    if not (atlas_live_spread and atlas_live_spread.id
        and atlas_live_spread.cell_cursor) then
        return true
    end
    local r = atlas_live_spread.cell_cursor[2] or 0
    if r ~= atlas_live_state.cursor.row then
        atlas_live_state.cursor.row = r
        local rec = atlas_live_state.rows[r - 1]
        if rec and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("build.atlas", rec.name or "?",
                rec.unit_idx or 0, {
                    build_unit  = rec.name,
                    build_state = rec.state,
                    build_exit  = 0,
                    name        = rec.name,
                })
            H.emit_result(string.format(
                "atlas:live:click:idx=%d:unit=%s:state=%s",
                rec.unit_idx or 0,
                tostring(rec.name or "?"),
                tostring(rec.state or "?")))
        end
    end
    return true
end

-- Stub: open an arcan_vk segment + senseye color shader for the 3D
-- atlas surface.  The Lua side wires the payload contract above into
-- the shader uniforms; the segment-init wrapper is TODO once the
-- arcan_vk lash binding lands.
local function atlas_gpu()
    cat9.add_message("atlas gpu: arcan_vk segment binding not yet wired"
        .. " — the payload contract (see top-of-file) is final;"
        .. " GPU init is a follow-up.")
    H.emit_result("atlas:gpu:not_implemented")
end

-- Cursor poller: clicking a unit row publishes the unit's name +
-- diff/size payload so disasm/dwarf/hilbert pivot.
local atlas_cursor = {row = 0}
local function poll_atlas_cursor()
    if not (atlas_spread and atlas_spread.id and atlas_spread.cell_cursor) then
        return true
    end
    local r = atlas_spread.cell_cursor[2] or 0
    if r ~= atlas_cursor.row then
        atlas_cursor.row = r
        local u = row_to_unit[r]
        if u and H.viz_bus and H.viz_bus.publish then
            H.viz_bus.publish("atlas", u.name, r, {
                name = u.name,
                file_size = u.size,
                diff_bytes = u.diff,
                status = u.status,
            })
            H.emit_result(string.format(
                "atlas:click:unit=%s:size=%d:diff=%d:status=%s",
                u.name, u.size, u.diff, u.status))
        end
    end
    return true
end

if cat9.timers then
    table.insert(cat9.timers, poll_atlas_cursor)
    table.insert(cat9.timers, poll_atlas_live_cursor)
end

local subcommands = {
    refresh = atlas_refresh,
    live    = atlas_live,
    gpu     = atlas_gpu,
}

function suggest.atlas(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"refresh", "live", "gpu"}, args[2]),
            "word")
    end
end

function builtins.atlas(verb, ...)
    ensure_spread()
    if not verb then return atlas_refresh() end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("atlas {refresh|live|gpu}")
end

end
