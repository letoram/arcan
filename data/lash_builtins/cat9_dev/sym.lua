-- sym <binary> [name=pattern] [disasm=symbol] [strings=pattern]
--
-- Symbol + disassembly browser. Phase 3.1 of bug 0118. Replaces:
--
--   nm <binary>
--   nm <binary> | grep pattern
--   objdump -d --disassemble=<symbol> <binary>
--   strings <binary> | grep pattern
--
-- The bug 0116 hunt used these three tools to:
--   1. find a global's address (`nm | grep atlas_curve_offset`)
--   2. verify a fix was in the binary (`strings | grep 'bug 0116'`)
--   3. confirm the fix landed in machine code (`objdump -d --disasm`)
--
-- Defaults: with just `sym <binary>`, dump the full symbol table
-- (sorted by address). With name=, filter by symbol-name regex.
-- disasm=symbol resolves the symbol and dumps its function body.
-- strings=pattern searches embedded literals.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.sym = "nm + strings + objdump unified — bug 0118 phase 3.1"

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

-- Parse `nm` output: "ADDR TYPE NAME"
-- ADDR may be empty (undefined symbols). TYPE is single char
-- (T = text, b = bss-local, B = bss-global, d = data, ...).
local function parse_nm(lines)
    local rows = {}
    for _, l in ipairs(lines) do
        local addr, typ, name = string.match(l, "^(%x*)%s+(%w)%s+(.+)$")
        if addr and typ and name then
            table.insert(rows, {
                addr = addr ~= "" and addr or "?",
                addr_n = tonumber(addr, 16) or 0,
                typ = typ,
                name = name,
            })
        end
    end
    return rows
end

-- Parse objdump -d output, very lightly — this is more or less
-- already covered by disasm.lua's H.parse_objdump_line; we just
-- forward.
local function dump_function(bin, sym)
    local argv = {
        "/usr/bin/objdump", "objdump",
        "-d", "--disassemble=" .. sym,
        bin,
    }
    return popen_lines(argv)
end

local function dump_strings(bin)
    return popen_lines({"/usr/bin/strings", "strings", "-a", bin})
end

local function parse_args(args)
    local bin = nil
    local opts = {}
    for _, a in ipairs(args) do
        if type(a) == "string" then
            local k, v = string.match(a, "^([%w_]+)=(.*)$")
            if k == "name" then opts.name = v
            elseif k == "disasm" then opts.disasm = v
            elseif k == "strings" then opts.strings = v
            elseif k == "type" then opts.type = v
            elseif k then
                -- unknown
            else
                if not bin then bin = a end
            end
        end
    end
    return bin, opts
end

function suggest.sym(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    else
        local last = args[#args] or ""
        cat9.readline:suggest({
            "name=", "disasm=", "strings=", "type=t", "type=b",
        }, "word", last)
    end
end

function builtins.sym(...)
    local args = {...}
    local bin, opts = parse_args(args)
    if not bin then
        cat9.add_message(
            "sym <binary> [name=pat] [disasm=sym] [strings=pat] [type=t|b|d]")
        return
    end
    -- sanity-check binary exists
    do
        local f = io.open(bin, "r")
        if not f then
            cat9.add_message("sym: cannot open " .. bin)
            H.emit_result("sym:err:reason=enoent:path=" .. bin)
            return
        end
        f:close()
    end

    if opts.disasm then
        local lines, err = dump_function(bin, opts.disasm)
        if not lines then
            cat9.add_message("sym disasm: " .. err); return
        end
        local rows = {}
        for _, l in ipairs(lines) do
            -- Skip blank / file-format lines, keep instruction lines.
            if l ~= "" then
                table.insert(rows, {tostring(#rows + 1), l})
            end
        end
        H.make_spread("sym disasm " .. opts.disasm,
            {"#", "ASM"}, rows)
        H.emit_result(string.format(
            "sym:disasm:bin=%s:sym=%s:lines=%d",
            bin, opts.disasm, #rows))
        return
    end

    if opts.strings then
        local lines, err = dump_strings(bin)
        if not lines then
            cat9.add_message("sym strings: " .. err); return
        end
        local pat = opts.strings
        local rows = {}
        for _, l in ipairs(lines) do
            if string.find(l, pat) then
                table.insert(rows, {l})
                if #rows >= H.MAX_LINES then break end
            end
        end
        H.make_spread("sym strings " .. (pat:sub(1, 32)),
            {"MATCH"}, rows)
        H.emit_result(string.format(
            "sym:strings:bin=%s:matches=%d", bin, #rows))
        if #rows == 0 then
            cat9.add_message(string.format(
                "sym strings: no matches for '%s' in %s — fix may "
                .. "not be in the linked output", pat, bin))
        end
        return
    end

    -- Default: full symbol table from nm
    local lines, err = popen_lines({"/usr/bin/nm", "nm", bin})
    if not lines then
        cat9.add_message("sym: " .. err); return
    end
    local rows = parse_nm(lines)
    -- name= filter
    if opts.name and opts.name ~= "" then
        local pat = opts.name
        local kept = {}
        for _, r in ipairs(rows) do
            if string.find(r.name, pat) then table.insert(kept, r) end
        end
        rows = kept
    end
    -- type= filter (single char)
    if opts.type and opts.type ~= "" then
        local kept = {}
        local want = opts.type:sub(1, 1)
        for _, r in ipairs(rows) do
            if r.typ == want or r.typ:lower() == want:lower() then
                table.insert(kept, r)
            end
        end
        rows = kept
    end
    -- sort by address
    table.sort(rows, function(a, b) return a.addr_n < b.addr_n end)
    if #rows == 0 then
        cat9.add_message("sym: no symbols match")
        H.emit_result("sym:nm:empty")
        return
    end

    local trows = {}
    for _, r in ipairs(rows) do
        table.insert(trows, {r.addr, r.typ, r.name})
    end
    H.make_spread("sym " .. (bin:match("([^/]+)$") or bin),
        {"ADDR", "T", "NAME"}, trows)

    -- viz_bus: clicking a row publishes the symbol — disasm.lua
    -- can subscribe and auto-disassemble on click.
    local spread = cat9.latestjob
    if spread and H.viz_bus and H.viz_bus.publish then
        spread.on_row_focus = function(row_idx)
            local r = rows[row_idx - 1]
            if not r then return end
            H.viz_bus.publish("sym", "symbol", row_idx, {
                disasm_func = r.name,
                disasm_target = bin,
                addr_range = {r.addr_n, r.addr_n},
            })
        end
    end

    H.emit_result(string.format(
        "sym:nm:bin=%s:rows=%d", bin, #rows))
end

end
