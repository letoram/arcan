-- fs <subcommand> — small file-management primitives (bug 0118-spirit).
--
-- Subcommands:
--   fs rm <path>           — unlink a file (refuses directories)
--   fs touch <path>        — create empty file or update mtime
--   fs mkdir <path>        — create directory (no -p)
--   fs mv <src> <dst>      — rename / move
--   fs stat <path>         — fstatus result as a 1-row spread
--
-- Replaces host-bash rm/touch/mkdir reflex for cat9-driven cell work
-- (chiefly: clearing emit-log files, prepping staging dirs).
--
-- Emits:
--   fs:rm:ok:path=…       fs:rm:err:path=…:reason=…
--   fs:touch:ok:path=…    fs:touch:err:path=…:reason=…
--   fs:mkdir:ok:path=…    fs:mkdir:err:path=…:reason=…
--   fs:mv:ok:src=…:dst=…  fs:mv:err:reason=…
--   fs:stat:ok:path=…
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.fs = "Small file-mgmt verbs: rm/touch/mkdir/mv/stat"

local function get_status(path)
    if root.fstatus then return root:fstatus(path) end
    return nil
end

local function builtin_rm(path)
    if not path then
        cat9.add_message("fs rm <path>")
        H.emit_result("fs:rm:err:reason=missing_args")
        return
    end
    -- Try to detect directories via fopen-read fail (directories can't
    -- be opened "r"); fstatus returns boolean on this build, so it can't
    -- distinguish kind.  Conservative: if path opens with "r" -> file.
    local probef = root:fopen(path, "r")
    if probef then
        probef:close()
    else
        H.emit_result(string.format("fs:rm:err:path=%s:reason=not_a_regular_file_or_unopenable", path))
        cat9.add_message("fs rm: " .. path .. " unopenable (refuse)")
        return
    end
    -- os.remove works for files in pure Lua.
    local ok, err = os.remove(path)
    if ok then
        H.emit_result(string.format("fs:rm:ok:path=%s", path))
    else
        H.emit_result(string.format("fs:rm:err:path=%s:reason=%s",
            path, tostring(err)))
        cat9.add_message("fs rm: " .. tostring(err))
    end
end

local function builtin_touch(path)
    if not path then
        cat9.add_message("fs touch <path>")
        H.emit_result("fs:touch:err:reason=missing_args")
        return
    end
    -- open+close for "a" mode creates if absent and bumps mtime.
    local f = root:fopen(path, "a")
    if not f then
        H.emit_result(string.format("fs:touch:err:path=%s:reason=fopen_failed", path))
        cat9.add_message("fs touch: fopen failed for " .. path)
        return
    end
    f:close()
    H.emit_result(string.format("fs:touch:ok:path=%s", path))
end

local function builtin_mkdir(path)
    if not path then
        cat9.add_message("fs mkdir <path>")
        H.emit_result("fs:mkdir:err:reason=missing_args")
        return
    end
    -- root:fmkdir or fall back to os.execute via popen of /bin/mkdir.
    if root.fmkdir then
        local ok = root:fmkdir(path)
        if ok then
            H.emit_result(string.format("fs:mkdir:ok:path=%s", path))
        else
            H.emit_result(string.format("fs:mkdir:err:path=%s:reason=fmkdir_failed", path))
            cat9.add_message("fs mkdir: fmkdir failed for " .. path)
        end
        return
    end
    if root.popen then
        local _, _, _, pid = root:popen({"/bin/mkdir", "/bin/mkdir", path}, "re")
        if pid then
            H.emit_result(string.format("fs:mkdir:ok:path=%s:via=popen", path))
        else
            H.emit_result(string.format("fs:mkdir:err:path=%s:reason=popen_failed", path))
        end
        return
    end
    H.emit_result("fs:mkdir:err:reason=no_primitive")
end

local function builtin_mv(src, dst)
    if not src or not dst then
        cat9.add_message("fs mv <src> <dst>")
        H.emit_result("fs:mv:err:reason=missing_args")
        return
    end
    local ok, err = os.rename(src, dst)
    if ok then
        H.emit_result(string.format("fs:mv:ok:src=%s:dst=%s", src, dst))
    else
        H.emit_result(string.format("fs:mv:err:src=%s:dst=%s:reason=%s",
            src, dst, tostring(err)))
        cat9.add_message("fs mv: " .. tostring(err))
    end
end

local function builtin_stat(path)
    if not path then
        cat9.add_message("fs stat <path>")
        H.emit_result("fs:stat:err:reason=missing_args")
        return
    end
    local ok_st, st = pcall(get_status, path)
    if not ok_st or not st then
        H.emit_result(string.format("fs:stat:err:path=%s:reason=fstatus_unavailable_or_missing", path))
        cat9.add_message("fs stat: no fstatus for " .. path)
        return
    end
    -- root:fstatus on this build returns a BOOLEAN (true=exists/false=missing)
    -- rather than a rich table of {kind, size, mtime, mode}.  Fall back
    -- on a manual probe via fopen+read_file_lines for size, lacking
    -- everything else.
    if type(st) ~= "table" then
        local size, ftype = "", "unknown"
        local f = root:fopen(path, "r")
        if f then
            local lines, _ = H.read_file_lines(path)
            if lines then
                local total = 0
                for _, ln in ipairs(lines) do total = total + #ln + 1 end
                size = tostring(total)
                ftype = "file"
            end
            f:close()
        else
            ftype = "directory_or_unreadable"
        end
        H.emit_result(string.format("fs:stat:ok:path=%s:exists=%s:approx_size=%s",
            path, tostring(st), size))
        pcall(H.make_spread, "fs stat " .. path,
            {"key", "value"},
            {
                {"path", path},
                {"exists", tostring(st)},
                {"kind", ftype},
                {"approx_size", size},
                {"note", "fstatus returned boolean; richer stat needs primitive"},
            })
        return
    end
    -- Rich table case (future-proof).
    local kind
    if st.kind then kind = tostring(st.kind)
    elseif st.dir then kind = "directory"
    else kind = "file" end
    local rows = {
        {"path", path},
        {"kind", kind},
        {"size", tostring(st.size or "")},
        {"mtime", tostring(st.mtime or "")},
        {"mode", tostring(st.mode or "")},
    }
    H.emit_result(string.format("fs:stat:ok:path=%s:kind=%s:size=%s",
        path, kind, tostring(st.size or "")))
    pcall(H.make_spread, "fs stat " .. path, {"key", "value"}, rows)
end

function suggest.fs(args, raw)
    if #args == 2 then
        cat9.readline:suggest({"rm", "touch", "mkdir", "mv", "stat"}, "word", args[2])
    end
end

function builtins.fs(sub, ...)
    if not sub then
        cat9.add_message("fs <rm|touch|mkdir|mv|stat> [args]")
        return
    end
    if sub == "rm" then return builtin_rm(...) end
    if sub == "touch" then return builtin_touch(...) end
    if sub == "mkdir" then return builtin_mkdir(...) end
    if sub == "mv" then return builtin_mv(...) end
    if sub == "stat" then return builtin_stat(...) end
    cat9.add_message("fs: unknown subcommand " .. tostring(sub))
end

end
