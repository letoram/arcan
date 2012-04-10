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

system_load("scripts/listview.lua")();

function menu_spawnmenu(list, listptr)
	if (#list < 1) then
		return nil;
	end

	local parent = current_menu;
	local props = image_surface_resolve_properties(current_menu.cursorvid);
	local windsize = #list * 24;

	if (props.y + windsize > VRESH) then
		windsize = VRESH - props.y;
	end

	current_menu = listview_create(list, windsize, VRESW / 3);
	current_menu.parent = parent;
	current_menu.ptrs = listptr;

	move_image( current_menu:window_vid(), props.x + props.width + 6, props.y);
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
	"Reconfigure Keys",
	"Reconfigure LEDs",
	"Cell Size",
	"LED display mode",
	"Key Repeat Rate",
	"Fade Delay",
	"Transition Delay",
	"Attract Mode",
	"Inactivity Shutdown"
};

local ledmodelbls = {
	"Disabled",
	"All toggle",
	"Game setting (always on)",
	"Game setting (on push)"
};

local ledmodeptrs = {}
	ledmodeptrs["Disabled"] = function(label, save) 
	settings.iodispatch["MENU_ESCAPE"](); 
	settings.ledmode = 0;
	if (save) then store_key("ledmode", 0); end
end

ledmodeptrs["All toggle"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.ledmode = 1;
	if (save) then store_key("ledmode", 1); end
end

ledmodeptrs["Game setting (always on)"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](); 
	settings.ledmode = 2; 
	if (save) then store_key("ledmode", 2); end
end

ledmodeptrs["Game setting (on push)"] = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](); 
	settings.ledmode = 3; 
	if (save) then store_key("ledmode", 3); end
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
	settings.iodispatch["MENU_ESCAPE"]();
	settings.fadedelay = tonumber(label);
	if (save) then
		store_key("fadedelay", tonumber(label));
	end
end
for ind,val in ipairs(fadedelaylbls) do fadedelayptrs[val] = fadedelaycb; end

local transitiondelayptrs = {}
local function transitiondelaycb(label, save)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.transitiondelay = tonumber(label);
	if (save) then
		store_key("transitiondelay", tonumber(label));
	end
end
for ind,val in ipairs(transitiondelaylbls) do transitiondelayptrs[val] = transitiondelaycb; end

local repeatlbls = { "0", "100", "200", "300", "400", "500"};
local repeatptrs = {};
local function repeatratecb(label, save)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.repeat_rate = tonumber(label);
	if (save) then
		store_key("repeatrate", tonumber(label));
	end
end
for ind,val in ipairs(repeatlbls) do repeatptrs[val] = repeatratecb; end

local gridlbls = { "48x48", "48x64", "64x48", "64x64", "96x64", "64x96", "96x96", "128x96", "96x128", "128x128", "196x128", "128x196", "196x196",
		"196x256", "256x196", "256x256"};
local gridptrs = {};

local function gridcb(label, save)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.cell_width = tonumber( string.sub(label, 1, string.find(label, "x") - 1) );
	settings.cell_height = tonumber( string.sub(label, string.find(label, "x") + 1, -1) );
	if (save) then
		store_key("cell_width", settings.cell_width);
		store_key("cell_height", settings.cell_height);
	end
end
for ind,val in ipairs(gridlbls) do gridptrs[val] = gridcb; end

local sortorderptrs = {};
local function sortordercb(label, save)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.sortlbl = label;
	
	if (save) then
		store_key("sortorder", label);
	end
end
for key, val in ipairs(sortorderlbls) do sortorderptrs[val] = sortordercb; end

local settingsptrs = {};
settingsptrs["Sort Order..."]    = function() menu_spawnmenu(sortorderlbls, sortorderptrs); end
settingsptrs["Reconfigure Keys"] = function()
	zap_resource("keysym.lua");
	gridle_keyconf();
end

settingsptrs["LED display mode"] = function() menu_spawnmenu(ledmodelbls, ledmodeptrs); end
settingsptrs["Key Repeat Rate"]  = function() menu_spawnmenu(repeatlbls, repeatptrs); end
settingsptrs["Reconfigure LEDs"] = function()
	zap_resource("ledsym.lua");
	gridle_ledconf();
end
settingsptrs["Fade Delay"] = function() menu_spawnmenu(fadedelaylbls, fadedelayptrs); end
settingsptrs["Transition Delay"] = function() menu_spawnmenu(transitiondelaylbls, transitiondelayptrs); end

settingsptrs["Cell Size"]        = function() menu_spawnmenu(gridlbls, gridptrs); end
settingsptrs["Repeat Rate"]      = function() menu_spawnmenu(repeatlbls, repeatptrs); end

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
		move_image(settings.statuslist:window_vid(), 5, settings.fadedelay);
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
			settings.iodispatch["MENU_ESCAPE"]();
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
		settings.iodispatch["MENU_ESCAPE"]();
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
			resptr[ res[i] ] = function(lbl) settings.iodispatch["MENU_ESCAPE"](); apply_gamefilter(lbl); settings.filters = {}; end
	end

	return res, resptr;
end

function gridlemenu_settings()
-- first, replace all IO handlers
	griddispatch = settings.iodispatch;

	settings.iodispatch = {};
	settings.iodispatch["MENU_UP"] = function(iotbl) current_menu:move_cursor(-1, true); end
	settings.iodispatch["MENU_DOWN"] = function(iotbl) current_menu:move_cursor(1, true); end
	settings.iodispatch["MENU_ESCAPE"] = function(iotbl)
		current_menu:destroy();
		if (current_menu.parent ~= nil) then
			current_menu = current_menu.parent;
			update_status();
		else -- top level
			if (#settings.games == 0) then
				settings.games = list_games( {} );
			end
			
		table.sort(settings.games, settings.sortfunctions[ settings.sortlbl ]);
			settings.cursor = 0;
			settings.pageofs = 0;
			build_grid(settings.cell_width, settings.cell_height);
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
			end
		end

-- just aliases
	settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];

-- hide the cursor and all selected elements
	erase_grid(false);
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

-- add an info window
	update_status();
	move_image(current_menu:window_vid(), 100, 120, settings.fadedelay);
end
