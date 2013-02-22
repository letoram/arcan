-- grid- view specific context menus
-- 
-- same as with gridle_intmenus and gridle_menus
-- just patching dispatchinput, a lot of string/functiontbls and calls to
-- spawn_menu. 
--
--
-- Filter 
-- Launch Mode
-- Admin
--

local filterlbls = {
	"Manufacturer",
	"System",
	"Year",
	"Players",
	"Buttons",
	"Genre"
};

local launchlbls = {
	"External",
	"Internal"
};

local launchptrs = {};
launchptrs["External"] = function()
	settings.iodispatch["MENU_ESCAPE"](false, nil, false); 
	settings.iodispatch["MENU_ESCAPE"](false, nil, true); 
	gridle_launchexternal(); 
end

launchptrs["Internal"] = function() 
	settings.iodispatch["MENU_ESCAPE"](false, nil, false); 
	settings.iodispatch["MENU_ESCAPE"](false, nil, true);
	gridle_launchinternal(); 
end

local filterptrs = {};

local function dofilter()
	settings.iodispatch["MENU_ESCAPE"](false, nil, false);
	settings.iodispatch["MENU_ESCAPE"](false, nil, true);

	table.sort(settings.games, settings.sortfunctions[ settings.sortorder ]);
	gridlemenu_filterchanged();
end

