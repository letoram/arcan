local workspaces = {} -- use to track client states
local ws_index = 1 -- active workspace
local hotkey_modifier = "lalt"
local syskey_modifier = "lalt_lctrl"
local clipboard_last = ""
local connection_point = "console"
local ws_limit = 100

local wayland_connection
local wayland_client
local wayland_config

function console(args)
	KEYBOARD = system_load("builtin/keyboard.lua")() -- get a keyboard state machine
	system_load("builtin/mouse.lua")() -- get basic mouse button definitions
	system_load("builtin/debug.lua")()
	system_load("builtin/string.lua")()
	system_load("builtin/table.lua")()
	wayland_client, wayland_connection = system_load("builtin/wayland.lua")()
	system_load("console_osdkbd.lua")() -- trigger on tap-events
	wayland_config = system_load("wayland_client.lua")() -- window management behavior for wayland clients

	mouse_setup(load_image("cursor.png"), 65535, 1, true, false)
	mouse_state().autohide = true

-- attach normal clients to this and use as an input capture surface to
-- allow more UI elements to be added more easily
	workspaces.anchor = null_surface(VRESW, VRESH)
	show_image(workspaces.anchor)
	mouse_addlistener({
		own = function(ctx, vid)
			return vid == workspaces.anchor
		end,
		tap = function(ctx)
			if console_osdkbd_active() then
				console_osdkbd_destroy(10)
			end
			return true
		end,
		name = "wm_anchor"
	}, {"tap"})

-- let the keymap handle repetition with whatever defaults exist
	KEYBOARD:kbd_repeat()
	KEYBOARD:load_keymap()
	switch_workspace(ws_index)

-- Spin up a new 'connection point' where one external connect can connect,
-- this gets re-opened after each 'connected' in the client event handler.
-- We provide a user or db overridable name, and the name is forwarded in
-- each new terminal that gets set up
	connection_point = get_key("connection_point") or connection_point
	target_alloc(connection_point, client_event_handler)
end

function console_input(input)
-- apply the keyboard translation table to all keyboard (translated) input and forward
	if input.translated then
		KEYBOARD:patch(input)

		console_osdkbd_destroy(10)
		if valid_hotkey(input) then
			return
		end

-- middle button paste shortcut, if more cursor features are added
	elseif input.mouse then
		if input.digital and input.subid == MOUSE_MBUTTON then
			if input.active then
				clipboard_paste(clipboard_last)
			end
		else
			mouse_iotbl_input(input)
			return
		end
	end

	local target = workspaces[ws_index]
	if not target then
		return
	end

-- let osdkeyboard get the first shot, might need some graphical element or other
-- trigger (gesture, ...) here instead so that the active application can get touch
	if input.touch and console_osdkbd_input(workspaces, target, input) then
		return
	end

	if (not input.kind) then
		print(debug.traceback())
	end
	target:input(input)
end

-- This entry point is only called in Lua-VM crash recovery state where a
-- scripting error or explicit WM swap (system_collapse(wmname)) call and
-- some handover protocol is needed.
function console_adopt(vid, kind, title, have_parent, last)
	local ok, opts = whitelisted(kind, vid)
	if not ok or have_parent or not find_free_space() then
		return false
	end
	local ret = new_client(vid, opts)
	if last then
		switch_workspace(1)
	end
	return ret
end

local function add_client_mouse(ctx, vid)
-- add a mouse handler that forwards mouse action to the target
	ctx.own =
	function(ctx, tgt)
		return vid == tgt
	end

	ctx.name = "ws_mh"
	ctx.button =
	function(ctx, vid, ind, pressed, x, y)
		target_input(vid, {
			devid = 0, subid = ind,
			mouse = true, kind = "digital",
			active = pressed
		})
	end

	ctx.motion =
	function(ctx, vid, x, y, rx, ry)
		target_input(vid, {
			devid = 0, subid = 0,
			kind = "analog", mouse = true,
			samples = {x, rx}
		})
		target_input(vid, {
			devid = 0, subid = 1,
			kind = "analog", mouse = true,
			samples = {y, ry}
		})
	end

-- all touch related events are normally forwarded, just need to intercept
-- here in order to disable the osd keyboard if it is active then tell the
-- caller to forward the input
	ctx.tap = function(ctx)
		if console_osdkbd_active() then
			console_osdkbd_destroy(10)
		end
		return true
	end

	ctx.mouse = true
	mouse_addlistener(ctx, {"motion", "button", "tap"})
end

-- find an empty workspace slot and assign / activate
function new_client(vid, opts)
	if not valid_vid(vid) then
		return
	end
	local new_ws = find_free_space()

