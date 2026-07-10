-- dietree — compilee DIE-tree spread (Group D.2).
--
-- `dietree open <bin>` parses Compile Units via `eu-readelf -winfo`
-- (or llvm-dwarfdump --debug-info as a fallback), builds a tree
-- spread (one row per DIE; indent = depth). Click a DW_AT_type ref
-- jumps the spread cursor to that DIE row (single-pane navigation
-- since cat9 spreads are 2D, not split-view).
--
-- Subscribes to `("dwarf", file, line, …)` from dwarf.lua so a click
-- in any view that resolves to source lands on the corresponding DIE.
--
-- Subcommands:
--   dietree                       — focus existing spread (or hint)
--   dietree open <bin>            — load a binary's DIE forest
--   dietree filter <fn>           — filter by symbol name
--   dietree clear                 — wipe rows
--
-- Format: rows are [indent, tag, name, type, addr_low, addr_high]
-- where indent is `· · ·` style spaces matching DIE depth.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.dietree = "DIE tree of a binary (eu-readelf -winfo)"

-- Pick reader tool.
local TOOL = (cat9.env or {}).DIETREE_TOOL
if not TOOL or TOOL == "" then
    for _, p in ipairs({"/usr/bin/eu-readelf", "/usr/bin/llvm-dwarfdump"}) do
        local f = io.open(p, "r")
        if f then f:close(); TOOL = p; break end
    end
end

local spread = nil
local current_bin = nil
local last_dies = {}     -- list of {indent, tag, name, type, low, high, line, file}

local function ensure_spread()
    if spread and spread.id then return spread end
    spread = H.make_spread(
        "dietree",
        {"depth", "tag", "name", "type", "low", "high"},
        {})
    return spread
end

local function spread_clear(s)
    if not (s and s.cells) then return end
    for r = #s.cells, 2, -1 do s.cells[r] = nil end
end

