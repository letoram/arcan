-- hash <path...> [algo=md5|sha256|blake3]
--
-- Content + metadata inspection. Phase 2.1 of bug 0118. Replaces:
--
--   md5sum / sha256sum / b3sum
--   stat -c '%y %s %i %n'
--   file <path>
--   cmp a b
--
-- The bug 0114 / 0116 hunt's first decisive moment was
-- `md5sum *.ttf` showing all four font files were byte-identical
-- — that single readout immediately ruled OUT "different fonts
-- per slot" and ruled IN "single corrupted font copied four
-- times". Surface that as one cat9 line per group of files.
--
-- Default algo: md5 (fast, sufficient for "are these two files
-- the same?"). Pass algo=sha256 or algo=blake3 for stronger.
--
-- Output spread: NAME, SIZE, MTIME, INODE, HASH, FILE_TYPE.
-- Files with identical hashes get a leading "=N" group marker
-- in the NAME column, so the all-same-MD5 pattern jumps out.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.hash = "content + metadata inspection — bug 0118 phase 2.1"

local function popen_lines(argv)
    local _, out, _, pid = root:popen(argv, "re")
    if not pid then return nil, "spawn failed: " .. argv[1] end
    local lines = {}
    local line, alive = out:read(true)
    while line do
        table.insert(lines, line)
        line, alive = out:read(true)
        if not alive then break end
    end
    out:close()
    return lines
end

local function popen_first(argv)
    local lines, err = popen_lines(argv)
    if not lines or #lines == 0 then return nil, err end
    return lines[1]
end

local ALGO_BIN = {
    md5    = {"/usr/bin/md5sum", "md5sum"},
    sha256 = {"/usr/bin/sha256sum", "sha256sum"},
    blake3 = {"/usr/bin/b3sum", "b3sum"},
    sha1   = {"/usr/bin/sha1sum", "sha1sum"},
    sha512 = {"/usr/bin/sha512sum", "sha512sum"},
}

local function hash_file(algo, path)
    local bin = ALGO_BIN[algo]
    if not bin then return nil, "unknown algo: " .. algo end
    local line, err = popen_first({bin[1], bin[2], path})
    if not line then return nil, err end
    -- "<hex>  path"
    local hex = string.match(line, "^(%w+)%s")
    return hex
end

local function stat_file(path)
    -- One stat -c invocation per file is fine — these are small
    -- syscalls. The format string keeps fields ordered + tab-
    -- separated for unambiguous parsing.
    local line, err = popen_first({
        "/usr/bin/stat", "stat",
        "-c", "%s\t%y\t%i\t%F",
        path,
    })
    if not line then return nil, err end
    local size, mtime, inode, kind = string.match(line, "^(%d+)\t([^\t]+)\t(%d+)\t(.+)$")
    return {
        size = tonumber(size),
        mtime = mtime,
        inode = tonumber(inode),
        kind = kind,
    }
end

local function file_type(path)
    -- libmagic via /usr/bin/file -b. Slow per call (~ms); skip if
    -- no_type=1 in args.
    local line, err = popen_first({"/usr/bin/file", "file", "-b", path})
    return line or "?"
end

-- Group rows by hash so duplicates are visually clustered.
local function group_by_hash(rows)
    -- count occurrences
    local count = {}
    for _, r in ipairs(rows) do
        if r.hash then count[r.hash] = (count[r.hash] or 0) + 1 end
    end
    -- annotate the NAME of grouped rows with a group marker
    for _, r in ipairs(rows) do
        if r.hash and count[r.hash] and count[r.hash] > 1 then
            r.group = string.format("[=%d]", count[r.hash])
        else
            r.group = ""
        end
    end
    -- stable sort: by hash first (so groups cluster), then by name
    table.sort(rows, function(a, b)
        if a.hash ~= b.hash then return (a.hash or "") < (b.hash or "") end
        return a.name < b.name
    end)
end

local function parse_args(args)
    local algo = "md5"
    local paths = {}
    local opts = {with_type = true}
    for _, a in ipairs(args) do
        if type(a) == "string" then
            local k, v = string.match(a, "^([%w_]+)=(.*)$")
            if k == "algo" then
                algo = v
            elseif k == "no_type" then
                opts.with_type = (v == "0" or v == "false")
            elseif k then
                -- unknown
            else
                table.insert(paths, a)
            end
        end
    end
    return algo, paths, opts
end

function suggest.hash(args, raw)
    local last = args[#args] or ""
    if string.match(last, "^algo=") then
        cat9.readline:suggest({
            "algo=md5", "algo=sha256", "algo=blake3",
            "algo=sha1", "algo=sha512",
        }, "word", last)
    else
        local argv, prefix, flt, offset =
            cat9.file_completion(last, cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.hash(...)
    local algo, paths, opts = parse_args({...})
    if #paths == 0 then
        cat9.add_message("hash <path...> [algo=md5|sha256|blake3] [no_type=1]")
        return
    end

    if not ALGO_BIN[algo] then
        cat9.add_message("hash: unknown algo " .. algo)
        return
    end

    local rows = {}
    for _, p in ipairs(paths) do
        local st = stat_file(p)
        local hex, hex_err
        if st and (st.kind == "regular file" or st.kind == "regular empty file") then
            hex, hex_err = hash_file(algo, p)
        end
        local kind = st and st.kind or "?"
        if opts.with_type and st and st.kind == "regular file" then
            kind = file_type(p)
        end
        table.insert(rows, {
            name = p:match("([^/]+)$") or p,
            full = p,
            size = st and st.size or 0,
            mtime = st and st.mtime or "?",
            inode = st and st.inode or 0,
            hash = hex,
            kind = kind,
        })
    end

    group_by_hash(rows)

    local trows = {}
    for _, r in ipairs(rows) do
        table.insert(trows, {
            r.group .. r.name,
            tostring(r.size),
            r.mtime,
            tostring(r.inode),
            r.hash or "?",
            r.kind,
        })
    end

    H.make_spread("hash " .. algo,
        {"NAME", "SIZE", "MTIME", "INODE", "HASH", "TYPE"}, trows)

    -- Detect the "all same hash" smoking-gun pattern (the
    -- bug 0114 font situation) and emit a result line that calls
    -- it out — viz_bus subscribers can light up on this.
    local first_hash = rows[1] and rows[1].hash
    local all_same = first_hash ~= nil
    for _, r in ipairs(rows) do
        if r.hash ~= first_hash then all_same = false; break end
    end
    if all_same and #rows > 1 then
        cat9.add_message(string.format(
            "hash: ALL %d FILES IDENTICAL (%s) — copy-overwrite or "
            .. "deduplication smoking gun, see bug 0114",
            #rows, first_hash))
        H.emit_result(string.format(
            "hash:all_same:n=%d:hash=%s", #rows, first_hash))
    else
        H.emit_result(string.format("hash:%s:n=%d", algo, #rows))
    end
end

end
