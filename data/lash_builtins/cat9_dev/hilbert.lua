-- hilbert
--
-- Renders the persistent compile-units state as a 2D Hilbert-curve
-- grid: step idx N maps to (x, y) coordinates in a base × base grid
-- where consecutive indices are spatially adjacent. A flapping unit
-- becomes a cell that keeps changing in the same spatial region; the
-- eye picks up "this region of the build is unstable" before
-- reading any text.
--
-- Senseye-applied step 4. The hilbert mapping is borrowed verbatim
-- from senseye/senseye/hilbert.lua (BSD-3-Clause, Bjorn Stahl 2015)
-- — the math is identical; only the surrounding integration changes.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.hilbert = "hilbert — 2D space-filling map of compile units"

-- Senseye hilbert.lua port (lua-side d2xy). Drops the LuaJIT bit.bxor
-- shortcut: lash here is Lua 5.4 so we use bit ops.
local function rot(n, x, y, rx, ry)
    if ry == 0 then
        if rx == 1 then
            x = n - 1 - x
            y = n - 1 - y
        end
        return y, x
    end
    return x, y
end

local function d2xy(base, ofs)
    local x = 0
    local y = 0
    local t = ofs
    local s = 1
    while s < base do
        local rx = (math.floor(t / 2)) & 1
        local ry = (rx ~ t) & 1
        x, y = rot(s, x, y, rx, ry)
        x = x + s * rx
        y = y + s * ry
        t = math.floor(t / 4)
        s = s * 2
    end
    return x, y
end

-- Round n up to the nearest power of two ≥ 2.
local function next_pow2(n)
    local b = 2
    while b * b < n do b = b * 2 end
    return b
end

-- Map status → single block-shade glyph. The eye scans density:
-- many `█`s = lots of completed work, scattered `▒`s = running,
-- `▓`s standing out = failing cells.
local function status_block(s)
    if s == "ok" then return "█" end
    if s == "fail" then return "▓" end
    if s == "running" or s == "start" then return "░" end
    if s == "skip" then return "▒" end
    return " "
end

local hilbert_spread = nil
local hilbert_base = 0      -- last rendered base; recomputed when count grows past base²
local hilbert_highlight_xy = nil   -- {x, y} of cell to invert on next refresh

-- bug 0027: temporal blink on edit:ok / fossil:diff events.  When an
-- edit lands on a source file, we light the unit's hilbert cell for
-- a few refresh ticks then let it return to its status glyph.  The
-- senseye "cursor in hex highlights pointcloud cluster" pattern,
-- applied temporally instead of spatially.
local blink_cells = {}      -- unit_idx (0-indexed) → ticks remaining
local BLINK_TICKS = 4       -- ≈ 200-400ms at the autorefresh cadence
local BLINK_GLYPH = "◉"

-- E.4 heat / heightmap mode (TUI fallback for the GPU heightmap; the
-- arcan_vk surface that lifts this onto a 3D shader subscribes to the
-- same fail_history payload).  Toggled via `hilbert heat`; the bus
-- publish on each refresh carries `heat_density[xy]` for the GPU side.
local heat_mode = false
local fail_history = {}     -- unit_name → ring buffer of "ok"|"fail"|"running"|...
local FAIL_WINDOW = 16
-- Heightmap glyph ramp.  Index 1 = no fails in window, 8 = all fails.
local HEAT_GLYPHS = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

local function record_status(name, status)
    if not name then return end
    local hist = fail_history[name]
    if not hist then hist = {}; fail_history[name] = hist end
    table.insert(hist, status)
    while #hist > FAIL_WINDOW do table.remove(hist, 1) end
end

local function heat_density(name)
    local hist = fail_history[name]
    if not hist or #hist == 0 then return 0 end
    local fails = 0
    for _, s in ipairs(hist) do if s == "fail" then fails = fails + 1 end end
    return fails / #hist   -- 0..1
end

