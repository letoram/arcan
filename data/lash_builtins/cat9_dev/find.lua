-- find <dir> [pattern]
--
-- Recursive directory walk via fglob (rooted at <dir>) + Lua-pattern
-- filename filter. Output is a spreadsheet with [path, kind].
--
-- Note: cat9.dev_helpers.walk_dir uses root:fstatus to differentiate
-- file/dir; if that's unavailable, all entries are reported as "file"
-- with a fallback test (suffix `/`).
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.find = "Recursive find (Lua pattern filter, pure Lua)"

function suggest.find(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

-- Cap rows so a `find /` doesn't try to populate a 100k-row
-- spreadsheet (each row is a cat9.parse_string("insert …") call;
-- pushing thousands through readline's parser at once can overrun
-- arcan's TUI write buffer).
local FIND_MAX_ROWS = 200

function builtins.find(dir, pattern, ...)
    if not dir then
        cat9.add_message("find <dir> [pattern]")
        H.emit_result("find:err:reason=missing_args")
        return
    end

    local rows = {}
    H.walk_dir(dir, {max_depth = 6}, function(ent)
        if #rows >= FIND_MAX_ROWS then return end
        if pattern then
            if not string.find(ent.name, pattern) then return end
        end
        local kind = ent.is_dir and "dir" or "file"
        table.insert(rows, {ent.full, kind})
    end)

    if #rows == 0 then
        cat9.add_message("find: no matches under " .. dir
            .. (pattern and (" for /" .. pattern .. "/") or ""))
        H.emit_result(string.format("find:ok:dir=%s:pat=%s:hits=0",
            dir, tostring(pattern)))
        return
    end

    H.make_spread(
        string.format("find %s%s (%d)", dir,
            pattern and (" " .. pattern) or "", #rows),
        {"path", "kind"},
        rows
    )
    H.emit_result(string.format("find:ok:dir=%s:pat=%s:hits=%d",
        dir, tostring(pattern), #rows))
end

end
