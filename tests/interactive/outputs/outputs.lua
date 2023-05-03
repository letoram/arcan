--
-- Test all the nasty drawing / mapping options
--
-- 1. image drawn to WORLDID, direct composition
-- 2. image drawn to WORLDID, rendertarget indirection
-- 3. image mapped as display
-- 4. image drawn to rendertarget, mapped to display
-- 5. image drawn to rendertarget via WORLDID
-- [6, not yet] display coordinate system changed (for direct composition multiple displays)
--

local function mode_1(set)
	delete_image(WORLDID);
	print("mode1, no worldid");
end

local function mode_2(set)
	print("mode2, rebuild worldid");
	resize_video_canvas(VRESW, VRESH);
	map_video_display(WORLDID, 0, HINT_YFLIP);
end

local function mode_3(set)
	if (set) then
		print("set mode_3");
		map_video_display(img, 0);
	else
		print("map WORLD");
		map_video_display(WORLDID, 0, HINT_YFLIP);
	end
end

local function mode_4(set)
	if (set) then
		print("set mode_4");
		RTARGET = alloc_surface(VRESW, VRESH);
		define_rendertarget(RTARGET, {img});
		show_image(RTARGET);
	else
		print("drop_mode4");
	end
end

local function mode_5(set)
	if (set) then
		print("set mode_5");
		map_video_display(RTARGET, 0);
	else
		print("drop_mode5");
		rendertarget_attach(WORLDID, img, RENDERTARGET_DETACH);
		delete_image(RTARGET);
		map_video_display(WORLDID, 0);
	end
end

local mode_ind = 1;
local modes = {mode_1, mode_2, mode_3, mode_4, mode_5};

function outputs()
	img = load_image("images/icons/arcanicon.png");
	resize_image(img, 64, 64);
	show_image(img);
	symtable = system_load("builtin/keyboard.lua")();
	modes[mode_ind](true);
end

function outputs_input(iotbl)
	local sym = symtable.tolabel(iotbl.keysym);
	if (iotbl.active and sym and sym == " ") then
		modes[mode_ind](false);
		mode_ind = mode_ind + 1;
		mode_ind = mode_ind > #modes and 1 or mode_ind;
		modes[mode_ind](true);
	end
end
