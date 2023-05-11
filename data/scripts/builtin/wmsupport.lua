--
-- basic functions to let other built-in scripts interact with a
-- window manager in order to establish some convention for
-- binding helper scripts with a wm
--
-- expected functions:
--  - wm_input_selected(iotbl)
--    send iotbl to the window that has input focus
--
--  - wm_input_grab(key) => 'current_key'
--    accessor to a 'grab' function stored under key,
--    input should be routed through this key until released
--    with wm_input_release_grab(key). If there already is a
--    'key' that has grab, the call will be ignored.
--    always returns the currently set grab.
--
--
--  - wm_input_release_grab(key) => bool
--    try to release the grab of 'key', returns true if the
--    grab was released, or false if the key mismatch the current
--    grab.
--
--  - wm_active_display() => rt, width, height, vppcm, hppcm
--    retrieve rendertarget and display properties for the currently
--    active display
--
--  - wm_active_display_listen(func)
--    add a permament callback that will be triggered whenever the
--    properties of the active display has changed
--
--  - wm_touch_normalize(iotbl) => iotbl
--    apply calibration and rescale input samples in iotbl to match
--    the coordinate space of the active display
--
--  - wm_get_keyboard_translation() => keytbl
--    retrieve a symbol table for translating and patching iotables
--    through the builtin/keyboard.lua setup.
--    keytbl:patch(iotbl) => iotbl to apply keymap to iotbl
--
-- callable by wm:
--  - wm_active_display_rebuild()
--    trigger all the active display listeners
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

-- accessor for a shared keyboard translation table
if not wm_get_keyboard_translation then
	local symtable = system_load("builtin/keyboard.lua")()
	symtable:load_keymap("default.lua")

	wm_get_keyboard_translation = function()
		return symtable
	end
end

-- normalize device-id touch input samples to the range of the active display
if not wm_touch_normalize then
	local rangetbl = {}
	wm_touch_normalize =
	function(io)
		local rt, w, h, _, _ = wm_active_display()
		local range = rangetbl[io.devid]
		if not range then
			local x_axis = inputanalog_query(io.devid, 0);
			local y_axis = inputanalog_query(io.devid, 1);

			if (x_axis and y_axis) then
				range = {x_axis.upper_bound, y_axis.upper_bound}
			else
				range = {w, h}
			end

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
