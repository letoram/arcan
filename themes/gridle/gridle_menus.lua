-- 
-- This file contains (a) menu helper functions (build_globmenu, gen_tbl_menu, gen_num_menu, spawn_menu, ...)
-- and the menu setup / spawning for the global settings menus.
-- quite messy, generalizing to a shared script would be nice.
-- 

function build_globmenu(globstr, cbfun, globmask)
	local lists = glob_resource(globstr, globmask);
	local resptr = {};
	
	for i = 1, #lists do
		resptr[ lists[i] ] = cbfun;
	end
	
	return lists, resptr;
end

-- name     : settings[name] to store under
-- tbl      : array of string with labels of possible values
-- isstring : treat value as string or convert to number before sending to store_key
function gen_tbl_menu(name, tbl, triggerfun, isstring)
	local reslbl = {};
	local resptr = {};

	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = isstring and label or tonumber(label);

		if (save) then
			play_audio(soundmap["MENU_FAVORITE"]);
			store_key(name, isstring and label or tonumber(label));
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

-- automatically generate a menu of numbers
-- name  : the settings key to store in
-- base  : start value
-- step  : value to add to base, or a function that calculates the value using an index
-- count : number of entries
-- triggerfun : hook to be called when selected 
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
		if (type(step) == "function") then 
			clbl = step(i); 
			if (clbl == nil) then 
				break;
			end
		end

		table.insert(reslbl, tostring(clbl));
		resptr[tostring(clbl)] = basename;
		
		if (type(step) == "number") then clbl = clbl + step; end
	end

	return reslbl, resptr;
end

-- inject a submenu into a main one
-- dstlbls : array of strings to insert into
-- dstptrs : hashtable keyed by label for which to insert the spawn function
-- label   : to use for dstlbls/dstptrs
-- lbls    : array of strings used in the submenu (typically from gen_num, gen_tbl)
-- ptrs    : hashtable keyed by label that acts as triggers (typically from gen_num, gen_tbl)
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

-- create and display a listview setup with the menu defined by the arguments.
-- list    : array of strings that make up the menu
-- listptr : hashtable keyed by list labels
-- fmtlist : hashtable keyed by list labels, on match, will be prepended when rendering (used for icons, highlights etc.)
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

	move_image( current_menu.anchor, math.floor(dx), math.floor(dy), settings.fadedelay );
	
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
	"Reconfigure Keys (Full)",
	"Reconfigure Keys (Players)",
};
	
local backgroundlbls = {
};

local updatebgtrigger = nil;

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

local function cellhnum(i)
	if (i * 32 < VRESH) then
		return i * 32;
	end
end

local function cellwnum(i)
	if (i * 32 < VRESW) then
		return i * 32;
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
local gridviewlbls   = {};
local gridviewptrs   = {};

-- hack around scoping and upvalue
local function bgtrig()
	updatebgtrigger();
end

local function reset_customview()
	zap_resource("customview_cfg.lua");
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		play_audio(soundmap["MENU_SELECT"]);

	if (customview.in_customview) then
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings.iodispatch["SWITCH_VIEW"]();
		settings.iodispatch["SWITCH_VIEW"]();
	end
end

