-- Description: Hem - reference user shell for Lash
-- License:     Unlicense
-- Reference:   https://github.com/letoram/cat9
-- See also:    HACKING.md, TODO.md

local hem =  -- vtable for local support functions
{
	scanner = {}, -- state for asynch completion scanning
	env = lash.root:getenv(),

-- all these tables are built / populated through the various builtin
-- sets currently available, as well as the dynamic scanning in jobmeta/promptmeta
	builtins = { hint = {}},
	suggest = {},
	handlers = {},
	views = {hint = {}},
	jobmeta = {},
	promptmeta = {},
	aliases = {},
	bindings = {
		chord = {}
	},

	config = loadfile(string.format("%s/cat9/config/config.lua", lash.scriptdir))(),
	jobs = lash.jobs,
	timers = {},

	resources = {}, -- used for clipboard and bchunk ops
	state = {export = {}, import = {}, orphan = {}},
	dir_monitor = {},
	builtin_name = "default",

	history = {},
	langsup = {},

	idcounter = 0, -- monotonic increment for each command dispatched
	lastdir = "",
	laststr = "",
	visible = true,
	focused = true,
	time = 0 -- monotonic tick
}

function hem.a11y_buffer(msg)
-- default no handling of a11y messages
end

if not hem.config then
	table.insert(lash.messages, "hem: error loading/parsing config/default.lua")
	return false
end

