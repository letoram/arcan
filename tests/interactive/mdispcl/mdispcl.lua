--
-- This scripts tests multiple display outputs
-- both in dry- run simulations (when run through arcan LWA)
-- and for real multi-display platforms.
--
-- [ by default, the mode is F11 ]
--
-- 1..8 = random size segment (if display) support dynamic modes,
--        otherwise, select a random preconfigured mode.
--
-- q = map world to all (shared)
-- a = map world to all (shared) through rendertargets
-- w = map world to all displays
-- e = world to first, disp_2 to 2, disp_3 to 3
--
-- z = delete the intermediate disp_2,3 (will likely terminate script)
--
function mdispcl()
	symtable = system_load("builtin/keyboard.lua")();
	bg = load_image("images/icons/arcanicon.png");
	disp_img = {
		load_image("images/icons/ok.png"),
		load_image("images/icons/remove.png")
	}

	resize_image(bg, VRESW, VRESH);
	show_image({bg});
end

active_displays = {};

dispatch = {};

dispatch["q"] = function()
	print("fair split, texco");
	step_s = 1.0 / #active_displays;
end

dispatch["a"] = function()
	print("fair split, rendertarget");
end

dispatch["w"] = function()
	print("all world");
	map_video_display(WORLDID, 0);

	for i=0,#active_displays do
		map_video_display(WORLDID, i);
	end
end

dispatch["e"] = function()
	print("unique");
	map_video_display(WORLDID, 0);
	local count = 1;

	for k,v in ipairs(active_displays) do
		map_video_display(disp_img[count], v);
		count = (count + 1 > #disp_img) and 1 or (count + 1);
	end
end

--
-- Event callback for display configuration hotplug
--
function mdispcl_display_state(state, displayid)
	if (state == "added") then
		table.insert(active_displays, displayid);
		map_video_display(WORLDID, displayid);

	elseif (state == "removed") then

		for k,v in ipairs(active_displays) do
			if (v == displayid) then
				table.remove(active_displays, k);
				break;
			end
		end

	end
end

function mdispcl_input(iotbl)
	local label = symtable.tolabel(iotbl.keysym)
	if (iotbl.translated and iotbl.active and
		dispatch[label]) then
		dispatch[label]();
	end
end
