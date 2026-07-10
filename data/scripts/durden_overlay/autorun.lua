-- data/scripts/durian_overlay/autorun.lua
--
-- Installed by build.zig to share/arcan/appl/durian/autorun.lua — durian's
-- stock autorun is a no-op stub, so this override is purely additive: it
-- wraps the built-in extevh handlers with shmifmon() tags so the shmif-
-- monitor log can show Lua-side handler fires interleaved with engine event
-- activity. It stays dormant unless ARCAN_SHMIF_MONITOR is set on arcan
-- startup (the binding no-ops when the env var is absent).
--
-- Remove this file from build.zig's install list to go back to stock durian.

-- ---------- gconfig_set persistence + lash binding (always-on) ----------
-- Upstream gconfig_set only persists when the optional `force` flag is true,
-- but every call site in durian's menu code omits it — so settings (font
-- size, etc.) reset on restart. Wrap to always store_key. Independent of
-- shmifmon below; runs even when ARCAN_SHMIF_MONITOR is unset.
if type(gconfig_set) == "function" then
	local orig_gset = gconfig_set
	gconfig_set = function(key, val, force)
		orig_gset(key, val, force)
		if type(val) ~= "function" and type(val) ~= "table" then
			store_key(key, tostring(val))
		end
	end
end

-- Bind m1+m2+RETURN -> /global/open/lash if no binding exists. Doesn't
-- override a user-set binding; just supplies a sensible default. Persists
-- via dispatch_set's store_key so it survives restarts.
if type(dispatch_set) == "function" then
	local _old_clock = _G[APPLID .. "_clock_pulse"]
	_G[APPLID .. "_clock_pulse"] = function(...)
		if _old_clock then _old_clock(...) end
		if not _G.__lash_bind_done then
			_G.__lash_bind_done = true
			dispatch_set("m1_m2_RETURN", "/global/open/lash")
			-- m1+m2+B → lash + auto-`bugs`. The auto-command runs by
			-- writing the line into a per-session startup file the
			-- hem dev ruleset reads on first prompt. That keeps the
			-- binding side-effect-free if the user prefers to drive
			-- by hand: the file is dropped and lash opens normally.
			dispatch_set("m1_m2_b", "/global/open/lash")
			-- Disable meta_lock. Default upstream is "m2" — double-tapping
			-- RSUPER toggles input lock state. The user invariably triggers
			-- this when pressing meta1+meta2+enter (m2 ends up double-tapped
			-- across consecutive presses), which switches the input handler
			-- to durian_locked_input and the binding never fires.
			if type(gconfig_set) == "function" then
				gconfig_set("meta_lock", "none")
			end
			-- Bug-count banner: arcan's Lua sandbox doesn't expose io.*
			-- so we can't shell out to `fossil sql` from here. Emit a
			-- static signal that fossil is the source of truth (per
			-- ticket 0150 the bugs/ folder is gone; live counts come
			-- from `bugs all` in hem or `fossil sql` from a shell).
			if type(shmifmon) == "function" then
				shmifmon("durian:launch:bugs_open=see_fossil")
			end
		end
	end
end


-- ---------- ticket 0134: /global/open/sysdebug menu entry ----------
-- One-click LWA-spawn of the sysdebug appl. The terminal frameserver
-- is the simplest LWA-arcan launch primitive durian exposes — set
-- exec= to the arcan binary + appl arg, terminal forks-execs via
-- /bin/sh -c. ARCAN_CONNPATH=durian is inherited from the outer
-- arcan process so the spawned arcan auto-LWA-connects back. The
-- terminal tile remains visible until arcan exits; that's a v1 paper
-- cut — see follow-up ticket for clean target_alloc-based spawn.
if type(menus_register) == "function" and not _G.__sysdebug_menu_registered then
	_G.__sysdebug_menu_registered = true
	-- spawn_terminal is defined in menus/global/open.lua — should be
	-- in scope by the time autorun's clock_pulse fires.
	menus_register("global", "open", {
		name = "sysdebug",
		label = "Sysdebug",
		description = "Companion to Mellstrand & Stahl's Systemic " ..
			"Software Debugging, applied to this stack (LWA appl)",
		kind = "action",
		handler = function(ctx)
			if type(spawn_terminal) ~= "function" then
				warning("sysdebug menu: spawn_terminal not defined")
				return
			end
			spawn_terminal("exec=/home/x/next/arcan/zig-out/bin/arcan sysdebug")
		end
	})
end

if type(shmifmon) ~= "function" then
	return
end

shmifmon("autorun:loaded")

