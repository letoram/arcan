--
-- Arcan "Workbench" theme
-- "inspired" by certain older desktop / windowing UI
--
-- Todo:
--  ( ) refactor the label/font use to not rely on just
--      (desktoplbl, menulbl) globals
--
--  ( ) config tool to change default colors, fonts, ...
--
--  ( ) helper tool (and a default implementation that
--      resurrects clippy ;)
--
--  ( ) autotiling
--
--  ( ) fullscreen mode for media windows
--
--  ( ) better icon management / struct and the option to switch them
--
--  ( ) move language strings to table for internationalization
--
wlist     = {
windows = {};
};

settings = {
mfact  = 0.2,
mvol   = 1.0
};

sysicons   = {};
imagery    = {};
colortable = {};

groupicn    = "awbicons/drawer.png";
groupselicn = "awbicons/drawer_open.png";
deffont     = "fonts/topaz8.ttf";
deffont_sz  = 12;
linespace   = 4;

ORDER_MOUSE     = 255;

kbdbinds = {};
kbdbinds["F11"]    = function() awbwman_gather_scatter();  end
kbdbinds["F12"]    = function() awbwman_shadow_nonfocus(); end

--  window (focus, minimize, maximize, close)
--  border (always visible, content (when not drag))

--  launch_window
-- console_window
--   group_window

function menulbl(text)
return render_text(string.format("\\#0055a9\\f%s,%d %s", 
deffont, 10, text));
end

function desktoplbl(text)
	if (type(text) ~= "string") then
		print(debug.traceback());
	end

text = text == nil and "" or text;
return render_text(string.format("\\#ffffff\\f%s,%d %s",
deffont, 10, text));
end

function inputlbl(text)
	text = text == nil and "" or text;
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 12, text));
end

function awb()
	symtable = system_load("scripts/symtable.lua")();
	system_load("awb_support.lua")();

-- shader function / model viewer
	system_load("scripts/calltrace.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/resourcefinder.lua")();
	system_load("tools/inputconf.lua")();
	system_load("tools/vidrec.lua")();
	system_load("tools/vidcmp.lua")();
	system_load("tools/hghtmap.lua")();

-- mouse abstraction layer 
-- (callbacks for click handlers, motion events etc.)
	system_load("scripts/mouse.lua")();

	if (DEBUGLEVEL > 1) then
		kbdbinds["F5"]     = function() print(current_context_usage()); end; 
		kbdbinds["F10"]    = mouse_dumphandlers;
		kbdbinds["F9"]     = function() Trace(); end
	end

	system_load("awb_iconcache.lua")();
	system_load("awbwnd.lua")();
	system_load("awbwnd_icon.lua")();
	system_load("awbwnd_list.lua")();
	system_load("awbwnd_media.lua")();
	system_load("awbwnd_target.lua")();
	system_load("awbwman.lua")();

	settings.defwinw = math.floor(VRESW * 0.35);
	settings.defwinh = math.floor(VRESH * 0.35);

-- the imagery pool is used as a static data cache,
-- since the windowing subsystem need link_ calls to work
-- we can't use instancing, so instead we allocate a pool
-- and then share_storage
	imagery.cursor       = load_image("awbicons/mouse.png", ORDER_MOUSE);
	awbwman_init(desktoplbl, menulbl);	

-- 
-- look in resources/scripts/mouse.lua
-- for heaps more options (gestures, trails, autohide) 
--
	image_tracetag(imagery.cursor, "mouse cursor");
	mouse_setup(imagery.cursor, ORDER_MOUSE, 1, true);

--
-- Since we'll only use the 3d subsystem as a view for specific windows
-- and those are populated through rendertargets, it's easiest to flip
-- the camera
--
	local supp3d = setup_3dsupport();
	awb_desktop_setup();

-- LCTRL + META = (toggle) grab to specific internal
-- LCTRL = (toggle) grab to this window
	kbdbinds["LCTRL"]  = awbwman_toggle_mousegrab;
	kbdbinds["ESCAPE"] = awbwman_cancel;
