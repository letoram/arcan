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

function dishwater()
    local keyfun = system_load("scripts/keyconf.lua");
    keyconf = keyfun();

    images.selector = fill_surface(VRESW * 0.5, 20, 0, 40, 200);
    show_image(images.selector);
    order_image(images.selector, 1);

    images.background = load_image("background.png", 0);
    resize_image(images.background, VRESW, VRESH, NOW);
	show_image(images.background);

    data.targets = list_targets();

    if (#data.targets == 0) then
	error "No targets found";
	shutdown(); 
    end

    data.games = list_games( {} );
    local width, height = textdimensions( [[\f]] .. font_name .. [[jJ\n]], font_vspace);

    gamelist.page_size = math.ceil ( (VRESH - 20) / height );
    
    do_menu();
    select_item();

    iodispatch["CURSOR_Y"]    = 
    function(tbl) 
	local dy = 0;
	
	if (tbl.relative) then
	    dy = tbl.samples[2];
	else
	    dy = tbl.samples[1] / 65535 * 20;
	end
	
	curs_dy = curs_dy + dy;
	if (curs_dy > 20) then
	    curs_dy = 0;
	    next_item(1);
	elseif (curs_dy < -20) then
	    curs_dy = 0;
	    next_item(-1);
	end
    end
    iodispatch["MENU_UP"]     = function(tbl) if tbl.active then next_item(-1); end end
    iodispatch["MENU_DOWN"]   = function(tbl) if tbl.active then next_item(1); end end
    iodispatch["MENU_SELECT"] = function(tbl) if tbl.active then launch_game(data.games[gamelist.number]); end end
    iodispatch["PLAYER1_BUTTON1"] = function(tbl) if tbl.active then random_item(); end end
    iodispatch["MENU_LEFT"]   = function(tbl) if tbl.active then next_item(-1 * gamelist.page_size); end end
    iodispatch["MENU_RIGHT"]  = function(tbl) if tbl.active then next_item(gamelist.page_size); end end
    iodispatch["MENU_ESCAPE"] = function(tbl) if tbl.active then shutdown(); end end
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

-- line-heights are stored from when we rendered the menu, use that as a LUT for where to draw the selection bar. 
    instant_image_transform(images.selector);
    move_image(images.selector, 0, images.menu_lines[page_ofs] - 2 + gamelist.yofs, 10);
    resize_image(images.selector, textwidth(data.games[ gamelist.number ].title) + 40, 20, 10);
    blend_image(images.selector, 1.0, 10);
    blend_image(images.selector, 0.5, 10);

-- grab a reference to the current game data
    local fn  = "movies/" .. game.setname .. ".avi";
    local fn2 = "screenshots/" .. game.setname .. ".png";

-- try to find a matching movie or screenshot .. 
    if (resource(fn) ~= nil) then
        images.gamepic, aid = load_movie(fn);
        if (images.gamepic) then 
    	    play_movie(images.gamepic);
	end
    end
    
    if (images.gamepic == nil and resource(fn2) ~= nil) then
        images.gamepic = load_image(fn2, 1);
    end

-- last fallback, just render a string with the setname (so the user knows which screenshot to fix)
    if (images.gamepic == nil) then
        images.gamepic, skip = render_text([[\f]] .. font_name_large .. game.setname, 0);
	end

    props = image_surface_properties(images.gamepic);
    local neww = 0;
    local newh = 0;

    if (props.width > props.height) then
        neww, newh = resize_image(images.gamepic, VRESW * 0.5, 0, 0);
    else
        neww, newh = resize_image(images.gamepic, 0, VRESH, 0);
    end

    blend_image(images.gamepic, 1.0, 20);
    move_image(images.gamepic, VRESW - neww, (VRESH - newh) * 0.5, 0);
end

------ Event Handlers ----------

function dishwater_on_show()
	blend_image(WORLDID, 0.0, 0);
	move_image(WORLDID, VRESW / 2, VRESH / 2, 0);
	move_image(WORLDID, 0, 0, 150);
	blend_image(WORLDID, 1.0, 150);
	rotate_image(WORLDID, 180, 0);
	rotate_image(WORLDID, 0, 150);

    if (keyconf.match("MENU_ESCAPE") == nil) then
		keyconf.new(1, nil, nil); -- 1 player, use default labels / options
		configkeys = true;
    end
end

function dishwater_input( iotbl )	
-- input- keys 
	if (configkeys) then
		if (keyconf.input( iotbl ) ) then
			return;
		else
			keyconf.save();
			configkeys = false;
		end
	end

    local restbl = keyconf.match( iotbl );
    if (restbl == nil) then
	return false;
    end
    
    for i,v in pairs(restbl) do 
	if (iodispatch[v]) then
	    iodispatch[v](iotbl);
	end
    end
end
