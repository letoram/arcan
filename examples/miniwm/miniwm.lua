--
-- This app is a minimal window manager
--
-- It demonstrates native mouse cursor,
-- keybindings, switching active windows,
-- and non-authoritative connections
--

-- used for global keybindings
dispatchtbl = {};
dispatchhlp = {};

-- tracks running external connections and helps re-use callback
windows = {};
window_id_position = 0;
vid_to_wnd = {};

-- connection path for external connection (export ARCAN_CONNPATH=...)
connection_path = "arcan";

-- switch to use some other button for triggering WM specific functions
-- (e.g. LALT etc. check scripts/keysym.lua)
meta_key = "MENU";

--
-- when adopting from a crashed script, we only accept the following:
--
accepted_types = {};
accepted_types["lightweight arcan"] = true;
accepted_types["multimedia"] = true;
accepted_types["shell"] = true;
accepted_types["remoting"] = true;
accepted_types["game"] = true;
accepted_types["application"] = true;
accepted_types["browser"] = true;
accepted_types["encoder"] = true;

--
-- used to indicate that the associated process has died
--
bwshader = [[
uniform sampler2D map_diffuse;
varying vec2 texco;
void main()
{
	vec4 col = texture2D(map_diffuse, texco);
	float intens = (col.r + col.g + col.b) / 3.0;
	gl_FragColor = vec4(intens, intens, intens, 0.5);
}
]];

--
-- we don't permit sources to specify their own alpha- channel
--
normalshader = [[
uniform sampler2D map_diffuse;
varying vec2 texco;
void main()
{
	vec4 col = texture2D(map_diffuse, texco);
	col.a = 1.0;
	gl_FragColor = col;
}
]];

--
-- some sources may need its Y-axis flipped
--
flipyvshader = [[
uniform mat4 modelview;
uniform mat4 projection;

attribute vec2 texcoord;
varying vec2 texco;
attribute vec4 vertex;

void main()
{
	gl_Position = (projection * modelview) * vertex;
	texco.s = texcoord.s;
	texco.t = 1.0 - texcoord.t;
}
]];

-- first entrypoint, and the only one required by the engine.
-- others used are:
-- miniwm_adopt (using the script for crash recover)
-- miniwm_clock_pulse (monotonic clock)
-- miniwm_input (mouse, keyboard, ...)
function miniwm()
	system_load("scripts/mouse.lua")();
	system_load("scripts/listview.lua")();
	symtable = system_load("scripts/symtable.lua")();

-- ugly green box as mouse cursor
	cursor = fill_surface(16, 16, 0, 255, 0, 16, 16);
	mouse_setup_native(cursor, {});

-- pick a background image if one is handy, otherwise just an ugly single color
	if (resource("background.png")) then
		background = load_image("background.png");
		resize_image(background, VRESW, VRESH);
	end

	if (not valid_vid(background)) then
		background = color_surface(VRESW, VRESH, 32, 64, 32);
	end

	show_image(background);
	image_tracetag(background, "background");

-- setup input handler for META + KEY WM specific actions
	dispatchtbl["TAB"] = {cycle_active, "Cycle Active Program"};
	dispatchtbl["F1"] = {global_popup, "System Popup Menu"};
	dispatchtbl["F2"] = {target_popup, "Window Specific Popup"};
	dispatchtbl["F4"] = {destroy_active, "Terminate Active Program"};
	dispatchtbl["l"]  = {toggle_mouse_grab, "Toggle Mouse Grab"};
	show_helper();

-- precompile shaders that will be used to draw the source data
	build_shader(flipyvshader, normalshader, "normal_mirror");
	build_shader(nil, bwshader, "dead");
	build_shader(nil, normalshader, "normal");
	build_shader(flipyvshader, bwshader, "dead_mirror");

-- enable external connections, if the engine build supports it
-- another process can connect using the shared memory interface
-- and the domain socket key (connection_path)
	if (target_alloc) then
		target_alloc(connection_path, external_connected);
	end
end

function miniwm_clock_pulse()
	mouse_tick(1);
end