end

--
-- Setup a frameserver session with an interactive target
-- as a new window, start with a "launching" canvas and 
-- on activation, switch to the real one.
--
function gamelist_launch(self, factstr)
	local captbl = launch_target_capabilities(self.target);
	if (captbl == nil) then
		awbwman_alert("Couldn't get capability table");
		return;
	end

	if (captbl.internal_launch == false) then
-- confirmation dialog
		launch_target(self.gameid, LAUNCH_EXTERNAL);
	else
		captbl.prefix = string.format("%s_%s_",self.target,
		self.tag.setname and self.tag.setname or "");

		local wnd, cb = awbwman_targetwnd(menulbl(self.name), 
			{refid = "targetwnd_" .. tostring(self.gameid),
			 factsrc = factstr}, captbl);
		wnd.gametbl = self.tag;

		wnd.recv, wnd.reca = launch_target(self.gameid, LAUNCH_INTERNAL, cb);
		wnd.factory_base = "gameid:" .. tostring(self.gameid);
	
		wnd.name = self.target .. "(" .. self.name .. ")";
	end
end

function spawn_vidwin(self)
	local wnd = awbwman_mediawnd(menulbl("Video Capture"), "capture", BADID,
	{refid = "vidcapwnd"});

	local res = awbwman_inputattach(function(msg) print(msg) end, 
		inputlbl, {
		w = 64,
		h = 32,
		owner = wnd.canvas.vid
	});

-- tests, border, noborder, static vs. dynamic
	wnd.input = function(self, tbl) res:input(tbl); end
end

function gamelist_media(tbl)
	local res  = resourcefinder_search(tbl, true);
	local list = {};

	for i,j in ipairs(res.movies) do
		local ment = {
			resource = j,
			name     = "video_" .. tostring(i),
			trigger  = function()
				local wnd, tfun = awbwman_mediawnd(
					menulbl("Media Player"), "frameserver");
				load_movie(j, FRAMESERVER_LOOP, tfun);
			end,
			cols     = {"video_" .. tostring(i)} 
		};
		table.insert(list, ment);
	end

	local imgcat = {"screenshots", "bezels", "marquees", "controlpanels",
		"overlays", "cabinets", "boxart"};

	for ind, cat in ipairs(imgcat) do
		if (res[cat]) then
			for i, j in ipairs(res[cat]) do
				local ment = {
					resource = j,
					trigger = function()
						local wnd, tfun = awbwman_mediawnd(
							menulbl(cat), "static");
						load_image_asynch(j, tfun);
					end,
					name = cat .. "_" .. tostring(i),
					cols = {cat .. "_" .. tostring(i)}
				};
				table.insert(list, ment);
			end
		end
	end

	local mdl = find_cabinet_model(tbl);
	if (mdl) then
		local ment = {
			resource = mdl,
			trigger  = function()
				local model = setup_cabinet_model(mdl, tbl, {});
				if (model.vid) then
					move3d_model(model.vid, 0.0, -0.2, -2.0);
				else
					model = {};
				end
				awbwman_mediawnd(menulbl("3D Model"), "3d", model); 
			end,
			name = "model(" .. mdl ..")",
			cols = {"3D Model"}
		};
		table.insert(list, ment);
	end

-- resource-finder don't sub-categorize properly so we'll 
-- have to do that manually
	awbwman_listwnd(menulbl("Media:" .. tbl.title), deffont_sz, linespace,
	{1.0}, list, desktoplbl);
end

function show_help()
	print("Help!");
end

function gamelist_popup(ent)
	local popup_opts = [[Launch\n\rFind Media\n\rList Siblings]];
	local vid, list  = desktoplbl(popup_opts);
	local popup_fun = {
		function() gamelist_launch(ent);     end,
		function() gamelist_media(ent.tag);  end,
		function() gamelist_family(ent);     end
	};

	awbwman_popup(vid, list, popup_fun);
end

