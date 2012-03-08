
grid = {};

imagery = { 
 zoomed = BADID;
};

settings = {
	filters = {
	},

	cursor_timer = 0,
	
	sortlbl = "Ascending",
	iodispatch = {},

	fadedelay = 10,
	transitiondelay = 30,
	
	vspacing = 4,
	hspacing = 4,
	cursor   = 0,
	cellcount= 0,
	pageofs  = 0,

	favorites = {},
	detailvids = {},
	favvids = {},
	
	repeat_rate = 250,
	celll_width = 48,
	cell_height = 48
};

settings.sortfunctions = {};
settings.sortfunctions["Ascending"]    = function(a,b) return string.lower(a.title) < string.lower(b.title) end 
settings.sortfunctions["Descending"]   = function(a,b) return string.lower(a.title) > string.lower(b.title) end
settings.sortfunctions["Times Played"] = function(a,b) return a.launch_counter > b.launch_counter end 
settings.sortfunctions["Favorites"]    = function(a,b) 
	local af = settings.favorites[a.title];
	local bf = settings.favorites[b.title];
	if (af and not bf) then
		return true
	elseif (bf and not af) then
		return false
	else
		return string.lower(a.title) < string.lower(b.title);
	end
end

function gridle_keyconf()
	local keylabels = {
        "rMENU_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP",
        "rMENU_DOWN", "rMENU_SELECT", " ZOOM_CURSOR", "rMENU_TOGGLE", " DETAIL_VIEW", " FLAG_FAVORITE",
		" OSD_KEYBOARD", "ACURSOR_X", "ACURSOR_Y"};

	if (INTERNALMODE ~= "NO SUPPORT") then table.insert(keylabels, " LAUNCH_INTERNAL"); end
	
    keyconfig = keyconf_create(1, keylabels);
    keyconfig.iofun = gridle_input;
	if (keyconfig.active == false) then
		gridle_input = function(iotbl) -- keyconfig io function hook
			if (keyconfig:input(iotbl) == true) then
				keyconf_tomame(keyconfig, "_mame/cfg/default.cfg");

				ledconfig = ledconf_create( keyconfig:labels() );
				if (ledconfig.active == false) then
					gridle_input = ledconfig_iofun;
				else -- no LED controller present, or LED configuration already exists
					gridle_input = keyconfig.iofun;
				end
			end
		end
	end
end

function gridle_ledconf()
	ledconfig = ledconf_create(keyconfig:labels() );
	if (ledconfig.active == false) then
		gridle_input = function(iotbl)
			local restbl = keyconfig:match(iotbl);

			if (iotbl.active and restbl and restbl[1] and
				ledconfig:input(restbl[1]) == true) then
				gridle_input = keyconfig.iofun;
			end
		end
	end
end	

function current_game()
	return settings.games[settings.cursor + settings.pageofs + 1];
end

function table.find(table, label)
	for a,b in pairs(table) do
		if (b == label) then return a end
	end

	return nil;  
end

function spawn_magnify( src )
	local vid = instance_image(magnifyimage);
	local w = settings.cell_width * 0.1;
	local h = settings.cell_height * 0.1;
	
	image_mask_clear(vid, MASK_SCALE);
	image_mask_clear(vid, MASK_OPACITY);
	force_image_blend(vid);

	local props = image_surface_properties( src );
	move_image(vid, props.x - (settings.cell_width * 0.05) + w + 4, props.y + (settings.cell_width * 0.05), 0);
	order_image(vid, 4);
	blend_image(vid, 1.0, settings.fadedelay);
	resize_image(vid, 1, 1, NOW);
	resize_image(vid, w, h, 10);
	table.insert(settings.detailvids, vid);
	
	return vid;
end

function spawn_favoritestar( src )
	local vid = instance_image(starimage);
	image_mask_clear(vid, MASK_SCALE);
	image_mask_clear(vid, MASK_OPACITY);
	force_image_blend(vid);

	local props = image_surface_properties( src );
	move_image(vid, props.x - (settings.cell_width * 0.05), props.y - (settings.cell_width * 0.05), 0);
	order_image(vid, 4);
	blend_image(vid, 1.0, settings.fadedelay);
	resize_image(vid, 1, 1, NOW);
	resize_image(vid, settings.cell_width * 0.1, settings.cell_height * 0.1, 10);
	table.insert(settings.favvids, vid);
	return vid;
end