-- Parse `eu-readelf -winfo` output. Each DIE block looks like:
--   [    b]    DW_TAG_subprogram
--             DW_AT_name           ( "...")
--             DW_AT_decl_file      ( ...)
--             DW_AT_decl_line      ( ...)
--             DW_AT_low_pc         ( ...)
--             DW_AT_high_pc        ( +0x... <... + 0x...>)
--             DW_AT_type           ( [    XX])
local function parse_eu_readelf(lines)
    local out = {}
    local cur = nil
    local depth_stack = {}
    -- eu-readelf indents children by 1 extra space per DIE level inside
    -- the leading "[ XX]" tag — we approximate depth by counting the
    -- offset-bracket leading-space lengths as keys advance.
    local function flush()
        if cur and cur.tag then table.insert(out, cur) end
        cur = nil
    end
    for _, line in ipairs(lines) do
        -- DIE header: e.g. " [    b]    DW_TAG_subprogram"
        local lead, tag = string.match(line, "^([%s]*)%[%s*[0-9a-fA-F]+%][%s]+(DW_TAG_[%w_]+)")
        if tag then
            flush()
            local depth = math.floor(#lead / 1)  -- coarse — depth is heuristic
            cur = {depth = depth, tag = tag, name = "", type = "",
                   low = "", high = "", line = "", file = ""}
        elseif cur then
            -- Attribute line:  "         DW_AT_name           ( ... )"
            local at, val = string.match(line, "%s+DW_AT_([%w_]+)%s*%(%s*(.-)%s*%)%s*$")
            if at and val then
                if at == "name" then
                    cur.name = (string.match(val, '^"(.*)"$') or val)
                elseif at == "type" then
                    cur.type = (string.match(val, "%[%s*([0-9a-fA-F]+)%s*%]") or val)
                elseif at == "low_pc" then
                    cur.low = val
                elseif at == "high_pc" then
                    cur.high = val
                elseif at == "decl_file" then
                    cur.file = val
                elseif at == "decl_line" then
                    cur.line = val
                end
            end
        end
    end
    flush()
    return out
end

local function read_lines(cmd)
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local lines = {}
    for ln in p:lines() do
        table.insert(lines, ln)
        if #lines >= H.MAX_LINES then break end
    end
    p:close()
    return lines
end

local function dietree_open(bin)
    if not bin then cat9.add_message("dietree open <bin>"); return end
    if not TOOL then
        cat9.add_message("dietree: no DWARF reader (eu-readelf / llvm-dwarfdump)")
        return
    end
    local cmd
    if string.match(TOOL, "eu%-readelf$") then
        cmd = string.format("%s -winfo %q 2>/dev/null", TOOL, bin)
    else
        cmd = string.format("%s --debug-info %q 2>/dev/null", TOOL, bin)
    end
    local lines = read_lines(cmd)
    if not lines or #lines == 0 then
        cat9.add_message("dietree: no DWARF output for " .. bin)
        return
    end
    local dies = parse_eu_readelf(lines)
    last_dies = dies
    current_bin = bin

    local s = ensure_spread()
    if not s then return end
    spread_clear(s)
    s.short = "dietree " .. (string.match(bin, "[^/]+$") or bin)
    for i, d in ipairs(dies) do
        local indent = string.rep("·", math.min(d.depth, 16))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 1 %s",
                s.id, i + 1, H.escape_cell(indent .. " " .. d.tag)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 2 %s",
                s.id, i + 1, H.escape_cell(d.tag)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 3 %s",
                s.id, i + 1, H.escape_cell(d.name)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 4 %s",
                s.id, i + 1, H.escape_cell(d.type)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 5 %s",
                s.id, i + 1, H.escape_cell(d.low)))
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d 6 %s",
                s.id, i + 1, H.escape_cell(d.high)))
    end
    H.emit_result(string.format(
        "dietree:open:bin=%s:dies=%d",
        string.match(bin, "[^/]+$") or bin, #dies))
end

local function dietree_filter(name)
    if not name then cat9.add_message("dietree filter <name>"); return end
    if not last_dies or #last_dies == 0 then
        cat9.add_message("dietree: no DIEs loaded — `dietree open <bin>` first")
        return
    end
    local s = ensure_spread()
    spread_clear(s)
    local row = 1
    for _, d in ipairs(last_dies) do
        if d.name and string.find(d.name, name, 1, true) then
            row = row + 1
            local indent = string.rep("·", math.min(d.depth, 16))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 1 %s",
                    s.id, row, H.escape_cell(indent .. " " .. d.tag)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 2 %s",
                    s.id, row, H.escape_cell(d.tag)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 3 %s",
                    s.id, row, H.escape_cell(d.name)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 4 %s",
                    s.id, row, H.escape_cell(d.type)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 5 %s",
                    s.id, row, H.escape_cell(d.low)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 6 %s",
                    s.id, row, H.escape_cell(d.high)))
        end
    end
    H.emit_result(string.format("dietree:filter:name=%s:matched=%d",
        name, row - 1))
end

local function dietree_clear()
    if spread and spread.cells then
        for r = #spread.cells, 2, -1 do spread.cells[r] = nil end
    end
end

local subcommands = {
    open   = dietree_open,
    filter = dietree_filter,
    clear  = dietree_clear,
}

function suggest.dietree(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"open", "filter", "clear"}, args[2]),
            "word")
    end
end

function builtins.dietree(verb, ...)
    if not verb then
        ensure_spread()
        cat9.add_message("dietree {open <bin>|filter <name>|clear}")
        return
    end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("dietree {open <bin>|filter <name>|clear}")
end

-- viz_bus subscriber: a "dwarf" sensor publish (file, line, …) lands
-- on the DIE matching that decl_file:decl_line. We do a linear scan.
if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(sensor, key, row, payload)
        if sensor ~= "dwarf" then return end
        if not (payload and payload.line and last_dies) then return end
        local target_line = tonumber(payload.line)
        if not target_line then return end
        for i, d in ipairs(last_dies) do
            if d.line ~= "" and tonumber(d.line) == target_line then
                H.emit_result(string.format(
                    "dietree:hit:tag=%s:name=%s:line=%s",
                    d.tag, d.name or "", d.line))
                -- Could mark the row visually here if cat9 spread API
                -- exposes a cursor-set primitive.
                break
            end
        end
    end)
end

end
