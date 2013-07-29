--
-- Monitor script based on the AWB- style window management
--

state = {
	process_sample = false,
	delta_sample = false
};

deffont = "fonts/default.ttf";

kbdbinds = {};

function menulbl(text)
	return render_text(string.format("\\#0055a9\\f%s,%d %s", 
		deffont, 10, text));
end

function desktoplbl(text)
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 10, text));
end

function awbmon()
	system_context_size(65535);
	pop_video_context();

	system_load("scripts/mouse.lua")();
	system_load("scripts/monitor/awbmon/awbwnd.lua")();
	system_load("scripts/monitor/awbmon/awbwman.lua")();
	symtable = system_load("scripts/symtable.lua")();

	cursor       = fill_surface(16, 16, 128, 255, 0);
	mouse_setup(cursor, 255, 1);
	mouse_acceleration(0.5);

	awbwman_init(menulbl, desktoplbl);

	kbdbinds["F11"]  = awbmon_help;
	kbdbinds["CTRL"] = toggle_mouse_grab;
	kbdbinds["ALTF4"] = shutdown;
	kbdbinds["F2"] = function() state.process_sample = true; end
end

function awbmon_help()
	local wnd = awbwman_spawn(menulbl("Help"));
	helpimg = desktoplbl([[Default Monitor Script Helper\n\r\n\r
(global)\n\r
CTRL\t Grab/Release Mouse\n\r
F2\t Wait for new Sample\n\r
ALT+F4\t Shutdown\n\r
F11\t Help Window\n\r\nr\r
(window-input)\n\r
ESC\tDestroy Window\n\r
F1\tGenerate Tree View\n\r
F2\tGenerate Allocation Map\n\r
F3\tSwitch Context Up\n\r
SHIFT+F3\tSwitch Context Down\n\r
F4\tContext Info\n\r
F5\tVideo Subsystem Info\n\r
Up/Down\t Move to Parent/Child\n\r
Left/Right\t Step to Prev/Next Object\n\r
Shift+L/R\t Step to Prev/Next Sibling\n\r
Shift+Enter\t Copy to new Window]]);
	link_image(helpimg, wnd.canvas.vid);
	show_image(helpimg);
	image_clip_on(helpimg, CLIP_SHALLOW);
	image_inherit_order(helpimg, true);
	order_image(helpimg, 1);
end

function context_vid(smpl, contn)
	local ctx = smpl.vcontexts[contn];

-- contexts
	local cimg = desktoplbl(string.format([[
Context:\t%d / %d\n\r
Rtargets:\t%d\n\r
Vobjects:\t%d (%d) / %d\n\r
Last Tick:\t%d\n\r]] , contn, #csample.vcontexts, 
#ctx.rtargets, ctx.alive, ctx.vobjs, ctx.limit, ctx.tickstamp));

	return cimg;
end



function spawn_sample(smpl, context, startid)
				print("spawnsample");
	local wnd = awbwman_spawn(menulbl(tostring(context) .. ":" .. 
		smpl.vcontexts[context].tickstamp));

		
	link_image(vid, wnd.canvas.vid);
	show_image(vid);
	image_clip_on(vid, CLIP_SHALLOW);
	image_inherit_order(vid, true);
	order_image(vid, 1);

	wnd.lastid  = 1;
	wnd.context = context;
	wnd.sample  = smpl;
end

--
-- Whenever we want a new sample, set process_sample to true
-- When parent sends one, it gets rendered to an image and set
-- as the canvas of a new window
--
function sample(smpl)
	if (state.process_sample == false) then
		return;
	end

	if (state.delta_sample) then
	else
		spawn_sample(smpl, 1, 0);
	end

	state.process_sample = false;
end

modtbl = {false, false, false, false};
function update_modifiers(sym, active)
	local ret = "";

	if (sym == "LSHIFT" or sym == "RSHIFT") then
		modtbl[1] = active;
	elseif (sym == "LCTRL" or sym == "RCTRL") then
		modtbl[2] = active;
	elseif (sym == "LALT" or sym == "RALT") then
		modtbl[3] = active;
	elseif (sym == "RMETA" or sym == "LMETA") then
		modftbl[4] = active;
	else
		ret = sym;
	end

	return "" .. (modtbl[1] and "SHIFT" or "") .. (modtbl[2] and "CTRL" or "") ..
		(modtbl[3] and "ALT" or "") .. (modtbl[4] and "META" or ""), ret;
end

minputtbl = {false, false, false};
function awbmon_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0,
			iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);

	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		if (iotbl.subid > 0 and iotbl.subid <= 3) then
			minputtbl[iotbl.subid] = iotbl.active;
			mouse_input(0, 0, minputtbl);
		end
	
	elseif (iotbl.kind == "digital" and iotbl.translated) then
		iotbl.keysym = symtable[iotbl.keysym] and symtable[iotbl.keysym] or "";
		iotbl.prefix, iotbl.keysym = update_modifiers(iotbl.keysym, iotbl.active);

		if (iotbl.active and kbdbinds[ iotbl.prefix .. iotbl.keysym ]) then
			kbdbinds[ iotbl.prefix .. iotbl.keysym ]();
		else
			awbwman_input(iotbl);
		end
	end
end
