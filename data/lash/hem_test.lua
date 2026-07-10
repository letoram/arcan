-- hem_test.lua — sibling lash ruleset for arcan-side functional tests
-- of hem. Activated via LASH_SHELL=cat9_test.
--
-- Two observation points are installed before stock cat9.lua loads:
--
-- 1. lash.root.readline is wrapped so that every readline() call hem
--    makes (one per prompt cycle) gets its callback wrapped. The wrap
--    emits test:input:<line> when a line is accepted.
--
-- 2. lash.root:set_handlers is wrapped so that the handlers table
--    hem hands over (hem.handlers) gets bchunk_in/out and tick
--    wraps installed before delegation. tick wraps run a per-tick
--    diff of lash.jobs vs the previous snapshot and emit
--    test:job_in / test:job_out per change. bchunk wraps emit
--    test:bchunk_{in,out}:id=N.
--
-- Strategy A — runtime source-patching cat9.lua at the
-- `while root:process()` anchor — was tried and hangs the kid (the
-- patched chunk fails to reach the main loop and arcan emits
-- out-reject-full). Don't go there. See feedback memory
-- cat9_test_harness_lessons.md.

if not (lash and lash.root and lash.root.message) then
    if lash and lash.messages then
        table.insert(lash.messages, "cat9_test: lash.root:message unavailable")
    end
    return false
end

local function emit(tag)
    pcall(function()
        lash.root:message(tag)
        lash.root:refresh()
    end)
end

emit("test:bootstrap:shell=cat9_test")

-- Install readline interceptor. hem calls lash.root:readline(cb, cfg)
-- once per prompt; we wrap cb so the accepted line surfaces as a
-- test:input:<line> message before delegating to hem's own handler.
local orig_readline = lash.root.readline
if type(orig_readline) == "function" then
    lash.root.readline = function(self, cb, cfg)
        local wrapped_cb
        if type(cb) == "function" then
            wrapped_cb = function(rlself, line, ...)
                if line and #line > 0 then
                    -- Sanitize newlines so each emit stays one shmon line.
                    local m = tostring(line):gsub("[\r\n]", " ")
                    emit("test:input:" .. m)
                end
                return cb(rlself, line, ...)
            end
        end
        return orig_readline(self, wrapped_cb or cb, cfg)
    end
    emit("test:bootstrap:readline_wrapped")
else
    emit("test:bootstrap:readline_wrap_skipped")
end

-- Hook lash.root:set_handlers to wrap entries on the handlers table
-- before hem's main loop starts. hem calls set_handlers exactly
-- once during setup with its hem.handlers table, so this fires
-- before the loop drains events.
local orig_set_handlers = lash.root.set_handlers
local installed = false
function lash.root:set_handlers(handlers)
    if not installed then
        installed = true
        emit("test:bootstrap:set_handlers_intercepted")

        -- Hook hem.add_message via the closures stored in handlers
        -- (hem is a *local* in cat9.lua so _G.hem is nil here; we
        -- reach it through debug.getupvalue on any handler closure).
        -- Surfaces add_message calls (e.g. "builtin: [dev:foo.lua]
        -- failed to load") as test:msg shmif events for the harness.
        local hem_ref
        for k, v in pairs(handlers) do
            if type(v) == "function" then
                local i = 1
                while true do
                    local n, val = debug.getupvalue(v, i)
                    if not n then break end
                    if n == "hem" and type(val) == "table"
                       and val.add_message and val.builtins then
                        hem_ref = val
                        break
                    end
                    i = i + 1
                end
                if hem_ref then break end
            end
        end
        if hem_ref then
            local _orig_addmsg = hem_ref.add_message
            hem_ref.add_message = function(s)
                emit("test:msg:" .. tostring(s):gsub("[\r\n]", " "))
                return _orig_addmsg(s)
            end
            local _orig_set = hem_ref.builtins["builtin"]
            if _orig_set then
                hem_ref.builtins["builtin"] = function(a, opt)
                    emit("test:builtin_switch:to=" .. tostring(a))
                    local r = _orig_set(a, opt)
                    emit("test:builtin_switch:after=" ..
                        tostring(hem_ref.builtin_name) ..
                        ":has_read=" .. tostring(hem_ref.builtins.read ~= nil) ..
                        ":has_write=" .. tostring(hem_ref.builtins.write ~= nil))
                    return r
                end
            end
        end

        local orig_bo = handlers.bchunk_out
        if orig_bo then
            handlers.bchunk_out = function(self, blob, id, ...)
                emit("test:bchunk_out:id=" .. tostring(id))
                return orig_bo(self, blob, id, ...)
            end
        end

        local orig_bi = handlers.bchunk_in
        if orig_bi then
            handlers.bchunk_in = function(self, blob, id, lref, ...)
                emit("test:bchunk_in:id=" .. tostring(id))
                return orig_bi(self, blob, id, lref, ...)
            end
        end

        -- handlers.tick fires per shmif tick. Snapshot lash.jobs
        -- (hem binds lash.jobs to its job table at setup) and emit
        -- one test:job_in/test:job_out per delta. We don't track
        -- exit codes here — that comes from job.exit which hem
        -- populates when the kid pid reaps. Emit as test:job_done
        -- when a tracked job's exit transitions from nil to a value.
        local orig_tick = handlers.tick
        local prev = {}
        local prev_exit = {}
        handlers.tick = function(...)
            local jobs = lash.jobs
            if jobs then
                local seen = {}
                for _, job in ipairs(jobs) do
                    local id = job.id
                    if id then
                        seen[id] = true
                        if not prev[id] then
                            prev[id] = job.short or job.raw or "?"
                            local short = tostring(prev[id]):gsub("[\r\n]", " ")
                            emit("test:job_in:id=" .. tostring(id) ..
                                ":short=" .. short)
                        end
                        if job.exit ~= nil and prev_exit[id] == nil then
                            prev_exit[id] = job.exit
                            emit("test:job_done:id=" .. tostring(id) ..
                                ":exit=" .. tostring(job.exit))
                        end
                    end
                end
                for id, _ in pairs(prev) do
                    if not seen[id] then
                        emit("test:job_out:id=" .. tostring(id))
                        prev[id] = nil
                        prev_exit[id] = nil
                    end
                end
            end
            if orig_tick then return orig_tick(...) end
        end

        emit("test:bootstrap:wraps=installed")
    end
    return orig_set_handlers(self, handlers)
end

emit("test:bootstrap:loading_hem")
local hem_path = lash.scriptdir .. "cat9.lua"
local fn, err = loadfile(hem_path)
if not fn then
    emit("test:bootstrap:err=loadfile:" .. tostring(err))
    return false
end
emit("test:bootstrap:cat9_loaded:about_to_run")
local ok, run_err = pcall(fn)
emit("test:teardown:cat9_returned:ok=" .. tostring(ok) .. ":err=" .. tostring(run_err))

-- Side-channel teardown trace. Shmif is normally dead by this point
-- (delete_image_vid above) so the emit() above might not reach arcan.
-- Write directly to a file so the runner can confirm hem ran the
-- post-loop block.
pcall(function()
    local f = io.open("/tmp/cat9_test_teardown.txt", "w")
    if f then
        f:write(string.format("ok=%s\nerr=%s\n", tostring(ok), tostring(run_err)))
        f:close()
    end
end)

return ok
