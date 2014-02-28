--
-- Arcan "Workbench" theme
-- "inspired" by certain older desktop / windowing UIs
--

sysicons   = {};

-- the imagery pool is used as a data cache,
-- since the windowing subsystem need link_ calls to work
-- we can't use instancing, so instead we allocate a pool
-- and then share_storage
imagery    = {};
colortable = {};

groupicn    = "awbicons/drawer.png";
groupselicn = "awbicons/drawer_open.png";
deffont     = "fonts/topaz8.ttf";
deffont_sz  = 10;
linespace   = 4;

ORDER_MOUSE     = 255;

kbdbinds = {};

function menulbl(text)
return render_text(string.format("\\#0055a9\\f%s,%d %s", 
deffont, deffont_sz, text));
end

function desktoplbl(text, len)
	if (type(text) ~= "string") then
		print(debug.traceback());
	end

	if (len and len > 0) then
		text = string.sub(text, 1, string.utf8forward(text, len)); 
		print(text);
	end

	text = text == nil and "" or text;
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
	deffont, deffont_sz, text), linespace);
end

-- input is trusted, i.e. data supposedly comes from
-- the "add shortcut" etc. parts and has not been modified
-- by the user
function iconlbl(text)
	local ofs     = 0;
	local sz      = 10;
	local rowc    = 1;
	local newofs  = 1;
	local cc      = 0;
	local workstr = {}; 

	while newofs ~= ofs do
		ofs = newofs;
		cc = cc + 1;
		newofs = string.utf8forward(text, ofs);
		table.insert(workstr, string.sub(text, ofs, ofs));
		if (cc > 10) then
			rowc = rowc - 1;
			if (rowc < 0) then
				sz = 8;
				table.insert(workstr, "...");
				break;
			else
				table.insert(workstr, "\\n\\r");
				cc = 0;
			end
		end
	end

	return render_text(
		string.format("\\#ffffff\\f%s,%d %s", deffont, 
			sz, table.concat(workstr, "")));
end

function inputlbl(text)
	text = text == nil and "" or text;
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 12, text));
end
		
debug_global = {};

local function shortcut_str(caption, state)
	return string.format(
		"local res = {};\nres.name=[[%s]];\n" ..
		"res.caption=[[%s]];\nres.icon=[[%s]];\n" ..
		"res.factorystr = [[%s]];\n" .. 
		"%s\n" .. 
		"\nreturn res;", state.name,
		caption, state.icon and state.icon or "default", 
		state.factorystr ~= nil and state.factorystr or state.factory,
		state.shortcut_trig ~= nil and state.shortcut_trig() or "");
end

function shortcut_popup(icn, tbl, name)
	local popup_opts = [[Rename...\n\rDrop Shortcut]];
	local vid, list  = desktoplbl(popup_opts);

	local popup_fun = {
		function()
			local state = system_load("shortcuts/" .. name)();
			local buttontbl = {
				{ caption = desktoplbl("OK"), trigger = 
				function(own)
					if (icn.set_caption == nil) then
						return;
					end
					zap_resource("shortcuts/" .. name);
						open_rawresource("shortcuts/" .. name);
						write_rawresource(shortcut_str(own.inputfield.msg, state));
					close_rawresource();
				end
				},
				{ caption = desktoplbl("Cancel"), trigger = function(own) end }
				};

				local dlg = awbwman_dialog(desktoplbl("Rename To:"), buttontbl, {
					input = { w = 100, h = 20, limit = 32, accept = 1, cancel = 2 }
					}, false);
				end,
		function() 
			zap_resource("shortcuts/" .. name);
			icn:destroy();
		end
	};

	awbwman_popup(vid, list, popup_fun);
end

function load_aux()
	system_load("awb_iconcache.lua")();

	system_load("awbwnd.lua")();
	system_load("awbwnd_icon.lua")();
	system_load("awbwnd_list.lua")();
	system_load("awbwnd_media.lua")();
	system_load("awbwnd_music.lua")();
	system_load("awbwnd_modelview.lua")();
	system_load("awbwnd_target.lua")();
	
	system_load("awbwman.lua")();

	system_load("awb_browser.lua")();
	system_load("tools/inputconf.lua")();
	system_load("tools/vidrec.lua")();
 	system_load("tools/vidcmp.lua")();
 	system_load("tools/hghtmap.lua")();
	system_load("tools/socsrv.lua")();
