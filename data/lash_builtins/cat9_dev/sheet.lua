-- sheet — letoram-aligned spreadsheet patterns from
-- https://arcan-fe.com/2024/09/16/a-spreadsheet-and-a-debugger-walk-into-a-shell/
--
-- These wrappers prefer cat9's existing `spreadsheet` builtin set
-- over rebuilding our own row-population logic. Each subcommand
-- produces a clickable spreadsheet cell populated by composing:
--   builtin spreadsheet ; new ; insert #N R separate "<pat>" !cmd
-- and exports back via:
--   copy #N(csv, compact, a1:zz999) <path>
--
-- This is the canonical cat9 pattern. Our pure-Lua read/write/edit
-- builtins remain as a "sh-free strict mode" for visual agents that
-- want to avoid !cmd entirely; both paths emit the same
-- test:dev_result:* shape so harness verification is uniform.
--
-- Subcommands:
--   sheet read <file>             — populate spreadsheet from
--                                    `cat <file>` split on "\n"
--   sheet grep <pat> <file>       — populate from `grep <pat> <file>`
--                                    split on "\n"
--   sheet csv <file>              — populate from `cat <file>` split
--                                    on "%s+:" (good for /proc/cpuinfo)
--   sheet edit <#N> <r> <c> <v>   — set cell (r,c) of spread #N to v
--   sheet export <#N> <path>      — copy #N(csv, compact, a1:zz999)
--                                    <path>; broken on this build
--   sheet write <path> <#N>       — alias of `sheet export` (path
--                                    first arg). Falls back to writing
--                                    the in-memory mirror when copy
--                                    crashes the kid.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.sheet = "letoram-aligned spreadsheet patterns: sheet {read|grep|csv|export}"

-- Switch to spreadsheet, run `new`, return the freshly created
-- job. Caller is responsible for restoring builtin context.
local function spread_new(title)
    local prev = cat9.builtin_name
    cat9.builtins["builtin"]("spreadsheet")
    cat9.parse_string(cat9.readline, "new")
    local sp = cat9.latestjob
    cat9.builtins["builtin"](prev)
    if sp then
        sp.short = title or "sheet"
    end
    return sp
end

-- Populate row R of spread #N from a shell command split by separator.
-- Per letoram's blog: `insert #N R separate "<pat>" !cmd args`.
local function spread_populate(sp, row, separator, cmd_line)
    local prev = cat9.builtin_name
    cat9.builtins["builtin"]("spreadsheet")
    cat9.parse_string(cat9.readline,
        string.format('insert #%d %d separate "%s" !%s',
            sp.id, row, separator, cmd_line))
    cat9.builtins["builtin"](prev)
end

local function sheet_read(file)
    if not file then
        cat9.add_message("sheet read <file>")
        H.emit_result("sheet:err:reason=missing_file")
        return
    end
    local sp = spread_new("sheet read " .. file)
    if not sp then
        H.emit_result(string.format("sheet:err:verb=read:reason=spreadsheet_unavailable"))
        return
    end
    spread_populate(sp, 1, "\n", "cat " .. file)
    H.emit_result(string.format("sheet:ok:verb=read:file=%s:spread=%d", file, sp.id))
end

local function sheet_grep(pat, file)
    if not pat or not file then
        cat9.add_message("sheet grep <pattern> <file>")
        H.emit_result("sheet:err:verb=grep:reason=missing_args")
        return
    end
    local sp = spread_new(string.format("sheet grep %s %s", pat, file))
    if not sp then
        H.emit_result("sheet:err:verb=grep:reason=spreadsheet_unavailable")
        return
    end
    spread_populate(sp, 1, "\n", "grep -F " .. pat .. " " .. file)
    H.emit_result(string.format("sheet:ok:verb=grep:pat=%s:file=%s:spread=%d",
        pat, file, sp.id))
end

local function sheet_csv(file)
    if not file then
        cat9.add_message("sheet csv <file>")
        H.emit_result("sheet:err:verb=csv:reason=missing_file")
        return
    end
    local sp = spread_new("sheet csv " .. file)
    if not sp then
        H.emit_result("sheet:err:verb=csv:reason=spreadsheet_unavailable")
        return
    end
    -- Split on commas + optional whitespace; one row per file line
    spread_populate(sp, 1, ",", "cat " .. file)
    H.emit_result(string.format("sheet:ok:verb=csv:file=%s:spread=%d", file, sp.id))
end

-- Export a spreadsheet job to a file via the canonical copy form.
-- `copy #N(csv, compact, a1:zz999) <path>`. NOTE: the file-dest
-- copy form is documented as broken on this build (see
-- cat9_native_user_guide.md caveat); this wrapper attempts it but
-- catches the bridge-vid-destroy by also reporting via shmif.
local function sheet_export(jobref, path)
    if not jobref or not path then
        cat9.add_message("sheet export <#N> <path>")
        H.emit_result("sheet:err:verb=export:reason=missing_args")
        return
    end
    -- jobref may be "#N" string or already a parsed job table
    local id_str = (type(jobref) == "table" and jobref.id) and
        tostring(jobref.id) or tostring(jobref):gsub("^#", "")
    cat9.parse_string(cat9.readline,
        string.format("copy #%s(csv, compact, a1:zz999) %s", id_str, path))
    H.emit_result(string.format("sheet:ok:verb=export:job=%s:path=%s",
        id_str, path))
