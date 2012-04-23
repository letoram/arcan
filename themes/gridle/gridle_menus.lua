-- this one is just a mess of tables, all mapping to a
-- global settings structure, nothing really interesting

-- theme storage keys used:
--  ledmode => settings.ledmode
--  transitiondelay => settings.transitiondelay
--  fadedelay => settings.fadedelay
--  repeatrate => settings.repeatrate
--  cell_width => settings.cell_width
--  cell_height => settings.cell_height
--  sortorder => settings.sortlbl
-- 

function menu_spawnmenu(list, listptr, fmtlist)
	if (#list < 1) then
		return nil;
	end

	local parent = current_menu;
	local props = image_surface_resolve_properties(current_menu.cursorvid);
	local windsize = #list * 24;

	if (props.y + windsize > VRESH) then
		windsize = VRESH - props.y;
	end

	current_menu = listview_create(list, windsize, VRESW / 3, fmtlist);
	current_menu.parent = parent;
	current_menu.ptrs = listptr;
	current_menu:show();
	
	play_audio(soundmap["SUBMENU_TOGGLE"]);
	move_image( current_menu.anchor, props.x + props.width + 6, props.y);
	return current_menu;
end

-- static menu entries
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
	"Target"
};

local attractlbls = {
	"Disabled",
	"1 Min",
	"5 Min",
	"10 Min",
	"15 Min"
};

local inactivitylbls = {
	"Disabled",
	"5 Min",
	"10 Min",
	"15 Min",
	"30 Min",
	"1 Hour"
};

local settingslbls = {
	"Sort Order...",
	"Cell Size...",
	"LED display mode...",
	"Key Repeat Rate...",
	"Fade Delay...",
	"Transition Delay...",
	"Inactivity Shutdown...",
	"Reconfigure Keys",
	"Reconfigure LEDs",
};

local ledmodelbls = {
	"Disabled",
	"All toggle",
	"Game setting (always on)",
	"Game setting (on push)"
};

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

local fadedelaylbls = {"5", "10", "20", "40"}
local transitiondelaylbls = {"5", "10", "20", "40"}
local fadedelayptrs = {}

local function fadedelaycb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.fadedelay = tonumber(label);
	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);
		store_key("fadedelay", tonumber(label));
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end
for ind,val in ipairs(fadedelaylbls) do fadedelayptrs[val] = fadedelaycb; end

local transitiondelayptrs = {}
local function transitiondelaycb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.transitiondelay = tonumber(label);
	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);
		store_key("transitiondelay", tonumber(label));
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end
for ind,val in ipairs(transitiondelaylbls) do transitiondelayptrs[val] = transitiondelaycb; end

local repeatlbls = { "0", "100", "200", "300", "400", "500"};
local repeatptrs = {};
local function repeatratecb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.repeat_rate = tonumber(label);
	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);
		store_key("repeatrate", tonumber(label));
	else
		play_audio(soundmap["MENU_SELECT"]);	
	end
end
for ind,val in ipairs(repeatlbls) do repeatptrs[val] = repeatratecb; end

local gridlbls = { "48x48", "48x64", "64x48", "64x64", "96x64", "64x96", "96x96", "128x96", "96x128", "128x128", "196x128", "128x196", "196x196",
		"196x256", "256x196", "256x256"};
local gridptrs = {};

