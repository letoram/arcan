-- read <file>
--
-- Pure-Lua file read. Opens via lash.root:fopen, drains lines via
-- sync nbio :read(true), creates a job whose body is the file
-- content. No /bin/sh, no `cat` binary spawn — just the TUI fopen
-- primitive.
--
-- Visual: standard cat9 cell. Collapsed shows config.collapsed_rows
-- (default 4); `view #N expand` to fill the screen. `view #N hex`
-- for binary inspection.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.read = "Read a file into a cat9 cell (pure Lua, no shell)"

function suggest.read(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.read(path, ...)
    if not path or type(path) ~= "string" or #path == 0 then
        cat9.add_message("read >file<")
        return
    end

    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("read: " .. tostring(err))
        H.emit_result(string.format("read:err:path=%s:reason=%s",
            path, tostring(err)))
        return
    end

    local data = {linecount = #lines, bytecount = 0}
    for _, line in ipairs(lines) do
        table.insert(data, line)
        data.bytecount = data.bytecount + #line
    end

    local job = {
        short = "read " .. path,
        raw = "read " .. path,
        data = data,
        exit = (err == "truncated") and 2 or 0,
    }
    cat9.import_job(job)
    cat9.flag_dirty()
    H.emit_result(string.format("read:ok:path=%s:lines=%d:bytes=%d",
        path, data.linecount, data.bytecount))
end

end