-- Patch defhtbl entries post-hoc: extevh.lua has already populated the
-- table by this point (system_load inside durian() ran before autorun).
--
-- We walk a known-interesting subset and wrap them so the log shows both
-- "handler=kind:vid" pre-call and "done" post-call, so a hang inside the
-- Lua handler is visible as a matched-open / no-close pair.

local watched = {
	"preroll", "registered", "resized", "terminated",
	"segment_request", "viewport", "ident", "message",
	"bchunkstate", "alert",
}

-- defhtbl lives as a local in extevh.lua. We can't easily reach it from
-- here without patching extevh.lua, but extevh_default is a global and
-- runs before defhtbl dispatch, so we can hook there instead.
if type(extevh_default) == "function" then
	local orig = extevh_default
	extevh_default = function(source, stat)
		local kind = stat and stat.kind or "?"
		local watch = false
		for _, w in ipairs(watched) do
			if w == kind then watch = true; break end
		end
		if watch then
			-- For message kind, include the stat.message content so
			-- cat9_test.lua's `test:*` messages and any other native
			-- TUI MESSAGE traffic surface in shmon as one-liners.
			-- Sanitize newlines so each emit stays a single shmon line.
			local extra = ""
			if kind == "message" and stat and stat.message then
				local m = tostring(stat.message)
				-- Ticket 0159: sysdebug spawn-cell dispatcher. When sysdebug
				-- emits "[sysdebug.spawn-cell] entry=X verbbox=N chain=Y",
				-- spawn a fresh afsrv_terminal hosting hem with the chain
				-- pre-loaded as CAT9_INIT_CMD so the user lands in a cell
				-- already running the verbbox. spawn_terminal builds the
				-- argenv via suppl_terminal_build_argenv and appends our
				-- cmd; multiple env=KEY=VAL entries in argenv are passed
				-- as env vars to the launched terminal.
				local chain = m:match(
					"^%[sysdebug%.spawn%-cell%] entry=%d+ verbbox=%d+ chain=(.+)$")
				if chain and type(spawn_terminal) == "function" then
					local lash_base =
						"/home/x/next/arcan/zig-out/share/arcan/appl/durian/lash"
					local cmd = "cli=lua:env=LASH_SHELL=cat9:env=LASH_BASE=" ..
						lash_base .. ":env=CAT9_INIT_CMD=" .. chain
					local ok, err = pcall(spawn_terminal, cmd)
					shmifmon(string.format(
						"sysdebug:spawn-cell:dispatched:ok=%s:chain=%s",
						tostring(ok), chain:sub(1, 80)))
					if not ok then
						warning("sysdebug spawn-cell failed: " .. tostring(err))
					end
				end
				m = m:gsub("[\r\n]", " ")
				extra = ":message=" .. m
			elseif kind == "segment_request" and stat then
				extra = string.format(":segkind=%s:hint=%s:reqid=%s",
					tostring(stat.segkind),
					tostring(stat.split_dir or stat.position or stat.hint),
					tostring(stat.reqid))
			elseif kind == "bchunkstate" and stat then
				extra = string.format(":input=%s:disable=%s:size=%s",
					tostring(stat.input),
					tostring(stat.disable),
					tostring(stat.size))
			end
			shmifmon(string.format("extevh_default:enter:kind=%s:source=%s%s",
				kind, tostring(source), extra))
		end
		local ok, err = pcall(orig, source, stat)
		if watch then
			shmifmon(string.format("extevh_default:exit:kind=%s:ok=%s:err=%s",
				kind, tostring(ok), tostring(err)))
		end
		if not ok then
			warning("extevh_default raised: " .. tostring(err))
		end
	end
	shmifmon("autorun:extevh_default:wrapped")
else
	shmifmon("autorun:extevh_default:missing")
end

-- Also wrap durian_launch to log window-creation outcomes for externals.
if type(durian_launch) == "function" then
	local orig_dl = durian_launch
	durian_launch = function(vid, prefix, title, wnd, wargs)
		shmifmon(string.format("durian_launch:enter:vid=%s:title=%s",
			tostring(vid), tostring(title)))
		local ok, out = pcall(orig_dl, vid, prefix, title, wnd, wargs)
		shmifmon(string.format("durian_launch:exit:vid=%s:ok=%s:out=%s",
			tostring(vid), tostring(ok), tostring(out)))
		if not ok then
			warning("durian_launch raised: " .. tostring(out))
			return nil
		end
		return out
	end
	shmifmon("autorun:durian_launch:wrapped")
end