-- avoid using the config.lua provided scanner argument as some might want to
-- switch that to fuzzy finder and similar tools
local function glob_builtins(dst)
	local arg =
	{
		"/usr/bin/env",
		"/usr/bin/env",
		"find",
		lash.scriptdir .. "cat9/",
		"-maxdepth", "1",
		"-type", "f"
	}
	local _, scan, _, pid = lash.root:popen(arg, "r", lash.root:getenv())

	if scan then
		scan:lf_strip(true)
			scan:data_handler(
			function()
				local msg, ok = scan:read()
				if msg then
					local base = string.match(msg, "[^/]*.lua$")
					local name = base and string.sub(base, 0, #base - 4) or nil
					if name == "default" then
						table.insert(dst, 1, name)
					else
						table.insert(dst, name)
					end
					return true
				end

				return ok
			end
		)
		lash.root:pwait(pid)
	end
end

-- zero env out so our launch properties doesn't propagate
hem.env["ARCAN_ARG"] = nil
hem.env["ARCAN_CONNPATH"] = nil

-- all builtin commands are split out into a separate 'command-set' dir
-- in order to have interchangeable sets for expanding cli/argv of others
local safe_builtins
local safe_suggest
local safe_views
builtin_completion = {}

local function load_builtins(base, flush)
	hem.builtin_name = base
	if flush then
		hem.builtins = {hint = {}}
		hem.suggest = {}
		hem.views = {hint = {}}
	else
		hem.builtins["_default"] = nil
	end

-- first load / overlay any static user config
	if not hem.config.builtins[base] then
		hem.config.builtins[base] = {}
	end
	local dcfg = hem.config.builtins[base]
	local fptr, msg = loadfile(string.format("%s/cat9/config/%s.lua", lash.scriptdir, base))
	if fptr then
		local ret, msg = pcall(fptr)
		if ret and type(msg) == "table" then
			for k,v in pairs(msg) do
				if not dcfg[k] then
					dcfg[k] = v
				end
			end
		else
			hem.add_message(string.format("builtin: [%s] broken config: %s", base, msg))
		end
	end

-- then load the actual command-description
--
-- the base 'read-only' config is provided in the lash table rather than as argument due
-- to the legacy of the builtin- set expected to return a table and not a function as the
-- case is with the actual commands
  lash.builtin_cfg = dcfg
	local fptr, msg = loadfile(string.format("%s/cat9/%s.lua", lash.scriptdir, base))
	if not fptr then
		return false, string.format("builtin: [%s] failed to load: %s", base, msg)
	end

-- this can fail with an error message if there is some precondition that can't be
-- fulfilled such as a missing support tool binary
	local set = fptr()
	if type(set) ~= "table" then
		msg = type(set) == "string" and set or "unknown"
		return false, string.format( "builtin: [%s] failed to run: %s", base, msg)
	end

-- load each command and append to the builtins/suggestions/views/config
	for _,v in ipairs(set) do
		local fptr, msg = loadfile(string.format("%s/cat9/%s/%s", lash.scriptdir, base, v))
		if fptr then
			local ret, msg = pcall(fptr(),
				hem, lash.root, hem.builtins, hem.suggest, hem.views, dcfg)

			if not ret then
				return false, string.format("builtin: [%s:%s] setup failure: %s", base, v, msg)
			end
		else
			return false, string.format("builtin: [%s:%s] failed to load: %s", base, v, msg)
		end
	end

-- rescan builtins for the base command
	local set = {}
	glob_builtins(set)
	hem.suggest["builtin"] =
	function(args, raw)
		if #args > 3 then
			hem.add_message("builtin [set]: too many arguments")
			return
		elseif #args == 3 then
			set = {"nodef"}
		end

		hem.readline:suggest(hem.prefix_filter(set, args[#args]), "word")
	end

	hem.builtins.hint.builtin = "Swap set of active commands"

-- force-inject loading builtin set so swapping works ok
	hem.builtins["builtin"] =
	function(a, opt)
		if not a or #a == 0 then
			a = "system"
		end

-- We cache the one used initially so hot-reloading a bad new builtin set
-- won't actually break the previous one.
		local ok, msg
		local flush = false
		hem.sh_runner_user = nil

		if opt then
			if opt ~= "nodef" then
				if a == "system" then
					hem.add_message("builtin system: user set to " .. opt)
					hem.sh_runner_user = opt
				else
					hem.add_message("builtin [set] [nodef]: unknown option argument")
					return
				end
			end
	-- currently don't permit arguments to the builtin set
		end

-- always append default builtins
		if a ~= "default" then
			load_builtins("default", true)
		end

		ok, msg = load_builtins(a, flush)

		if not ok then
			local default = string.format(
				"missing requested builtin set [%s] - revert to system.", a)
			hem.add_message(msg or default)
			hem.builtins = safe_builtins
			hem.builtin_name = "default"
			hem.suggest = safe_suggest
			hem.views = safe_views
		end
		hem.a11y_buffer("builtin " .. hem.builtin_name)
	end

-- build the indexed table, sort and resolve-overlay the hints
	builtin_completion = {}
	for k, _ in pairs(hem.builtins) do
		if string.sub(k, 1, 1) ~= "_" and k ~= "hint" then
			table.insert(builtin_completion, k)
		end
	end
	table.sort(builtin_completion)
	builtin_completion.hint = hem.builtins.hint

	return true
end

local function load_feature(name, base)
	base = base and base or "base"
	fptr, msg = loadfile(
		string.format("%s/cat9/%s/%s", lash.scriptdir, base, name))
	if not fptr then
		return false, msg
	end

	local init = fptr()
	init(hem, lash.root, hem.config)
end

-- treat config overloading as injecting additional state
-- (builtin/config config =save/=load maps)
function hem.reload()
load_feature("misc.lua")    -- support functions that doesn't fit anywhere else
load_feature("ioh.lua")     -- event handlers for display server device/state io
load_feature("scanner.lua") -- running hidden jobs that collect information
load_feature("jobctl.lua")  -- processing / forwarding job input-output
load_feature("parse.lua")   -- breaking up a command-line into actions and suggestions
load_feature("layout.lua")  -- drawing screen, decorations and related handlers
load_feature("vt100.lua")   -- state machine to plugin decoding
load_feature("jobmeta.lua") -- job contextual information providers
load_feature("json.lua")    -- json parsing
load_feature("editctl.lua") -- making jobs editable
load_feature("promptmeta.lua") --  prompt contextual information providers
load_feature("diff_match_patch.lua")
load_feature("bindings.lua", "config")
load_feature("langsup.lua", "langsup")
load_builtins("default")
hem.path_set = nil -- binary completion for exec is statically cached
safe_builtins = hem.builtins
safe_suggest = hem.suggest
safe_views = hem.views
load_builtins("system")
load_feature("accessibility.lua")
hem.get_history_source()
hem.set_history_exporter()
end
hem.reload()

-- Dev-driver autoexec hook: if CAT9_INIT_CMD is set in env, dispatch
-- it once after hem finishes init via a one-shot timer (so hem.readline
-- is ready).  Commands separated by `|||` (three pipes) so chains can
-- carry pipes/semicolons/regex without collision (the previous `;`
-- delimiter ate `mouse_show\|mouse_hide` etc).
do
    local init_cmd = (hem.env and hem.env.CAT9_INIT_CMD) or
                     (os.getenv and os.getenv("CAT9_INIT_CMD"))
    if init_cmd and init_cmd ~= "" then
        local fired = false
        hem.timers = hem.timers or {}
        table.insert(hem.timers, function()
            if fired then return false end
            if not (hem.readline and hem.parse_string) then return true end
            fired = true
            -- Split on |||; trim each piece; skip empties.
            local rest = init_cmd
            while rest ~= "" do
                local sep = string.find(rest, "|||", 1, true)
                local piece = sep and string.sub(rest, 1, sep - 1) or rest
                rest = sep and string.sub(rest, sep + 3) or ""
                local t = string.gsub(piece, "^%s+", "")
                t = string.gsub(t, "%s+$", "")
                if t ~= "" then hem.parse_string(hem.readline, t) end
            end
            return false
        end)
    end
end

-- now that the builtins are available, load the ingoing state groups
if hem.config.allow_state and hem.handlers.state_in then
	lash.root:state_size(1 * 1024)
	local state = lash.root:fopen(
		hem.system_path("state") .. "/cat9_state.lua", "r")
	if state then
		hem.handlers.state_in(lash.root, state)
	end
end

hem.config.readline.verify = hem.readline_verify

lash.root:set_flags(tui.flags.mouse_full)
lash.root:set_handlers(hem.handlers)
hem.reset()
hem.update_lastdir()
hem.flag_dirty()

-- make sure :revert() calls always cleans the readline state, this is enough
-- of an annoying thing to debug that this workaround is the least painful
-- option
local old_revert = lash.root.revert
lash.root.revert =
function(...)
	hem.last_revert = debug.traceback()
	hem.readline = nil
	hem.get_prompt = hem.default_prompt
	return old_revert(...)
end

-- import job-table and add whatever metadata we want to track
local old = lash.jobs
lash.jobs = {}
hem.jobs = lash.jobs
for _, v in ipairs(old) do
	hem.import_job(v)
end

local root = lash.root
root:update_identity(root:chdir())

if tui.arguments then
	for i,v in ipairs(tui.arguments) do
		hem.parse_string(hem.readline, v)
	end
end

while root:process() do
	if (hem.process_jobs()) then
-- updating the current prompt will also cause the contents to redraw
		hem.flag_dirty()
	end

-- this should also catch detached jobs that are flagged as dirty so
-- now need to do this separately
	if hem.dirty then
		hem.redraw()
		hem.dirty = false

		for _, v in ipairs(hem.jobs) do
			if v.hidden and v.detach_handlers then
				if v.redraw then
					v:redraw(v, false, true)
				end
				v.detach_handlers.redraw(v.root)
				if v.redraw then
					v:redraw(v, true, true)
				end
			end
		end
	end

	if not hem.readline and hem.selectedjob then
		local sj = hem.selectedjob
		local rgb = sj.cursor_rgb
		sj.root:cursor_to(
			sj.region[1] +
			sj.line_number_width +	hem.config.content_offset +
			sj.cursor[1],
			sj.region[2] + sj.cursor[2] + 1,
			sj.cursor_style,
			unpack(rgb or {})
		)
	end

	root:refresh()
end

-- ensure destroy handlers are triggered before shutting down so any
-- external cleanup isn't omitted if the window is forcibly closed.
for i=#hem.jobs,1,-1 do
	hem.remove_job(hem.jobs[i])
end

-- update config/state persistence, note that the tmp file and dest
-- need to be on the same filesystem for the atomic rename to work
if hem.config.allow_state and hem.handlers.state_out then
	local spath = hem.system_path("state")
	root:chdir(spath)
	local tmp, path = root:tempfile(spath .. "/stateXXXXXX")

	if tmp then
		hem.handlers.state_out(root, tmp, true)
		tmp:flush(-1)
		root:frename(path, spath .. "/cat9_state.lua")
		tmp:close()
	end
end