--
-- Set up a basic gamelist view from a prefiltered selection
-- (which can be fine-grained afterwards ofc). 
--
function gamelist_wnd(selection)
	local tgtname = selection.name;
	local tgttotal = #list_games({target = tgtname});
	local wnd = awbwman_listwnd(menulbl(tgtname), deffont_sz, linespace, 
		{0.7, 0.3}, function(filter, ofs, lim, iconw, iconh)
		
		local res = {};

		local tbl = list_games({offset = ofs-1, limit = lim, target = tgtname});	

		if (tbl) then
		for i=1,#tbl do
			local ent = {
				name     = tbl[i].title,
				gameid   = tbl[i].gameid,
				target   = tbl[i].target,
				tag      = tbl[i],
				rtrigger = gamelist_popup,
				trigger  = gamelist_launch,
				cols     = {tbl[i].title, 
					(tbl[i].genre ~= nil and string.len(tbl[i].genre) > 0) and tbl[i].genre or "(none)"}
			};

			table.insert(res, ent);
		end
		end
	
		return res, tgttotal;
	end, desktoplbl, {refid = "listwnd_" .. tgtname});
	wnd.name = "List(" .. tgtname .. ")";
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
		table.insert(ftbl, function()
			image_sharestorage(ctag.source.canvas.vid, awbwman_cfg().root.canvas.vid);
		end);
	end

	if (ctag.factory) then
		table.insert(lbls, "Add Shortcut");
		table.insert(ftbl, function()
			awbwman_shortcut( ctag.factory );
		end);
	end

	if (#lbls > 0) then
		local vid, lines = desktoplbl(table.concat(lbls, "\\n\\r"));
		awbwman_popup(vid, lines, ftbl);
	end
end

local function amediahandler(path, base, ext)
	local name = path .. "/" .. base .. "." .. ext;
	local wnd, tfun = awbwman_mediawnd(menulbl("Music Player"), "frameserver_music");
	load_movie(name, FRAMESERVER_NOLOOP, tfun, 1, "novideo=true");
	wnd.name = base; 
end

local function vmediahandler(path, base, ext)
	local name = path .. "/" .. base .. "." .. ext;
	local wnd, tfun = awbwman_mediawnd(menulbl("Media Player"), "frameserver");
	load_movie(name, FRAMESERVER_NOLOOP, tfun);
	wnd.name = base; 
end

local function imghandler(path, base, ext)
	local wnd, tfun = awbwman_mediawnd(menulbl(base), "static");
	local name = path .. "/" .. base .. "." .. ext;
	load_image_asynch(name, tfun);
end

local handlers = {
	MP3 = amediahandler,
	OGG = amediahandler,
	MKV = vmediahandler,
	AVI = vmediahandler,
	MPG = vmediahandler,
	MPEG= vmediahandler,
	JPG = imghandler,
	PNG = imghandler 
};

local function exthandler(path, base, ext)
	if (ext == nil) then
		return false;
	end

	local hfun = handlers[string.upper(ext)];
	if (hfun ~= nil) then
		hfun(path, base, ext);
		return true;
	end

	return false;
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
	
	awbwman_listwnd(menulbl("MediaBrowser"), deffont_sz, linespace, {1.0}, 
		function(filter, ofs, lim, iconw, iconh)
			local res = {};
			local ul = ofs + lim;
	
			for i=ofs, ul do
				local ment = {
					resource = list[i],
					trigger  = function()
						local base, ext = string.extension(list[i]);
						if (not exthandler(path, base, ext)) then
							wnd_media(path .. "/" .. list[i]); 
						end
					end,
					name = "mediaent",
					cols = {list[i]}
				};
	
				table.insert(res, ment);
			end
			return res, #list;
		end, desktoplbl);
end

function awb_desktop_setup()
	sysicons.group        = load_image("awbicons/drawer.png");
	sysicons.group_active = load_image("awbicons/drawer_open.png");
	sysicons.boing        = load_image("awbicons/boing.png");
	sysicons.floppy       = load_image("awbicons/floppy.png");
	sysicons.shell        = load_image("awbicons/shell.png");

-- constraint, lru_cache limit should always be >= the number of icons
-- in a fullscreen iconview window (else, if every entry is unique,
-- images will be deleted before they are used)
	sysicons.lru_cache    = awb_iconcache(64, 
		{"images/icons", "icons", "images/systems", "awbicons"}, sysicons.floppy);

	local groups = {
		{
			name    = "Tools",
			key     = "tools",
			trigger = function()
				local wnd = awbwman_iconwnd(menulbl("Tools"), builtin_group, 
					{refid = "iconwnd_tools"});
				wnd.name = "List(Tools)";
			end
		},
		{
			name    = "Saves",
			key     = "savestates",
			trigger = function() end, 
		},
		{
			name    = "Systems",
			key     = "systems",
			trigger = function()
				local tbl =	awbwman_iconwnd(menulbl("Systems"), system_group,
					{refid = "iconwnd_systems"});
				tbl.idfun = list_targets;
				tbl.name = "List(Systems)";
			end
		},
		{
			name = "Music",
			key  = "music",
			trigger = function() 
				wnd_media("music");
			end
		},
		{
			name = "Recordings",
			key = "recordings",
			trigger = function()
				wnd_media("recordings");
			end,
		},
		{
			name = "Videos",
			key = "videos",
			trigger = function()
				wnd_media("movies");
			end,
			rtrigger = function()
				print("balle");
			end
		},
	};

	for i,j in pairs(groups) do
		local lbl = desktoplbl(j.name);
		awbwman_rootaddicon(j.key, lbl, sysicons.group, 
			sysicons.group_active, j.trigger);
	end

	local cfg = awbwman_cfg();
	cfg.on_rootdnd = rootdnd;

-- shortcuts are stored as a group- key with individual factories 
	local scuts = get_key("shortcuts");
	if (scuts ~= nil) then

	end
end

--
-- Since these use the icon LRU cache, parts of 
-- the tables need to be generated dynamically
--
function builtin_group(self, ofs, lim, desw, desh)
	local tools = {
		{"BOING!",    spawn_boing,    "boing"},
		{"InputConf", awb_inputed,  "inputed"},
		{"Recorder",  spawn_vidrec,  "vidrec"},
--		{"Network",   spawn_socsrv, "network"},
		{"VidCap",    spawn_vidwin,  "vidcap"},
--		{"Compare",   spawn_vidcmp,  "vidcmp"},
		{"HeightMap", spawn_hmap,   "hghtmap"}
--		{"ShaderEd",  spawn_shadeed, "shadeed"},
	};

	local restbl = {};

	lim = lim + ofs;
	while ofs <= lim and ofs <= #tools do
		local newtbl = {};
		newtbl.caption = desktoplbl(tools[ofs][1]);
		newtbl.trigger = tools[ofs][2];
		newtbl.name    = tools[ofs][3];
		newtbl.icon    = sysicons.lru_cache:get(newtbl.name, desw, desh).icon;
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
		newtbl.icon    = sysicons.lru_cache:get(newtbl.name, desw, desh).icon;
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

	a.name = "Boing!"; 
	
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
		mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0, 
			iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);

	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		if (iotbl.subid > 0 and iotbl.subid <= 3) then

-- meta converts LMB to RMB
--			if (iotbl.subid == 1 and awbwman_cfg().meta.shift) then
--				iotbl.subid = 3;
--			end

			minputtbl[iotbl.subid] = iotbl.active;
			mouse_input(0, 0, minputtbl);
		end

	elseif (iotbl.kind == "digital" and iotbl.translated) then
		iotbl.lutsym = symtable[iotbl.keysym];

		if (iotbl.lutsym == "LSHIFT" or iotbl.lutsym == "RSHIFT") then 
			awbwman_meta("shift", iotbl.active);
		end

		if (iotbl.active and kbdbinds[ iotbl.lutsym ]) then
		 	kbdbinds[ iotbl.lutsym ](); 
		else
			awbwman_input(iotbl);
		end
	end
end

