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

local mainlbls = {
	"Quickfilter",
	"Admin"
}

local filterlbls = {
	"Manufacturer",
	"System",
	"Year",
	"Players",
	"Buttons",
	"Genre"
};

local filterptrs = {};

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

	settings.iodispatch["MENU_ESCAPE"](false, nil, nil);
	settings.iodispatch["MENU_ESCAPE"](false, nil, nil);
	play_audio(soundmap["MENU_FADE"]);

	table.sort(settings.games, settings.sortfunctions[ settings.sortlbl ]);
	settings.cursor = 0;
	settings.pageofs = 0;
	
	erase_grid(false);
	build_grid(settings.cell_width, settings.cell_height);
	move_cursor(1, true);
end

local function gridlemenu_quickfilter(source, target, sound)
	settings.iodispatch["MENU_ESCAPE"](false, nil, nil);
	settings.iodispatch["MENU_ESCAPE"](false, nil, nil);
	
	settings.filters = {};
	settings.filters[source] = current_game()[source];
	settings.games = list_games(settings.filters);
	
	play_audio(soundmap["MENU_FADE"]);
	table.sort(settings.games, settings.sortfunctions[ settings.sortlbl ]);

	settings.cursor = 0;
	settings.pageofs = 0;
			
	erase_grid(false);
	build_grid(settings.cell_width, settings.cell_height);
	move_cursor(1, true);
end

-- change launch mode for this particular game
function gridlemenu_context( gametbl )
	griddispatch = settings.iodispatch;
	settings.iodispatch = {};
	gridle_oldinput = gridle_input;
	gridle_input = gridle_dispatchinput;
	
	gridlemenu_defaultdispatch();

-- we'll resort to the aspect ratio of the cursor_vid() no matter what,
-- if we have a loaded movie though, we'll instance that
	local screenshot = cursor_vid();
	image_pushasynch( screenshot );
	local props = image_surface_properties( screenshot );
	if (valid_vid( imagery.movie )) then screenshot = imagery.movie; end 
	
	screenshot = instance_image( screenshot );
	image_mask_clear( screenshot, MASK_POSITION );
	
-- split the screen in half, resize the current screenshot / movie to fit the rightmost half
	
-- derive the menu based on the current game
	local ptrs = {};
	ptrs["Quickfilter"] = function()
		local gametbl = current_game();
		local restbl = {};
		local resptr = {};
		
		for ind, val in ipairs(filterlbls) do
			local key = string.lower( val );
			if (gametbl[key] and string.len(gametbl[key]) > 0) then
				table.insert(restbl, key);
				resptr[ key ] = gridlemenu_quickfilter;
			end	
		end
	
		local famtbl = game_family( gametbl.gameid );
		if (#famtbl > 0) then
			table.insert(restbl, "family");
			resptr[ "family" ] = gridlemenu_familyfilter;
		end
		
		if (#restbl > 0) then
			menu_spawnmenu(restbl, resptr, {});
		end
	end
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;
	
	current_menu:show();
	move_image(current_menu.anchor, 10, 120, settings.fadedelay);	
end