local function update_status()
-- show # games currently in list, current filter or gamelist

	list = {};
	table.insert(list, "# Games: " .. tostring(#settings.games));
	table.insert(list, "Sort Order: " .. settings.sortorder);
	
	filterstr = "Filters: ";
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
		settings.statuslist:invalidate();
		settings.statuslist:redraw();
	end
end

local function build_gamelists()
	local lists = glob_resource("lists/*.txt", THEME_RESOURCE);
	local res = {};
	local resptr = {};

	for i=1, #lists do
			res[i] = string.sub(lists[i], 1, -5);
			resptr[ res[i] ] = function(lbl) settings.iodispatch["MENU_ESCAPE"](nil, nil, false); apply_gamefilter(lbl); settings.filters = {}; end
	end

	return res, resptr;
end

-- we know there's a family list available with 1..n titles where n >= 1.
local function gridlemenu_familyfilter(source, target, sound)
	namelist = game_family( current_game().gameid );
	settings.games = {};
	settings.filters = {};
	
	for ind, val in ipairs(namelist) do
		local filter = {};
		filter["title"] = val;
		
		local dblookup = list_games( filter )
		for dind, dval in ipairs(dblookup) do
			table.insert(settings.games, dval);
		end
	end

	dofilter(); 
end

local function gridlemenu_resetfilter(source, target, sound)
	settings.filters = {};
	settings.games = list_games(settings.filters);
	dofilter();
end

local function gridlemenu_quickfilter(source, target, sound)
	local filters = {};
	filters[source] = current_game()[source];

	local gl = list_games(filters);
	if (gl == nil) then
		settings.games = list_games(settings.filters);
	else
		settings.games = gl;
		settings.filters = filters;
	end
	
	dofilter();
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
			settings.filters[string.lower(current_menu:select())] = lbl;
			settings.games = list_games(settings.filters);
			update_status();
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

function gridlemenu_setzoom( source, reference )
	local props = image_surface_initial_properties( reference );
	local desw = 0.5 * VRESW;
	local ar = props.width / props.height;
	local endh;
	local endw;
	
	if (ar > 1.0) then
		endw = desw;
		endh = endw / ar;
	else
		endh = desw / ar;
		endw = endh * ar;
	end
	
	resize_image(source, endw, endh, 20);
	move_image(source, desw + 0.5 * (desw - endw), 0.5 * (VRESH - endh), settings.transitiondelay);
	blend_image(source, 1.0, settings.transitiondelay);
	order_image(source, max_current_image_order());
end

-- change launch mode for this particular game
function gridlemenu_context( gametbl )
	local mainlbls = {"Game Lists...", "Filters...", "Quickfilter..."};
	
	local itbl = {};

-- split the screen in half, resize the current screenshot / movie to fit the rightmost half

-- derive the menu based on the current game
	local ptrs = {};
	ptrs["Quickfilter..."] = function()
		local gametbl = current_game();
		local restbl = {};
		local resptr = {};
		
		for ind, val in ipairs(filterlbls) do
			local key = string.lower( val );
			if (gametbl[key] and string.len(gametbl[key]) > 0) and
				(key ~= "year" or tonumber(gametbl[key]) > 0) then
				table.insert(restbl, key);
				resptr[ key ] = gridlemenu_quickfilter;
			end	
		end
	
		local famtbl = game_family( gametbl.gameid );
		if (#famtbl > 0) then
			table.insert(restbl, "family");
			resptr[ "family" ] = gridlemenu_familyfilter;
		end
	
		table.insert(restbl, "reset");
		resptr[ "reset" ] = gridlemenu_resetfilter;
		
		menu_spawnmenu(restbl, resptr, {});
	end

	itbl["MENU_ESCAPE"] = function(key, store, silent)
		current_menu:destroy();
		if (current_menu.background) then
			expire_image(current_menu.background, settings.fadedelay);
			blend_image(current_menu.background, 0.0, settings.fadedelay);
			current_menu.background = nil;
		end
		
		if (current_menu.parent == nil) then
			blend_image(imagery.zoomed, 0.0, settings.fadedelay);
			expire_image(imagery.zoomed, settings.fadedelay);
			imagery.zoomed = BADID;
		
			if (settings.statuslist) then
				settings.statuslist:destroy();
				current_menu.updatecb = false;
				settings.statuslist = nil;
			end
		
			if (silent == nil or silent == false) then
				play_audio(soundmap["MENU_FADE"]);
			end
			dispatch_pop();
		else
			current_menu = current_menu.parent;
			if (silent == nil or silent == false) then
				play_audio(soundmap["SUBMENU_FADE"]);
			end
		end
		
	end

	if (gametbl.capabilities) then
		if (gametbl.capabilities.external_launch and gametbl.capabilities.internal_launch) then
			table.insert(mainlbls, "Launch...");
			ptrs[ "Launch..." ] = function() menu_spawnmenu(launchlbls, launchptrs, {}); end
		elseif (gametbl.capabilities.external_launch) then 
			table.insert(mainlbls, "Launch External");
			ptrs[ "Launch External" ] = function()
				settings.iodispatch["MENU_ESCAPE"](false, nil, false);
				gridle_launchexternal();
		end
		else
			table.insert(mainlbls, "Launch Internal");
			ptrs[ "Launch Internal" ] = function()
				settings.iodispatch["MENU_ESCAPE"](false, nil, false);
				gridle_launchinternal();
			end
		end
	end

	ptrs["Game Lists..."] = function() menu_spawnmenu( build_gamelists() ); end
	ptrs["Filters..."]    = function() menu_spawnmenu( update_filterlist() ); end

	add_submenu(mainlbls, ptrs, "Sort Order...", "sortorder", 
		gen_tbl_menu("sortorder", {"Ascending", "Descending", "Times Played", "Favorites"}, update_status,  true));

	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;

	current_menu.background = fill_surface(VRESW, VRESH, 0, 0, 0);
	blend_image(current_menu.background, 0.8, settings.transitiondelay);
	order_image(current_menu.background, max_current_image_order() + 1);
	
	imagery.zoomed = cursor_vid();
	image_pushasynch( imagery.zoomed ); 

	if (valid_vid( imagery.movie )) then 
		imagery.zoomed = imagery.movie; 
	end 

	imagery.zoomed = instance_image( imagery.zoomed );
	image_mask_clear( imagery.zoomed, MASK_POSITION );
	gridlemenu_setzoom( imagery.zoomed, imagery.zoomed );

	update_status();
	local props = image_surface_properties(settings.statuslist.border, 5);

	gridlemenu_defaultdispatch(itbl);
	dispatch_push(itbl, "context_menu");
	current_menu:show();

	move_image(current_menu.anchor, 5, math.floor(props.y + props.height + (VRESH - props.height) * 0.09), settings.fadedelay);
end