end

function awb()
	MESSAGE = system_load("language/default.lua")();

-- maintain a list of global symbols
-- from the launch, on a keypress, dump
-- anything that has been added / changed
-- to track down namespace pollution
	if (DEBUGLEVEL > 1) then
		for k,v in pairs(_G) do
			debug_global[k] = true;
		end
	end

	symtable = system_load("scripts/symtable.lua")();

	system_load("awb_support.lua")();
	system_load("scripts/calltrace.lua")();
	system_load("scripts/3dsupport.lua")();
	setup_3dsupport(true);

	system_load("scripts/resourcefinder.lua")();

-- mouse abstraction layer 
-- (callbacks for click handlers, motion events etc.)
-- 
-- look in resources/scripts/mouse.lua
-- for heaps more options (gestures, trails, autohide) 
--
	system_load("scripts/mouse.lua")();
	local cursor = load_image("awbicons/mouse.png", ORDER_MOUSE);
	image_tracetag(cursor, "mouse cursor");
	mouse_setup(cursor, ORDER_MOUSE, 1, true);
		
	load_aux(); -- support classes (awbwnd etc.)
	awbwman_init(desktoplbl, menulbl);	

	awb_desktop_setup();

-- check that there are things that can be launched, else
-- we probably have an incomplete installation / setup
	local gametbl = list_games( {} );
	if (gametbl == nil or #gametbl == 0) then
		show_gamewarning();
	end

-- first time launching, show help window
	if (get_key("help_shown") == nil) then
		show_help();
	end

	map_inputs();

	local img = load_image("background.png");
	if (valid_vid(img)) then
		image_sharestorage( img, awbwman_cfg().root.canvas.vid );
		delete_image(img);	
	end

	awbwman_toggle_mousegrab();
end

function dumpvid()
	local px, ly = mouse_xy();
	local res = pick_items(px, ly, 1, 1);
	if (res[1] ~= nil) then
		local props = image_surface_properties(res[1]);
		local tag = image_tracetag(res[1]);
		print(string.format("(%d) tag: %s, pos: %f, %f, dimensions: %f, %f",
			res[1], tag ~= nil and tag or "no name", props.x, 
			props.y, props.width, props.height));
	end
end

function map_inputs()
	if (DEBUGLEVEL > 1) then
		kbdbinds["F3"]     = function() 
			zap_resource("syssnap.lua"); 
			system_snapshot("syssnap.lua"); 
		end

		kbdbinds["F5"]     = function() print(current_context_usage()); end;
		kbdbinds["F6"]     = debug.debug;
		kbdbinds["F10"]    = mouse_dumphandlers;
		kbdbinds["F4"]     = function()
			local newglob = {};

			print("[dump globals]");
			for k,v in pairs(_G) do
				if (debug_global[k] == nil) then
					print(k, v);
				end
				newglob[k] = true;
			end

			debug_global = newglob;
			print("[/dump globals]");
		end;
		kbdbinds["F9"]     = function() 
			if (global_tracing ~= true) then
				Trace();
				global_tracing = true;
			else
				global_tracing = false;
				Untrace();	
			end
		end
	end

	kbdbinds["LCTRL"]  = awbwman_toggle_mousegrab;
	kbdbinds["ESCAPE"] = awbwman_cancel;
	kbdbinds["F11"] = awbwman_gather_scatter;
	kbdbinds["F12"]	= awbwman_shadow_nonfocus;
	kbdbinds["F7"] = dumpvid;
end

--
-- Setup a frameserver session with an interactive target
-- as a new window, start with a "launching" canvas and 
-- on activation, switch to the real one.
--
function gamelist_launch(self, factstr, coreargs)
	local game = self.tag;
	if (game == nil) then
		return;
	end

	targetwnd_setup(game, factstr, coreargs);
end

function launch_factorytgt(tbl, factstr, coreopts)
	local lines  = string.split(factstr, "\n");
	local idline = lines[1];
	local idval  = tonumber(string.split(idline, "=")[2]);

	local tbl = { tag = game_info(idval) };
	if (tbl ~= nil) then
		local wnd = gamelist_launch(tbl, factstr, coreopts);
	else
		warning("broken gameid / lnk, check database reference.");
	end
end

local function search_popup(reficn)
	local placeholdr = desktoplbl("AAAAAAAAAAAAAAAA");
	local wnd = awbwman_popup(placeholdr, deffont_sz - 4, 
		function() end, {ref = reficn.vid}); 

	if (wnd == nil) then
		return;
	end

	hide_image(wnd.cursor);
	mouse_droplistener(wnd);
	delete_image(placeholdr);

	local cw = image_surface_properties(wnd.cursor).width;

	local wndopt = {
		owner = wnd.border.anchor,
		w = cw
	};

	wnd.inputfield = awbwman_inputattach(
		function(a) end, desktoplbl, wndopt);

	wnd.inputfield:resize(cw, deffont_sz);

	wnd.input = 
	function(self, tbl)
		wnd.inputfield:input(tbl); 
	end

	wnd.inputfield.accept = function(self)
		local list = list_games({title = wnd.inputfield.msg});
		if (list ~= nil and #list > 0) then
			gamelist_tblwnd(list, wnd.inputfield.msg);
		else
			wnd:destroy();
		end
	end

end

function spawn_vidwin(self)
	local wnd = awbwman_capwnd(menulbl("Video Capture"), 
		{refid = "vidcapwnd"});
end

function show_gamewarning()
	local wnd = awbwman_spawn(menulbl("Notice"), {noresize = true});
	if (wnd == nil) then
		return;
	end

	wnd:focus();

	local helpimg = desktoplbl(MESSAGE["WARNING_NOGAMES"]);
	link_image(helpimg, wnd.canvas.vid);
	show_image(helpimg);
	image_clip_on(helpimg, CLIP_SHALLOW);
	image_mask_set(helpimg, MASK_UNPICKABLE);
	image_inherit_order(helpimg, true);
	order_image(helpimg, 1);
	local props =	image_surface_properties(helpimg);
	move_image(helpimg, 10, 10);
	wnd:resize(props.width + 20, props.height + 20, true);
	
	wnd.lasthelp = helpimg;
end

function show_help()
	local wnd = awbwman_gethelper();
	local focusmsg = MESSAGE["HELP_GLOBAL"];
	local focus = awbwman_cfg().focus;

	if (focus ~= nil and type(focus.helpmsg) == "string" and
		string.len(focus.helpmsg) > 0) then
		focusmsg = focus.helpmsg;
	end

	if (wnd ~= nil) then
		wnd:focus();
		wnd.name = "Help Window";
		wnd:helpmsg(focusmsg);
		return;
	end

	local wnd = awbwman_spawn(menulbl("Help"), {noresize = true});
	if (wnd == nil) then
		return;
	end

	awbwman_sethelper( wnd );

	wnd.helpmsg = function(self, msg)
		if (wnd.lasthelp) then
			delete_image(wnd.lasthelp);
		end

		local helpimg = desktoplbl(msg);
		if (not valid_vid(helpimg)) then
			return;
		end
		link_image(helpimg, wnd.canvas.vid);
		show_image(helpimg);
		image_clip_on(helpimg, CLIP_SHALLOW);
		image_mask_set(helpimg, MASK_UNPICKABLE);
		image_inherit_order(helpimg, true);
		order_image(helpimg, 1);
		local props =	image_surface_properties(helpimg);
		move_image(helpimg, 10, 10);
		wnd:resize(props.width + 20, props.height + 20, true);
	
		wnd.lasthelp = helpimg;
	end

	wnd:helpmsg(focusmsg);

	local mh = {
		own = function(self, vid) return vid == wnd.canvas.vid; end,
		click = function() wnd:focus(); end
	};

	mouse_addlistener(mh, {"click"});
	table.insert(wnd.handlers, mh);

	wnd.on_destroy = function() 
		store_key("help_shown", "yes");
		awbwman_sethelper ( nil );
	end
end

function sortopts_popup(ent, wnd)
	local sortfun = function() end
	local resort = function()
		table.sort(wnd.data, sortfun); 
		wnd:force_update();
	end

	local popup_opts = [[Title(Asc)\n\rTitle(Desc)\n\rGenre(Asc)\n\rGenre(Desc)\n\r]];
	local popup_fun = {
		function() sortfun = function(a, b) 
			return string.lower(a.title) < string.lower(b.title);
		end resort(); end,

		function() sortfun = function(a, b) 
			return string.lower(a.title) > string.lower(b.title);
		end resort(); end,

		function() sortfun = function(a, b) 
			return string.lower(a.genre) < string.lower(b.genre);
		end resort(); end,

		function() sortfun = function(a, b) 
			return string.lower(a.genre) > string.lower(b.genre);
		end resort(); end
	};

	local vid, lines = desktoplbl(popup_opts);
	awbwman_popup(vid, lines, popup_fun);
end

function gamelist_popup(ent, wnd)
	local popup_opts = [[Launch\n\rFind Media\n\rList Siblings\n\rSort...]];
	local vid, list  = desktoplbl(popup_opts);
	local popup_fun = {
		function() gamelist_launch(ent);     end,
		function() awbbrowse_gamedata(ent.tag);  end,
		function() 
			local tbl = game_family(ent.gameid);

			if (#tbl > 0) then
				local restbl = {};

				for i,j in ipairs(tbl) do
					local gtbl = game_info(j);
					if (gtbl ~= nil and gtbl[1] ~= nil) then
						table.insert(restbl, gtbl[1]);
					end
				end

				if (#restbl > 0) then
					gamelist_tblwnd(restbl, "Family: " .. ent.name);
				end
			end
		end,
		function()
			sortopts_popup(ent, wnd);
		end
	};

	awbwman_popup(vid, list, popup_fun);
end

function gamelist_tblwnd(tbl, capt)
	if (tbl == nil or #tbl == 0) then
		return;
	end

	local ltf = function(self) gamelist_launch(self); end;

	local wnd = awbwman_listwnd(menulbl(capt), deffont_sz, linespace,
		{0.7, 0.3}, function(filter, ofs, lim, iconw, iconh)
			local ul = ofs + lim;
			local res = {};

			ul = (ul > #tbl) and #tbl or ul;

			for i=ofs,ul do
				if (tbl[i] ~= nil) then
				local ent = {
					name = tbl[i].title,
					gameid = tbl[i].gameid,
					target = tbl[i].target,
					tag = tbl[i],
					rtrigger = gamelist_popup,
					trigger = ltf, 
					cols = {tbl[i].title, (tbl[i].genre ~= nil and 
						string.len(tbl[i].genre) > 0) and tbl[i].genre or "(none)"}
				};

				table.insert(res, ent);
				end
			end

			return res, #tbl;
		end, desktoplbl, {});

	if (wnd ~= nil) then
		wnd.name = "List(" .. capt .. ")";
		wnd.data = tbl;
	end
end

last_bgwin = nil;
local function background_tagh(funptr, wnd, srcvid)

-- set as new background	
	image_sharestorage(srcvid, awbwman_cfg().root.canvas.vid);
	background_dirty = true; -- save upon closing
end

local function register_bghandler(wnd)
	if (last_bgwin == wnd) then
		return;
	end

-- de-register from last window that updated
	if (last_bgwin ~= nil) then
		last_bgwin:drop_handler("on_update", background_tagh);
	end

-- add to updatehandler for new window
	wnd:add_handler("on_update", background_tagh);
end

function gamelist_wnd(selection)
	local tgtname = selection.name;
	local tgttotal = list_games({target = tgtname});
	gamelist_tblwnd(tgttotal, tgtname);
end

function rootdnd(ctag)
	local lbls = {};
	local ftbl = {};

--
-- If we can use a string- reference as allocation function
-- (this needs to be stored on the database, read on desktup setup
-- and use the construction string to rebuild on activation)
--
	if (ctag.conststr) then
		table.insert(lbls, "Shortcut");
		table.insert(ftbl, function() end);
	end

	if (ctag.source and ctag.source.canvas 
		and valid_vid(ctag.source.canvas.vid)) then
		table.insert(lbls, "Background");
		table.insert(ftbl, 
			function()
				image_sharestorage(ctag.source.canvas.vid, 
					awbwman_cfg().root.canvas.vid);
				background_dirty = true; -- save upon closing
				register_bghandler(ctag.source);
			end);
	end

	if (ctag.factory) then
		table.insert(lbls, "Add Shortcut");

		table.insert(ftbl, function()
			local ind  = 1;
			local base = string.match(ctag.caption, "[%a %d_-]+");
			local line = "shortcuts/" .. base .. ".lnk";

			while (resource(line)) do
				line = string.format("shortcuts/%s_%d.lnk", base, ind);
				ind = ind + 1;
			end

			while (awbwman_rootgeticon(base .. tostring(ind))) do
				ind = ind + 1;
			end

			if (open_rawresource(line)) then
				write_rawresource(shortcut_str(base .. tostring(ind), ctag));
				close_rawresource();
			end

			local tbl = system_load(line)();
				if (tbl ~= nil and tbl.factorystr and tbl.name and tbl.caption) then
					local icn, w, h = get_root_icon(tbl.icon);

					local icn = awbwman_rootaddicon(tbl.name, iconlbl(tbl.caption),
						icn, icn, function() launch_factorytgt(tbl, tbl.factorystr); end, 
						function(self) shortcut_popup(self, tbl, base .. ".lnk");	end,
						{w = w, h = h, helper = tbl.caption});
					local mx, my = mouse_xy();
					icn.x = math.floor(mx);
					icn.y = math.floor(my);
					move_image(icn.anchor, icn.x, icn.y);
				end
			end);
	end

	if (#lbls > 0) then
		local vid, lines = desktoplbl(table.concat(lbls, "\\n\\r"));
		awbwman_popup(vid, lines, ftbl);
	end
end

local function amediahandler(path, base, ext)
	local name = path .. "/" .. base .. "." .. ext;
	local awbwnd = awbwnd_globalmedia();

	if (awbwnd == nil) then
		awbwnd = awbwman_aplayer(menulbl("Music Player"));
	end

	awbwnd:add_playitem(base, name);

-- animate where the playlist item is actually going
	local aspeed = awbwman_cfg().animspeed;
	local lbl = desktoplbl(string.gsub(
		string.sub(base, 1, 8), "\\", "\\\\"));
	show_image(lbl);
	local x, y = mouse_xy();
	move_image(lbl, x, y);

	if (awbwnd.minimized == true) then
		blend_image(lbl, 1.0, aspeed * 2);
		move_image(lbl, 40, 0, aspeed);
		move_image(lbl, 40, 0, aspeed);
		blend_image(lbl, 0.0, aspeed);
	else
		local prop = image_surface_properties(lbl);
		local dstx = -1 * 0.5 * prop.width;
		local dstw = awbwnd.playlistwnd ~= nil and awbwnd.playlistwnd or awbwnd;

		prop = image_surface_properties(dstw.canvas.vid);
		dstx = dstx + prop.width * 0.5; 

		link_image(lbl, dstw.canvas.vid);
		image_inherit_order(lbl, true);
		move_image(lbl, prop.x - x, prop.y - y);
		blend_image(lbl, 1.0, aspeed * 2);
		move_image(lbl, dstx, prop.height * 0.5, aspeed); 
		move_image(lbl, dstx, prop.height * 0.5, aspeed);
		blend_image(lbl, 0.0, aspeed);		
	end

	expire_image(lbl, aspeed * 3); 
end

local function vmediahandler(path, base, ext)
	local name = path .. "/" .. base .. "." .. ext;
	local wnd, tfun = awbwman_mediawnd(menulbl("Media Player"));
	load_movie(name, FRAMESERVER_NOLOOP, tfun);
	wnd.name = base; 
end

local function imghandler(path, base, ext)
	local wnd, tfun = awbwman_imagewnd(menulbl(base), nil);
	local name = path .. "/" .. base .. "." .. ext;
	load_image_asynch(name, tfun);
end

local exthandler = {
	MP3 = amediahandler,
	OGG = amediahandler,
	MKV = vmediahandler,
	MOV = vmediahandler,
	MP4 = vmediahandler,
	AVI = vmediahandler,
	MPG = vmediahandler,
	MPEG= vmediahandler,
	JPG = imghandler,
	PNG = imghandler 
};

local function wnd_3dmodels()
	local list = {};
	local res = glob_resource("models/*");

	local mtrig = 
	function(a, b)
		local model = setup_cabinet_model(
			a.name, {}, {});
		if (model and model.vid) then
			move3d_model(model.vid, 0.0, -0.2, -2.0);
			awbwman_modelwnd(menulbl(a.name), model);
		end
	end

	for k,l in ipairs(res) do
		local ent = {};
		ent.trigger = mtrig;
		ent.name = tostring(l);
		ent.cols = {tostring(l)};

		table.insert(list, ent);
	end

	if (#list == 0) then
		return;
	end

	local wnd = awbwman_listwnd(menulbl("3D Models"), deffont_sz, 
		linespace, {1.0}, list, desktoplbl);

	wnd.name = "3D Models";
end

local function wnd_media(path)
	local list = {};
	local res = glob_resource(path .. "/*");

	for k,l in ipairs(res) do
		table.insert(list, l);
	end

	if (#list == 0) then
		return;
	end

	table.sort(list, function(a, b)
		local ab, ax = string.extension(a);
		local bb, bx = string.extension(b);
	end);
	
	local wnd = awbwman_listwnd(menulbl("MediaBrowser"), 
		deffont_sz, linespace, {1.0},
		function(filter, ofs, lim)
			local res = {};
			local ul = ofs + lim - 1;
	
			for i=ofs, ul do
				local ment = {
					resource = list[i],
					trigger  = function()
						local base, ext = string.extension(list[i]);
						local handler = exthandler[ 
							string.upper(ext ~= nil and ext or "") ];
	
						if (handler) then
							handler(path, base, ext);
						else
							wnd_media(path .. "/" .. list[i]); 
						end
					end,
					name = "mediaent",
					cols = {list[i]}
				};
-- FIXME: prefix icon based on extension, use that to set icon
				table.insert(res, ment);
			end
			return res, #list;
		end, desktoplbl);
	wnd.name = "Media Browser";
end

function awb_desktop_setup()
	sysicons.group        = load_image("awbicons/drawer.png");
	sysicons.group_active = load_image("awbicons/drawer_open.png");
	sysicons.boing        = load_image("awbicons/boing.png");
	sysicons.floppy       = load_image("awbicons/floppy.png");
	sysicons.shell        = load_image("awbicons/shell.png");

	sysicons.lru_cache    = awb_iconcache(64, 
		{"images/icons", "icons", "images/systems", "awbicons"}, sysicons.floppy);

	local groups = {
		{
			name    = MESSAGE["GROUP_TOOLS"],
			key     = "tools",
			trigger = function()
			local wnd = awbwman_iconwnd(menulbl(MESSAGE["GROUP_TOOLS"]), 
				builtin_group, {refid = "iconwnd_tools"});
				wnd.name = "List(Tools)";
			end
		},
		{
			name    = MESSAGE["GROUP_SYSTEMS"],
			key     = "systems",
			trigger = function()
				local tbl =	awbwman_iconwnd(menulbl(MESSAGE["GROUP_SYSTEMS"]), 
					system_group, {refid = "iconwnd_systems"});
				tbl.idfun = list_targets;
				tbl.name = "List(Systems)";
			end
		},
		{
			name = MESSAGE["GROUP_MODELS"],
			key = "models",
			trigger = wnd_3dmodels
		},
		{
			name = MESSAGE["GROUP_MUSIC"],
			key  = "music",
			trigger = function() 
				wnd_media("music");
			end
		},
		{
			name = MESSAGE["GROUP_RECORDINGS"],
			key = "recordings",
			trigger = function()
				wnd_media("recordings");
			end
		},
		{
			name = MESSAGE["GROUP_VIDEOS"], 
			key = "videos",
			trigger = function()
				wnd_media("movies");
			end
		},
	};

	for i,j in pairs(groups) do
		local lbl = desktoplbl(j.name);
		awbwman_rootaddicon(j.key, lbl, sysicons.group, 
			sysicons.group_active, j.trigger, j.rtrigger);
	end

	local cfg = awbwman_cfg();
	cfg.on_rootdnd = rootdnd;

	local rtbl = glob_resource("shortcuts/*.lnk");
	if (rtbl) then
		for k,v in ipairs(rtbl) do
			local tbl = system_load("shortcuts/" .. v)();
			if (tbl ~= nil and 
				tbl.factorystr and tbl.name and tbl.caption) then
				local icn, desw, desh = get_root_icon(tbl.icon);
	
				awbwman_rootaddicon(tbl.name, iconlbl(tbl.caption),
				icn, icn, function()
					launch_factorytgt(tbl, tbl.factorystr, tbl.coreopts); end, 
					function(self) shortcut_popup(self, tbl, v); end,
				{w = desw, h = desh, helper = tbl.caption}); 
			end
		end
	end

	local tbar = awbwman_cfg().root.dir.t;
	tbar:add_icon("search", "r", cfg.bordericns["search"],
		function(self) search_popup(self); end);
end

function get_root_icon(hint)
	local icn = sysicons.lru_cache:get(hint).icon;
	local props = image_surface_properties(icn);
	local desw = 48; local desh = 48;
	if (props.width < 48 and props.height < 48) then
		desw = nil;
		desh = nil;
	end
	return icn, desw, desh;
end

function builtin_group(self, ofs, lim, desw, desh)
	local tools = {
 		{"BOING!",    spawn_boing, "boing"   },
		{"InputConf", awb_inputed, "inputed" },
		{"Recorder",  spawn_vidrec, "vidrec" },
		{"Compare",   spawn_vidcmp, "vidcmp" },
		{"Network",   spawn_socsrv, "network"},
		{"VidCap",    spawn_vidwin, "vidcap" },
		{"HeightMap", spawn_hmap, "hghtmap"  }
	};

 	local restbl = {};

	lim = lim + ofs;
	while ofs <= lim and ofs <= #tools do
 		local newtbl = {};
   	newtbl.caption = desktoplbl(tools[ofs][1]);
   	newtbl.trigger = tools[ofs][2];
   	newtbl.name = tools[ofs][3];
   	newtbl.icon = sysicons.lru_cache:get(newtbl.name).icon;
   	table.insert(restbl, newtbl);
   	ofs = ofs + 1;
  end

	return restbl, #tools;
end

function system_group(self, ofs, lim, desw, desh)
	local targets = list_targets();
	local restbl = {};

	lim = lim + ofs;
	while ofs <= lim and ofs <= #targets do
		local newtbl = {};
		newtbl.caption = desktoplbl(targets[ofs]);
		newtbl.trigger = gamelist_wnd;
		newtbl.name    = targets[ofs];
		newtbl.icon    = sysicons.lru_cache:get(newtbl.name).icon;
		table.insert(restbl, newtbl);
		ofs = ofs + 1;
	end
	
	return restbl, #targets;
end

--
-- A little hommage to the original, shader is from rendertoy
--
function spawn_boing(caption)
	local int oval = math.random(1,100);
	local a = awbwman_spawn(menulbl("Boing!"));
	if (a == nil) then
		return;
	end

	a.name = "Boing!"; 
	a.kind = sysicons.boing; 

	local boing = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/boing.fShader", "boing" .. oval, {});
		
	local props = image_surface_properties(a.canvas.vid);
		a.canvas.resize = function(self, neww, newh)
		shader_uniform(boing, "display", "ff", PERSIST, neww, newh); 
		shader_uniform(boing, "offset", "i", PERSIST, oval);
		resize_image(self.vid, neww, newh);
	end

	image_shader(a.canvas.vid, boing);
	a.canvas:resize(props.width, props.height);

	return a;
end

minputtbl = {false, false, false};
function awb_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		if (awbwman_minput(iotbl)) then
			mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0, 
				iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);
		end

	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		if (iotbl.subid > 0 and iotbl.subid <= 3) then

-- meta converts LMB to RMB
--			if (iotbl.subid == 1 and awbwman_cfg().meta.shift) then
--				iotbl.subid = 3;
--			end

			minputtbl[iotbl.subid] = iotbl.active;
			if (awbwman_minput(iotbl)) then
				mouse_input(0, 0, minputtbl);
			end
		end

	elseif (iotbl.kind == "digital") then
		iotbl.lutsym = symtable[iotbl.keysym];
		if (iotbl.lutsym == nil) then
			iotbl.lutsym = "UNKNOWN";
		end

		local kbdbindbase = awbwman_meta() .. iotbl.lutsym;
		local forward = true;

		if (iotbl.lutsym == "LSHIFT" or iotbl.lutsym == "RSHIFT") then 
			awbwman_meta("shift", iotbl.active);
		end

		if (iotbl.lutsym == "LALT" or iotbl.lutsym == "RALT") then
			awbwman_meta("alt", iotbl.active);
		end

		if (iotbl.active and kbdbinds[ kbdbindbase ]) then
			forward = kbdbinds[ kbdbindbase ]() == nil;
		end
	
		if (forward) then
			awbwman_input(iotbl, kbdbindbase);
		end

	elseif (iotbl.kind == "analog") then
			awbwman_ainput(iotbl);
	end
end

function awb_shutdown()
	if (background_dirty) then
		zap_resource("background.png");
		save_screenshot("background.png", 0,
			awbwman_cfg().root.canvas.vid);
	end
end