local function gridcb(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.cell_width = tonumber( string.sub(label, 1, string.find(label, "x") - 1) );
	settings.cell_height = tonumber( string.sub(label, string.find(label, "x") + 1, -1) );
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
	
	local node = current_menu;
	while (node.parent) do node = node.parent; end
	node.gamecount = -1;
	
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
local settingsptrs = {};
settingsptrs["Sort Order..."]    = function() 
	local fmts = {};
	fmts[ settings.sortlbl ] = settings.colourtable.notice_fontstr;
	if ( get_key("sortorder") ) then
		fmts[ get_key("sortorder") ] = settings.colourtable.alert_fontstr; 
	end
	menu_spawnmenu(sortorderlbls, sortorderptrs, fmts); 
end

settingsptrs["Reconfigure Keys"] = function()
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

settingsptrs["Key Repeat Rate..."]  = function() 
	local fmts = {};

	fmts[ tostring( settings.repeat_rate) ] = settings.colourtable.notice_fontstr;
	if (get_key("repeatrate")) then
		fmts[ get_key("repeatrate") ] = settings.colourtable.alert_fontstr;
	end
	
	menu_spawnmenu(repeatlbls, repeatptrs, fmts); 
end

settingsptrs["Reconfigure LEDs"] = function()
	zap_resource("ledsym.lua");
	gridle_ledconf();
end
settingsptrs["Fade Delay..."] = function() 
	local fmts = {};
	fmts[ tostring( settings.fadedelay ) ] =  settings.colourtable.notice_fontstr;
	if (get_key("fadedelay")) then
		fmts[ get_key("fadedelay") ] = settings.colourtable.alert_fontstr;
	end
	
	menu_spawnmenu(fadedelaylbls, fadedelayptrs, fmts); 
end

settingsptrs["Transition Delay..."] = function() 
	local fmts = {};
	fmts[ tostring( settings.transitiondelay ) ] = settings.colourtable.notice_fontstr;
	if (get_key("transitiondelay")) then
		fmts[ get_key("transitiondelay") ] = settings.colourtable.alert_fontstr;
	end

	menu_spawnmenu(transitiondelaylbls, transitiondelayptrs, fmts); 
end

settingsptrs["Cell Size..."] = function()
	local fmts = {};
	fmts[ tostring(settings.cell_width) .. "x" .. tostring(settings.cell_height) ] = settings.colourtable.notice_fontstr;
	if (get_key("cell_width") and get_key("cell_height")) then
		fmts[ get_key("cell_width") .. "x" .. get_key("cell_height") ] = settings.colourtable.alert_fontstr;
	end

	menu_spawnmenu(gridlbls, gridptrs, fmts); 
end

settingsptrs["Repeat Rate..."]      = function() menu_spawnmenu(repeatlbls, repeatptrs); end

local function update_status()
-- show # games currently in list, current filter or gamelist

	list = {};
	table.insert(list, "# games: " .. tostring(#settings.games));
	table.insert(list, "grid dimensions: " .. settings.cell_width .. "x" .. settings.cell_height);
	table.insert(list, "sort order: " .. settings.sortlbl);
	table.insert(list, "repeat rate: " .. settings.repeat_rate);
	
	filterstr = "filters: ";
	if (settings.filters.title)   then filterstr = filterstr .. " title("    .. settings.filters.title .. ")"; end
	if (settings.filters.genre)   then filterstr = filterstr .. " genre("    .. settings.filters.genre .. ")"; end
	if (settings.filters.subgenre)then filterstr = filterstr .. " subgenre(" .. settings.filters.subgenre .. ")"; end
	if (settings.filters.target)  then filterstr = filterstr .. " target("   .. settings.filters.target .. ")"; end
	if (settings.filters.year)    then filterstr = filterstr .. " year("     .. tostring(settings.filters.year) .. ")"; end
	if (settings.filters.players) then filterstr = filterstr .. " players("  .. tostring(settings.filters.players) .. ")"; end
	if (settings.filters.buttons) then filterstr = filterstr .. " buttons("  .. tostring(settings.filters.buttons) .. ")"; end

	table.insert(list, filterstr);
	if (settings.statuslist == nil) then
		settings.statuslist = listview_create(list, 24 * 5, VRESW * 0.75);
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

function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function apply_gamefilter(listname)
	local reslist = {};
	local filter = {};

	open_rawresource("./lists/" .. listname .. ".txt");
	line = read_rawresource();
-- linear search, blergh.
		while (line) do
			filter["title"] = line;
			local dblookup = list_games( filter )
			if #dblookup > 0 then
				table.insert(reslist, dblookup[1]);
			end
			line = read_rawresource();
		end
	close_rawresource();

	settings.games = reslist;
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

function gridlemenu_settings()
-- first, replace all IO handlers
	griddispatch = settings.iodispatch;

	settings.iodispatch = {};
	settings.iodispatch["MENU_UP"] = function(iotbl) play_audio(soundmap["MENUCURSOR_MOVE"]); current_menu:move_cursor(-1, true); end
	settings.iodispatch["MENU_DOWN"] = function(iotbl) play_audio(soundmap["MENUCURSOR_MOVE"]); current_menu:move_cursor(1, true); end
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
			settings.cursor = 0;
			settings.pageofs = 0;
			
			if (current_menu.gamecount ~= #settings.games) then
				erase_grid(false);
				build_grid(settings.cell_width, settings.cell_height);
				move_cursor(1, true);
			end
			
			settings.iodispatch = griddispatch;
			if (settings.statuslist) then
				settings.statuslist:destroy();
				settings.statuslist = nil;
			end
		end

		init_leds();
	end

-- figure out if we should modify the settings table
	settings.iodispatch["MENU_SELECT"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, false);
				update_status();
			end
		end

	settings.iodispatch["FLAG_FAVORITE"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, true);
				update_status();
			end
		end

-- just aliases
	settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];

-- hide the cursor and all selected elements
	if (movievid) then
		instant_image_transform(movievid);
		expire_image(movievid, settings.fadedelay);
		blend_image(movievid, 0.0, settings.fadedelay);
		movievid = nil;
	end

	current_menu = listview_create(menulbls, #menulbls * 24, VRESW / 3);
	current_menu.ptrs = {};
	current_menu.ptrs["Game Lists..."] = function() menu_spawnmenu( build_gamelists() ); end
	current_menu.ptrs["Filters..."]    = function() menu_spawnmenu( update_filterlist() ); end
	current_menu.ptrs["Settings..."]   = function() menu_spawnmenu( settingslbls, settingsptrs ); end

	current_menu.gamecount = #settings.games;
	current_menu:show();
	
-- add an info window
	update_status();
	move_image(current_menu.anchor, 100, 140, settings.fadedelay);
end
