-- this one is just a mess of tables, all mapping to a
-- global settings structure, nothing really interesting

-- traverse the current menu back up to the root node, set the gamecount to an "impossible" number
-- 
function menu_resetgcount(node)
	local node = current_menu;
	while (node.parent) do node = node.parent; end
	node.gamecount = -1;
end

function build_globmenu(globstr, cbfun, globmask)
	local lists = glob_resource(globstr, globmask);
	local resptr = {};
	
	for i = 1, #lists do
		resptr[ lists[i] ] = cbfun;
	end
	
	return lists, resptr;
end

-- for some menu items we just want to have a list of useful values
-- this little function builds a list of those numbers, with corresponding functions,
-- dispatch handling etc.
function gen_tbl_menu(name, tbl, triggerfun, isstring)
	local reslbl = {};
	local resptr = {};
	
	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = isstring and label or tonumber(label);
		if (save) then
			play_audio(soundmap["MENU_FAVORITE"]);
			store_key(name, tonumber(label));
		else
			play_audio(soundmap["MENU_SELECT"]);
		end
		
		if (triggerfun) then triggerfun(label); end
	end

	for key,val in ipairs(tbl) do
		table.insert(reslbl, val);
		resptr[val] = basename;
	end
	
	return reslbl, resptr;
end

function gen_num_menu(name, base, step, count, triggerfun)
	local reslbl = {};
	local resptr = {};
	local clbl = base;
	
	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = tonumber(label);
		if (save) then
			play_audio(soundmap["MENU_FAVORITE"]);
			store_key(name, tonumber(label));
		else
			play_audio(soundmap["MENU_SELECT"]);
		end
		
		if (triggerfun) then triggerfun(); end
	end

	clbl = base;
	for i=1,count do
		if (type(step) == "function") then clbl = step(i); end

		table.insert(reslbl, tostring(clbl));
		resptr[tostring(clbl)] = basename;
		
		if (type(step) == "number") then clbl = clbl + step; end
	end

	return reslbl, resptr;
end

