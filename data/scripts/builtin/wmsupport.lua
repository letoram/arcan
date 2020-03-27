--
-- basic functions to let other built-in scripts interact with a
-- window manager in order to establish some convention for
-- binding helper scripts with a wm
--

if not wm_input_selected then
	wm_input_selected =
	function(iotbl)
-- no-op if not implemented
	end
end

-- key is to help trouble-shoot api misuse or unexpected chain
-- of event handlers - the input_grab uses some unique identifier
-- that needs to be released before a new on is permitted
local grab_key
if not wm_input_grab then
	wm_input_grab =
	function(key)
		if key and not grab_key then
			grab_key = key
		end
		return grab_key
	end
end

-- relese without a key is not permitted, release without a previous
-- key is not permitted - return boolean on match status
if not wm_input_release_grab then
	wm_input_release_grab =
	function(key)
		assert(key)
		assert(grab_key ~= nil)
		if key == grab_key then
			grab_key = nil
			return true
		end
		return false
	end
end

-- display management bits
--
-- active_display
-- should be enough to figure out basic rendering parameters
if not wm_active_display then
	wm_active_display =
	function()
		return WORLDID, VRESW, VRESH, HPPCM, VPPCM
	end
end

-- rebuild is called by the wm side, used to indicate that resources should
-- be redrawned or reworked to fit new display properties
local active_display_listeners = {}
if not wm_active_display_rebuild then
	wm_active_display_rebuild =
	function()
		local rt, w, h, hppcm, vppcm = wm_active_display()
		for _,v in ipairs(active_display_listeners) do
			v(rt, w, h, hppcm, vppcm)
		end
	end
end

-- listen is used to register components that should react on target display
-- change, other builtin scripts will make use of this
if not wm_active_display_listen then
	wm_active_display_listen =
	function(hnd)
		assert(hnd)
		assert(type(hnd) == "function")
		for _,v in ipairs(active_display_listeners) do
			if v == hnd then
				return
			end
		end
		table.insert(active_display_listeners, hnd)
	end
end

-- normalize device-id touch input samples to the range of the active display
if not wm_touch_normalize then
	local rangetbl = {}
	wm_touch_normalize =
	function(io)
-- there is no support script for touch- ranging yet as the scripts in durden
-- are not mature enough (and no input platform that does the job) - assume
-- values are ranged to the display, then autorange as needed.
		local rt, w, h, _, _ = wm_active_display()
		local range = rangetbl[io.devid]
		if not range then
			range = {w, h}
			rangetbl[io.devid] = range
		end

		if io.x > range[1] then
			range[1] = io.x
		end

		if io.y > range[2] then
			range[2] = io.y
		end

		io.x = io.x / range[1] * w
		io.y = io.y / range[2] * h
	end
end
