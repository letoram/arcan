-- wc <file>          — line/word/byte count as a 1x3 spreadsheet.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.wc = "Word/line/byte count (spreadsheet output, pure Lua)"

function suggest.wc(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.wc(path, ...)
    if not path then
        cat9.add_message("wc >file<")
        H.emit_result("wc:err:reason=missing_args")
        return
    end
    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("wc: " .. tostring(err))
        H.emit_result(string.format("wc:err:path=%s:reason=%s",
            path, tostring(err)))
        return
    end
    local linec = #lines
    local words, bytes = 0, 0
    for _, line in ipairs(lines) do
        bytes = bytes + #line + 1  -- approximate +newline
        for _ in string.gmatch(line, "%S+") do words = words + 1 end
    end

    H.make_spread(
        "wc " .. path,
        {"lines", "words", "bytes"},
        {{linec, words, bytes}}
    )
    H.emit_result(string.format("wc:ok:path=%s:lines=%d:words=%d:bytes=%d",
        path, linec, words, bytes))
end

end
