-- region <file> <line> [ctx]    — show file lines around an anchor.
--
-- Default ctx = 12 (so a `region foo.zig 340` shows lines 328-352).
-- Replaces the `!!sed -n '340,360p' foo.zig` pattern called out as
-- cheating in feedback_use_cat9_view_edit.md. Bug 0028.
--
-- Variants for follow-up (NYI):
--   region <file> /<pat>/   — anchor by pattern match (first hit)
--   region <bug-id>         — pull anchor from fossil ticket snippet
--                             metadata (file: + lines: fields)
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.region =
    "Show file lines around an anchor (replaces sed-pre-crop)"

function suggest.region(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.region(path, line, ctx, ...)
    if not path or not line then
        cat9.add_message("region >file< >line< [ctx=12]")
        return
    end
    local anchor = tonumber(line)
    if not anchor or anchor < 1 then
        cat9.add_message(
            "region: <line> must be a positive integer (got " ..
            tostring(line) .. ")")
        return
    end
    local context = tonumber(ctx) or 12
    if context < 0 then context = 0 end

    -- Read enough lines to cover the upper bound. read_file_lines
    -- returns up to N lines; we ask for anchor+context+1 so the
    -- file-end marker behavior matches head.lua.
    local upper = anchor + context
    local lines, err = H.read_file_lines(path, upper + 1)
    if not lines then
        cat9.add_message("region: " .. tostring(err))
        return
    end

    local lo = math.max(1, anchor - context)
    local hi = math.min(#lines, upper)

    local out = {}
    for i = lo, hi do
        -- Prefix each line with its 1-based line number so the
        -- spread row clearly reads as "L342: code". Right-aligned
        -- to the highest line number's width for visual alignment.
        local lw = #tostring(hi)
        table.insert(out, string.format("%" .. lw .. "d: %s", i, lines[i]))
    end

    local data = {linecount = #out, bytecount = 0}
    for _, l in ipairs(out) do
        table.insert(data, l)
        data.bytecount = data.bytecount + #l
    end

    local short = string.format("region %s @%d \xc2\xb1%d",
        path, anchor, context)
    cat9.import_job({
        short = short,
        raw   = short,
        data  = data,
        exit  = 0,
    })

    -- Emit a viz_bus event so dwarf / disasm / hilbert can pivot
    -- to the same anchor.
    if H.viz_bus and H.viz_bus.publish then
        H.viz_bus.publish("region", path, anchor, {
            file = path,
            line = anchor,
        })
    end
    if H.emit_result then
        H.emit_result(string.format(
            "region:ok:path=%s:anchor=%d:ctx=%d:visible=%d",
            path, anchor, context, #out))
    end

    cat9.flag_dirty()
end

end
