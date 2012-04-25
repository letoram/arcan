-- "Dull as dishwater" theme.
-- Written as a sort of minimalistic example,
-- and to see how far I'd get with a theme on a 60-minute time limit ;-)
--
-- Features demonstrated;
-------------------------------------------
-- * text rendering (list on the left)
-- * image drawing (just screenshot)
-- * image generation (selector bar)
-- * movie playback (for games with samples)
-- * resolution independent (for "sensible" resolutions)
-- * world- state manipulation (intro effect)
-- * key configuration
-- * LED- buttons 
-------------------------------------------

local gamelist = {
 vid  = BADID,
 yofs = 40,
 vspace = 6,
 number = 1
};

local data = {
    games = {},
    targets = {}
}

local configkeys = false;
local font_name  = "fonts/default.ttf,14 "; 
local font_name_large = "fonts/default.ttf,96 ";
local curs_dy = 0;
local images = {};
local iodispatch = {};

local function ledconfig_iofun(iotbl)
	local restbl = keyconfig:match(iotbl);

	if (iotbl.active and restbl and restbl[1] and ledconfig:input(restbl[1]) == true) then
			dishwater_input = default_input;
	end
end

local function keyconfig_iofun(iotbl)
	if (keyconfig:input(iotbl) == true) then
		keyconf_tomame(keyconfig, "_mame/cfg/default.cfg");
		ledconfig = ledconf_create( keyconfig:labels() );
		if (ledconfig.active == false) then
			dishwater_input = ledconfig_iofun;
		else -- no LED controller present, or LED configuration already exists
			dishwater_input = default_input;
		end
	end
end


