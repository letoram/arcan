-- dashboard — single-keystroke composition of the auto-arch surface.
--
-- Opens (or re-focuses) the spreads we use to watch the SH-fork
-- self-host arc evolve: bugs ledger, snippet browser, compile units +
-- errors + timeline, live metrics, hilbert spatial map. No new
-- visualization, no new helpers — pure composition over existing
-- dev/ builtins.
--
-- Idempotent. First call creates everything. Subsequent calls
-- re-render the cheap views (bugs reload, hilbert refresh, snippets
-- re-load) without re-spawning compile/metrics shell jobs.
--
-- Invocation:
--   dashboard           — open or focus the standard layout
--   dashboard reload    — force re-run of bugs reload + cheap renders
return
function(cat9, root, builtins, suggest, views, builtin_cfg)

cat9.dev_helpers = cat9.dev_helpers or {}
local H = cat9.dev_helpers

builtins.hint.dashboard =
    "dashboard — open auto-arch surface (bugs/snippets/units/errors/metrics/hilbert)"

local dashboard_opened = false

local function run(cmd)
    cat9.parse_string(cat9.readline, cmd)
end

local function open_first_time()
    -- Re-query fossil so the ledger reflects any tickets added or
    -- mutated since session start. Plan calls this "bugs sync"; the
    -- existing verb is `bugs reload` — same operation.
    run("bugs reload")
    run("bugs")
    run("snippets")
    run("metrics")
    run("hilbert")
    -- New (D/E) surfaces.  All are no-arg-safe; each opens its
    -- spread or quietly no-ops if its data source isn't available.
    run("time")            -- C.1 round-bucket aggregator
    run("atlas")           -- E.1 build atlas (sourced from diff-vs-llvm.log)
    run("memcloud")        -- E.2 mapping cloud (sourced from /proc)
    run("dwarf open")      -- D.1 addr→DIE resolver, idle until clicks
    H.emit_result(
        "dashboard:open:layout=bugs+snippets+metrics+hilbert"
        .. "+time+atlas+memcloud+dwarf")
end

local function refocus()
    run("bugs reload")
    run("bugs")
    run("hilbert")
    H.emit_result("dashboard:focus")
end

function builtins.dashboard(...)
    local args = {...}
    local force = false
    for _, v in ipairs(args) do
        if v == "reload" then force = true end
    end
    if dashboard_opened and not force then
        refocus()
        return
    end
    dashboard_opened = true
    open_first_time()
end

function suggest.dashboard(args, raw)
    if #args == 2 then
        cat9.readline:suggest(cat9.prefix_filter({"reload"}, args[2]), "word")
    end
end

end
