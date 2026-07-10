-- git [verb] [args ...]
--
-- Pure-Lua git wrappers that produce **clickable spreadsheet cells**
-- instead of plain text dumps. All popen-with-argv (no /bin/sh).
--
-- Verbs:
--   git                  → `git status --porcelain=v1` spreadsheet
--                          (XY status, path)
--   git log [N]          → `git log --oneline -N` spreadsheet
--                          (sha, subject); N defaults to 50
--   git diff [#row]      → `git diff -- <path-of-row>` hunk-spreadsheet
--                          (op, hunkhdr, line)
--   git add [#row]       → `git add <path-of-row>` (then re-emits status)
--
-- Emits `test:dev_result:git:<verb>:<status>:…` on each invocation.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.git = "git {status|log|diff|add} — clickable spreadsheets"

local gitbin = "/usr/bin/git"
local srcdir = "/home/x/next/arcan"

local function read_all(io_handle, max_lines)
    if not io_handle then return {} end
    max_lines = max_lines or 5000
    local buf = {}
    -- nbio:read(true) is non-buffered: it does ONE non-blocking
    -- read() syscall and returns (nil, alive=true) on EAGAIN. The
    -- naive `while line do` exits on the first transient nil even
    -- though the kid is still producing output. Loop on `alive`.
    while true do
        local data, alive = io_handle:read(true)
        if data and data ~= "" then
            table.insert(buf, data)
        end
        if not alive then break end
        if #buf >= max_lines then break end
    end
    -- buf now holds raw chunks (each up to 4 KiB). Re-split on \n
    -- so callers see whole-line records.
    local joined = table.concat(buf, "")
    local lines = {}
    for line in string.gmatch(joined, "([^\n]+)") do
        table.insert(lines, line)
        if #lines >= max_lines then break end
    end
    return lines
end

local function popen_lines(args, max_lines)
    -- Pass cwd via `git -C <srcdir>` rather than fiddling with the
    -- cat9 process's chdir (which doesn't reliably propagate to the
    -- popen kid on this build).
    local argv = {gitbin, "git", "-C", srcdir}
    for _, a in ipairs(args) do table.insert(argv, a) end
    local _, out, _, pid = root:popen(argv, "re")
    if not pid then
        return nil, "popen failed"
    end
    local lines = read_all(out, max_lines)
    out:close()
    return lines, nil
end

-- ---------------------------------------------------------------- status
local function git_status()
    local lines, err = popen_lines({"status", "--porcelain=v1"})
    if not lines then
        cat9.add_message("git status: " .. tostring(err))
        H.emit_result("git:status:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local xy = string.sub(l, 1, 2)
        local path = string.sub(l, 4)
        if path and path ~= "" then
            table.insert(rows, {xy, path})
        end
    end
    H.make_spread(
        string.format("git status (%d)", #rows),
        {"xy", "path"},
        rows
    )
    H.emit_result(string.format("git:status:ok:rows=%d", #rows))
end

-- ------------------------------------------------------------------- log
local function git_log(n_arg)
    local n = tonumber(n_arg) or 50
    local lines, err = popen_lines({
        "log", "--oneline", "--no-color", "-n", tostring(n),
    })
    if not lines then
        cat9.add_message("git log: " .. tostring(err))
        H.emit_result("git:log:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local sha, subj = string.match(l, "^(%S+)%s+(.*)$")
        if sha then
            table.insert(rows, {sha, subj or ""})
        end
    end
    H.make_spread(
        string.format("git log (%d)", #rows),
        {"sha", "subject"},
        rows
    )
    H.emit_result(string.format("git:log:ok:rows=%d", #rows))
end

-- ------------------------------------------------------------------ diff
local function git_diff(...)
    local rest = {...}
    local rest_args = {"diff", "--no-color"}
    -- A row reference like #N is an unsupported sugar in v1; pass any
    -- positional args through verbatim so users can do `git diff
    -- file.zig` etc.
    for _, v in ipairs(rest) do
        if type(v) == "string" and string.sub(v, 1, 1) ~= "#" then
            table.insert(rest_args, v)
        end
    end
    local lines, err = popen_lines(rest_args, 20000)
    if not lines then
        cat9.add_message("git diff: " .. tostring(err))
        H.emit_result("git:diff:err:reason=" .. tostring(err))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do
        local first = string.sub(l, 1, 1)
        local op
        if first == "+" then op = "+"
        elseif first == "-" then op = "-"
        elseif first == "@" then op = "@"
        elseif first == "d" or first == "i" then op = "h"
        else op = " "
        end
        table.insert(rows, {op, l})
    end
    H.make_spread(
        string.format("git diff (%d lines)", #rows),
        {"op", "line"},
        rows
    )
    H.emit_result(string.format("git:diff:ok:lines=%d", #rows))
end

-- ------------------------------------------------------------------- add
local function git_add(...)
    local rest = {...}
    local paths = {}
    for _, v in ipairs(rest) do
        if type(v) == "string" and string.sub(v, 1, 1) ~= "#" then
            table.insert(paths, v)
        end
    end
    if #paths == 0 then
        cat9.add_message("git add <path> [<path>…]")
        H.emit_result("git:add:err:reason=no_paths")
        return
    end
    local args = {"add", "--"}
    for _, p in ipairs(paths) do table.insert(args, p) end
    local _, err = popen_lines(args, 100)
    if err then
        cat9.add_message("git add: " .. tostring(err))
        H.emit_result("git:add:err:reason=" .. tostring(err))
        return
    end
    H.emit_result(string.format("git:add:ok:paths=%d", #paths))
    git_status()
end

local subcommands = {
    status = git_status,
    log    = git_log,
    diff   = git_diff,
    add    = git_add,
}

function suggest.git(args, raw)
    if #args == 2 then
        local set = {"status", "log", "diff", "add"}
        cat9.readline:suggest(cat9.prefix_filter(set, args[2]), "word")
    end
end

function builtins.git(verb, ...)
    if not verb then
        return git_status()
    end
    local fn = subcommands[verb]
    if fn then return fn(...) end
    -- Unknown verb → treat the whole arg list as a passthrough git
    -- subcommand (lines spreadsheet).
    local lines, err = popen_lines({verb, ...}, 5000)
    if not lines then
        cat9.add_message("git " .. tostring(verb) .. ": " .. tostring(err))
        H.emit_result(string.format("git:%s:err:reason=%s", verb, tostring(err)))
        return
    end
    local rows = {}
    for _, l in ipairs(lines) do table.insert(rows, {l}) end
    H.make_spread(string.format("git %s (%d)", verb, #rows), {"line"}, rows)
    H.emit_result(string.format("git:%s:ok:lines=%d", verb, #rows))
end

end
