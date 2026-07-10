-- dwarf — addr → DIE resolver (Group D.1).
--
-- Subscribes to addr-bearing payloads on H.viz_bus (currently
-- `addr_range` from disasm clicks; `frame_pc` and `coredump_addr`
-- when those land). For each address, shells out to eu-addr2line
-- (preferred) or llvm-addr2line and emits:
--
--   test:dev_result:dwarf:resolve:bin=...:addr=0x...:file=...:line=...:fn=...
--
-- and publishes ("dwarf", file, line, {bin, addr, fn}) so units / errors
-- / hilbert / snippets pivot to the source location as if a build error
-- pointed at it.
--
-- Subcommands:
--   dwarf                          — open the persistent spread
--   dwarf resolve <bin> <addr>     — one-shot resolution (hex or 0x-prefixed)
--   dwarf clear                    — wipe spread rows
--
-- Tool selection: $DWARF_TOOL env override, else first of:
--   /usr/bin/eu-addr2line, /usr/bin/llvm-addr2line, /usr/bin/addr2line
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.dwarf = "Resolve addr → file:line:fn via DWARF (eu/llvm-addr2line)"

-- Pick the resolver tool once at load time.
local TOOL = (cat9.env or {}).DWARF_TOOL
if not TOOL or TOOL == "" then
    for _, p in ipairs({
        "/usr/bin/eu-addr2line",
        "/usr/bin/llvm-addr2line",
        "/usr/bin/addr2line",
    }) do
        local f = io.open(p, "r")
        if f then f:close(); TOOL = p; break end
    end
end

local resolve_spread = nil
local function ensure_spread()
    if resolve_spread and resolve_spread.id then return resolve_spread end
    resolve_spread = H.make_spread(
        "dwarf",
        {"bin", "addr", "fn", "file", "line"},
        {})
    return resolve_spread
end

local function shell_quote(s)
    return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

-- Run one resolution. Returns {fn, file, line} or nil on failure.
local function resolve_one(bin, addr)
    if not (TOOL and bin and addr) then return nil end
    -- eu-addr2line / llvm-addr2line / addr2line all accept -e <bin> -f -C <addr>
    local cmd = string.format("%s -e %s -f -C %s 2>/dev/null",
        TOOL, shell_quote(bin), shell_quote(addr))
    local p = io.popen(cmd, "r")
    if not p then return nil end
    local fn = p:read("*l") or "??"
    local fline = p:read("*l") or "??:0"
    p:close()
    if fn == "" or fline == "" or fline == "??:0" then return nil end
    local file, line = string.match(fline, "^(.+):([0-9]+)")
    if not file then return nil end
    return {fn = fn, file = file, line = tonumber(line) or 0}
end

local function add_row(bin, addr, info)
    local spread = ensure_spread()
    if not spread then return end
    local row = #spread.cells + 1
    local fn = info and info.fn or "??"
    local file = info and info.file or "??"
    local line = info and tostring(info.line) or "0"
    -- Compress bin path to last segment for readability.
    local bin_short = string.match(bin, "([^/]+)$") or bin
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 1 %s",
            spread.id, row, H.escape_cell(bin_short)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 2 %s",
            spread.id, row, H.escape_cell(addr)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 3 %s",
            spread.id, row, H.escape_cell(fn)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 4 %s",
            spread.id, row, H.escape_cell(file)))
    cat9.parse_string(cat9.readline,
        string.format("set #%d %d 5 %s",
            spread.id, row, H.escape_cell(line)))

    H.emit_result(string.format(
        "dwarf:resolve:bin=%s:addr=%s:file=%s:line=%s:fn=%s",
        bin_short, addr, file, line, fn))

    if H.viz_bus and H.viz_bus.publish then
        H.viz_bus.publish("dwarf", file, info and info.line or 0, {
            file = file,
            line = info and info.line or 0,
            fn = fn,
            addr = addr,
            bin = bin,
        })
    end
end

local function dwarf_resolve(bin, addr)
    if not (bin and addr) then
        cat9.add_message("dwarf resolve <bin> <addr>")
        return
    end
    if not TOOL then
        cat9.add_message("dwarf: no addr2line tool found "
            .. "(eu-addr2line / llvm-addr2line / addr2line)")
        return
    end
    -- Normalize address: ensure 0x prefix.
    if not string.match(addr, "^0[xX]") then addr = "0x" .. addr end
    local info = resolve_one(bin, addr)
    if not info then
        cat9.add_message(string.format(
            "dwarf: could not resolve %s in %s", addr, bin))
        H.emit_result(string.format(
            "dwarf:err:bin=%s:addr=%s:reason=no_info",
            string.match(bin, "[^/]+$") or bin, addr))
        return
    end
    add_row(bin, addr, info)
end

local function dwarf_clear()
    if resolve_spread and resolve_spread.cells then
        for r = #resolve_spread.cells, 2, -1 do
            resolve_spread.cells[r] = nil
        end
    end
end

-- Open or focus the spread.
local function dwarf_open()
    ensure_spread()
    if not TOOL then
        cat9.add_message("dwarf: no addr2line tool found — resolutions will fail")
    else
        H.emit_result("dwarf:start:tool=" .. (string.match(TOOL, "[^/]+$") or TOOL))
    end
end

local subcommands = {
    resolve = dwarf_resolve,
    clear   = dwarf_clear,
    open    = dwarf_open,
}

function suggest.dwarf(args, raw)
    if #args == 2 then
        cat9.readline:suggest(
            cat9.prefix_filter({"resolve", "clear", "open"}, args[2]),
            "word")
    end
end

function builtins.dwarf(verb, ...)
    if not verb then return dwarf_open() end
    local sub = subcommands[verb]
    if sub then return sub(...) end
    cat9.add_message("dwarf {resolve <bin> <addr>|clear|open}")
end

-- Selection-bus subscriber: any view publishing addr_range or addr drives
-- the resolver. Payload contract:
--   addr_range = {start, end}  (we resolve `start`)
--   bin        = <abs path>     (REQUIRED for resolution)
if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(sensor, key, row, payload)
        if not payload then return end
        local addr
        if payload.addr then
            addr = payload.addr
        elseif payload.addr_range then
            local r = payload.addr_range
            addr = type(r) == "table" and r[1] or r
        else
            return
        end
        local bin = payload.bin or payload.disasm_target
        if not bin then return end
        if type(addr) == "number" then
            addr = string.format("0x%x", addr)
        elseif not string.match(addr, "^0[xX]") then
            addr = "0x" .. addr
        end
        local info = resolve_one(bin, addr)
        if info then add_row(bin, addr, info) end
    end)
end

end