local function heat_glyph(d)
    local idx = 1 + math.floor(d * (#HEAT_GLYPHS - 1) + 0.5)
    if idx < 1 then idx = 1 end
    if idx > #HEAT_GLYPHS then idx = #HEAT_GLYPHS end
    return HEAT_GLYPHS[idx]
end

local function ensure_hilbert_spread(base)
    if hilbert_spread and hilbert_spread.id then return hilbert_spread end
    -- One header cell per column so cell_cursor[1] resolves x. Header
    -- text is just A/B/C…/AA/BB/… which the spreadsheet auto-fills if
    -- we leave it empty; we pass empty headers to keep them out of
    -- the user's way.
    local headers = {}
    for _ = 1, base or 4 do table.insert(headers, "") end
    hilbert_spread = H.make_spread("compile hilbert", headers, {})
    return hilbert_spread
end

local function spread_set_cell(spread, row, col, value)
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %q",
            spread.id, row, col, tostring(value)))
end

local function refresh()
    local state = H.units_state and H.units_state() or nil
    if not state or state.count <= 0 then return true end

    local base = next_pow2(state.count)
    if base < 4 then base = 4 end
    hilbert_base = base

    local spread = ensure_hilbert_spread(base)
    if not spread then return true end

    -- Build the 2D grid in memory, then write one cell per (col, row)
    -- so cell_cursor lands precisely on (x, y) when the user clicks.
    -- Wide-cell-per-row was a defect — it pinned col=1 and broke
    -- per-cell click resolution.
    local grid = {}
    for y = 0, base - 1 do grid[y] = {} ; for x = 0, base - 1 do grid[y][x] = " " end end

    -- Build heat payload for any GPU surface subscribing to hilbert
    -- (E.4 GPU lift uses this verbatim).  density[(x,y)] in 0..1 even
    -- when heat_mode is off so the spread + arcan_vk segment can be
    -- viewed simultaneously.
    local density = {}
    for i = 1, state.count do
        local x, y = d2xy(base, i - 1)
        local name = state.name_at(i + 1) or ("u" .. tostring(i))
        local s = state.status_at(i + 1) or "none"
        record_status(name, s)
        local d = heat_density(name)
        density[y * base + x] = d
        if heat_mode then
            grid[y][x] = heat_glyph(d)
        else
            grid[y][x] = status_block(s)
        end
    end

    if H.viz_bus and H.viz_bus.publish then
        H.viz_bus.publish("hilbert", "heat", 0, {
            base = base,
            density = density,
            window = FAIL_WINDOW,
            mode = heat_mode and "heat" or "status",
        })
    end

    if hilbert_highlight_xy then
        local hx, hy = hilbert_highlight_xy[1], hilbert_highlight_xy[2]
        if grid[hy] and grid[hy][hx] then
            grid[hy][hx] = "◉"
        end
    end

    -- bug 0027: paint blinking cells (active for N more ticks).
    if next(blink_cells) ~= nil then
        for idx, ticks in pairs(blink_cells) do
            if ticks > 0 then
                local x, y = d2xy(base, idx)
                if grid[y] and grid[y][x] then
                    grid[y][x] = BLINK_GLYPH
                end
            end
        end
    end

    -- Per-cell write. Spread row = y + 1 (1 is header), spread col =
    -- x + 1 (1-indexed). cell_cursor[1] now yields x, cell_cursor[2]
    -- yields y after subtracting 1 each.
    for y = 0, base - 1 do
        for x = 0, base - 1 do
            spread_set_cell(spread, y + 1, x + 1, grid[y][x])
        end
    end

    -- bug 0027: decrement blink timers AFTER painting so the cell is
    -- visible at least once before fading back.  Cells that hit 0 are
    -- removed; next refresh paints the underlying status glyph again.
    if next(blink_cells) ~= nil then
        local expired = {}
        for idx, ticks in pairs(blink_cells) do
            blink_cells[idx] = ticks - 1
            if blink_cells[idx] <= 0 then
                table.insert(expired, idx)
            end
        end
        for _, idx in ipairs(expired) do blink_cells[idx] = nil end
    end
    return true
end

-- bug 0027: light up unit cells whose name overlaps the given path
-- or unit string.  Used by the edit:* / fossil:diff:* subscriber to
-- find which hilbert cells to blink.
local function blink_by_name(name)
    if not name or name == "" then return end
    local state = H.units_state and H.units_state() or nil
    if not state then return end
    for i = 0, state.count - 1 do
        local unit_name = state.name_at(i + 2)
        if unit_name and unit_name ~= "" then
            if string.find(name, unit_name, 1, true)
               or string.find(unit_name, name, 1, true) then
                blink_cells[i] = BLINK_TICKS
            end
        end
    end
