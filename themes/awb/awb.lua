--
-- Arcan "Workbench" theme
-- "inspired" by certain older desktop / windowing UI
-- but mainly thought of as an experiment towards better 
-- networking features and testing out the API for more
-- desktop- kindof window management. 
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
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 10, text));
end

function awb()
	symtable = system_load("scripts/symtable.lua")();

-- shader function / model viewer
  system_load("scripts/calltrace.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/resourcefinder.lua")();
	system_load("tools/inputconf.lua")();
	system_load("tools/vidrec.lua")();

-- mouse abstraction layer 
-- (callbacks for click handlers, motion events etc.)
	system_load("scripts/mouse.lua")();
	kbdbinds["F10"]    = mouse_dumphandlers;

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
	mouse_setup(imagery.cursor, ORDER_MOUSE, 1);
	mouse_acceleration(0.5);
	
	setup_3dsupport();
	awb_desktop_setup();

-- LCTRL + META = (toggle) grab to specific internal
-- LCTRL = (toggle) grab to this window
	kbdbinds["LCTRL"]  = toggle_mouse_grab;
	kbdbinds["ESCAPE"] = awbwman_cancel;

-- awb_inputed();
--local tbl = list_games({title = "Moon P%"})[1];
--	local res = resourcefinder_search(tbl, true);
--	local mdl = find_cabinet_model(tbl);
--	local model = setup_cabinet_model(mdl, res, {});
--	if (model.vid) then
--		move3d_model(model.vid, 0.0, -0.2, -2.0);
--	else
--		model = {};
--	end
--	awbwman_mediawnd(menulbl("3D Model"), "3d", model);
end

--
-- Setup a frameserver session with an interactive target
-- as a new window, start with a "launching" canvas and 
-- on activation, switch to the real one.
--
function gamelist_launch(self)
	local captbl = launch_target_capabilities(self.target);

	if (captbl.internal_launch == false) then
-- confirmation dialog
		launch_target(self.gameid, LAUNCH_EXTERNAL);
	else
		local wnd, cb = awbwman_targetwnd(menulbl(self.name), 
			{refid = "targetwnd_" .. tostring(self.gameid)});
		wnd.recv, wnd.reca = launch_target(self.gameid, LAUNCH_INTERNAL,cb);
	end
end

function spawn_vidwin(self)
	awbwman_mediawnd(menulbl("Video Capture"), "capture", BADID,
		{refid = "vidcapwnd"});
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
	{1.0}, function(filter, ofs, lim, iconw, iconh)
		local res = {};
		local ul = ofs + lim;
		for i=ofs, ul do
			table.insert(res, list[i]);
		end
		return res, #list;
	end, desktoplbl);
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

	awbwman_listwnd(menulbl(tgtname), deffont_sz, linespace, 
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
					string.len(tbl[i].genre) > 0 and tbl[i].genre or "(none)"}
			};

			table.insert(res, ent);
		end
		end
	
		return res, tgttotal;
	end, desktoplbl, {refid = "listwnd_" .. tgtname});
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
				awbwman_iconwnd(menulbl("Tools"), builtin_group, 
					{refid = "iconwnd_tools"});
			end
		},
		{
			name    = "Saves",
			key     = "savestates",
			trigger = nil, 
		},
		{
			name    = "Systems",
			key     = "sytems",
			trigger = function()
				local tbl =	awbwman_iconwnd(menulbl("Systems"), system_group,
					{refid = "iconwnd_systems"});
				tbl.idfun = list_targets;
			end
		}
	};

	for i,j in pairs(groups) do
		local lbl = desktoplbl(j.name);
		awbwman_rootaddicon(j.key, lbl, sysicons.group, 
			sysicons.group_active, j.trigger);
	end
end

function attrstr(self)
	return self.title;
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
		{"Network",   spawn_socsrv, "network"},
		{"VidCap",    spawn_vidwin,  "vidcap"},
		{"Compare",   spawn_vidcmp,  "vidcmp"},
		{"ShaderEd",  spawn_shadeed, "shadeed"},
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

	a.name = "boingwnd" .. tostring(oval);
	
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
		if (symtable[iotbl.keysym] == "LSHIFT" or 
			symtable[iotbl.keysym] == "RSHIFT") then 
			awbwman_meta("shift", iotbl.active);
		end

		iotbl.lutsym = symtable[iotbl.keysym];

		if (iotbl.active and kbdbinds[ iotbl.lutsym ]) then
		 	kbdbinds[ iotbl.lutsym ](); 
		else
			awbwman_input(iotbl);
		end
	end
end