local function efftrigger(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.bgeffect = label;
	updatebgtrigger();
	
	if (save) then
		store_key("bgeffect", settings.bgeffect);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
end

local function setsndfun(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.soundmap = label;

	if (save) then
		store_key("soundmap", settings.soundmap);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end

	load_soundmap(label);
end

local bgeffmen, bgeffdesc = build_globmenu("shaders/bgeffects/*.fShader", efftrigger, ALL_RESOURCES);

add_submenu(backgroundlbls, backgroundptrs, "Image...", "bgname", build_globmenu("backgrounds/*.png", setbgfun, ALL_RESOURCES));
add_submenu(backgroundlbls, backgroundptrs, "Background Effects...", "bgeffect", bgeffmen, bgeffdesc);
add_submenu(backgroundlbls, backgroundptrs, "Tile (vertical)...", "bg_rh", gen_num_menu("bg_rh", 1, tilenums, 8, bgtrig));
add_submenu(backgroundlbls, backgroundptrs, "Tile (horizontal)...", "bg_rw", gen_num_menu("bg_rw", 1, tilenums, 8, bgtrig));
add_submenu(backgroundlbls, backgroundptrs, "Animate (horizontal)...", "bg_speedv", gen_num_menu("bg_speedv", 1, animnums, 8, bgtrig));
add_submenu(backgroundlbls, backgroundptrs, "Animate (vertical)...", "bg_speedh", gen_num_menu("bg_speedh", 1, animnums, 8, bgtrig));
add_submenu(backgroundlbls, backgroundptrs, "Movie Audio Gain...", "movieagain", gen_num_menu("movieagain", 0, 0.1, 11));
add_submenu(backgroundlbls, backgroundptrs, "Movie Playback Cooldown...", "cooldown_start", gen_num_menu("cooldown_start", 0, 15, 5));

add_submenu(gridviewlbls, gridviewptrs, "Background...", "bgname", backgroundlbls, backgroundptrs);
add_submenu(gridviewlbls, gridviewptrs, "Tile Background...", "tilebg", {"None", "White", "Black", "Sysicons"}, {None = bgtileupdate, White = bgtileupdate, Black = bgtileupdate, Sysicons = bgtileupdate});
add_submenu(gridviewlbls, gridviewptrs, "Cursor Scale...", "cursor_scale", gen_num_menu("cursor_scale", 1.0, 0.1, 5));

local settingsptrs = {};

add_submenu(gridviewlbls, gridviewptrs, "Cell Width...", "cell_width", gen_num_menu("cell_width", 1, cellwnum, 10));
add_submenu(gridviewlbls, gridviewptrs, "Cell Height...", "cell_height", gen_num_menu("cell_height", 1, cellhnum, 10));
add_submenu(settingslbls, settingsptrs, "Launch Mode...", "default_launchmode", {"Internal", "External"}, {Internal = launchmodeupdate, External = launchmodeupdate});
add_submenu(settingslbls, settingsptrs, "Repeat Rate...", "repeatrate", gen_num_menu("repeatrate", 0, 100, 6, function() kbd_repeat(settings.repeatrate); end));
add_submenu(settingslbls, settingsptrs, "Fade Delay...", "fadedelay", gen_num_menu("fadedelay", 5, 5, 10));
add_submenu(settingslbls, settingsptrs, "Soundmaps...", "soundmap", build_globmenu("soundmaps/*", setsndfun, ALL_RESOURCES));
add_submenu(settingslbls, settingsptrs, "Sample Gain...", "effect_gain", gen_num_menu("effect_gain", 0.0, 0.1, 11));
add_submenu(settingslbls, settingsptrs, "Transition Delay...", "transitiondelay", gen_num_menu("transitiondelay", 5, 5, 10));
add_submenu(settingslbls, settingsptrs, "Autosave...", "autosave", {"On", "Off"}, {On = autosaveupd, Off = autosaveupd}); 
add_submenu(settingslbls, settingsptrs, "Network Remote...", "network_remote", gen_tbl_menu("network_remote", {"Disabled", "Passive", "Active"}, function() end, true))
table.insert(settingslbls, "----");
add_submenu(settingslbls, settingsptrs, "Default View Mode...", "view_mode", gen_tbl_menu("view_mode", {"Grid", "Custom"}, function() end, true));
add_submenu(settingslbls, settingsptrs, "Custom View...", "cview_skip", {"Reset"}, {Reset = reset_customview});
add_submenu(settingslbls, settingsptrs, "Grid View...", "skip", gridviewlbls, gridviewptrs, {});

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

local sortorderptrs = {};

local function sortordercb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.sortlbl = label;
	
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
function gridlemenu_defaultdispatch(dst)
	if (not dst["MENU_UP"]) then
		dst["MENU_UP"] = function(iotbl)
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			current_menu:move_cursor(-1, true); 
		end
	end

	if (not dst["MENU_DOWN"]) then
			dst["MENU_DOWN"] = function(iotbl)
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			current_menu:move_cursor(1, true); 
		end
	end
	
	if (not dst["MENU_SELECT"]) then
		dst["MENU_SELECT"] = function(iotbl)
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
	if (not dst["FLAG_FAVORITE"]) then
		dst["FLAG_FAVORITE"] = function(iotbl)
				selectlbl = current_menu:select();
				if (current_menu.ptrs[selectlbl]) then
					current_menu.ptrs[selectlbl](selectlbl, true);
					if (current_menu and current_menu.updatecb) then
						current_menu.updatecb();
					end
				end
			end
	end
	
	if (not dst["MENU_ESCAPE"]) then
		dst["MENU_ESCAPE"] = function(iotbl, restbl, silent)
			current_menu:destroy();

			if (current_menu.parent ~= nil) then
				if (silent == nil or silent == false) then play_audio(soundmap["SUBMENU_FADE"]); end
				current_menu = current_menu.parent;
			else -- top level
				play_audio(soundmap["MENU_FADE"]);
				dispatch_pop();
			end
		end
	end
	
	if (not dst["MENU_RIGHT"]) then
		dst["MENU_RIGHT"] = dst["MENU_SELECT"];
	end
	
	if (not dst["MENU_LEFT"]) then
		dst["MENU_LEFT"]  = dst["MENU_ESCAPE"];
	end
end

function gridlemenu_filterchanged()
	settings.cursor = 0;
	settings.pageofs = 0;

	erase_grid(false);
	build_grid(settings.cell_width, settings.cell_height);
	move_cursor(1, true);
end

function gridlemenu_settings(cleanup_hook, filter_hook)
-- first, replace all IO handlers
	local imenu = {};
	
	imenu["MENU_ESCAPE"] = function(iotbl, restbl, silent)
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
		cleanup_hook();
		dispatch_pop();

		if (settings.statuslist) then
			settings.statuslist:destroy();
			settings.statuslist = nil;
		end
	end

		init_leds();
	end

	gridlemenu_defaultdispatch(imenu);
	updatebgtrigger = filter_hook;
	
-- hide the cursor and all selected elements
	if (movievid) then
		instant_image_transform(movievid);
		expire_image(movievid, settings.fadedelay);
		blend_image(movievid, 0.0, settings.fadedelay);
		movievid = nil;
	end

-- add an info window
	update_status();
	local props = image_surface_properties(settings.statuslist.border, 5);

	current_menu = listview_create(menulbls, math.floor((VRESH - props.height) * 0.9), VRESW / 3);
	current_menu.ptrs = {};
	current_menu.ptrs["Game Lists..."] = function() menu_spawnmenu( build_gamelists() ); end
	current_menu.ptrs["Filters..."]    = function() menu_spawnmenu( update_filterlist() ); end
	current_menu.ptrs["Settings..."]   = function() menu_spawnmenu( settingslbls, settingsptrs ); end
	current_menu.updatecb = update_status;
	
	current_menu:show();
	dispatch_push(imenu);
	
	move_image(current_menu.anchor, 5, math.floor(props.y + props.height + (VRESH - props.height) * 0.09), settings.fadedelay);
end
