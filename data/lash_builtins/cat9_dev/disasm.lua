-- disasm <object.o> [--func <name>]
--
-- Spreadsheet of [addr, bytes, asm, src_file, src_line] for an
-- object file's disassembly. Calls `objdump -dS` (with --line-numbers
-- if the binary supports it) via lash.root:popen — explicit argv,
-- no /bin/sh.
--
-- The parser (cat9.dev_helpers.parse_objdump_line) returns one of
-- {kind=addr,…}, {kind=src,…}, {kind=func,…}; we walk the output
-- carrying current src state forward so each addr row inherits the
-- most recent source-line annotation.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.disasm = "Disassemble an .o into a spreadsheet (asm ↔ source)"

-- Senseye-applied step 6: persistent disasm spread. The spread is the
-- substrate; this is just another view that mutates in place when
-- re-driven instead of spawning a fresh window per invocation.
-- Future views (units cursor, errors cursor, trigram cluster click)
-- drive this view by publishing on the selection bus with a
-- `disasm_target` payload field — see the bus subscriber below.
local disasm_spread = nil
local disasm_current_path = nil
local disasm_current_func = nil

local function ensure_disasm_spread()
    if disasm_spread and disasm_spread.id then return disasm_spread end
    disasm_spread = H.make_spread(
        "disasm",
        {"addr", "bytes", "asm", "src_file", "src_ln"},
        {}
    )
    return disasm_spread
end

local function spread_clear(spread)
    if not (spread and spread.id and spread.cells) then return end
    -- cat9's spread builtin exposes the cells array; clear it down
    -- to row 1 (header) so the next pass starts fresh.
    for r = #spread.cells, 2, -1 do
        spread.cells[r] = nil
    end
end

function suggest.disasm(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.disasm(path, ...)
    if not path then
        cat9.add_message("disasm <object.o> [--func <name>]")
        return
    end

    local rest = {...}
    local target_func
    for i, v in ipairs(rest) do
        if v == "--func" and rest[i + 1] then
            target_func = rest[i + 1]
        end
    end

    -- Drive objdump synchronously and accumulate output.
    -- argv: objdump-binary, "-dS", "--line-numbers", path
    local argv = {"/usr/bin/objdump", "objdump", "-dS", "--line-numbers", path}

    local _, out, _, pid = root:popen(argv, "re")
    if not pid then
        cat9.add_message("disasm: couldn't spawn /usr/bin/objdump")
        return
    end

    local raw_lines = {}
    local line, alive = out:read(true)
    while line do
        table.insert(raw_lines, line)
        if #raw_lines >= H.MAX_LINES then break end
        line, alive = out:read(true)
        if not alive then break end
    end
    out:close()

    -- Parse, carrying src state forward. Optionally filter to one fn.
    local rows = {}
    local cur_src_file, cur_src_line, cur_src_text = nil, nil, ""
    local in_target = (target_func == nil)
    local cur_fn = nil

    for _, l in ipairs(raw_lines) do
        local p = H.parse_objdump_line(l)
        if p then
            if p.kind == "func" then
                cur_fn = p.name
                if target_func then
                    in_target = (p.name == target_func)
                end
                if in_target then
                    table.insert(rows, {
                        p.addr, "", "── " .. p.name .. " ──", "", ""
                    })
                end
            elseif p.kind == "src" then
                cur_src_file = p.file
                cur_src_line = p.line
                cur_src_text = p.content
            elseif p.kind == "addr" and in_target then
                table.insert(rows, {
                    p.addr, p.bytes, p.asm,
                    cur_src_file or "",
                    cur_src_line and tostring(cur_src_line) or "",
                })
            end
        else
            -- Possibly a source-content continuation line. If we have
            -- a recent src marker, append it to cur_src_text.
            if cur_src_file then
                cur_src_text = cur_src_text .. " " .. l
            end
        end
    end

    if #rows == 0 then
        cat9.add_message("disasm: no rows produced (target_func mismatch? object empty?)")
        H.emit_result(string.format("disasm:err:path=%s:reason=no_rows", path))
        return
    end

    -- Mutate the persistent spread in place. First disasm invocation
    -- creates it; subsequent ones replace its rows. The window
    -- doesn't proliferate as the user drills around.
    local spread = ensure_disasm_spread()
    if not spread then
        cat9.add_message("disasm: spreadsheet unavailable")
        H.emit_result(string.format("disasm:err:path=%s:reason=spreadsheet", path))
        return
    end
    spread_clear(spread)
    spread.short = string.format("disasm %s%s",
        path, target_func and (" --func " .. target_func) or "")
    for i, r in ipairs(rows) do
        for c, v in ipairs(r) do
            cat9.parse_string(cat9.readline,
                string.format("set #%d %d %d %s",
                    spread.id, i + 1, c, H.escape_cell(v)))
        end
    end
    disasm_current_path = path
    disasm_current_func = target_func
    H.emit_result(string.format("disasm:ok:path=%s:func=%s:rows=%d",
        path, tostring(target_func), #rows))
end

-- Selection-bus subscriber: any view can publish a payload with
-- `disasm_target = "/path/to/file.o"` (optionally `disasm_func =
-- "name"`) and this subscriber drives the persistent disasm view.
-- Same path + func as the current view → no-op (avoids redundant
-- objdump runs as the cursor sweeps the same row).
if H.viz_bus and H.viz_bus.subscribe then
    H.viz_bus.subscribe(function(_sensor, _key, _row, payload)
        if not (payload and payload.disasm_target) then return end
        local path = payload.disasm_target
        local func = payload.disasm_func
        if path == disasm_current_path and func == disasm_current_func then
            return
        end
        if func then
            builtins.disasm(path, "--func", func)
        else
            builtins.disasm(path)
        end
    end)
end

end