function miniwm_adopt(vid, wnd_type, wnd_title)
	if (accepted_types[wnd_type] == nil) then
		delete_image(vid);
		return;
	end

	register_window(vid, string.gsub(wnd_title, "\\", "\\\\") .." (adopted)");
	target_updatehandler(vid, default_cb);
end

function show_helper()
	local lines = {[[\ffonts/default.ttf,18 \#ffffff ]]};
	for k,v in pairs(dispatchtbl) do
		table.insert(lines, string.format("%s + %s \t %s", meta_key, k, v[2]));
	end
	table.insert(lines, "");
	table.insert(lines, "Popup Navigation");
	table.insert(lines, "UP/DOWN    \t Move Cursor");
	table.insert(lines, "ENTER/RIGHT\t Trigger Selected");
	table.insert(lines, "LEFT/ESCAPE\t Close Popup");

	local helper = render_text(table.concat(lines, [[\n\r]]));
	local props = image_surface_properties(helper);
	local helper_bg = color_surface(props.width * 1.1, props.height * 1.1, 0, 0, 0);
	blend_image(helper_bg, 0.5);
	show_image(helper);
	expire_image(helper_bg, 500);
	expire_image(helper, 500);
	order_image(helper_bg, 4);
	order_image(helper, 4);
end

-- priority (high-low):
-- dispatchtable
-- popupmenu
-- active_window
function miniwm_input(iotbl)
	local keysym = symtable[iotbl.keysym];
	if (iotbl.kind == "digital" and iotbl.translated) then
		if (keysym == meta_key) then
			meta_key_held = iotbl.active;

		elseif (meta_key_held and dispatchtbl[keysym] and iotbl.active) then
			return dispatchtbl[keysym][1]();
		end
	end

	if (active_popup) then
		if (iotbl.kind == "digital") then
-- button clicks also updates the state table for mouse input
			if (iotbl.source == "mouse") then
				mouse_button_input(iotbl.subid, iotbl.active);
			end

			popup_keyinput(symtable[iotbl.keysym], iotbl.active);
		else
			mouse_motion(iotbl.subid == 0 and iotbl.samples[2] or 0,
				iotbl.subid == 1 and iotbl.samples[2] or 0);
		end

	elseif (active_window) then
		target_input(active_window.id, iotbl);
	end
end

--
-- Every external connection consumes the active listener,
-- which therefore needs to be allocated.
--
function external_connected(source, status)
	target_alloc(connection_path, external_connected);
	register_window(source);
	target_updatehandler(source, default_cb);
	default_cb(source, status);
end

function register_window(vid, subtype)
	local wndtbl = {
		id = vid,
		kind = subtype,
		name = ("unknown" .. (#windows + 1))
	};
	vid_to_wnd[vid] = wndtbl;
	suspend_target(vid);
	table.insert(windows, wndtbl);
end

function window_index(vid)
	for i=1,#windows do
		if windows[i].id == vid then
			return i;
		end
	end
end

function cycle_active()
	window_id_position = window_id_position + 1;
	if (window_id_position > #windows) then
		window_id_position = 1;
	end
	activate_window(windows[window_id_position]);
end

function destroy_active()
	if (active_window == nil) then
		return;
	end

	local wnd_ind = window_index(active_window.id);

	delete_image(active_window.id);
	table.remove(windows, wnd_ind);

	if (wnd_ind > #windows) then
		wnd_ind = 1;
	end

	active_window = nil;
	activate_window(windows[wnd_ind]);
end

function activate_window(wnd)
	if (wnd == nil) then
		return;
	end
	assert(type(wnd) == "table");

	if (active_window ~= nil and wnd ~= active_window) then
		blend_image(active_window.id, 0.0, 5);
		suspend_target(active_window.id);
	end

	active_window = wnd;
	window_id_position = window_index(wnd.id);

-- resize to display and center, maintain aspect ratio
	local props = image_surface_initial_properties(wnd.id);
	if ( (math.abs(props.width - VRESW)) < math.abs(props.height - VRESH)) then
		resize_image(wnd.id, VRESW, 0);
	else
		resize_image(wnd.id, 0, VRESH);
	end
	props = image_surface_properties(wnd.id);
	move_image(wnd.id, math.floor(0.5 * (VRESW - props.width)),
		math.floor(0.5 * (VRESH - props.height)));

	blend_image(wnd.id, 1.0, 5);
	resume_target(wnd.id);
end

function default_cb(source, status)
-- always fit to screen, maintaining aspect
	if (status.kind == "resized") then
		local wnd = vid_to_wnd[source];
		wnd.mirrored = status.mirrored;
		image_shader(source, wnd.mirrored and "normal_mirror" or "normal");

		if (active_window == nil or source == active_window.id) then
			local wnd = vid_to_wnd[source];

			if (status.source_audio) then
				wnd.audio = status.source_audio;
			end
			activate_window(wnd);
		end

	elseif (status.kind == "terminated") then
		local wnd = vid_to_wnd[source];
		image_shader(source, wnd.mirrored and "dead_mirror" or "dead");
	end
end

function popup_config(targetname)
	local cfgs = target_configurations(targetname);
	print("popup ", targetname, #cfgs);

	local lptr = {};
	for i,v in ipairs(cfgs) do
		lptr[v] = function()
			register_window(
				launch_target(targetname, v, LAUNCH_INTERNAL, default_cb)
			);
		end
	end
	set_popup(cfgs, lptr, {});
end

function global_popup()
	local list = {};
	local fptr = {};
	local fmts = {};

	table.insert(list, "List Targets");
	fptr["List Targets"] = function()
		local lst = list_targets();
		local lstptr = {};
		for i,v in ipairs(lst) do
			lstptr[v] = function() popup_config(lst[i]); end
		end
		set_popup(lst, lstptr, {});
	end

	table.insert(list, "Dump State");
	fptr["Dump State"] = function()
		zap_resource("dump.lua");
		system_snapshot("dump.lua");
		warning("saved state to (dump.lua)");
	end

	table.insert(list, "Quit");
	fptr["Quit"] = shutdown;

	for i=1,#windows do
		table.insert(list, windows[i].name);
		fptr[windows[i].name] = function()
			activate_window(windows[i]);
		end;
	end

	set_popup(list, fptr, fmts);
end

function set_popup(list, funptr, fmts)
	popup_destroy();

-- create list and center on screen
	active_popup = listview_create(list, VRESW, VRESW, fmts);
	active_popup:show(5);
	active_popup.animspeed = 0;
	active_popup.items = funptr;
	active_popup.on_click = function(self, ind, rclick)
		if (ind == nil) then
			popup_destroy();
		else
			popup_keyinput("RIGHT", true);
		end
	end
	local props = image_surface_properties(active_popup.border);
	move_image(active_popup.anchor,
		math.floor(0.5 * (VRESW - props.width)),
		math.floor(0.5 * (VRESH - props.height))
	);

-- reposition mouse cursor and show
	mouse_addlistener(active_popup.mhandler, {"click", "rclick", "motion"});
	mouse_show();
end

function target_popup()
	if (active_window == nil) then
		return;
	end

	local list = {"Close Program"};
	local fmtstr = {
		{"\\#ffffff ", " \\#aaaaaa " .. string.format("%s + F4", meta_key)}
	};

	local funptr = {};
	funptr["Close Program"] = destroy_active;

	set_popup(list, funptr, fmtstr);
end

function popup_destroy()
	if (active_popup == nil) then
		return;
	end

	mouse_droplistener(active_popup.mhandler);
	mouse_hide();
	active_popup:destroy();
	active_popup = nil;
end

function popup_keyinput(key, pressed)
	if (pressed == false) then
		return;
	end

	if (key == "ESCAPE" or key == "LEFT") then
		popup_destroy();

	elseif (key == "UP") then
		active_popup:move_cursor(-1, true);

	elseif (key == "DOWN") then
		active_popup:move_cursor( 1, true);

	elseif (key == "RIGHT" or key == "KP_ENTER" or key == "RETURN") then
		local fun = active_popup.items[active_popup:select()];
		popup_destroy();
		if (fun) then
			fun();
		end
	end
end

