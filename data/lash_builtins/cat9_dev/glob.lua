-- glob <pattern> [dir]
--
-- Single-directory glob via lash.root:fglob. Wildcards are
-- shell-style (*, ?). Defaults dir to cwd. Output is a spreadsheet
-- with [name, full_path].
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.glob = "Single-dir glob (shell-style wildcards, fglob-backed)"

function suggest.glob(args, raw)
    if #args == 3 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[3], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.glob(pattern, dir, ...)
    if not pattern then
        cat9.add_message("glob <pattern> [dir]")
        H.emit_result("glob:err:reason=missing_args")
        return
    end
    dir = dir or root:chdir()

    -- Build the fglob argument: dir/pattern
    local glob_arg = dir
    if not glob_arg:find("/$") then glob_arg = glob_arg .. "/" end
    glob_arg = glob_arg .. pattern

    local ioh = root:fglob(glob_arg)
    if not ioh then
        cat9.add_message("glob: fglob rejected " .. glob_arg)
        H.emit_result(string.format("glob:err:pat=%s:dir=%s:reason=fglob_rejected",
            pattern, dir))
        return
    end
    ioh:lf_strip(true, "\0")

    local rows = {}
    local line, alive = ioh:read()
    while line do
        if line ~= "" then
            local name = string.match(line, "([^/]+)$") or line
            table.insert(rows, {name, line})
            if #rows >= H.MAX_FILES then break end
        end
        line, alive = ioh:read()
        if not alive then break end
    end
    ioh:close()

    if #rows == 0 then
        cat9.add_message("glob: no matches for " .. glob_arg)
        H.emit_result(string.format("glob:ok:pat=%s:dir=%s:hits=0",
            pattern, dir))
        return
    end

    H.make_spread(
        string.format("glob %s (%d)", glob_arg, #rows),
        {"name", "path"},
        rows
    )
    H.emit_result(string.format("glob:ok:pat=%s:dir=%s:hits=%d",
        pattern, dir, #rows))
end

end
