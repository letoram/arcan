-- diegraph — DWARF DIE relation graph (E.5).
--
-- TUI fallback for the GPU DIE-graph: a force-directed 3D graph where
-- DIEs are nodes and DW_AT_type / DW_AT_specification /
-- DW_AT_abstract_origin links are edges.  This builtin extracts the
-- adjacency list from `eu-readelf -winfo` and publishes it for the
-- arcan_vk consumer.
--
-- Payload contract:
--   sensor:  "diegraph"
--   key:     <die_id>           e.g. "[0x1234]"
--   row:     <node_idx>
--   payload: {
--     die       = <id>,
--     tag       = "DW_TAG_…",
--     name      = <name>,
--     edges     = { {kind="type", to="[0xABCD]"}, … },
--     bin       = <abs path>,
--   }
--
-- Subcommands:
--   diegraph open <bin>            — load + paint adjacency
--   diegraph filter <name>         — restrict to nodes matching name
--   diegraph gpu                   — TODO (arcan_vk + force-directed shader)
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.diegraph = "DIE relation graph (TUI fallback for E.5)"

local TOOL = (cat9.env or {}).DIETREE_TOOL
if not TOOL or TOOL == "" then
    for _, p in ipairs({"/usr/bin/eu-readelf", "/usr/bin/llvm-dwarfdump"}) do
        local f = io.open(p, "r")
        if f then f:close(); TOOL = p; break end
    end
end

local spread = nil
local nodes = {}        -- list of {die, tag, name, edges = {...}}
local current_bin = nil

local function ensure_spread()
    if spread and spread.id then return spread end
    spread = H.make_spread(
        "diegraph",
        {"die", "tag", "name", "edges", "first_target"},
        {})
    return spread
end

local function spread_clear(s)
    if not (s and s.cells) then return end
    for r = #s.cells, 2, -1 do s.cells[r] = nil end
end

local function read_lines(cmd)
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local out = {}
    for ln in p:lines() do
        table.insert(out, ln)
        if #out >= H.MAX_LINES then break end
    end
    p:close()
    return out
end

-- Extract an adjacency list from `eu-readelf -winfo` output.  Each
-- DW_TAG line opens a new node; DW_AT_(type|specification|abstract_origin)
-- attributes become edges (kind=type/spec/abs).
local function parse_eu_readelf(lines)
    local out = {}
    local cur = nil
    local function flush()
        if cur and cur.die and cur.tag then table.insert(out, cur) end
        cur = nil
    end
    for _, line in ipairs(lines) do
        local id, tag = string.match(line, "%[%s*([0-9a-fA-F]+)%]%s+(DW_TAG_[%w_]+)")
        if id and tag then
            flush()
            cur = {die = id, tag = tag, name = "", edges = {}}
        elseif cur then
            local name = string.match(line, 'DW_AT_name%s*%(%s*"([^"]+)"')
            if name then cur.name = name end
            for kind, target in string.gmatch(line,
                    "DW_AT_(type)%s*%(%s*%[%s*([0-9a-fA-F]+)%s*%]") do
                table.insert(cur.edges, {kind = "type", to = target})
            end
            for target in string.gmatch(line,
                    "DW_AT_specification%s*%(%s*%[%s*([0-9a-fA-F]+)%s*%]") do
                table.insert(cur.edges, {kind = "spec", to = target})
            end
            for target in string.gmatch(line,
                    "DW_AT_abstract_origin%s*%(%s*%[%s*([0-9a-fA-F]+)%s*%]") do
                table.insert(cur.edges, {kind = "abs", to = target})
            end
        end
    end
    flush()
    return out
end

local function paint(filter_name)
    local s = ensure_spread()
    if not s then return end
    spread_clear(s)
    local idx = 0
    for _, n in ipairs(nodes) do
        if (not filter_name) or string.find(n.name or "", filter_name, 1, true) then
            idx = idx + 1
            local row = idx + 1
            local first_to = (n.edges[1] and n.edges[1].to) or ""
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 1 %s", s.id, row,
                    H.escape_cell("[" .. n.die .. "]")))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 2 %s", s.id, row, H.escape_cell(n.tag)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 3 %s", s.id, row, H.escape_cell(n.name)))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 4 %d", s.id, row, #n.edges))
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d 5 %s", s.id, row,
                    H.escape_cell(first_to)))
            if H.viz_bus and H.viz_bus.publish then
                H.viz_bus.publish("diegraph", n.die, idx, {
                    die = n.die, tag = n.tag, name = n.name,
                    edges = n.edges, bin = current_bin,
                })
            end
        end
    end
    H.emit_result(string.format("diegraph:painted:nodes=%d", idx))
end

local function diegraph_open(bin)
    if not bin then cat9.add_message("diegraph open <bin>"); return end
    if not TOOL then
        cat9.add_message("diegraph: no DWARF reader available")
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
        cat9.add_message("diegraph: no DWARF for " .. bin); return
    end
    nodes = parse_eu_readelf(lines)
    current_bin = bin
    paint(nil)
end

local function diegraph_filter(name)
    if #nodes == 0 then
        cat9.add_message("diegraph: no nodes loaded — `diegraph open <bin>` first")
        return
    end
    paint(name)
end

local function gpu_stub()
    cat9.add_message("diegraph gpu: 3D force-directed graph (arcan_vk + "
        .. "30-line shader) is the natural lift; payload contract is final.")
    H.emit_result("diegraph:gpu:not_implemented")
end

local subcommands = {
    open   = diegraph_open,
    filter = diegraph_filter,
    gpu    = gpu_stub,
}

function suggest.diegraph(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"open", "filter", "gpu"}, args[2]),
            "word")
    end
end

function builtins.diegraph(verb, ...)
    ensure_spread()
    if not verb then
        cat9.add_message("diegraph {open <bin>|filter <name>|gpu}")
        return
    end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("diegraph {open <bin>|filter <name>|gpu}")
end

end
