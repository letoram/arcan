vertex_shader = [[
uniform int n_ticks;

void main(void)
{
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_TexCoord[0].s = gl_TexCoord[0].s + fract(float(n_ticks) / 64.0);
    gl_TexCoord[0].t = gl_TexCoord[0].t + fract(float(n_ticks) / 64.0);
    gl_Position = ftransform();
}]];

fragment_shader = [[
#version 120
uniform sampler2D tex;

void main() {
    vec4 color = texture2D(tex, gl_TexCoord[0].st);
	gl_FragColor = color;
}
]];

grid = {};

imagery = { 
 zoomed = BADID;
};

settings = {
	filters = {
	},

	sortlbl = "Default",
	iodispatch = {},

	vspacing = 4,
	hspacing = 4,
	cursor   = 0,
	cellcount= 0,
	pageofs  = 0,

	repeat_rate = 250,
	cell_width = 48,
	cell_height = 48
};

function gridle_keyconf()
    keyconfig = keyconf_create(1, {
        "rMENU_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP",
        "rMENU_DOWN", "rMENU_SELECT",
	" ZOOM_CURSOR", "rMENU_TOGGLE"} );
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

-- use the key,val facility of the DB backend to store theme-specific settings
function gridle_loadsettings()
end

function gridle_savesettings()
end

function gridle()
    system_load("scripts/keyconf.lua")();
    system_load("scripts/keyconf_mame.lua")();
    system_load("scripts/ledconf.lua")();
    system_load("gridle_menus.lua")();
	
-- make sure that the engine API version and the version this theme was tested for, align.
	if (API_VERSION_MAJOR ~= 0 and API_VERSION_MINOR ~= 3) then
		msg = "Engine/Script API version match, expected 0.3, got " .. API_VERSION_MAJOR .. "." .. API_VERSION_MINOR;
		error(msg);
		shutdown();
	end

	cellw = get_key("cell_width");
	cellh = get_key("cell_height");
	if (cellw and cellh and tonumber(cellw) >= 48 and tonumber(cellh) >= 48) then
		settings.cell_width = tonumber(cellw);
		settings.cell_height = tonumber(cellh);
	end
	
-- We'll reduce stack layers and increase number of elements,
-- make sure that it fits the resolution of the screen with the minimum grid-cell size
	system_context_size( (VRESW * VRESH) / (48 * 48) * 6 );
