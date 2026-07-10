-- write <file> <content...>
--
-- Pure-Lua file write. <content...> is the rest of the line (joined
-- with single spaces). Writes via lash.root:fopen(file, "w") + nbio
-- :write — no /bin/sh, no echo binary spawn.
--
-- Visual: a small cell with a one-line summary "wrote N bytes to <file>".
-- Registers in the dev_helpers.edits tracker so `edits` cell shows it.
--
-- For multi-line content, use a temp form: `write <file> #N` to write
-- job N's data (each row becomes a line). For clipboard contents:
-- `write <file> clipboard:`.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.write = "Write a file (pure Lua, no shell). Usage: write <file> <content|#N|clipboard:>"

function suggest.write(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.write(path, ...)
    if not path then
        cat9.add_message("write >file< <content|#N|clipboard:>")
        H.emit_result("write:err:reason=missing_path")
        return
    end

    local args = {...}
    if #args == 0 then
        cat9.add_message("write: missing content")
        H.emit_result(string.format("write:err:path=%s:reason=missing_content", path))
        return
    end

    local content
    -- Job ref: first arg is a table {parg = ?, ...} or starts with #
    local first = args[1]
    if type(first) == "table" and first.id then
        -- cat9 parsed a job reference into a table
        local job = first
        if job.data and #job.data > 0 then
            local lines = {}
            for _, line in ipairs(job.data) do table.insert(lines, line) end
            content = lines
        else
            content = ""
        end
    elseif type(first) == "string" and first == "clipboard:" then
        -- clipboard read isn't a stable Lua API on cat9, so emit a
        -- diagnostic and treat as no-op for now
        cat9.add_message("write: clipboard: source NYI in dev/write — use a job ref instead")
        return
    else
        -- Plain string: join all remaining string args with spaces
        local parts = {}
        for _, v in ipairs(args) do
            if type(v) == "string" then table.insert(parts, v) end
        end
        content = table.concat(parts, " ")
    end

    local bytes, err = H.write_file(path, content)
    if not bytes then
        cat9.add_message("write: " .. tostring(err))
        H.emit_result(string.format("write:err:path=%s:reason=%s",
            path, tostring(err)))
        return
    end

    H.register_edit(path, "write")

    local data = {linecount = 1, bytecount = 0}
    local summary = string.format("wrote %d bytes to %s", bytes, path)
    table.insert(data, summary)
    data.bytecount = #summary

    cat9.import_job({
        short = "write " .. path,
        raw = "write " .. path,
        data = data,
        exit = 0,
    })
    cat9.flag_dirty()
    H.emit_result(string.format("write:ok:path=%s:bytes=%d", path, bytes))
end

end