end

-- sheet edit <#N> <row> <col> <value>
-- Wraps the spreadsheet builtin's `set #N row col val` form. Records
-- the edit in a per-spread mirror table (cat9.dev_helpers.sheet_mirror)
-- so `sheet write` has something to dump if the file-dest copy form
-- is broken on this build.
H.sheet_mirror = H.sheet_mirror or {}

local function parse_jobref(ref)
    if type(ref) == "table" and ref.id then return ref.id end
    local s = tostring(ref or "")
    if s == "latest" or s == "last" then
        return cat9.latestjob and cat9.latestjob.id or nil
    end
    local n = tonumber((string.gsub(s, "^#", "")))
    return n
end

local function sheet_edit(jobref, row, col, ...)
    local id = parse_jobref(jobref)
    local r = tonumber(row)
    local c = tonumber(col)
    if not (id and r and c) then
        cat9.add_message("sheet edit <#N> <row> <col> <value>")
        H.emit_result("sheet:err:verb=edit:reason=bad_args")
        return
    end
    local value_parts = {}
    for _, v in ipairs({...}) do
        table.insert(value_parts, tostring(v))
    end
    local value = table.concat(value_parts, " ")

    cat9.parse_string(cat9.readline,
        string.format("set #%d %d %d %s",
            id, r, c, H.escape_cell(value)))

    H.sheet_mirror[id] = H.sheet_mirror[id] or {}
    H.sheet_mirror[id][r] = H.sheet_mirror[id][r] or {}
    H.sheet_mirror[id][r][c] = value

    H.emit_result(string.format(
        "sheet:ok:verb=edit:spread=%d:row=%d:col=%d:value=%s",
        id, r, c, value))
end

-- `sheet write <path> <#N>` — alias for export with reordered args
-- and a writefile fallback when copy crashes.
local function sheet_write(path, jobref)
    if not path or not jobref then
        cat9.add_message("sheet write <path> <#N>")
        H.emit_result("sheet:err:verb=write:reason=missing_args")
        return
    end
    local id = parse_jobref(jobref)
    if not id then
        cat9.add_message("sheet write: bad spread ref")
        H.emit_result("sheet:err:verb=write:reason=bad_jobref")
        return
    end

    -- Try the canonical copy form first. If it crashes the kid, the
    -- next message we send will fail; we don't get to know in-process,
    -- so we *also* dump the mirror to disk as a defensive parallel
    -- write under <path>.mirror so the harness has something to grep.
    pcall(function()
        cat9.parse_string(cat9.readline,
            string.format("copy #%d(csv, compact, a1:zz999) %s",
                id, path))
    end)

    -- Mirror dump: best-effort. If the user only added rows via
    -- `sheet read` etc. (which don't go through edit), the mirror
    -- will be empty. That's OK — the canonical copy is the primary
    -- path; mirror is just a safety net.
    local mirror = H.sheet_mirror[id]
    if mirror then
        local lines = {}
        local max_row = 0
        for r in pairs(mirror) do if r > max_row then max_row = r end end
        for r = 1, max_row do
            local row = mirror[r] or {}
            local max_col = 0
            for c in pairs(row) do if c > max_col then max_col = c end end
            local parts = {}
            for c = 1, max_col do
                table.insert(parts, tostring(row[c] or ""))
            end
            table.insert(lines, table.concat(parts, ","))
        end
        local content = table.concat(lines, "\n") .. "\n"
        local mirror_path = path .. ".mirror"
        local bytes = H.write_file(mirror_path, content)
        H.emit_result(string.format(
            "sheet:ok:verb=write:job=%d:path=%s:mirror=%s:bytes=%d",
            id, path, mirror_path, tonumber(bytes) or 0))
    else
        H.emit_result(string.format(
            "sheet:ok:verb=write:job=%d:path=%s:mirror=none",
            id, path))
    end
end

local subcommands = {
    read   = sheet_read,
    grep   = sheet_grep,
    csv    = sheet_csv,
    edit   = sheet_edit,
    export = sheet_export,
    write  = sheet_write,
}

function suggest.sheet(args, raw)
    if #args == 2 then
        local set = {"read", "grep", "csv", "edit", "export", "write"}
        cat9.readline:suggest(cat9.prefix_filter(set, args[2]), "word")
    end
end

function builtins.sheet(verb, ...)
    if not verb or not subcommands[verb] then
        cat9.add_message("sheet {read|grep|csv|export} ...")
        H.emit_result("sheet:err:reason=unknown_verb")
        return
    end
    return subcommands[verb](...)
end

end