-- make sure the current context runs with the new limit
	pop_video_context();
	
    settings.games = list_games( {} );
    if (#settings.games == 0) then
        error "No settings.games found";
        shutdown();
    end

	gridle_keyconf();
	gridle_ledconf();

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
	settings.iodispatch["MENU_TOGGLE"]  = function(iotbl) remove_zoom(); gridlemenu_settings(); end
    settings.iodispatch["MENU_SELECT"]  = function(iotbl) if (settings.games[settings.cursor + settings.pageofs + 1]) then
    launch_target( settings.games[settings.cursor + settings.pageofs + 1].title, LAUNCH_EXTERNAL); move_cursor(0); end end

    build_grid(settings.cell_width, settings.cell_height);

-- Animated background
    switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
    bgimage = load_image("background.png");
    resize_image(bgimage, VRESW, VRESH);
    image_scale_txcos(bgimage, VRESW / 32, VRESH / 32);
    image_program(bgimage, vertex_shader, fragment_shader);
    show_image(bgimage);
    switch_default_texmode( TEX_CLAMP, TEX_CLAMP );
	build_fadefunctions();

end

function cell_coords(x, y)
    return (0.5 * borderw) + x * (settings.cell_width + settings.hspacing), (0.5 * borderh) + y * (settings.cell_height + settings.vspacing);
end

function build_fadefunctions()
	fadefunctions = {};

-- spin
	table.insert(fadefunctions, function(vid, col, row)
		local delay = 10 + math.random(10, 30);
		expire_image(vid, delay);
		rotate_image(vid, 270.0, delay);
		scale_image(vid, 0.01, 0.01, delay);
		return delay;
 	end);

-- flee left/right
	table.insert(fadefunctions, function(vid, col, row)
		local props = image_surface_properties(vid);
		if (row % 2 > 0) then
			move_image(vid, -1 * (ncw-col) * props.width, props.y, 60);
		else
			move_image(vid, (col * props.width) + VRESW + props.width, props.y, 60);
		end
		expire_image(vid, 60);
		return 60;
	end);
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
			resize_image(vid, 0, VRESH * 0.75, 10);
		else
			resize_image(vid, VRESW * 0.75, 0, 10);
		end

		props = image_surface_properties( cursor_vid() );
		local dx = props.x;
		local dy = props.y;
		move_image(vid, dx, dy, 0);

-- make sure that it fits the current window
		props = image_surface_properties(vid, 10);
		if (dx + props.width > VRESW) then
			dx = VRESW - props.width;
		end
		
		if (dy + props.height > VRESH) then
			dy = VRESH - props.height;
		end

		blend_image(vid, 1.0, 10);
		move_image(vid, dx, dy, 10);
		imagery.zoomed = vid;
	end
end

function remove_zoom()
	if (imagery.zoomed ~= BADID) then
		local props = image_surface_properties( image_parent( imagery.zoomed ) );
		move_image(imagery.zoomed, props.x, props.y, 20);
		blend_image(imagery.zoomed, 0.0, 20);
		resize_image(imagery.zoomed, 1, 1, 20);
		expire_image(imagery.zoomed, 20);
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
    blend_gridcell(0.3, 10);
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
        expire_image(movievid, 20);
        blend_image(movievid, 0.0, 20);
		movievid = nil;
	end

    if (game and ledconfig) then
    	ledconfig:toggle(game.players, game.buttons);
    end

-- look for a movie, if one exists, enable a timer that we'll check for later
    if (setname and resource( "movies/" .. setname .. ".avi")) then
        movievid = load_movie( "movies/" .. setname .. ".avi" );
        if (movievid) then
            move_image(movievid, x, y);
            order_image(movievid, 3);
        end
    else
        moviefile = "";
        movietimer = nil;
    end

    blend_gridcell(1.0, 10);
end

function get_image(romset)
    local rvid = BADID;

    if resource("screenshots/" .. romset .. ".png") then
        rvid = load_image_asynch("screenshots/" .. romset .. ".png");
    end

    if (rvid == BADID) then
        rvid = render_text( [[\#000088\ffonts/default.ttf,96 ]] .. romset );
		blend_image(rvid, 0.3);
	end

    return rvid;
end

function erase_grid(rebuild)
    settings.cellcount = 0;
	local fadefunc = fadefunctions[ math.random(1,#fadefunctions) ];
	
    for row=0, nch-1 do
     for col=0, ncw-1 do
      if (grid[row][col]) then

        if (rebuild) then
            delete_image(grid[row][col]);
        else
            local x, y = cell_coords(row, col);
			local imagevid = grid[row][col];

			res = image_children(imagevid);
			for key,val in ipairs(res) do delete_image(val); end
			 fadefunc(imagevid, col, row);
       end

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

    for row=0, nch-1 do
        grid[row] = {};
        for col=0, ncw-1 do
            local gameno = (row * ncw + col + settings.pageofs + 1); -- settings.games is 1 indexed
            if (settings.games[gameno] == nil) then break; end
            local vid = get_image(settings.games[gameno]["setname"]);
            resize_image(vid, settings.cell_width, settings.cell_height);
            move_image(vid,cell_coords(col, row));
            order_image(vid, 2);

			local whitebg = fill_surface(settings.cell_width, settings.cell_height, 255, 255, 255);
	        order_image(whitebg, 1);
	        show_image(whitebg);
	        link_image(whitebg, vid);
			image_mask_clear(whitebg, MASK_SCALE);
	        image_mask_clear(whitebg, MASK_ORIENTATION);
	        image_mask_clear(whitebg, MASK_OPACITY);

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
			audio_gain(aid, 1.0, 40);
			blend_image(vid, 1.0, 40);
			resize_image(vid, settings.cell_width, settings.cell_height);
		else
			instant_image_transform(source);
			blend_image(source, 0.0, 20);
			expire_image(source, 20);
		end

	elseif (event.kind == "loaded") then
		local cursor_row = math.floor(settings.cursor / ncw);
		local gridcell_vid = cursor_vid();

		if (source == gridcell_vid) then
			blend_image(source, 1.0);
		else
			blend_image(source, 0.3);
		end
		
        resize_image(source, settings.cell_width, settings.cell_height);
	end
end

function gridle_shutdown()
	store_key("cell_width", tostring(settings.cell_width));
	store_key("cell_height", tostring(settings.cell_height));
end

function gridle_input(iotbl)
 local restbl = keyconfig:match(iotbl);
 if (restbl and iotbl.active) then
  for ind,val in pairs(restbl) do
   if (settings.iodispatch[val]) then
     settings.iodispatch[val](restbl);
   end
  end
 end
end
