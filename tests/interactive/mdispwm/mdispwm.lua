--
-- This interactive script is to test the compositioning
-- surface support script, but also arcan_lwa multiple
-- windows.
--
-- Right-clicking a connected window surface will push a
-- a subsegment that the underlying _lwa platform will
-- treat as a newly connected display.
--
-- pressing LCTRL + DELETE will delete a window.
--
-- Later, this interactive test will be cleaned up and
-- used as an example for a minimalistic "classic" style
-- window manager.
--

connection_path = "mdispwm";
meta_key = "LCTRL";

function mdispwm()
	system_load("scripts/composition_surface.lua")();
	system_load("builtin/mouse.lua")();
	symtable = system_load("builtin/keyboard.lua")();

-- ugly red square as mouse cursor
	cursimg = fill_surface(16, 16, 255, 0, 0, 16, 16);
	mouse_setup_native(cursimg, {});

	wm = compsurf_create(VRESW, VRESH, {});
	table.insert(wm.handlers.select, focus_window);
	table.insert(wm.handlers.deselect, defocus_window);
	table.insert(wm.handlers.destroy, destroy_window);

-- all mouse input will be treated as drag/resize etc.
	target_alloc(connection_path, new_connection);
end

function defocus_window(wnd)
	blend_image(wnd.canvas, 0.5);
end

function focus_window(wnd)
	blend_image(wnd.canvas, 1.0);
end

--
-- a new connection has been initiated, add it to
-- running composition surface
--
local fsrv_lut = {};
function register_window(source)
	local wnd = wm:add_window(source, {});
	wnd:set_border(1);
	wnd.input = function(wnd, tbl)
		target_input(wnd.canvas, tbl);
	end
	wnd.dblclick = add_subwindow;
	fsrv_lut[source] = wnd;
	print("registered:", source);
end

function add_subwindow(pwnd)
	local vid = target_alloc(pwnd.canvas, default_wh);
	show_image(vid);
	local wnd = wm:add_window(vid, {
		parent = pwnd -- flag means that this window will disappear if parent does
	});

-- highlight that this is different from the normal windows
	wnd:set_border(1, {0, 255, 0, 255});

-- map the input to the parent instead (this is really)
	wnd.input = function(wnd, tbl)
		target_input(pwnd.canvas, tbl);
	end

	fsrv_lut[vid] = wnd;

	zap_resource("dump.state");
	system_snapshot("dump.state");
end

function destroy_window(source)
	if (fsrv_lut[ source.canvas ]) then
		fsrv_lut[source.canvas] = nil;
	end
end

function default_wh(source, status)
	if (status.kind == "resized") then
		print("resource on:", source, status.width, status.height);
		fsrv_lut[source]:resize(status.width, status.height);
	else
		print("unhandled event:", status.kind);
	end
end

function new_connection(source, status)
	local vid,aid = target_alloc(connection_path, new_connection);
	show_image(vid);

	register_window(source);
	target_updatehandler(source, default_wh);
	default_wh(source, status);
end

function mdispwm_clock_pulse()
	mouse_tick(1);
end

mid_c = 0;
mid_v = {0, 0};
function mdispwm_input(iotbl)
	if (iotbl.source == "mouse") then
		if (iotbl.kind == "digital") then
			mouse_button_input(iotbl.subid, iotbl.active);
		else
			mid_v[iotbl.subid+1] = iotbl.samples[1];
			mid_c = mid_c + 1;

			if (mid_c == 2) then
				mouse_absinput(mid_v[1], mid_v[2]);
				mid_c = 0;
			end
		end

	elseif (iotbl.translated) then
		local label = symtable.tolabel(iotbl.keysym)
-- propagate meta-key state (for resize / drag / etc.)
		if (label == meta_key) then
			wm.meta = iotbl.active and true or nil;

-- spawn a random color surface for testing
		elseif (label == "F11" and iotbl.active) then
			surf = color_surface(128, 128, math.random(128)+127,
				math.random(128)+127, math.random(128)+127);

			local wnd = wm:add_window(surf, {});
			wnd:set_border(1);

-- delete the selected window
		elseif (label == "DELETE" and
			wm.meta == true and wm.selected and iotbl.active) then

			wm.selected:destroy();

		elseif (wm.selected) then
			wm.selected:input(iotbl);
		end
	end
end
