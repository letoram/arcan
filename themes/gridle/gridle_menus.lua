-- dependencies
system_load("scripts/listview.lua")();

local function spawnmenu(list, listptr)
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
	
local settingslbls = {
	"Sort Order...",
	"Reconfigure Keys",
	"Reconfigure LEDs",
	"Cell Size",
	"Repeat Rate",
	"Fade Delay",
	"Transition Delay"
};

local sortorderlbls = {
	"Ascending",
	"Descending",
	"Times Played",
	"Favorites"
};

local fadedelaylbls = {"5", "10", "20", "40"}
local transitiondelaylbls = {"5", "10", "20", "40"}
local fadedelayptrs = {}
fadedelayptrs["5"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.fadedelay = 5; end
fadedelayptrs["10"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.fadedelay = 10; end
fadedelayptrs["20"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.fadedelay = 20; end
fadedelayptrs["40"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.fadedelay = 40; end

local transitiondelayptrs = {}
transitiondelayptrs ["5"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.transitiondelay = 5; end
transitiondelayptrs ["10"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.transitiondelay= 10; end
transitiondelayptrs ["20"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.transitiondelay= 20; end
transitiondelayptrs ["40"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.transitiondelay= 40; end

local repeatlbls = { "Disable", "100", "200", "300", "400", "500"};
local repeatptrs = {};
repeatptrs["Disable"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 0; kbd_repeat(settings.repeat_rate); end
repeatptrs["100"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 100; kbd_repeat(settings.repeat_rate); end
repeatptrs["200"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 200; kbd_repeat(settings.repeat_rate); end
repeatptrs["300"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 300; kbd_repeat(settings.repeat_rate); end
repeatptrs["400"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 400; kbd_repeat(settings.repeat_rate); end
repeatptrs["500"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.repeat_rate = 500; kbd_repeat(settings.repeat_rate); end

local gridlbls = { "48x48", "48x64", "64x48", "64x64", "96x64", "64x96", "96x96", "128x96", "96x128", "128x128", "196x128", "128x196", "196x196",
		"196x256", "256x196", "256x256"};
local gridptrs = {};

gridptrs["48x48"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 48; settings.cell_height= 48; end
gridptrs["48x64"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 48; settings.cell_height = 64; end
gridptrs["64x48"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 64; settings.cell_height = 48; end
gridptrs["64x64"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 64; settings.cell_height = 64; end
gridptrs["96x64"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 96; settings.cell_height = 64; end
gridptrs["64x96"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 64; settings.cell_height = 96; end
gridptrs["96x96"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 96; settings.cell_height = 96; end
gridptrs["96x128"]  = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 96; settings.cell_height = 128; end
gridptrs["128x96"]  = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 128; settings.cell_height = 96; end
gridptrs["128x128"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 128; settings.cell_height = 128; end
gridptrs["196x128"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 196; settings.cell_height = 128; end
gridptrs["128x196"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 128; settings.cell_height = 196; end
gridptrs["196x196"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 196; settings.cell_height = 196; end
gridptrs["256x196"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 256; settings.cell_height = 196; end
gridptrs["196x256"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 196; settings.cell_height = 256; end
gridptrs["256x256"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.cell_width = 256; settings.cell_height = 256; end

local sortorderptrs = {};
sortorderptrs["Ascending"]    = function() settings.iodispatch["MENU_ESCAPE"](); settings.sortlbl = "Ascending"; end
sortorderptrs["Descending"]   = function() settings.iodispatch["MENU_ESCAPE"](); settings.sortlbl = "Descending"; end
sortorderptrs["Times Played"] = function() settings.iodispatch["MENU_ESCAPE"](); settings.sortlbl = "Times Played"; end
sortorderptrs["Favorites"]    = function() settings.iodispatch["MENU_ESCAPE"](); settings.sortlbl = "Favorites"; end

local settingsptrs = {};
settingsptrs["Sort Order..."]    = function() spawnmenu(sortorderlbls, sortorderptrs); end
settingsptrs["Reconfigure Keys"] = function()
	zap_resource("keysym.lua");
	gridle_keyconf();
end
settingsptrs["Reconfigure LEDs"] = function()
	zap_resource("ledsym.lua");
	gridle_ledconf();
end
settingsptrs["Fade Delay"] = function() spawnmenu(fadedelaylbls, fadedelayptrs); end
settingsptrs["Transition Delay"] = function() spawnmenu(transitiondelaylbls, transitiondelayptrs); end

settingsptrs["Cell Size"]        = function() spawnmenu(gridlbls, gridptrs); end
settingsptrs["Repeat Rate"]      = function() spawnmenu(repeatlbls, repeatptrs); end

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
		filterresptr[filterlbl] = function(lbl) spawnmenu( get_unique(settings.games, string.lower(lbl)) ); end
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
	end

-- figure out if we should modify the settings table
	settings.iodispatch["MENU_SELECT"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl);
				update_status();
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

	parent_menu = nil;
	current_menu = listview_create(menulbls, #menulbls * 24, VRESW / 3);
	current_menu.ptrs = {};
	current_menu.ptrs["Game Lists..."] = function() spawnmenu( build_gamelists() ); end
	current_menu.ptrs["Filters..."]    = function() spawnmenu( update_filterlist() ); end
	current_menu.ptrs["Settings..."]   = function() spawnmenu( settingslbls, settingsptrs ); end

-- add an info window
	update_status();
	move_image(current_menu:window_vid(), 100, 120, settings.fadedelay);
end