-- safe-guard against out of workspaces
	if not new_ws then
		delete_image(vid)
		return
	end

-- or assign and activate
	local ctx = {
		index = new_ws,
		vid = vid,
		scale = opts.scaling,
		clipboard_temp = "",
	}

-- caller provided input hook?
	if not opts.input then
		ctx.input = function(ctx, tbl)
			target_input(vid, tbl)
		end
	else
		ctx.input = opts.input
	end

-- reserve first order to a capture surface for mouse input
	order_image(vid, 2)
	link_image(vid, workspaces.anchor)

	if not opts.block_mouse then
		add_client_mouse(ctx, vid)
	end

-- activate
	workspaces[new_ws] = ctx

	switch_workspace(new_ws)
	return true, ctx
end

-- read configuration from database if its there, or use a default
-- e.g. arcan_db add_appl_kv console terminal env=LC_ALL=C:palette=solarized
function spawn_terminal()
	local term_arg = (
		get_key("terminal") or "palette=solarized") ..
		":env=ARCAN_CONNPATH=" .. connection_point

	local inarg = appl_arguments()
	for _,v in ipairs(inarg) do
		if v == "lash" then
			term_arg = "cli=lua:" .. term_arg
		end
	end

	return launch_avfeed(term_arg, "terminal",
		function(source, status)
			return client_event_handler(source, status)
	end)
end

local function scale_client(ws, w, h)
	if ws.scale then
		local ar = w / h
		local wr = w / VRESW
		local hr = h / VRESH
		return
			(hr > wr and math.floor(VRESH * ar) or VRESW),
			(hr < wr and math.floor(VRESW / ar) or VRESH)
	else
		return w, h
	end
end

function client_event_handler(source, status)
-- Lost client, last visible frame etc. kept, and we get access to any exit-
-- message (last words) and so on here. Now, just clean up and remove any
-- tracking
	if status.kind == "terminated" then
		delete_image(source)
		local _, index = find_client(source)

-- if we lost the current active workspace client, switch to a better choice
		if index then
			delete_workspace(index)
		end

-- this says that the 'storage' resolution has changed and might no longer be
-- synched with the 'presentation' resolution so it will be scaled and filtered,
-- explicitly resizing counteracts that. Resize will always be called the
-- first time a client has submitted a frame, so it can be used as a
-- connection trigger as well.
	elseif status.kind == "resized" then
		local ws, index = find_client(source)
		if ws then

-- some clients might not be able to supply a proper sized buffer, if possible,
-- scale to fit (candidate for adding pan and zoom like behavior)
			local w, h = scale_client(ws, status.width, status.height)
			resize_image(source, w, h)
			center_image(source, workspaces.anchor)
			image_set_txcos_default(source, status.origo_ll)
			ws.aid = status.source_audio
		else
			delete_image(source)
		end

-- an external connection goes through a 'connected' (the socket has been consumed)
-- state where the decision to re-open the connection point should be made, always
-- re-open, but destroy if we are out of workspaces
	elseif status.kind == "connected" then
		if (find_free_space() == nil) then
			delete_image(source)
		end
		target_alloc(connection_point, client_event_handler)

-- an external connection also goes through a 'registered' phase where auth-
-- primitives etc. are provided, it is here we know the 'type' of the connection
	elseif status.kind == "registered" then
		local ok, opts = whitelisted(status.segkind, source)
		if not ok then
			delete_image(source)
			return
		end

-- wayland needs a completely different ruleset and an outer 'client' that deals
-- with bootstrapping the rest
		if status.segkind == "bridge-wayland" then
			wayland_connection(source,
				function(source, status)
					local _, wl_cl = new_client(source, {block_mouse = true})
					local cfg = wayland_config(wl_cl)
					local cl = wayland_client(source, status, cfg)
					wl_cl.bridge = cl
				end
			)
			return
		end

		local client_ws = find_client(source)
		if not client_ws then
			_, client_ws = new_client(source, opts)
			if not client_ws then
				delete_image(source)
				return
			end

-- track these so we can have type-specific actions other than those from the
-- specific handler, useful with, the osd-keyboard for instance
			client_ws.segkind = status.segkind
			client_ws.input_labels = {}
		end

	elseif status.kind == "input_label" then
		local client_ws = find_client(source)
		if #status.labelhint == 0 then
			client_ws.input_labels.input_labels = {}
		else
			table.insert(client_ws.input_labels, status)
		end

-- the 'preroll' state is the time to provide any starting state you'd like
-- the client to have access to immediately after the connection is activated
	elseif status.kind == "preroll" then