function add_submenu(dstlbls, dstptrs, label, key, lbls, ptrs)
	if (dstlbls == nil or dstptrs == nil or #lbls == 0) then return; end
	
	table.insert(dstlbls, label);
	
	dstptrs[label] = function()
		local fmts = {};
		local ind = tostring(settings[key]);
	
		if (ind) then
			fmts[ ind ] = settings.colourtable.notice_fontstr;
			if(get_key(key)) then
				fmts[ get_key(key) ] = settings.colourtable.alert_fontstr;
			end
		end
		
		menu_spawnmenu(lbls, ptrs, fmts);
	end
end

function menu_spawnmenu(list, listptr, fmtlist)
	if (#list < 1) then
		return nil;
	end

	local parent = current_menu;
	local props = image_surface_resolve_properties(current_menu.cursorvid);
	local windsize = VRESH;

	local yofs = 0;
	if (props.y + windsize > VRESH) then
		yofs = VRESH - windsize;
	end

	current_menu = listview_create(list, windsize, VRESW / 3, fmtlist);
	current_menu.parent = parent;
	current_menu.ptrs = listptr;
	current_menu.updatecb = parent.updatecb;
	current_menu:show();
	move_image( current_menu.anchor, props.x + props.width + 6, props.y);
	
	local xofs = 0;
	local yofs = 0;
	
-- figure out where the window is going to be.
	local aprops_l = image_surface_properties(current_menu.anchor, settings.fadedelay);
	local wprops_l = image_surface_properties(current_menu.window, settings.fadedelay);
	local dx = aprops_l.x;
	local dy = aprops_l.y;
	
	local winw = wprops_l.width;
	local winh = wprops_l.height;
	
	if (dx + winw > VRESW) then
		dx = dx + (VRESW - (dx + winw));
	end
	
	if (dy + winh > VRESH) then
		dy = dy + (VRESH - (dy + winh));
	end
	
	move_image( current_menu.anchor, dx, dy, settings.fadedelay );
	
	play_audio(soundmap["SUBMENU_TOGGLE"]);
	return current_menu;
end

local menulbls = {
	"Game Lists...",
	"Filters...",
	"Settings...",
};

local filterlbls = {
	"Year",
	"Players",
	"Buttons",
	"Genre",
	"Subgenre",
	"System",
--	"Manufacturer", typically yields such a large list it'd be useless.
	"Target"
};

local settingslbls = {
	"Sort Order...",
	"Cell Size...",
	"Reconfigure Keys (Full)",
	"Reconfigure Keys (Players)",
};
	
local backgroundlbls = {
};

local function updatebgtrigger()
	grab_sysicons();
	zap_whitegrid();
	build_whitegrid();
	set_background(settings.bgname, settings.bg_rw, settings.bg_rh, settings.bg_speedv, settings.bg_speedh)	
end

local function setbgfun(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
	settings.bgname = label;

	if (save) then 
		store_key("bgname", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
  updatebgtrigger();
end

local function animnums(i)
	if (i > 1) then
		return math.pow(2, i);
	else
		return 1;
	end
end

local function tilenums(i)
	if (i > 1) then
		return 4 * (i - 1);
	else
		return 1;
	end
end

local function bgtileupdate(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.tilebg = label;

	if (save) then 
		store_key("tilebg", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
  updatebgtrigger();
end

local function autosaveupd(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.autosave = label;
	
	if (save) then
		store_key("autosave", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
end

local function launchmodeupdate(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.default_launchmode = label;
	
	if (save) then
		store_key("default_launchmode", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

local backgroundptrs = {};
add_submenu(backgroundlbls, backgroundptrs, "Image...", "bgname", build_globmenu("backgrounds/*.png", setbgfun, ALL_RESOURCES));
add_submenu(backgroundlbls, backgroundptrs, "Tile (vertical)...", "bg_rh", gen_num_menu("bg_rh", 1, tilenums, 8, updatebgtrigger));
add_submenu(backgroundlbls, backgroundptrs, "Tile (horizontal)...", "bg_rw", gen_num_menu("bg_rw", 1, tilenums, 8, updatebgtrigger));
add_submenu(backgroundlbls, backgroundptrs, "Animate (vertical)...", "bg_speedv", gen_num_menu("bg_speedv", 1, animnums, 8, updatebgtrigger));
add_submenu(backgroundlbls, backgroundptrs, "Animate (horizontal)...", "bg_speedh", gen_num_menu("bg_speedh", 1, animnums, 8, updatebgtrigger));

local settingsptrs = {};
add_submenu(settingslbls, settingsptrs, "Launch Mode...", "default_launchmode", {"Internal", "External"}, {Internal = launchmodeupdate, External = launchmodeupdate});
add_submenu(settingslbls, settingsptrs, "Repeat Rate...", "repeatrate", gen_num_menu("repeatrate", 0, 100, 6));
add_submenu(settingslbls, settingsptrs, "Fade Delay...", "fadedelay", gen_num_menu("fadedelay", 5, 5, 10));
add_submenu(settingslbls, settingsptrs, "Transition Delay...", "transitiondelay", gen_num_menu("transitiondelay", 5, 5, 10));
add_submenu(settingslbls, settingsptrs, "Movie Audio Gain...", "movieagain", gen_num_menu("movieagain", 0, 0.1, 11));
add_submenu(settingslbls, settingsptrs, "Movie Playback Cooldown...", "cooldown_start", gen_num_menu("cooldown_start", 0, 15, 5));
add_submenu(settingslbls, settingsptrs, "Background...", "bgname", backgroundlbls, backgroundptrs);
add_submenu(settingslbls, settingsptrs, "Tile Background...", "tilebg", {"None", "White", "Black", "Sysicons"}, {None = bgtileupdate, White = bgtileupdate, Black = bgtileupdate, Sysicons = bgtileupdate});
add_submenu(settingslbls, settingsptrs, "Autosave...", "autosave", {"On", "Off"}, {On = autosaveupd, Off = autosaveupd}); 
add_submenu(settingslbls, settingsptrs, "Cursor Scale...", "cursor_scale", gen_num_menu("cursor_scale", 1.0, 0.1, 5));

if (LEDCONTROLLERS > 0) then
	table.insert(settingslbls, "LED display mode...");
	table.insert(settingslbls, "Reconfigure LEDs");
end
	
local ledmodelbls = {
	"Disabled",
	"All toggle",
	"Game setting (always on)"
};

if INTERNALMODE ~= "NO SUPPORT" then
	table.insert(ledmodelbls, "Game setting (on push)");
end
	
local ledmodeptrs = {}
	ledmodeptrs["Disabled"] = function(label, save) 
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
	settings.ledmode = 0;
	if (save) then 
		store_key("ledmode", 0);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

ledmodeptrs["All toggle"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.ledmode = 1;
	if (save) then 
		store_key("ledmode", 1);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

ledmodeptrs["Game setting (always on)"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
	settings.ledmode = 2; 
	if (save) then
		store_key("ledmode", 2); 
		play_audio(soundmap["MENU_FAVORITE"])
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

ledmodeptrs["Game setting (on push)"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
	settings.ledmode = 3; 
	if (save) then 
		store_key("ledmode", 3); 
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"])	
	end
end

local sortorderlbls = {
	"Ascending",
	"Descending",
	"Times Played",
	"Favorites"
};

local gridlbls = { "48x48", "48x64", "64x48", "64x64", "96x64", "64x96", "96x96", "128x96", "96x128", "128x128", "196x128", "128x196", "196x196",
		"196x256", "256x196", "256x256"};
local gridptrs = {};

local function gridcb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.cell_width = tonumber( string.sub(label, 1, string.find(label, "x") - 1) );
	settings.cell_height = tonumber( string.sub(label, string.find(label, "x") + 1, -1) );
	menu_resetgcount(current_menu);

	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);	
		store_key("cell_width", settings.cell_width);
		store_key("cell_height", settings.cell_height);
	else
		play_audio(soundmap["MENU_SELECT"]);	
	end
end
for ind,val in ipairs(gridlbls) do gridptrs[val] = gridcb; end

local sortorderptrs = {};
local function sortordercb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.sortlbl = label;
	
	menu_resetgcount(current_menu);
	
	if (save) then
		store_key("sortorder", label);
		play_audio(soundmap["MENU_FAVORITE"]);	
	else
		play_audio(soundmap["MENU_SELECT"]);	
	end
end
for key, val in ipairs(sortorderlbls) do sortorderptrs[val] = sortordercb; end

-- These submenus all follow the same pattern,
-- lookup label matches the name of the entry, force a different formatting (cyan) for the current value,
-- and set the "favorite" (default / stored) value to green
settingsptrs["Sort Order..."]    = function() 
	local fmts = {};
	fmts[ settings.sortlbl ] = settings.colourtable.notice_fontstr;
	if ( get_key("sortorder") ) then
		fmts[ get_key("sortorder") ] = settings.colourtable.alert_fontstr; 
	end
	menu_spawnmenu(sortorderlbls, sortorderptrs, fmts); 
end

settingsptrs["Reconfigure Keys (Full)"] = function()
	zap_resource("keysym.lua");
	gridle_keyconf();
end

settingsptrs["LED display mode..."] = function() 
	local fmts = {};

	fmts[ ledmodelbls[ tonumber(settings.ledmode) + 1] ] = settings.colourtable.notice_fontstr;
	if (get_key("ledmode")) then
		fmts[ ledmodelbls[ tonumber(get_key("ledmode")) + 1] ] = settings.colourtable.alert_fontstr;
	end
	
	menu_spawnmenu(ledmodelbls, ledmodeptrs, fmts); 
end


settingsptrs["Reconfigure LEDs"] = function()
	zap_resource("ledsym.lua");
	gridle_ledconf();
end

settingsptrs["Reconfigure Keys (Players)"] = function()
	keyconfig:reconfigure_players();
	kbd_repeat(0);

	gridle_input = function(iotbl) -- keyconfig io function hook
		if (keyconfig:input(iotbl) == true) then
			keyconf_tomame(keyconfig, "_mame/cfg/default.cfg"); -- should be replaced with a more generic export interface

			gridle_input = gridle_dispatchinput;
			kbd_repeat(settings.repeatrate);
		end
	end
end

settingsptrs["Cell Size..."] = function()
	local fmts = {};
	fmts[ tostring(settings.cell_width) .. "x" .. tostring(settings.cell_height) ] = settings.colourtable.notice_fontstr;
	if (get_key("cell_width") and get_key("cell_height")) then
		fmts[ get_key("cell_width") .. "x" .. get_key("cell_height") ] = settings.colourtable.alert_fontstr;
	end

	menu_spawnmenu(gridlbls, gridptrs, fmts); 
end

local function update_status()
-- show # games currently in list, current filter or gamelist

	list = {};
	table.insert(list, "# games: " .. tostring(#settings.games));
	table.insert(list, "grid dimensions: " .. settings.cell_width .. "x" .. settings.cell_height);
	table.insert(list, "sort order: " .. settings.sortlbl);
	table.insert(list, "repeat rate: " .. settings.repeatrate);
	
	filterstr = "filters: ";
	if (settings.filters.title)   then filterstr = filterstr .. " title("    .. settings.filters.title .. ")"; end
	if (settings.filters.genre)   then filterstr = filterstr .. " genre("    .. settings.filters.genre .. ")"; end
	if (settings.filters.subgenre)then filterstr = filterstr .. " subgenre(" .. settings.filters.subgenre .. ")"; end
	if (settings.filters.target)  then filterstr = filterstr .. " target("   .. settings.filters.target .. ")"; end
	if (settings.filters.year)    then filterstr = filterstr .. " year("     .. tostring(settings.filters.year) .. ")"; end
	if (settings.filters.players) then filterstr = filterstr .. " players("  .. tostring(settings.filters.players) .. ")"; end
	if (settings.filters.buttons) then filterstr = filterstr .. " buttons("  .. tostring(settings.filters.buttons) .. ")"; end
	if (settings.filters.system)  then filterstr = filterstr .. " system(" .. tostring(settings.filters.system) .. ")"; end
	if (settings.filters.manufacturer) then filterstr = filterstr .. " manufacturer(" .. tostring(settings.filters.manufacturer) .. ")"; end

	table.insert(list, filterstr);
	if (settings.statuslist == nil) then
		settings.statuslist = listview_create(list, VRESH * 0.9, VRESW * 0.75);
		settings.statuslist:show();
		move_image(settings.statuslist.anchor, 5, settings.fadedelay);
		hide_image(settings.statuslist.cursorvid);
	else
		settings.statuslist.list = list;
		settings.statuslist:redraw();
	end
end

local function get_unique(list, field)
	local res = {};
	local tmp = {};

	for i=1,#list do
		if ( list[i][field] and
			string.len( list[i][field]) > 0 ) then
			tmp[ list[i][field] ] = true;
		end
	end

-- convert to number indexed table, #elements must match for listview
	for key,val in pairs(tmp) do
		table.insert(res, key);
	end

	table.sort(res, function(a,b) return a > b; end);
	resptr = {};
	for i=1,#res do
		resptr[res[i]] = function(lbl)
			settings.iodispatch["MENU_ESCAPE"](nil, nil, false);
			update_status();
			settings.filters[string.lower(current_menu:select())] = lbl;
			settings.games = list_games(settings.filters);
		end
	end

	return res, resptr;
end

local function update_filterlist()
	local filterres = {};
	local filterresptr = {};

	table.insert(filterres, "Reset");
	filterresptr["Reset"] = function()
		settings.filters = {};
		settings.games = list_games( {} );
		settings.iodispatch["MENU_ESCAPE"](nil, nil, false);
	end

	for i=1,#filterlbls do
		local filterlbl = filterlbls[i];
		if (settings.filters[ filterlbls[i] ]) then
			filterlbls[i] = filterlbls[i] .. [[\i (]] .. settings.filters[ filterlbls[i] ] .. [[)\!i]];
		end

		table.insert(filterres, filterlbl);
		filterresptr[filterlbl] = function(lbl) menu_spawnmenu( get_unique(settings.games, string.lower(lbl)) ); end
	end

	return filterres, filterresptr;
end

function string.trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function apply_gamefilter(listname)
	local reslist = {};
	local filter = {};

	open_rawresource("./lists/" .. listname .. ".txt");
	line = read_rawresource();

	while (line) do
			filter["title"] = line;
			local dblookup = list_games( filter )

			if dblookup and #dblookup > 0 then
				table.insert(reslist, dblookup[1]);
			end

			line = read_rawresource();
		end
	close_rawresource();

	if (#reslist == 0) then
			spawn_warning("No games from gamelist( " .. listname .. ") could be found.");
	else
		settings.games = reslist;
	end
end

function build_gamelists()
	local lists = glob_resource("lists/*.txt", THEME_RESOURCE);
	local res = {};
	local resptr = {};

	for i=1, #lists do
			res[i] = string.sub(lists[i], 1, -5);
			resptr[ res[i] ] = function(lbl) settings.iodispatch["MENU_ESCAPE"](nil, nil, false); apply_gamefilter(lbl); settings.filters = {}; end
	end

	return res, resptr;
end

-- reuse by other menu functions
function gridlemenu_defaultdispatch()
	if (not settings.iodispatch["MENU_UP"]) then
		settings.iodispatch["MENU_UP"] = function(iotbl) 
			play_audio(soundmap["MENUCURSOR_MOVE"]); 
			current_menu:move_cursor(-1, true); 
		end
	end

	if (not settings.iodispatch["MENU_DOWN"]) then
			settings.iodispatch["MENU_DOWN"] = function(iotbl)
			play_audio(soundmap["MENUCURSOR_MOVE"]); 
			current_menu:move_cursor(1, true); 
		end
	end
	
	if (not settings.iodispatch["MENU_SELECT"]) then
		settings.iodispatch["MENU_SELECT"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, false);
				if (current_menu and current_menu.updatecb) then
					current_menu.updatecb();
				end
			end
		end
	end
	
-- figure out if we should modify the settings table
	if (not settings.iodispatch["FLAG_FAVORITE"]) then
		settings.iodispatch["FLAG_FAVORITE"] = function(iotbl)
				selectlbl = current_menu:select();
				if (current_menu.ptrs[selectlbl]) then
					current_menu.ptrs[selectlbl](selectlbl, true);
					if (current_menu and current_menu.updatecb) then
						current_menu.updatecb();
					end
				end
			end
	end
	
	if (not (settings.iodispatch["MENU_ESCAPE"])) then
		settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();

		if (current_menu.parent ~= nil) then
			if (silent == nil or silent == false) then play_audio(soundmap["SUBMENU_FADE"]); end
			current_menu = current_menu.parent;
		else -- top level
			play_audio(soundmap["MENU_FADE"]);
			settings.iodispatch = griddispatch;
		end
		end
	end
	
	if (not settings.iodispatch["MENU_RIGHT"]) then
		settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	end
	
	if (not settings.iodispatch["MENU_LEFT"]) then
		settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];
	end
end

function gridlemenu_filterchanged()
	settings.cursor = 0;
	settings.pageofs = 0;

	erase_grid(false);
	build_grid(settings.cell_width, settings.cell_height);
	move_cursor(1, true);
end

function gridlemenu_settings()
-- first, replace all IO handlers
	griddispatch = settings.iodispatch;

	settings.iodispatch = {};

	settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();
		if (current_menu.parent ~= nil) then
			if (silent == nil or silent == false) then play_audio(soundmap["SUBMENU_FADE"]); end
			current_menu = current_menu.parent;
			update_status();
		else -- top level
			if (#settings.games == 0) then
				settings.games = list_games( {} );
			end
		
		play_audio(soundmap["MENU_FADE"]);
		table.sort(settings.games, settings.sortfunctions[ settings.sortlbl ]);

-- only rebuild grid if we have to
		gridlemenu_filterchanged();
			
		settings.iodispatch = griddispatch;
		if (settings.statuslist) then
			settings.statuslist:destroy();
			settings.statuslist = nil;
		end
	end

		init_leds();
	end

	gridlemenu_defaultdispatch();
	
-- hide the cursor and all selected elements
	if (movievid) then
		instant_image_transform(movievid);
		expire_image(movievid, settings.fadedelay);
		blend_image(movievid, 0.0, settings.fadedelay);
		movievid = nil;
	end

	current_menu = listview_create(menulbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = {};
	current_menu.ptrs["Game Lists..."] = function() menu_spawnmenu( build_gamelists() ); end
	current_menu.ptrs["Filters..."]    = function() menu_spawnmenu( update_filterlist() ); end
	current_menu.ptrs["Settings..."]   = function() menu_spawnmenu( settingslbls, settingsptrs ); end
	current_menu.updatecb = update_status;
	
	current_menu.gamecount = #settings.games;
	current_menu:show();
	
-- add an info window
	update_status();
	move_image(current_menu.anchor, 100, 140, settings.fadedelay);
end
