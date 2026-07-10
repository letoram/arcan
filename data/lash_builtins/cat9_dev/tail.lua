-- tail <file> [N]    — last N lines (default 10).
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.tail = "Last N lines of a file (pure Lua)"

function suggest.tail(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.tail(path, n, ...)
    if not path then
        cat9.add_message("tail >file< [N]")
        return
    end
    n = tonumber(n) or 10
    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("tail: " .. tostring(err))
        return
    end
    local start = math.max(1, #lines - n + 1)
    local out = {}
    for i = start, #lines do table.insert(out, lines[i]) end

    local data = {linecount = #out, bytecount = 0}
    for _, line in ipairs(out) do
        table.insert(data, line)
        data.bytecount = data.bytecount + #line
    end
    cat9.import_job({
        short = string.format("tail %s %d", path, n),
        raw = string.format("tail %s %d", path, n),
        data = data,
        exit = 0,
    })
    cat9.flag_dirty()
end

end
