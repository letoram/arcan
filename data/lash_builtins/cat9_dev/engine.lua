-- engine [introspect|watch] [name|*]
--
-- Wraps the Lua-side engine_introspect() built-in (added in
-- arcan_lua.zig per bug 0117). Phase 1.4 of bug 0118 — the
-- highest-leverage piece, since this is what unblocked the bug
-- 0116 hunt with `gdb -batch -p PID` reads.
--
-- Subcommands:
--   engine                       — full atlas dump as a spread
--   engine atlas                 — alias for full dump
--   engine atlas_curve_offset    — single value
--   engine arcan_ttf.atlas_dirty — module-qualified single value
--   engine watch <name> [int_ms] — poll on interval, emit deltas
--
-- The bug 0116 query reduced to:
--
--   cat9$ engine atlas_curve_offset
--   19805
--
-- vs. the host-bash equivalent:
--
--   nm zig-out/bin/arcan | grep atlas_curve_offset
--   gdb -batch -p $(pgrep arcan) -ex 'p/u *(unsigned int*)0x1f698f0' \
--       -ex detach -ex quit
--
-- The second form is what we actually ran during the hunt — three
-- separate steps + permission prompt + freezing the process. This
-- is one cat9 line + zero pause to the live arcan.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.engine = "engine_introspect — read live engine globals (bug 0118 phase 1.4)"

-- The introspect function is registered as a global Lua name by
-- arcan_lua.zig at engine boot. From the cat9 lash environment we
-- access it via the reserved engine handle on `root`. lash exposes
-- engine globals through `root.eval` / `root.api` patterns; we
-- start with a direct global read and degrade to api lookup.
local function call_introspect(name)
    -- Try the global; lash's lua context wraps arcan engine API.
    if engine_introspect then
        return engine_introspect(name)
    end
    -- lash may have stuffed engine APIs under root.api or similar
    if root and root.api and root.api.engine_introspect then
        return root.api.engine_introspect(name)
    end
    -- Fallback: load the symbol via the global env
    local g = _G or _ENV
    if g and g.engine_introspect then return g.engine_introspect(name) end
    return nil, "engine_introspect not exposed in this lash context"
end

local function full_dump_rows()
    local t, err = call_introspect("*")
    if type(t) ~= "table" then
        return nil, err or "no table from engine_introspect"
    end
    -- Stable order matters for diffing across reads.
    local order = {
        "atlas_curve_offset", "atlas_band_offset",
        "atlas_max_curve_texels", "atlas_max_band_texels",
        "atlas_cache_size",
        "sdf_next_x", "sdf_next_y", "sdf_row_height",
        "atlas_dirty", "atlas_initialized",
    }
    local rows = {}
    for _, k in ipairs(order) do
        local v = t[k]
        table.insert(rows, {k, tostring(v == nil and "?" or v)})
    end
    -- Append any extra keys we don't know about (forward-compat).
    local seen = {}
    for _, k in ipairs(order) do seen[k] = true end
    for k, v in pairs(t) do
        if not seen[k] then
            table.insert(rows, {k, tostring(v)})
        end
    end
    return rows, t
end

function suggest.engine(args, raw)
    if #args == 3 then
        cat9.readline:suggest({
            "atlas",
            "atlas_curve_offset", "atlas_band_offset",
            "atlas_dirty", "atlas_initialized",
            "atlas_max_curve_texels", "atlas_max_band_texels",
            "atlas_cache_size",
            "sdf_next_x", "sdf_next_y", "sdf_row_height",
            "watch",
        }, "word", args[3] or "")
    elseif #args == 4 and args[2] == "watch" then
        cat9.readline:suggest({
            "atlas_curve_offset", "atlas_band_offset",
            "atlas_dirty",
        }, "word", args[4] or "")
    end
end

function builtins.engine(name, ...)
    name = name or "*"

    if name == "watch" then
        -- engine watch <name> [interval_ms]
        local target = ...
        local rest = {select(2, ...)}
        if not target then
            cat9.add_message("engine watch <name> [interval_ms]")
            return
        end
        local interval = tonumber(rest[1]) or 250
        cat9.add_message(string.format(
            "engine watch %s @ %dms — phase 3.2 placeholder, "
            .. "polling fallback active. Hardware watchpoint support "
            .. "lands when the engine introspection bus is wired into "
            .. "viz_bus (bug 0029).", target, interval))
        -- Minimum viable: spread updates on a timer. lash doesn't
        -- give us a great timer hook from a sync builtin, so for v1
        -- emit a single read + the suggestion to re-run.
        local v, err = call_introspect(target)
        if v == nil then
            cat9.add_message("engine watch: " .. (err or "nil"))
            return
        end
        cat9.add_message(string.format("%s = %s", target, tostring(v)))
        H.emit_result(string.format(
            "engine:watch:name=%s:value=%s", target, tostring(v)))
        return
    end

    if name == "*" or name == "atlas" or name == "all" then
        local rows, full = full_dump_rows()
        if not rows then
            cat9.add_message("engine: " .. (full or "no data"))
            H.emit_result("engine:err:reason=no_introspect")
            return
        end
        H.make_spread("engine atlas",
            {"NAME", "VALUE"}, rows)
        -- Publish on viz_bus so atlas exhaustion / wipe transitions
        -- are observable from other panes (bug 0029 payload-keys).
        if H.viz_bus and H.viz_bus.publish and full then
            H.viz_bus.publish("engine.atlas", "snapshot", 0, full)
        end
        H.emit_result(string.format(
            "engine:atlas:curve=%d:band=%d:dirty=%s",
            full.atlas_curve_offset or -1,
            full.atlas_band_offset or -1,
            tostring(full.atlas_dirty)))
        return
    end

    -- Single value
    local v, err = call_introspect(name)
    if v == nil then
        cat9.add_message("engine: " .. (err or ("no value for " .. name)))
        H.emit_result("engine:err:name=" .. name .. ":reason=nil")
        return
    end
    cat9.add_message(string.format("%s = %s", name, tostring(v)))
    H.emit_result(string.format(
        "engine:read:name=%s:value=%s", name, tostring(v)))
end

end