function dishwater()
	system_load("scripts/colourtable.lua")();
	system_load("scripts/keyconf.lua")();
	system_load("scripts/keyconf_mame.lua")();
	system_load("scripts/ledconf.lua")();
	system_load("scripts/resourcefinder.lua")();
	
	local menutbl = {
		"rMENU_ESCAPE",
		"rMENU_UP",
		"rMENU_DOWN",
		"rMENU_SELECT",
		" MENU_RIGHT",
		" MENU_LEFT",
		" MENU_RANDOM"
	};

	clipregion = fill_surface(1,1,0,0,0);
	show_image(clipregion);
	resize_image(clipregion, VRESW * 0.5, VRESH);

	images.selector = fill_surface(VRESW * 0.5, 20, 0, 40, 200);
	link_image(images.selector, clipregion);
	image_clip_on(images.selector);
	image_mask_clear(images.selector, MASK_OPACITY);

	show_image(images.selector);
	order_image(images.selector, 1);

	images.background = load_image("background.png", 0);
	resize_image(images.background, VRESW, VRESH, NOW);
	show_image(images.background);

    data.games = list_games( {} );
	if (#data.games == 0) then
		error("No Games configured, terminating.");
		shutdown();
	end

    local width, height = textdimensions( [[\f]] .. font_name .. [[jJ\n]], font_vspace);
    gamelist.page_size = math.ceil ( (VRESH - 20) / height );
    
    do_menu();
    select_item();

	keyconfig = keyconf_create(menutbl);
	if (keyconfig.active == false) then
		dishwater_input = keyconfig_iofun;
	else
		ledconfig = ledconf_create( keyconfig:labels() );
		if (ledconfig.active == false) then
				dishwater_input = ledconfig_iofun;
		end
	end

    iodispatch["MENU_UP"]         = function(tbl) if tbl.active then next_item(-1); end end
    iodispatch["MENU_DOWN"]       = function(tbl) if tbl.active then next_item(1); end end
    iodispatch["MENU_SELECT"]     = function(tbl) if tbl.active then launch_game(data.games[gamelist.number]); end end
    iodispatch["MENU_RANDOM"]     = function(tbl) if tbl.active then random_item(); end end
    iodispatch["MENU_RIGHT"]      = function(tbl) if tbl.active then next_item(-1 * gamelist.page_size); end end
    iodispatch["MENU_LEFT"]       = function(tbl) if tbl.active then next_item(gamelist.page_size); end end
    iodispatch["MENU_ESCAPE"]     = function(tbl) if tbl.active then shutdown(); end end
end

function textdimensions(str, vspace)
    local teststr, testlines = render_text( str, vspace );
    props = image_surface_properties(teststr);
    delete_image(teststr);
    
    return props.width, props.height;
end

function textwidth(str)
    width, height = textdimensions(str, gamelist.vspace);
    return width;
end

function launch_game(game)
    launch_target(game.title, LAUNCH_EXTERNAL);
end

function random_item()
    gamelist.number = math.random(1, #data.games);
    do_menu();
    select_item();
end

function next_item(step)
    local ngamenumber = gamelist.number + step;

    if (ngamenumber < 1) then
	ngamenumber = #data.games;
    elseif (ngamenumber > #data.games) then
	ngamenumber = 1;
    end

    gamelist.number = ngamenumber;
    do_menu();
-- update LEDs, game selector, screenshot / ovie
    select_item();
end

function calc_page(number, size, limit)
    local page_start = math.floor( (number-1) / size) * size;
    local offset = (number - 1) % size;
    local page_end = page_start + size;
    
    if (page_end > limit) then
	page_end = limit;
    end

    return page_start + 1, offset + 1, page_end;
end

function fit_image(vid)
		resize_image(vid, VRESW * 0.5, 0);
		if (image_surface_properties(vid).height > VRESH) then resize_image(vid, 0, VRESH); end
		local prop = image_surface_properties(vid);

		local dx = VRESW * 0.5 - prop.width;
		local dy = VRESH - prop.height;

		move_image(vid, 0.5 * (VRESW + dx), dy * 0.5,0);
end

function do_menu()
    if (images.menu ~= nil) then
	delete_image(images.menu);
    end

    page_beg, page_ofs, page_end = calc_page(gamelist.number, gamelist.page_size, #data.games);
    
    renderstr = [[\#ffffff\f]] ..font_name;
    for ind = page_beg, page_end do
	tmpname = data.games[ind].title;
	renderstr = renderstr .. tmpname .. [[\n\r]];
    end

    images.menu, images.menu_lines = render_text(renderstr, gamelist.vspace);
	link_image(images.menu, clipregion);
	image_clip_on(images.menu);
	image_mask_clear(images.menu, MASK_SCALE);

    props = image_surface_properties(images.menu);

    order_image(images.menu, 2);
    move_image(images.menu, 20, gamelist.yofs, 0);
    show_image(images.menu);
end

function select_item()
-- clean up any old image (fade it out and then have the engine kill it off) 
local game = data.games[gamelist.number];
	page_beg, page_ofs, page_end = calc_page(gamelist.number, gamelist.page_size, #data.games);

	if (images.gamepic ~= nil) then
		reset_image_transform(images.gamepic);
		blend_image(images.gamepic, 0.0, 30);
		expire_image(images.gamepic, 30);
		images.gamepic = nil;
	end

	if (ledconfig) then	ledconfig:toggle(game.players, game.buttons); end
	
-- line-heights are stored from when we rendered the menu, use that as a LUT for where to draw the selection bar. 
	instant_image_transform(images.selector);
	move_image(images.selector, 0, images.menu_lines[page_ofs] - 2 + gamelist.yofs, 10);
	resize_image(images.selector, textwidth(data.games[ gamelist.number ].title) + 40, 20, 10);
	blend_image(images.selector, 1.0, 10);
	blend_image(images.selector, 0.5, 10);

	local restbl = resourcefinder_search(game, false);
		if (restbl:find_movie()) then
			images.gamepic = load_movie(restbl:find_movie(), 1, function(source, status)
			if (source == images.gamepic) then
				local vid, aid = play_movie(source);
				audio_gain(aid, 0.0);
				audio_gain(aid, 1.0, 80);
				blend_image(source, 1.0, 20);
				fit_image(source);
			end
		end)
	
	elseif (restbl:find_screenshot()) then
		images.gamepic = load_image(restbl:find_screenshot(), 1);
		fit_image(images.gamepic);
		blend_image(images.gamepic, 1.0, 20);
	end
end

function dishwater_show()
	blend_image(WORLDID, 0.0, 0);
	blend_image(WORLDID, 1.0, 150);
end

function default_input( iotbl )
	local restbl = keyconfig:match(iotbl);
	if (restbl) then
		for i,v in pairs(restbl) do
			if (iodispatch[v]) then
				iodispatch[v](iotbl);
			end
		end
	end
end

function dishwater_input( tobl )
	default_input(iotbl)
end
