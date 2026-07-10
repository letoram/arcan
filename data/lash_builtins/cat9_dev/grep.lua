-- grep <pattern> <file>
--
-- Pure-Lua content search. Lua patterns (NOT POSIX regex). Reads via
-- fopen, walks lines, matches via string.find. No `grep` binary, no
-- shell.
--
-- Visual: spreadsheet of [line, content] for single-file. For
-- directory recursion, we don't auto-recurse here — use `find` to get
-- a list and then iterate. Keeping this builtin simple matches the
-- 1-thought-1-cell philosophy.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.grep = "Search for a Lua pattern in a file (pure Lua, spreadsheet output)"

function suggest.grep(args, raw)
    if #args == 3 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[3], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.grep(pattern, path, ...)
    if not pattern or not path then
        cat9.add_message("grep <pattern> <file>")
        H.emit_result("grep:err:reason=missing_args")
        return
    end

    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("grep: " .. tostring(err))
        H.emit_result(string.format("grep:err:pat=%s:file=%s:reason=%s",
            pattern, path, tostring(err)))
        return
    end

    local matches = {}
    for i, line in ipairs(lines) do
        if string.find(line, pattern) then
            table.insert(matches, {tostring(i), line})
        end
    end

    if #matches == 0 then
        cat9.add_message("grep: no matches for /" .. pattern .. "/ in " .. path)
        H.emit_result(string.format("grep:ok:pat=%s:file=%s:matches=0",
            pattern, path))
        return
    end

    H.make_spread(
        string.format("grep %s %s (%d)", pattern, path, #matches),
        {"line", "content"},
        matches
    )
    H.emit_result(string.format("grep:ok:pat=%s:file=%s:matches=%d",
        pattern, path, #matches))
end

end
