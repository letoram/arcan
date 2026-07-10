-- run <bin> [args...]
--
-- Explicit-argv process spawn via cat9.setup_shell_job(argv, "re", ...).
-- "re" mode is **raw exec** — the kid uses popen() with the literal argv,
-- NOT /bin/sh -c "...". So no shell quoting concerns; what you write is
-- what gets exec'd.
--
-- Visual: the standard cat9 job cell — header shows pid_or_exit + the
-- short form (the binary name); body is stdout. `view #N err` for
-- stderr.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.run = "Spawn a binary with explicit argv (no /bin/sh)"

function suggest.run(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.run(...)
    local args = {...}
    if #args < 1 then
        cat9.add_message("run <bin> [args...]")
        return
    end

    -- Filter to plain strings (cat9 might pass tables for parg etc.)
    local argv = {}
    for _, v in ipairs(args) do
        if type(v) == "string" then table.insert(argv, v) end
    end
    if #argv == 0 then
        cat9.add_message("run: no string-argv tokens")
        return
    end

    local env = cat9.table_copy_shallow(cat9.env)
    -- setup_shell_job's args[1] is the binary path; args[2] becomes
    -- the conventional argv[0] (program-name visible to the spawned
    -- process). We mirror conventional argv: arg[0] = basename of bin.
    local bin = argv[1]
    local final_argv = {bin}
    -- argv[2] = arg0 (program name)
    local basename = string.match(bin, "([^/]+)$") or bin
    table.insert(final_argv, basename)
    -- remaining args
    for i = 2, #argv do table.insert(final_argv, argv[i]) end

    local line = "run " .. table.concat(argv, " ")
    local job = cat9.setup_shell_job(final_argv, "re", env, line, {close = true})
    if not job then return end
    job.short = "run " .. basename

    -- Track-C precursor: watch stderr for `RUNTIME\tPANIC\t…` lines
    -- emitted by the patched fork's defaultPanic when ARCAN_CONNPATH
    -- is inherited. Each panic line populates a row in a (lazily
    -- created) Panics spreadsheet, and emits dev_result:run:panic for
    -- shmif-native verification.
    local panics_spread = nil
    local panic_count = 0

    local function spread_set(sp, row, col, value)
        cat9.parse_string(cat9.readline,
            string.format("set #%d %d %d %s",
                sp.id, row, col, H.escape_cell(value)))
    end

    local function on_stderr_line(s)
        if string.sub(s, 1, 8) ~= "RUNTIME\t" then return end
        -- RUNTIME\tPANIC\t<tid>\t<msg>
        local kind = string.match(s, "^RUNTIME\t([^\t]+)\t")
        if kind ~= "PANIC" then return end
        local tid, msg = string.match(s, "^RUNTIME\tPANIC\t([^\t]+)\t(.*)$")
        if not panics_spread then
            panics_spread = H.make_spread(
                "panics " .. basename,
                {"thread", "binary", "message"},
                {}
            )
        end
        if not panics_spread then return end
        panic_count = panic_count + 1
        local row = panic_count + 1
        spread_set(panics_spread, row, 1, tid or "?")
        spread_set(panics_spread, row, 2, basename)
        spread_set(panics_spread, row, 3, msg or "")
        H.emit_result(string.format(
            "run:panic:bin=%s:tid=%s", basename, tid or "?"))
    end

    if job.err and job.err.data_handler then
        job.err:data_handler(function()
            local data, alive = job.err:read(true)
            while data do
                for one in string.gmatch(data, "([^\n]+)") do
                    on_stderr_line(one)
                end
                data, alive = job.err:read(true)
                if not alive then break end
            end
        end)
    end
end

end