end

local function blink_by_path(path)
    if not path or path == "" then return end
    local base = string.match(path, "([^/]+)$") or path
    local stem = string.match(base, "(.+)%.[^.]+$") or base
    blink_by_name(base)
    if stem ~= base then blink_by_name(stem) end
end

-- Reverse: given (x, y) in hilbert space, find the unit idx whose
-- d2xy lands at that cell. Linear scan; for ≤1024 cells the cost is
-- invisible. Returns nil if no unit occupies that cell.
local function xy_to_idx(base, x, y)
    for i = 0, base * base - 1 do
        local cx, cy = d2xy(base, i)
        if cx == x and cy == y then
            local state = H.units_state and H.units_state() or nil
            if state and i < state.count then return i end
            return nil
        end
    end
    return nil
end

-- cell_cursor poller: with the per-cell grid layout (one set call per
-- (col, row) write), cell_cursor[1] resolves to the column the user
-- clicked, cell_cursor[2] to the row. Subtract 1 for the 0-indexed
-- (x, y) hilbert coordinates. Reverse-lookup unit, publish.
local cursor_state = {row = 0, col = 0}
local function poll_hilbert_cursor()
    if not (hilbert_spread and hilbert_spread.id and hilbert_spread.cell_cursor) then
        return true
    end
    local cc = hilbert_spread.cell_cursor
    local col, row = cc[1] or 0, cc[2] or 0
    if row ~= cursor_state.row or col ~= cursor_state.col then
        cursor_state.row, cursor_state.col = row, col
        if hilbert_base > 0 then
            local x = col - 1
            local y = row - 1
            if y >= 0 and y < hilbert_base and x >= 0 and x < hilbert_base then
                local idx = xy_to_idx(hilbert_base, x, y)
                if idx ~= nil then
                    local state = H.units_state and H.units_state() or nil
                    local name = state and state.name_at(idx + 2)
                    if name then
                        H.viz_bus.publish("hilbert", name, idx + 2, {
                            name = name,
                            hilbert_xy = {x, y},
                        })
                    end
                end
            end
        end
    end
    return true
end

-- Subscribe to bus: when another view selects a unit by name, find
-- its hilbert (x, y) and flag it for highlight on next refresh.
-- Also listens for bug 0027 edit:* / fossil:diff:* events: if the
-- payload carries an `edit_path`, `fossil_path`, or `build_unit`
-- key, the corresponding cell(s) blink for BLINK_TICKS refreshes.
if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(_sensor, _key, _row, payload)
        if not payload then return end

        -- bug 0027: temporal blink for edit / fossil / build events.
        local touched = false
        if payload.edit_path then
            blink_by_path(payload.edit_path); touched = true
        end
        if payload.fossil_path then
            blink_by_path(payload.fossil_path); touched = true
        end
        if payload.build_unit then
            blink_by_name(payload.build_unit); touched = true
        end
        if touched and hilbert_base > 0 then
            refresh()
        end

        if not payload.name then return end
        local state = H.units_state and H.units_state() or nil
        if not state or hilbert_base == 0 then return end
        for i = 0, state.count - 1 do
            if state.name_at(i + 2) == payload.name then
                local x, y = d2xy(hilbert_base, i)
                hilbert_highlight_xy = {x, y}
                refresh()
                return
            end
        end
        -- No match — clear any prior highlight.
        if hilbert_highlight_xy then
            hilbert_highlight_xy = nil
            refresh()
        end
    end)
end

local poll_installed = false

function builtins.hilbert(verb, ...)
    ensure_hilbert_spread()
    if verb == "heat" then
        heat_mode = not heat_mode
        H.emit_result("hilbert:mode=" .. (heat_mode and "heat" or "status"))
    elseif verb == "status" then
        heat_mode = false
        H.emit_result("hilbert:mode=status")
    end
    refresh()
    if not poll_installed then
        poll_installed = true
        if cat9.timers then
            table.insert(cat9.timers, refresh)
            table.insert(cat9.timers, poll_hilbert_cursor)
        end
    end
    H.emit_result("hilbert:start")
end

function suggest.hilbert(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"heat", "status"}, args[2]),
            "word")
    end
end

end
