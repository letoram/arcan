-- edit <file> <pattern> <replacement> [g|first]
-- edit <file> -f <patchfile>                — bug 0022 patchfile mode
--
-- Pure-Lua file find/replace. Reads file via fopen, walks lines,
-- applies string.gsub(line, pattern, replacement) — Lua pattern
-- semantics. Writes back atomically (via fopen "w" — same path,
-- truncates).
--
-- Visual: spreadsheet of [line, before, after] — one row per
-- changed line. Click a row → future drill-through to source.
--
-- Modes:
--   default = "g" — replace all matches in every line.
--   "first"        — replace only the first match (in the whole file).
--   <number N>     — replace at most N matches per line (Lua gsub's nth arg).
--
-- Patchfile mode (bug 0022) — when the second arg is `-f`, the
-- third arg is a path to a TSV file with one PATTERN<TAB>REPLACEMENT
-- per line. Blank lines and lines starting with `#` are skipped.
-- Substitutions apply in file order; each gets its own emit row so
-- the status spread shows one event per pattern. The cat9 tokenizer
-- never sees the special chars (parens, quotes, escapes) because
-- they live in the file, not the command line.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.edit = "Find/replace in-place using Lua patterns (pure Lua)"

function suggest.edit(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

-- Apply a single (pattern, replacement) substitution to an in-memory
-- line array. Returns (new_lines, changes_table, n_changes). mode
-- semantics match the positional-form below ("g" / "first" / N).
local function apply_pattern(lines, pattern, replacement, mode)
    local n_per_line = nil
    if mode == "first" then
        n_per_line = 1
    elseif tonumber(mode) then
        n_per_line = tonumber(mode)
    end
    local changes = {}
    local first_done = false
    local new_lines = {}
    for i, line in ipairs(lines) do
        local before = line
        local after, n
        if mode == "first" and not first_done then
            after, n = string.gsub(line, pattern, replacement, 1)
            if n > 0 then first_done = true end
        elseif n_per_line then
            after, n = string.gsub(line, pattern, replacement, n_per_line)
        else
            after, n = string.gsub(line, pattern, replacement)
        end
        if n and n > 0 then
            table.insert(changes, {tostring(i), before, after})
        end
        table.insert(new_lines, after)
    end
    return new_lines, changes, #changes
end

-- Bug 0022 patchfile dispatch. patchfile is TSV: each non-blank,
-- non-#-comment line is "PATTERN<TAB>REPLACEMENT". Substitutions
-- apply in file order, in-memory, then a single write commits.
local function edit_from_patchfile(path, patchfile)
    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("edit -f: " .. tostring(err))
        H.emit_result(string.format("edit:err:path=%s:reason=%s",
            path, tostring(err)))
        return
    end
    local patch_lines, perr = H.read_file_lines(patchfile)
    if not patch_lines then
        cat9.add_message("edit -f: cannot read patchfile " ..
            tostring(patchfile) .. ": " .. tostring(perr))
        H.emit_result(string.format(
            "edit:err:path=%s:patchfile=%s:reason=%s",
            path, patchfile, tostring(perr)))
        return
    end

    local all_changes = {}
    local total_substitutions = 0
    local applied_pairs = 0
    for _, l in ipairs(patch_lines) do
        if l ~= "" and string.sub(l, 1, 1) ~= "#" then
            local pat, repl = string.match(l, "^([^\t]*)\t(.*)$")
            if pat and pat ~= "" then
                local new_lines, changes, n = apply_pattern(
                    lines, pat, repl, nil)
                lines = new_lines
                applied_pairs = applied_pairs + 1
                total_substitutions = total_substitutions + n
                -- Per-pair shmon emit so the status spread shows
                -- one row per pattern.
                H.emit_result(string.format(
                    "edit:ok:path=%s:pat=%s:changes=%d",
                    path, pat:sub(1, 60), n))
                -- Tag changes with which pattern produced them.
                for _, c in ipairs(changes) do
                    table.insert(all_changes,
                        {c[1], pat:sub(1, 24), c[2], c[3]})
                end
            end
        end
    end

    if total_substitutions == 0 then
        cat9.add_message("edit -f: no matches across " ..
            applied_pairs .. " pattern(s)")
        H.emit_result(string.format(
            "edit:err:path=%s:patchfile=%s:reason=no_matches",
            path, patchfile))
        return
    end

    -- Strip "(truncated …)" sentinel if present
    if lines[#lines] and string.sub(lines[#lines], 1, 12) == "(truncated a" then
        table.remove(lines, #lines)
    end

    local bytes, werr = H.write_file(path, lines)
    if not bytes then
        cat9.add_message("edit -f: " .. tostring(werr))
        H.emit_result(string.format("edit:err:path=%s:reason=%s",
            path, tostring(werr)))
        return
    end
    H.register_edit(path, "edit -f")

    H.make_spread(
        string.format("edit -f %s (%d patterns, %d changes)",
            path, applied_pairs, total_substitutions),
        {"line", "pat", "before", "after"},
        all_changes
    )
    H.emit_result(string.format(
        "edit:ok:path=%s:patchfile=%s:patterns=%d:changes=%d:bytes=%d",
        path, patchfile, applied_pairs, total_substitutions, bytes))
end

function builtins.edit(path, pattern, replacement, mode, ...)
    if not path or not pattern then
        cat9.add_message("edit >file< <pattern> <replacement> [g|first|N]")
        cat9.add_message("       or: edit >file< -f <patchfile>")
        H.emit_result("edit:err:reason=missing_args")
        return
    end

    -- Bug 0022 patchfile dispatch: `edit <file> -f <patchfile>`.
    if pattern == "-f" then
        if not replacement then
            cat9.add_message("edit -f: missing patchfile path")
            H.emit_result("edit:err:reason=missing_patchfile")
            return
        end
        return edit_from_patchfile(path, replacement)
    end

    if not replacement then
        cat9.add_message("edit >file< <pattern> <replacement> [g|first|N]")
        H.emit_result("edit:err:reason=missing_args")
        return
    end

    local lines, err = H.read_file_lines(path)
    if not lines then
        cat9.add_message("edit: " .. tostring(err))
        H.emit_result(string.format("edit:err:path=%s:reason=%s",
            path, tostring(err)))
        return
    end

    local n_per_line = nil  -- nil = global
    if mode == "first" then
        n_per_line = 1
    elseif tonumber(mode) then
        n_per_line = tonumber(mode)
    end

    local changes = {}
    local first_done = false
    local new_lines = {}

    for i, line in ipairs(lines) do
        local before = line
        local after, n
        if mode == "first" and not first_done then
            after, n = string.gsub(line, pattern, replacement, 1)
            if n > 0 then first_done = true end
        elseif n_per_line then
            after, n = string.gsub(line, pattern, replacement, n_per_line)
        else
            after, n = string.gsub(line, pattern, replacement)
        end
        if n and n > 0 then
            table.insert(changes, {tostring(i), before, after})
        end
        table.insert(new_lines, after)
    end

    if #changes == 0 then
        cat9.add_message("edit: no matches for /" .. pattern .. "/ in " .. path)
        H.emit_result(string.format("edit:err:path=%s:pat=%s:reason=no_matches",
            path, pattern))
        return
    end

    -- Strip away the "(truncated …)" marker if read_file_lines returned one
    -- so we don't write it back to disk.
    if new_lines[#new_lines] and string.sub(new_lines[#new_lines], 1, 12) == "(truncated a" then
        table.remove(new_lines, #new_lines)
    end

    local bytes, werr = H.write_file(path, new_lines)
    if not bytes then
        cat9.add_message("edit: " .. tostring(werr))
        H.emit_result(string.format("edit:err:path=%s:reason=%s",
            path, tostring(werr)))
        return
    end

    H.register_edit(path, "edit")

    H.make_spread(
        string.format("edit %s %d changes", path, #changes),
        {"line", "before", "after"},
        changes
    )
    H.emit_result(string.format("edit:ok:path=%s:pat=%s:changes=%d:bytes=%d",
        path, pattern, #changes, bytes))
end

end