-- Hide and remap the OSD Keyboard, and if there's a filter msg, apply that one
-- alongside other filters and user-set sort order
function osdkbd_filter(msg)
	osdkbd:hide();
	gridle_input = settings.inputfun;
	
	if (msg ~= nil) then
		local titlecpy = settings.filters.title;
		settings.filters.title = msg;
		local gamelist = list_games( settings.filters );

		if (#gamelist > 0) then
			settings.games = gamelist;
		
			if (settings.sortfunctions[settings.sortlbl]) then
				table.sort(settings.games, settings.sortfunctions[settings.sortlbl]);
			end

			erase_grid(false);
			build_grid(settings.cell_width, settings.cell_height);
		end
	end
end

function gridle()
    system_load("scripts/keyconf.lua")();
    system_load("scripts/keyconf_mame.lua")();
    system_load("scripts/ledconf.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/osdkbd.lua")();
    system_load("gridle_menus.lua")();
	system_load("gridle_detail.lua")();

	pixelate_shader = load_shader("shaders/diffuse_only.vShader", "shaders/pixelate.fShader", "pixelate");
	shader_uniform(pixelate_shader, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(pixelate_shader, "pixelw", "f", PERSIST, 15);
	shader_uniform(pixelate_shader, "pixelh", "f", PERSIST, 15);
	shader_uniform(pixelate_shader, "targetw", "f", PERSIST, VRESW);
	shader_uniform(pixelate_shader, "targeth", "f", PERSIST, VRESH);
	
	video_3dorder(ORDER_LAST);
	
-- make sure that the engine API version and the version this theme was tested for, align.
	if (API_VERSION_MAJOR ~= 0 and API_VERSION_MINOR ~= 4) then
		msg = "Engine/Script API version match, expected 0.4, got " .. API_VERSION_MAJOR .. "." .. API_VERSION_MINOR;
		error(msg);
		shutdown();
	end

	load_settings();
	local bgshader = load_shader("shaders/anim_txco.vShader", "shaders/diffuse_only.fShader");
	shader_uniform(bgshader, "speedfact", "f", PERSIST, 64.0);
-- We'll reduce stack layers and increase number of elements,
-- make sure that it fits the resolution of the screen with the minimum grid-cell size
	system_context_size( (VRESW * VRESH) / (48 * 48) * 3 );
-- make sure the current context runs with the new limit
	pop_video_context();
	
    settings.games = list_games( {} );
    if (#settings.games == 0) then
        error "No settings.games found";
        shutdown();
    end

	if (settings.sortfunctions[settings.sortlbl]) then
		table.sort(settings.games, settings.sortfunctions[settings.sortlbl]);
	end

-- enable key-repeat events AFTER we've done possible configuration of label->key mapping
	kbd_repeat(settings.repeat_rate);
	settings.iodispatch["ZOOM_CURSOR"]  = function(iotbl)
		if imagery.zoomed == BADID then
			zoom_cursor();
		else
			remove_zoom();
		end
end

-- the dispatchtable will be manipulated by settings and other parts of the program
    settings.iodispatch["MENU_UP"]      = function(iotbl) play_sample("click.wav"); move_cursor( -1 * ncw); end
    settings.iodispatch["MENU_DOWN"]    = function(iotbl) play_sample("click.wav"); move_cursor( ncw ); end
    settings.iodispatch["MENU_LEFT"]    = function(iotbl) play_sample("click.wav"); move_cursor( -1 ); end
    settings.iodispatch["MENU_RIGHT"]   = function(iotbl) play_sample("click.wav"); move_cursor( 1 ); end
    settings.iodispatch["MENU_ESCAPE"]  = function(iotbl) shutdown(); end
	settings.iodispatch["FLAG_FAVORITE"]= function(iotbl)
		local ind = table.find(settings.favorites, current_game().title);
		if (ind == nil) then -- flag
			table.insert(settings.favorites, current_game().title);
			local props = spawn_favoritestar(cursor_vid());
			settings.favorites[current_game().title] = props;
		else -- unflag
			fvid = settings.favorites[current_game().title];
			if (fvid) then
				blend_image(fvid, 0.0, settings.fadedelay);
				expire_image(fvid, settings.fadedelay);
				settings.favorites[current_game().title] = nil;
			end
			
			table.remove(settings.favorites, ind);
		end
	end

-- When OSD keyboard is to be shown, remap the input event handler,
-- Forward all labels that match, but also any translated keys (so that we
-- can use this as a regular input function as well) 
	settings.iodispatch["OSD_KEYBOARD"]  = function(iotbl)
		osdkbd = create_osdkbd();
		osdkbd:show();
		settings.inputfun = gridle_input;
		gridle_input = function(iotbl)
			if (iotbl.active) then
				local restbl = keyconfig:match(iotbl);
				local resstr = nil;
				local done   = false;
				
				if (restbl) then
					
					for ind,val in pairs(restbl) do
						if (val == "MENU_ESCAPE") then
							return osdkbd_filter(nil);
							
						elseif (val ~= "MENU_SELECT" and val ~= "MENU_UP" and val ~= "MENU_LEFT" and
								val ~= "MENU_RIGHT" and val ~= "MENU_DOWN" and iotbl.translated) then
							resstr = osdkbd:input_key(iotbl);
						else
							resstr = osdkbd:input(val);
						end
					end
				elseif (iotbl.translated) then
					resstr = osdkbd:input_key(iotbl);
				end
				if (resstr) then return osdkbd_filter(resstr); end
			end
		end
	end
	
	settings.iodispatch["DETAIL_VIEW"]  = function(iotbl)
		local key = gridledetail_havedetails(current_game());
		if (key) then
			remove_zoom();
			gridledetail_show(key, current_game());
		end
	end
	
	settings.iodispatch["MENU_TOGGLE"]  = function(iotbl) remove_zoom(); gridlemenu_settings(); end
    settings.iodispatch["MENU_SELECT"]  = function(iotbl) launch_target( current_game().title, LAUNCH_EXTERNAL); move_cursor(0); end
-- the analog conversion for devices other than mice is so-so atm.
    settings.iodispatch["CURSOR_X"] = function(lblres, tbl)
		if (tbl.source == "mouse") then mx = tbl.samples[1]; else mx = mx + (tbl.samples[1] / 32768) * step.x; end
		move_image(mouse_cursor, mx, my, 0);
		order_image(mouse_cursor, max_current_image_order() + 1);
		show_image(mouse_cursor);
		
    end

    settings.iodispatch["CURSOR_Y"] = function(lblres, tbl)
		if (tbl.source == "mouse") then my = tbl.samples[1]; elseif (tbl.samples[1] > 0) then my = my + (tbl.samples[1] / 32768) * step.y;
		else my = my - step.y; end
		move_image(mouse_cursor, mx, my, 0);
		show_image(mouse_cursor);
		order_image(mouse_cursor, max_current_image_order() + 1);
    end

	whiteblock = fill_surface(1,1,255,255,255);
	move_image(whiteblock, 0,0);
	
-- Animated background
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
	bgimage = load_image("background.png");
	resize_image(bgimage, VRESW, VRESH);
	image_scale_txcos(bgimage, VRESW / 32, VRESH / 32);
	image_shader(bgimage, bgshader);
	show_image(bgimage);
	switch_default_texmode( TEX_CLAMP, TEX_CLAMP );

-- Little star keeping track of games marked as favorites
	starimage    = load_image("star.png");
	magnifyimage = load_image("magnify.png");
    mouse_cursor = load_image("images/mouse_cursor.png");
	resize_image(mouse_cursor, 64, 64);
	force_image_blend(mouse_cursor);
	
	build_grid(settings.cell_width, settings.cell_height);
	build_fadefunctions();

	osd_visible = false;
	
	gridle_keyconf();
	gridle_ledconf();
end

function cell_coords(x, y)
    return (0.5 * borderw) + x * (settings.cell_width + settings.hspacing), (0.5 * borderh) + y * (settings.cell_height + settings.vspacing);
end

function match_cell_coords(x, y)

end

function build_fadefunctions()
	fadefunctions = {};

-- spin
	table.insert(fadefunctions, function(vid, col, row)
		expire_image(vid, settings.transitiondelay);
		rotate_image(vid, 270.0, settings.transitiondelay);
		scale_image(vid, 0.01, 0.01, settings.transitiondelay);
		return delay;
 	end);

-- pixelate
	table.insert(fadefunctions, function(vid, col, row)
		expire_image(vid, settings.transitiondelay);
		count = settings.transitiondelay;
		image_shader(vid, pixelate_shader);
		blend_image(vid, 0.0, settings.transitiondelay);
		resize_image(vid, VRESW, VRESH, settings.transitiondelay * 2.0);
	end)

-- odd / even scale + fade
	table.insert(fadefunctions, function(vid, col, row)
		local props = image_surface_properties(vid);
		local time = settings.transitiondelay;
		if (math.floor(col * row) % 2 > 0) then
			time = math.floor(time * 0.4);
		end

		move_image(vid, props.x + props.width / 2, props.y + props.height / 2, time);
		blend_image(vid, 0.0, time);
		resize_image(vid, 1, 1, time);
	end)
	
-- flee left/right
	table.insert(fadefunctions, function(vid, col, row)
		local props = image_surface_properties(vid);
		if (row % 2 > 0) then
			move_image(vid, -1 * (ncw-col) * props.width, props.y, settings.transitiondelay);
		else
			move_image(vid, (col * props.width) + VRESW + props.width, props.y, settings.transitiondelay);
		end
		expire_image(vid, settings.transitiondelay);
		return settings.transitiondelay;
	end);
end

function got_asynchimage(source, status)
	local cursor_row = math.floor(settings.cursor / ncw);
	local gridcell_vid = cursor_vid();

	if (status == 1) then
		if (source == gridcell_vid) then
			blend_image(source, 1.0);
		else
			blend_image(source, 0.3);
		end
		
		resize_image(source, settings.cell_width, settings.cell_height);
	end
	
end

function have_video(setname)
	local exts = {".avi", ".mp4", ".mkv", ".mpg"};

	for ind,val in ipairs(exts) do
		local moviefn = "movies/" .. setname .. val;
		if (resource(moviefn)) then
			return moviefn;
		end
	end

	return nil;
end

function zoom_cursor()
	if (imagery.zoomed == BADID) then
-- calculate aspect based on initial properties, not current ones.
		local props = image_surface_initial_properties( cursor_vid() );
		local aspect = props.width / props.height;
		
		local vid = movievid and instance_image(movievid) or instance_image( cursor_vid() );
-- make sure it is on top
		order_image(vid, max_current_image_order() + 1);

-- we want to zoom using the global coordinate system
		image_mask_clear(vid, MASK_SCALE);
		image_mask_clear(vid, MASK_ORIENTATION);
		image_mask_clear(vid, MASK_OPACITY);
		image_mask_clear(vid, MASK_POSITION);

-- how big should we make it?
		resize_image(vid, 1, 1, 0);
		if (aspect < 1.0) then -- vertical video
			resize_image(vid, 0, VRESH * 0.75, settings.fadedelay);
		else
			resize_image(vid, VRESW * 0.75, 0, settings.fadedelay);
		end

		props = image_surface_properties( cursor_vid() );
		local dx = props.x;
		local dy = props.y;
		move_image(vid, dx, dy, 0);

-- make sure that it fits the current window
		props = image_surface_properties(vid, settings.fadedelay);
		if (dx + props.width > VRESW) then
			dx = VRESW - props.width;
		end
		
		if (dy + props.height > VRESH) then
			dy = VRESH - props.height;
		end

		blend_image(vid, 1.0, settings.fadedelay);
		move_image(vid, dx, dy, settings.fadedelay);
		imagery.zoomed = vid;
	end
end

function remove_zoom()
	if (imagery.zoomed ~= BADID) then
		local props = image_surface_properties( cursor_vid() );
		move_image(imagery.zoomed, props.x, props.y, settings.fadedelay);
		blend_image(imagery.zoomed, 0.0, settings.fadedelay);
		resize_image(imagery.zoomed, 1, 1, settings.fadedelay);
		expire_image(imagery.zoomed, settings.fadedelay);
		imagery.zoomed = BADID;
	end
end
	
function cursor_vid()
	local cursor_row = math.floor(settings.cursor / ncw);
	return grid[cursor_row][settings.cursor - cursor_row * ncw ];
end

function blend_gridcell(val, dt)
    local gridcell_vid = cursor_vid();

    if (gridcell_vid) then
	    instant_image_transform(gridcell_vid);
	    blend_image(gridcell_vid, val, dt);
    end
end

function resize_grid(step)
 local new_cellw = settings.cell_width; local new_cellh = settings.cell_width;

 -- find the next grid size that would involve a density change
 repeat
    new_cellw = new_cellw + step;
 until math.floor(VRESW / (new_cellw + settings.hspacing)) ~= ncw;

 repeat
    new_cellh = new_cellh + step;
 until math.floor(VRESH / (new_cellh + settings.vspacing)) ~= nch;

-- safety checks
 if (new_cellw < 64 or new_cellw > VRESW * 0.75) then return; end
 if (new_cellh < 64 or new_cellh > VRESH * 0.75) then return; end

 settings.cell_width = new_cellw;
 settings.cell_height = new_cellh;

 local currgame = settings.pageofs + settings.cursor;
 local new_ncc = math.floor( VRESW / (new_cellw + settings.hspacing) ) * math.floor( VRESH / (new_cellh + settings.vspacing) );
 settings.pageofs = math.floor( currgame / new_ncc ) * new_ncc;
 settings.cursor = currgame - settings.pageofs;
 if (settings.cursor < 0) then settings.cursor = 0; end

-- remove the old grid
 erase_grid(true);
 build_grid(settings.cell_width, settings.cell_height);
end

function move_cursor( ofs )
    local pageofs_cur = settings.pageofs;
	blend_gridcell(0.3, settings.fadedelay);
	remove_zoom();

	settings.cursor = settings.cursor + ofs;
-- paging calculations
	if (ofs > 0) then -- right/forward
		if (settings.cursor >= ncc) then -- move right or "forward"
			settings.cursor = settings.cursor - ncc;
			pageofs_cur = pageofs_cur + ncc;
		end

		-- wrap around on overflow
		if (pageofs_cur + settings.cursor >= #settings.games) then
			pageofs_cur = 0;
			settings.cursor = 0;
		end
	elseif (ofs < 0) then -- left/backward
		if (settings.cursor < 0) then -- step back a page
			pageofs_cur = pageofs_cur - ncc;
			settings.cursor = ncc - ( -1 * settings.cursor);
			if (pageofs_cur < 0) then -- wrap page around
				pageofs_cur = math.floor(#settings.games / ncc) * ncc;
				if (pageofs_cur == #settings.games) then
					pageofs_cur = pageofs_cur - ncc;
				end
			end

			if (settings.cursor < 0 or settings.cursor >= #settings.games - pageofs_cur) then
				settings.cursor = #settings.games - pageofs_cur - 1;
			end
		end
	end
	
    local x,y = cell_coords(math.floor(settings.cursor % ncw), math.floor(settings.cursor / ncw));

-- reload images of the page has changed
	if (pageofs_cur ~= settings.pageofs) then
		erase_grid(false);
		settings.pageofs = pageofs_cur;
		build_grid(settings.cell_width, settings.cell_height);
	end

    local game = settings.games[settings.cursor + settings.pageofs + 1];
    setname = game and game.setname or nil;

    if (movievid) then
		instant_image_transform(movievid);
        expire_image(movievid, settings.fadedelay);
        blend_image(movievid, 0.0, settings.fadedelay);
		movievid = nil;
	end

    if (game and ledconfig) then
    	ledconfig:toggle(game.players, game.buttons);
    end

	local moviefile = have_video(setname);
	if (moviefile) then
	    movievid = load_movie( moviefile );
        if (movievid) then
            move_image(movievid, x, y);
            order_image(movievid, 3);
			props = image_surface_properties(movievid);
			return
		end
    else
        moviefile = "";
        movietimer = nil;
    end

	blend_gridcell(1.0, settings.fadedelay);
end

function get_image(romset)
    local rvid = BADID;

    if resource("screenshots/" .. romset .. ".png") then
        rvid = load_image_asynch("screenshots/" .. romset .. ".png", got_asynchimage);
		blend_image(rvid, 0.3);
	end

    if (rvid == BADID) then
        rvid = render_text( [[\#000088\ffonts/default.ttf,96 ]] .. romset );
		blend_image(rvid, 0.3);
	end

    return rvid;
end

function erase_grid(rebuild)
    settings.cellcount = 0;

	for ind,vid in pairs(settings.favvids) do
		expire_image(vid, settings.fadedelay);
		blend_image(vid, 0.0, settings.fadedelay);
	end

	for ind,vid in pairs(settings.detailvids) do
		expire_image(vid, settings.fadedelay);
		blend_image(vid, 0.0, settings.fadedelay);
	end

	settings.detailvids = {};
	settings.favvids = {};
	
	local fadefunc = fadefunctions[ math.random(1,#fadefunctions) ];
	
    for row=0, nch-1 do
     for col=0, ncw-1 do
      if (grid[row][col]) then

        if (rebuild) then
            delete_image(grid[row][col]);
        else
            local x, y = cell_coords(row, col);
			local imagevid = grid[row][col];
			fadefunc(imagevid, col, row);
		end

		delete_image(whitegrid[row][col]);
		whitegrid[row][col] = nil;
		grid[row][col] = nil;
      end
     end
    end
end

function build_grid(width, height)
--  figure out how many full cells we can fit with the current resolution
    ncw = math.floor(VRESW / (width + settings.hspacing));
    nch = math.floor(VRESH / (height + settings.vspacing));
    ncc = ncw * nch;

--  figure out how much "empty" space we'll have to pad with
    borderw = VRESW % (width + settings.hspacing);
    borderh = VRESH % (height + settings.vspacing);

	whitegrid = {};
    for row=0, nch-1 do
        grid[row] = {};
		whitegrid[row] = {};

        for col=0, ncw-1 do
            local gameno = (row * ncw + col + settings.pageofs + 1); -- settings.games is 1 indexed
            if (settings.games[gameno] == nil) then break; end
            local vid = get_image(settings.games[gameno]["setname"]);
            resize_image(vid, settings.cell_width, settings.cell_height);
            move_image(vid,cell_coords(col, row));
            order_image(vid, 2);

			local ofs = 0;
			if (settings.favorites[ settings.games[gameno].title ]) then
				settings.favorites[ settings.games[gameno].title ] = spawn_favoritestar( vid );
			end

			if (gridledetail_havedetails( settings.games[gameno] )) then
				ofs = ofs + spawn_magnify( vid, ofs );
			end
		
			gridbg = instance_image(whiteblock);
			resize_image(gridbg, settings.cell_width, settings.cell_height);
			move_image(gridbg, cell_coords(col, row));
	        image_mask_clear(gridbg, MASK_OPACITY);
			order_image(gridbg, 1);
			show_image(gridbg);

			whitegrid[row][col] = gridbg;
            grid[row][col] = vid;
            settings.cellcount = settings.cellcount + 1;
        end
    end

    move_cursor(0);
end

function gridle_video_event(source, event)
    if (event.kind == "movieready") then
		if (source == movievid) then
			vid,aid = play_movie(movievid);
			audio_gain(aid, 0.0);
			audio_gain(aid, 1.0, settings.fadedelay);
			blend_image(vid, 1.0, settings.fadedelay);
			resize_image(vid, settings.cell_width, settings.cell_height);
		else
			instant_image_transform(source);
			blend_image(source, 0.0, settings.fadedelay);
			expire_image(source, settings.fadedelay);
		end
	end
end

function gridle_shutdown()
	store_key("transitiondelay", tostring(settings.transitiondelay));
	store_key("fadedelay", tostring(settings.fadedelay));
	store_key("cell_width", tostring(settings.cell_width));
	store_key("cell_height", tostring(settings.cell_height));
	store_key("sortorder", settings.sortlbl);

	zap_resource("lists/favorites");
	if (open_rawresource("lists/favorites")) then
		for a=1,#settings.favorites do
			if ( write_rawresource(settings.favorites[a] .. "\n") == false) then
				print("Couldn't save favorites in lists/favorites. Check permissions.");
				break;
			end
		end

		close_rawresource();
	end
end

function load_settings()
	local cellw = get_key("cell_width");
	local cellh = get_key("cell_height");
	if (cellw and cellh and tonumber(cellw) >= 48 and tonumber(cellh) >= 48) then
		settings.cell_width = tonumber(cellw);
		settings.cell_height = tonumber(cellh);
	else
		settings.cell_width = 128;
		settings.cell_height = 128;
	end

	local setdelay = get_key("fadedelay");
	local transdelay = get_key("transitiondelay");
	if (setdelay) then settings.fadedelay = setdelay; end
	if (transdelay) then settings.transitiondelay = transdelay; end

	local sort = get_key("sortorder");
	if (sort and sort ~= "Default") then
		settings.sortlbl = sort;
	end
	
	local repeatrate = get_key("repeatrate");
	if (repeatrate) then settings.repeat_rate = tostring(repeatrate); end

	if ( open_rawresource("lists/favorites") ) then
		line = read_rawresource();
		while line ~= nil do
			table.insert(settings.favorites, line);
			settings.favorites[line] = true;
			line = read_rawresource();
		end
	end
end

function gridle_clock_pulse()
	if (settings.cursor_timer > 0) then
		settings.cursor_timer = settings.cursor_timer - 1;
		if (settings.cursor_timer == 0) then hide_image(mouse_cursor); end
	end

	if (settings.shutdown_timer) then
		settings.shutdown_timer = settings.shutdown_timer - 1;
		if (settings.shutdown_timer == 0) then shutdown(); end
	end
end

function gridle_input(iotbl)
	local restbl = keyconfig:match(iotbl);
 
	if (restbl and iotbl.active) then
		for ind,val in pairs(restbl) do
			if (settings.iodispatch[val]) then
				settings.iodispatch[val](restbl, iotbl);
			end
		end
	end
end
