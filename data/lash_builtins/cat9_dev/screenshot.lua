-- screenshot [outpath] — capture the durden display as a PNG.
--
-- Bug 0118-aligned: until arcan exposes a proper shmif-side capture
-- primitive (and bug 0036/agent_screenshot_recipe is replaced), this
-- wraps the host-X11 path:
--   xdotool search --name durden  → window id
--   import -window <wid> <path>   → PNG capture
--
-- This is a transitional builtin: the right long-term answer is a
-- shmif/segment-side screenshot that doesn't depend on X11.  Using
-- /usr/bin/{xdotool,import} via root:popen makes the dependency
-- explicit; the agent can then `read <path>` the PNG and the user
-- sees both the capture and what we did.
--
-- Defaults:
--   outpath = $CAT9_SCREENSHOT_DIR/screen-<timestamp>.png
--             or /home/x/.local/share/zig-sh-testing/screen-<timestamp>.png
--
-- Emits:
--   screenshot:ok:path=…:wid=…
--   screenshot:err:reason=…
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.screenshot = "Capture durden display to PNG (xdotool+import wrapper, transitional)"

local DEFAULT_DIR = (cat9.env or {}).CAT9_SCREENSHOT_DIR
    or "/home/x/.local/share/zig-sh-testing"

-- xdotool wid lookup is async.  popen synchronous read returns nil on
-- this build (pipe data arrives after Lua's tight read loop completes),
-- so use cat9.add_background_job (build.lua pattern) and resume work in
-- the on_exit callback.
local function find_durden_wid_async(on_done)
    if not (root.popen and cat9.add_background_job) then
        on_done(nil, "popen_or_bgjob_unavailable")
        return
    end
    local display = (cat9.env or {}).DISPLAY or ":0"
    local _, outf, errf, pid = root:popen(
        {"/bin/sh", "/bin/sh", "-c",
         "DISPLAY=" .. display ..
         " /usr/bin/xdotool search --name durden | head -1"},
        "re"
    )
    if not pid then
        on_done(nil, "popen_failed")
        return
    end
    local lines = {}
    local job = cat9.add_background_job(outf, pid,
        {lf_strip = true, err = errf},
        function(job, code)
            local first
            for _, ln in ipairs(lines) do
                local s = ln:gsub("[\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if s ~= "" and s:match("^%d+$") then
                    first = s
                    break
                end
            end
            if first then on_done(first) else on_done(nil, "no_durden_window") end
        end)
    table.insert(job.hooks.on_data, function(line)
        if line then table.insert(lines, line) end
    end)
end

local function default_outpath()
    -- timestamp via os.date so we don't collide on rapid captures.
    local ts = os.date("%Y%m%d-%H%M%S")
    return DEFAULT_DIR .. "/screen-" .. ts .. ".png"
end

function suggest.screenshot(args, raw)
    if #args == 2 then
        local argv, prefix, flt, offset =
            cat9.file_completion(args[2], cat9.config.glob.file_argv)
        cat9.filedir_oracle(argv, function(set)
            if flt then set = cat9.prefix_filter(set, flt, offset) end
            cat9.readline:suggest(set, "word", prefix)
        end)
    end
end

function builtins.screenshot(outpath, ...)
    outpath = outpath or default_outpath()

    find_durden_wid_async(function(wid, werr)
        if not wid then
            H.emit_result(string.format("screenshot:err:reason=%s", werr))
            cat9.add_message("screenshot: " .. tostring(werr))
            return
        end
        if not root.popen then
            H.emit_result("screenshot:err:reason=popen_unavailable")
            return
        end
        local display = (cat9.env or {}).DISPLAY or ":0"
        local _, importf, importerr, pid = root:popen(
            {"/bin/sh", "/bin/sh", "-c",
             "DISPLAY=" .. display ..
             " /usr/bin/import -window " .. wid .. " " .. outpath},
            "re"
        )
        if not pid then
            H.emit_result(string.format("screenshot:err:reason=import_popen_failed:wid=%s", wid))
            return
        end
        -- Wait for import to finish so the path is actually populated when
        -- we emit ok.
        cat9.add_background_job(importf, pid,
            {lf_strip = true, err = importerr},
            function(job, code)
                if code and code ~= 0 then
                    H.emit_result(string.format("screenshot:err:reason=import_exit_%s:wid=%s",
                        tostring(code), wid))
                    return
                end
                H.emit_result(string.format("screenshot:ok:path=%s:wid=%s", outpath, wid))
                H.make_spread(
                    "screenshot",
                    {"key", "value"},
                    {
                        {"path", outpath},
                        {"wid", wid},
                        {"note", "read " .. outpath .. " to render"},
                    }
                )
            end)
    end)
end

end