-- tell the client about the dimensions and density we'd prefer it to have,
-- these match whatever 'primary' display that arcan decided on
		target_displayhint(source,
			VRESW, VRESH, TD_HINT_IGNORE, {ppcm = VPPCM})

-- tell the terminal about the fonts we want it to use (if set)
		local font = get_key("terminal_font")
		local font_sz = get_key("font_size")

		if font and (status.segkind == "tui" or status.segkind == "terminal") then
			target_fonthint(source, font, (tonumber(font_sz) or 12) * FONT_PT_SZ, 2)
		else
			target_fonthint(source, (tonumber(font_sz) or 12) * FONT_PT_SZ, 2)
		end

-- the client wish a new subwindow of a certain type, only ones we'll accept
-- now is a clipboard which is used for 'copy' operations
	elseif status.kind == "segment_request" then
		if status.segkind == "clipboard" then

-- tell the client that we accept the new clipboard and assign its event handler
-- a dumb client could allocate more clipboards here, but we don't care about
-- tracking / limiting
			local vid = accept_target(clipboard_handler)
			if not valid_vid(vid) then
				return
			end
-- tie the lifespan of the clipboard to that of the parent
			link_image(vid, source)

		elseif status.segkind == "handover" then
			local vid = accept_target(client_event_handler)
		end
	end
end

local last_index = 1
function switch_workspace(index)
-- if an index is not provided, switch to the previous one if there is one
	if not index then
		if workspaces[last_index] then
			return switch_workspace(last_index)

-- but if that is empty, grab the first one that isn't
		else
			for i=1,10 do
				if workspaces[i] then
					return switch_workspace(i)
				end
			end
		end

-- or just pick one
		index = 1
	end

-- hide the current one so we don't overdraw, reset position as that might
-- have been modified by other tools like the osd keyboard
	if workspaces[ws_index] then
		hide_image(workspaces[ws_index].vid)
		move_image(workspaces[ws_index].vid, 0, 0)
	end

-- remember the last unique one so we can switch back on destroy
	if ws_index ~= index then
		last_index = ws_index
		ws_index = index
	end

-- spawn_terminal -> launch_avfeed -> [handler] -> find_free will land back
-- into this, and set visibility on first frame
	if not workspaces[ws_index] then
		spawn_terminal()
	end

-- show the new one
	local new_space = workspaces[ws_index]
	if new_space and valid_vid(new_space.vid) then
		show_image(new_space.vid)
		console_osdkbd_invalidate(workspaces, new_space)
	end
end

-- scan the workspaces for one that hasn't been allocated yet,
-- bias towards the currently selected 'index'
function find_free_space()
	if not workspaces[ws_index] then
		return ws_index
	end

	for i=1,10 do
		if not workspaces[i] then
			return i
		end
	end
end

-- sweep the workspaces and look for an allocated one with a matching vid
function find_client(vid)
	for i=1,10 do
		if workspaces[i] and workspaces[i].vid == vid then
			return workspaces[i], i
		end
	end
end

function valid_hotkey(input)

-- use falling edge and two different sets of actions based on impact
	local mods = decode_modifiers(input.modifiers, "_")

	if not input.active or
		(mods ~= hotkey_modifier and mods ~= syskey_modifier) then
		return false
	end

	if mods == syskey_modifier then
-- for handy testing of adoption etc.
		if input.keysym == KEYBOARD.SYSREQ then
			system_collapse()

		elseif input.keysym == KEYBOARD.BACKSPACE then
			return shutdown()
		end

		return true
	end

	if input.keysym == KEYBOARD.v then
		clipboard_paste(clipboard_last)

-- forcibly destroy the current workspace
	elseif input.keysym == KEYBOARD.DELETE then
		if workspaces[ws_index] and workspaces[ws_index].vid then
			delete_workspace(ws_index)
		end

-- toggle mute on a specific audio source by querying the current value
-- and inverting it (1.0 - n)
	elseif input.keysym == KEYBOARD.m then
		if workspaces[ws_index] and workspaces[ws_index].aid then
			local current = audio_gain(workspaces[ws_index].aid, nil)
			audio_gain(workspaces[ws_index].aid, 1.0 - current)
		end

	elseif input.keysym == KEYBOARD.l then
		next_workspace()

	elseif input.keysym == KEYBOARD.h then
		previous_workspace()

-- covert Fn key to numeric index and switch workspace
	elseif input.keysym >= KEYBOARD.F1 and input.keysym <= KEYBOARD.F10 then
		switch_workspace(input.keysym - KEYBOARD.F1 + 1)
	end

	return true
end

local clipboard_temp = ""
function clipboard_handler(source, status)
	if status.kind == "terminated" then
		delete_image(source)

