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
	settings.iodispatch["MENU_ESCAPE"](false, nil, true); 
	settings.iodispatch["MENU_ESCAPE"](false, nil, true); 
	gridle_launchexternal(); 
end

launchptrs["Internal"] = function() 
	settings.iodispatch["MENU_ESCAPE"](false, nil, true); 
	settings.iodispatch["MENU_ESCAPE"](false, nil, true);
	gridle_launchinternal(); 
end

local filterptrs = {};

local function dofilter()
	settings.iodispatch["MENU_ESCAPE"](false, nil, true);
	settings.iodispatch["MENU_ESCAPE"](false, nil, true);

	table.sort(settings.games, settings.sortfunctions[ settings.sortlbl ]);
	gridlemenu_filterchanged();
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
	local mainlbls = {"Quickfilter"};
	
	griddispatch = settings.iodispatch;
	settings.iodispatch = {};
	gridle_oldinput = gridle_input;
	gridle_input = gridle_dispatchinput;
	
	gridlemenu_defaultdispatch();

-- we'll resort to the aspect ratio of the cursor_vid() no matter what,
-- if we have a loaded movie though, we'll instance that
	imagery.zoomed = cursor_vid();
	image_pushasynch( imagery.zoomed ); 

	if (valid_vid( imagery.movie )) then 
		imagery.zoomed = imagery.movie; 
	end 

	imagery.zoomed = instance_image( imagery.zoomed );
	image_mask_clear( imagery.zoomed, MASK_POSITION );
	gridlemenu_setzoom( imagery.zoomed, imagery.zoomed );
	
-- split the screen in half, resize the current screenshot / movie to fit the rightmost half

-- derive the menu based on the current game
	local ptrs = {};
	ptrs["Quickfilter"] = function()
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

	parent_escapefun = settings.iodispatch["MENU_ESCAPE"];
	settings.iodispatch["MENU_ESCAPE"] = function(key, store, silent)
		if (current_menu.parent == nil) then
			blend_image(imagery.zoomed, 0.0, settings.fadedelay);
			expire_image(imagery.zoomed, settings.fadedelay);
			imagery.zoomed = BADID;
		end
		parent_escapefun(key, store, silent);
	end
	settings.iodispatch["MENU_LEFT"] = settings.iodispatch["MENU_ESCAPE"];

	if (gametbl.capabilities) then
		if (gametbl.capabilities.external_launch and gametbl.capabilities.internal_launch) then
			table.insert(mainlbls, "Launch...");
			ptrs[ "Launch..." ] = function() menu_spawnmenu(launchlbls, launchptrs, {}); end
		elseif (gametbl.capabilities.external_launch) then 
			table.insert(mainlbls, "Launch External");
			ptrs[ "Launch External" ] = function() settings.iodispatch["MENU_ESCAPE"](false, nil, true); gridle_launchexternal(); end 
		else
			table.insert(mainlbls, "Launch Internal");
			ptrs[ "Launch Internal" ] = function() settings.iodispatch["MENU_ESCAPE"](false, nil, true); gridle_launchinternal(); end
		end
	end

	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;
	
	current_menu:show();
	move_image(current_menu.anchor, 10, 120, settings.fadedelay);	
end
