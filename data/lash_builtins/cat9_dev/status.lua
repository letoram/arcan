-- status — live "what's happening now" title-bar spread.
--
-- Opens a spreadsheet whose rows update on every dev_result emit
-- the running kid sees (own viz_bus publishes plus, optionally,
-- shmon.log tail when CAT9_SHMON_PATH is set in env so we can
-- follow other kids' emits via the filesystem).
--
-- Each row: time | kind | source | detail.
-- Columns:
--   time   — HH:MM:SS of the emit
--   kind   — read / edit / write / build / repro / view-tour / …
--   source — file path, bug id, build target …
--   detail — bytes / lines / changes / exit / status text
--
-- Use as a pinned cell at top or bottom of the tiler.  Acts as
-- the dev loop's title bar / current-activity ticker per the
-- feedback_visible_dev_loop_target.md target.
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.status = "status — live one-row-per-job activity spread"

-- Module-level so subsequent `status` invocations re-focus instead of
-- spawning a new spread.
local status_spread = nil
local rows_max = 32

-- Parse a `kind:detail:key=val:key=val:…` tag emitted by H.emit_result.
-- Returns (kind, source, detail).  The token after the first colon is
-- the most useful one to display as the row's "kind" column.
local function parse_emit(tag)
    if not tag or tag == "" then return "?", "", "" end
    -- Strip our shmon-side prefix if present.
    tag = tag:gsub("^test:dev_result:", "")
    local first_colon = tag:find(":", 1, true)
    if not first_colon then return tag, "", "" end
    local kind = tag:sub(1, first_colon - 1)
    local rest = tag:sub(first_colon + 1)
    -- Pull source out of common keys.
    local source = rest:match("path=([^:]+)")
        or rest:match("file=([^:]+)")
        or rest:match("source=([^:]+)")
        or rest:match("bug_id=([^:]+)")
        or rest:match("target=([^:]+)")
        or ""
    -- Trim path-prefix noise so the column stays narrow.
    if #source > 40 then source = "…" .. source:sub(-37) end
    -- Pull detail out of bytes/lines/changes/exit/count/steps.
    local detail = rest:match("bytes=(%d+)") and ("bytes=" .. rest:match("bytes=(%d+)"))
        or rest:match("lines=(%d+)") and ("lines=" .. rest:match("lines=(%d+)"))
        or rest:match("changes=(%d+)") and ("changes=" .. rest:match("changes=(%d+)"))
        or rest:match("exit=(%-?%d+)") and ("exit=" .. rest:match("exit=(%-?%d+)"))
        or rest:match("count=(%d+)") and ("count=" .. rest:match("count=(%d+)"))
        or rest:match("steps=(%d+)") and ("steps=" .. rest:match("steps=(%d+)"))
        or (#rest > 50 and (rest:sub(1, 47) .. "…")) or rest
    return kind, source, detail
end

local function now_hhmmss()
    local t = os.date("*t")
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

local function ensure_spread()
    if status_spread then return status_spread end
    status_spread = H.make_spread("dev-status",
        {"time", "kind", "source", "detail"}, {})
    if not status_spread then return nil end
    status_spread.dev_kind = "status"
    -- Initial header row so the spread doesn't render blank
    -- before any emit lands.
    if status_spread.add_row then
        status_spread:add_row({now_hhmmss(), "status", "init", "live ticker"})
    end
    return status_spread
end

local function append_row(kind, source, detail)
    local sp = ensure_spread()
    if not sp then return end
    if sp.add_row then
        sp:add_row({now_hhmmss(), kind, source, detail})
    end
    -- Cap the row count so the spread stays a title bar, not a log.
    if sp.rows and #sp.rows > rows_max and sp.remove_row then
        sp:remove_row(1)
    end
    if sp.refresh then sp:refresh() end
end

-- viz_bus tap — every publish lands here.  For senseye-style cross
-- pane selection we already get a payload table; surface its name /
-- file / bug_id field as the row "source".
local function on_viz(sensor, key, row, payload)
    local source = ""
    if payload then
        source = payload.file or payload.bug_id or payload.name
            or tostring(payload.snippet_id or "") or ""
    end
    if #source > 40 then source = "…" .. source:sub(-37) end
    append_row("viz", tostring(sensor or "?"),
        string.format("key=%s row=%s src=%s",
            tostring(key or "?"), tostring(row or "0"), source))
end

-- Public hook so other builtins (or the user) can inject a row.
function H.status_emit(tag)
    local kind, source, detail = parse_emit(tag)
    append_row(kind, source, detail)
end

function builtins.status(verb, ...)
    if verb == "clear" then
        if status_spread and status_spread.clear_rows then
            status_spread:clear_rows()
        end
        return
    end
    ensure_spread()
    -- Subscribe once.
    if not H.status_subscribed then
        H.viz_bus.subscribe(on_viz)
        -- Wrap H.emit_result so every dev_result emit in THIS kid
        -- adds a status-spread row.  The original still fires the
        -- shmif MESSAGE; we just T-off into the row aggregator.
        local orig_emit = H.emit_result
        H.emit_result = function(tag)
            local k, s, d = parse_emit(tostring(tag or ""))
            append_row(k, s, d)
            return orig_emit(tag)
        end
        H.status_subscribed = true
    end
    -- Marker row so the user sees the pin happened.
    append_row("status", "open", "subscribed-to-viz_bus+emit_result")
    H.emit_result("status:opened")
end

function suggest.status(args, raw)
    if #args == 2 then
        cat9.readline:suggest(cat9.prefix_filter({"clear"}, args[2]), "word")
    end
end

end
