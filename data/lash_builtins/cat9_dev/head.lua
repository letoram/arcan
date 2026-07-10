-- head <file> [N]    — first N lines (default 10).
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.head = "First N lines of a file (pure Lua)"

function suggest.head(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.head(path, n, ...)
    if not path then
        cat9.add_message("head >file< [N]")
        return
    end
    n = tonumber(n) or 10
    local lines, err = H.read_file_lines(path, n + 1)
    if not lines then
        cat9.add_message("head: " .. tostring(err))
        return
    end
    -- Trim to n if we read more (read_file_lines stops at n+1 with marker)
    local out = {}
    for i = 1, math.min(n, #lines) do table.insert(out, lines[i]) end

    local data = {linecount = #out, bytecount = 0}
    for _, line in ipairs(out) do
        table.insert(data, line)
        data.bytecount = data.bytecount + #line
    end
    cat9.import_job({
        short = string.format("head %s %d", path, n),
        raw = string.format("head %s %d", path, n),
        data = data,
        exit = 0,
    })
    cat9.flag_dirty()
end

end