-- A clipboard paste operation might be split multipart over multiple
-- messages, so we need to track its state and only 'promote' when we
-- have received all of them. To avoid a client- race the tracking is
-- done per- workspace.
	elseif status.kind == "message" then
		tbl, _ = find_client(image_parent(source))
		tbl.clipboard_temp = tbl.clipboard_temp .. status.message

-- Multipart set means that there are more to follow, with untrusted
-- clients - this should truncate / react on some size but we do not
-- do that here. Promote to the 'shared' paste slot.
		if not status.multipart then
			clipboard_last = tbl.clipboard_temp
			tbl.clipboard_temp = ""
		end
	end
end

-- Triggered by the 'paste' keybinding or mouse middle button press.
function clipboard_paste(msg)
	msg = msg and msg or clipboard_last
	local dst_ws = workspaces[ws_index]
	if not dst_ws or not
		valid_vid(dst_ws.vid, TYPE_FRAMESERVER) or #clipboard_last == 0 then
		return false
	end

-- The client 'pasteboard' is allocated on demand, so if client
-- doesn't have one, reallocate again.
	if not valid_vid(dst_ws.clipboard) then
		dst_ws.clipboard = define_nulltarget(dst_ws.vid, "clipboard",
			function(source, status)
				if status.kind == "terminated" then
					delete_image(source)
				end
			end
		)
-- Frameserver allocations can always fail
		if not valid_vid(dst_ws.clipboard) then
			return
		end

-- And tie life-span to workspace video object
		link_image(dst_ws.clipboard, dst_ws.vid)
	end

	target_input(dst_ws.clipboard, msg)
end

function previous_workspace()
	for i=ws_index+1,1,-1 do
		if workspaces[i] ~= nil then
			switch_workspace(i)
			return
		end
	end

	for i=ws_limit,ws_index,-1 do
		if workspaces[i] ~= nil then
			switch_workspace(i)
			return
		end
	end
end

function next_workspace()
	for i=ws_index+1,ws_limit do
		if workspaces[i] ~= nil then
			switch_workspace(i)
			return
		end
	end

	for i=1,ws_index do
		if workspaces[i] ~= nil then
			switch_workspace(i)
			return
		end
	end
end

function resize_workspace(i, w, h)
	if not workspaces[i] then
		return
	end

	target_displayhint(workspaces[i].vid, w, h, TD_HINT_IGNORE)
end

function delete_workspace(i)
	if workspaces[i] and valid_vid(workspaces[i].vid) then
		delete_image(workspaces[i].vid)
	end

	if workspaces[i].destroy then
		workspaces[i]:destroy()
	end

	if workspaces[i].mouse then
		mouse_droplistener(workspaces[i])
	end

	workspaces[i] = nil

	if i == ws_index then
		switch_workspace()
	end
end

-- There are many types that can be allocated as primary (first connection)
-- or secondary (segment_request) and validation is necessary at 'connect'
-- and at 'adopt'. We might want to differentiate the implementation of their
-- events, or reject the ones with a type we don't support.
function whitelisted(kind, vid)
	local set = {
		["vm"] = {client_event_handler, {}},
		["lightweight arcan"] = {client_event_handler, {}},
		["multimedia"] = {client_event_handler, {scale = true}},
		["tui"] = {client_event_handler, {}},
		["game"] = {client_event_handler, {scale = true}},
		["application"] = {client_event_handler, {}},
		["browser"] = {client_event_handler, {}},
		["terminal"] = {client_event_handler, {}},
		["bridge-x11"] = {client_event_handler, {}},
		["bridge-wayland"] = {client_event_handler, {}},
	}
	if (set[kind]) then
		if (vid) then
			target_updatehandler(vid, set[kind][1])
		end
		return true, set[kind][2]
	end
end

function console_clock_pulse()
	mouse_tick(1)
	KEYBOARD:tick()
end

function console_display_state(status)
	resize_video_canvas(VRESW, VRESH)
	resize_image(workspaces.anchor, VRESW, VRESH)
	mouse_querytarget(WORLDID)

	for i,v in pairs(workspaces) do
		if type(v) == "table" then
			if v.bridge then
				v.bridge:resize(VRESW, VRESH)
			elseif valid_vid(v.vid) then
				target_displayhint(v.vid, VRESW, VRESH, TD_HINT_IGNORE, WORLDID)
			end
		end
	end

-- since density, font and so on might have changed - we want to rebuild the
-- osd keyboard to account for that
	local target = workspaces[ws_index]
	if not target then
		console_osdkbd_destroy(0)
		return
	end

	console_osdkbd_invalidate(workspaces, target)
end
