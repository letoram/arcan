grid = {};

internal_vid = BADID;
internal_aid = BADID;

-- shared images, statebased vids etc.
imagery = {
	movie = nil,
	black = BADID,
	white = BADID,
	bgimage = BADID, 
	zoomed = BADID
};

soundmap = {
	MENU_TOGGLE     = load_asample("sounds/menu_toggle.wav"),
	MENU_FADE       = load_asample("sounds/menu_fade.wav"),
	MENU_SELECT     = load_asample("sounds/detail_view.wav"),
	MENU_FAVORITE   = load_asample("sounds/launch_external.wav"),
	MENUCURSOR_MOVE = load_asample("sounds/move.wav"),
	GRIDCURSOR_MOVE = load_asample("sounds/gridcursor_move.wav"),
	GRID_NEWPAGE    = load_asample("sounds/grid_newpage.wav"),
	GRID_RANDOM     = load_asample("sounds/click.wav"),
	SUBMENU_TOGGLE  = load_asample("sounds/menu_toggle.wav"),
	SUBMENU_FADE    = load_asample("sounds/menu_fade.wav"),
	LAUNCH_INTERNAL = load_asample("sounds/launch_internal.wav"),
	LAUNCH_EXTERNAL = load_asample("sounds/launch_external.wav"),
	SWITCH_GAME     = load_asample("sounds/switch_game.wav"),
	DETAIL_VIEW     = load_asample("sounds/detail_view.wav"),
	SET_FAVORITE    = load_asample("sounds/set_favorite.wav"),
	CLEAR_FAVORITE  = load_asample("sounds/clear_favorite.wav"),
	OSDKBD_TOGGLE   = load_asample("sounds/osdkbd_show.wav"),
	OSDKBD_MOVE     = load_asample("sounds/gridcursor_move.wav"),
	OSDKBD_ENTER    = load_asample("sounds/osdkb.wav"),
	OSDKBD_ERASE    = load_asample("sounds/click.wav"),
	OSDKBD_SELECT   = load_asample("sounds/osdkbd_select.wav"),
	OSDKBD_HIDE     = load_asample("sounds/osdkbd_hide.wav")
};

-- constants,
 BGLAYER = 0;
 GRIDBGLAYER = 1;
 GRIDLAYER = 3;
 GRIDLAYER_MOVIE = 2;
 
 ICONLAYER = 4;
 
 ZOOMLAYER = 6;
 ZOOMLAYER_MOVIE = 5;

settings = {
	filters = {
	},
	
	borderstyle = "Normal", 
	sortlbl = "Ascending",
	viewmode = "Grid",
	scalemode = "Keep Aspect",
	iodispatch = {},

	fadedelay = 10,
	transitiondelay = 30,

-- 0: disable, 1: all on, 2: game (all on), 3: game (press on) 
	ledmode = 2,
	
	vspacing = 4,
	hspacing = 4,
	cursor   = 0,
	cellcount= 0,
	pageofs  = 0,
	gameind  = 1,

	favorites = {},
	detailvids = {},
	favvids = {},
	
	repeat_rate = 250,
	celll_width = 48,
	cell_height = 48,
	
	cooldown = 15,
	cooldown_start = 15,
	zoom_countdown = 0,
	
	internal_input = "Normal",
	flipinputaxis = false,
	internal_again = 1.0,
	fullscreenshader = "default",
	in_internal = false
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

function gridle_video_event(source, event)
	if (event.kind == "resized") then
-- a launch_internal almost immediately generates this event, so a decent trigger to use
		if (source == internal_vid) then
				gridlemenu_resize_fullscreen(internal_vid);
		end

		if (not in_internal) then
			in_internal = true;

-- don't need these running in the background 
			erase_grid(true);
			if (imagery.movie and imagery.movie ~= BADID) then 
				delete_image(imagery.movie); 
				imagery.movie = nil; 
			end

			show_image(internal_vid);
			local props = image_surface_properties(internal_vid);
			resize_image(internal_vid, 1,1);
			move_image(internal_vid, VRESW * 0.5, VRESH * 0.5);
			resize_image(internal_vid, props.width, props.height, settings.transitiondelay);
			move_image(internal_vid, props.x, props.y, settings.transitiondelay);

			internal_vidborder = instance_image( imagery.black );
			image_mask_clearall(internal_vidborder);
			resize_image(internal_vidborder, VRESW, VRESH);
			blend_image(internal_vidborder, 1.0, settings.transitiondelay * 2);
			order_image(internal_vid, 1);
			order_image(internal_vidborder, 0);
		end
	end
end

function gridle_keyconf()
	local keylabels = {
		"rMENU_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT", " ZOOM_CURSOR", "rMENU_TOGGLE", " DETAIL_VIEW", " FLAG_FAVORITE",
		" RANDOM_GAME", " OSD_KEYBOARD" };
	local listlbls = {};
	local lastofs = 1;
	
	if (INTERNALMODE ~= "NO SUPPORT") then
		table.insert(keylabels, " LAUNCH_INTERNAL");
		system_load("gridle_intmenus.lua")();
	end

	for ind, key in ipairs(keylabels) do
		table.insert(listlbls, string.sub(key, 2));
	end
		
	keyconfig = keyconf_create(1, keylabels);
	
	if (keyconfig.active == false) then
		kbd_repeat(0);

-- keep a listview in the left-side behind the dialog to show all the labels left to configure
		keyconf_labelview = listview_create(listlbls, VRESH, VRESW / 4, "fonts/default.ttf", 18,  nil);
		local props = image_surface_properties(keyconf_labelview:window_vid(), 5);
		if (props.height < VRESH) then
			move_image(keyconf_labelview:anchor_vid(), 0, VRESH * 0.5 - props.height* 0.5);
		end
		
		keyconfig:to_front();

-- replace the current input function until we have a working keyconfig
		gridle_input = function(iotbl) -- keyconfig io function hook
			if (keyconfig:input(iotbl) == true) then
				keyconf_tomame(keyconfig, "_mame/cfg/default.cfg"); -- should be replaced with a more generic export interface
				gridle_input = gridle_dispatchinput;
				kbd_repeat(settings.repeat_rate);
				if (keyconf_labelview) then keyconf_labelview:destroy(); end
				
			else -- more keys to go, labelview MAY disappear but only if the user defines PLAYERn_BUTTONm > 0
				if (keyconfig.ofs ~= lastofs and keyconf_labelview) then 
					lastofs = keyconfig.ofs;
					keyconf_labelview:move_cursor(1, 1); 
				elseif (keyconfig.in_playerconf and keyconf_labelview) then
					keyconf_labelview:destroy();
					keyconf_labelview = nil;
				end
			end
		end
--

	end
end
 
-- very similar to gridle_keyconf, only real difference is that the labels are a subset
-- of the output from keyconf (PLAYERn)
function gridle_ledconf()
	ledconflabels = {};

	for ind, val in ipairs(keyconfig:labels()) do
		if (string.match(val, "PLAYER%d") ~= nil) then
			table.insert(ledconflabels, val);
		end
	end

	ledconfig = ledconf_create( ledconflabels );

-- LED config, use a subset of the labels defined in keyconf
	if (ledconfig.active == false) then
		ledconf_labelview = listview_create(ledconflabels, VRESH, VRESW / 4, "fonts/default.ttf", 18,  nil);
				
		local props = image_surface_properties(ledconf_labelview:window_vid(), 5);
		if (props.height < VRESH) then
			move_image(ledconf_labelview:anchor_vid(), 0, VRESH * 0.5 - props.height* 0.5);
		end

		ledconfig:to_front();
		ledconfig.lastofs = ledconfig.labelofs;
		
-- since we have a working symbol/label set by now, use that one
		gridle_input = function(iotbl)
			local restbl = keyconfig:match(iotbl);

-- just push input until all labels are covered
			if (iotbl.active and restbl and restbl[1]) then 
				if (ledconfig:input(restbl[1]) == true) then
					gridle_input = gridle_dispatchinput;
					ledconf_labelview:destroy();
					ledconf_labelview = nil;
					init_leds();
				else -- more input
					if (ledconfig.lastofs ~= ledconfig.labelofs) then
							ledconfig.lastofs = ledconfig.labelofs;
							ledconf_labelview:move_cursor(1, 1);
					end
				end
			end
		end
-- already got working LEDconf
	else
		init_leds();
	end
end

function current_game()
	return settings.games[settings.cursor + settings.pageofs + 1];
end

-- ncc (number of cells per page)
-- num within 1..#settings.games
-- gives page and offset from page base.

function page_calc(num)
	num = num - 1;
	local pageofs = math.floor( num / ncc ) * ncc;
	return pageofs, num - pageofs;
end

function table.find(table, label)
	for a,b in pairs(table) do
		if (b == label) then return a end
	end

	return nil;  
end

function spawn_magnify( src )
	local vid = instance_image(imagery.magnifyimage);
	local w = settings.cell_width * 0.1;
	local h = settings.cell_height * 0.1;
	
	image_mask_clear(vid, MASK_SCALE);
	image_mask_clear(vid, MASK_OPACITY);
	force_image_blend(vid);

	local props = image_surface_properties( src );
	move_image(vid, props.x - (settings.cell_width * 0.05) + w + 4, props.y + (settings.cell_width * 0.05), 0);
	order_image(vid, ICONLAYER);
	blend_image(vid, 1.0, settings.fadedelay);
	resize_image(vid, 1, 1, NOW);
	resize_image(vid, w, h, 10);
	table.insert(settings.detailvids, vid);
	
	return vid;
end

function spawn_warning( message )
-- render message and make sure it is on top
	local vid = render_text([[\ffonts/default.ttf,18\#ff0000 ]] .. message)
	order_image(vid, max_current_image_order() + 1);
	local props = image_surface_properties(vid);

-- long messages, vertical screens
	if (props.width > VRESW) then 
		props.width = VRESW;
		resize_image(vid, VRESW, 0);
	end

-- position and start fading slowly
	move_image(vid, VRESW * 0.5 - props.width * 0.5, 5, NOW);
	show_image(vid);
	expire_image(vid, 250);
	blend_image(vid, 0.0, 250);
end

function spawn_favoritestar( src )
	local vid = instance_image(imagery.starimage);
	image_mask_clear(vid, MASK_SCALE);
	image_mask_clear(vid, MASK_OPACITY);
	force_image_blend(vid);

	local props = image_surface_properties( src );
	move_image(vid, props.x - (settings.cell_width * 0.05), props.y - (settings.cell_width * 0.05), 0);
	order_image(vid, ICONLAYER);
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
		else
		-- no match, send a warning message
			spawn_warning("Couldn't find any games matching title: " .. settings.filters.title );
	-- and restore settings
			settings.filters.title = titlecpy;
		end
	end
end

function gridle()
-- grab all dependencies;
	system_load("scripts/listview.lua")();       -- used by menus (_menus, _intmenus) and key/ledconf
	system_load("scripts/resourcefinder.lua")(); -- heuristics for finding media
	system_load("scripts/keyconf.lua")();        -- input configuration dialoges
	system_load("scripts/keyconf_mame.lua")();   -- convert a keyconf into a mame configuration
	system_load("scripts/ledconf.lua")();        -- associate input labels with led controller IDs
	system_load("scripts/3dsupport.lua")();      -- used by detailview, simple model/material/shader loader
	system_load("scripts/osdkbd.lua")();         -- on-screen keyboard using only MENU_UP/DOWN/LEFT/RIGHT/SELECT/ESCAPE
	system_load("gridle_menus.lua")();           -- in-frontend configuration options
	system_load("gridle_detail.lua")();          -- detailed view showing either 3D models or game- specific scripts

-- make sure that the engine API version and the version this theme was tested for, align.
	if (API_VERSION_MAJOR ~= 0 and API_VERSION_MINOR ~= 4) then
		msg = "Engine/Script API version match, expected 0.4, got " .. API_VERSION_MAJOR .. "." .. API_VERSION_MINOR;
		error(msg);
		shutdown();
	end

-- make sure that we don't have any weird resolution configurations
	if (VRESW < 256 or VRESH < 256) then
	  error("Unsupported resolution (" .. VRESW .. " x " .. VRESH .. ") requested. Check -w / -h arguments.");
	end

-- We'll reduce stack layers (since we don't use them) and increase number of elements on the default one
-- make sure that it fits the resolution of the screen with the minimum grid-cell size, including the white "background"
-- instances etc.
	system_context_size( (VRESW * VRESH) / (48 * 48) * 4 );

-- make sure the current context runs with the new limit
	pop_video_context();

-- keep an active list of available games, make sure that we have something to play/show
-- since we want a custom sort, we'll have to keep a table of all the games (expensive)
	settings.games = list_games( {} );
	
	if (#settings.games == 0) then
		error("There are no games defined in the database.");
		shutdown();
	end

-- any 3D rendering (models etc.) should happen after any 2D surfaces have been draw
	video_3dorder(ORDER_LAST); 

-- use the DB theme-specific key/value store to populate the settings table
	load_settings();

-- shader for an animated background (tiled with texture coordinates aligned to the internal clock)
	local bgshader = load_shader("shaders/anim_txco.vShader", "shaders/diffuse_only.fShader", "background");
	shader_uniform(bgshader, "speedfact", "f", PERSIST, 64.0);
	
	if (settings.sortfunctions[settings.sortlbl]) then
		table.sort(settings.games, settings.sortfunctions[settings.sortlbl]);
	end
	
-- enable key-repeat events AFTER we've done possible configuration of label->key mapping
	kbd_repeat(settings.repeat_rate);

-- setup callback table for input events
	settings.iodispatch["ZOOM_CURSOR"]  = function(iotbl)
		if imagery.zoomed == BADID then
			zoom_cursor(settings.fadedelay);
		else
			remove_zoom(settings.fadedelay);
		end
	end

-- the dispatchtable will be manipulated by settings and other parts of the program
	settings.iodispatch["MENU_UP"]      = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 * ncw); end
	settings.iodispatch["MENU_DOWN"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( ncw ); end
	settings.iodispatch["MENU_LEFT"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 ); end
	settings.iodispatch["MENU_RIGHT"]   = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( 1 ); end
	settings.iodispatch["RANDOM_GAME"]  = function(iotbl) move_cursor( math.random(-#settings.games, #settings.games) ); end
	settings.iodispatch["MENU_ESCAPE"]  = function(iotbl) shutdown(); end
	settings.iodispatch["FLAG_FAVORITE"]= function(iotbl)
		local ind = table.find(settings.favorites, current_game().title);
		if (ind == nil) then -- flag
			table.insert(settings.favorites, current_game().title);
			local props = spawn_favoritestar(cursor_vid());
			settings.favorites[current_game().title] = props;
			play_audio(soundmap["SET_FAVORITE"]);
		else -- unflag
			fvid = settings.favorites[current_game().title];
			if (fvid) then
				blend_image(fvid, 0.0, settings.fadedelay);
				expire_image(fvid, settings.fadedelay);
				settings.favorites[current_game().title] = nil;
			end
			
			table.remove(settings.favorites, ind);
			play_audio(soundmap["CLEAR_FAVORITE"]);
		end
	end

-- When OSD keyboard is to be shown, remap the input event handler,
-- Forward all labels that match, but also any translated keys (so that we
-- can use this as a regular input function as well) 
	settings.iodispatch["OSD_KEYBOARD"]  = function(iotbl)
		play_audio(soundmap["OSDKBD_TOGGLE"]);
		
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
							play_audio(soundmap["OSDKBD_HIDE"]);
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
		local gametbl = current_game();
		local key = gridledetail_havedetails(gametbl);
		if (key) then
			remove_zoom(settings.fadedelay);
			local gameind = 0;
			blend_image( cursor_vid(), 0.3 );
			play_audio( soundmap["DETAIL_VIEW"] ); 
			
-- cache curind so we don't have to search if we're switching game inside detail view 
			for ind = 1, #settings.games do
				if (settings.games[ind].title == gametbl.title) then
					gameind = ind;
					break;
				end
			end

			if (imagery.movie and imagery.movie ~= BADID) then 
				delete_image(imagery.movie); 
				imagery.movie = nil; 
			end
			
			gridledetail_show(key, gametbl, gameind);
		end
	end
	
	settings.iodispatch["MENU_TOGGLE"]  = function(iotbl) 
		play_audio(soundmap["MENU_TOGGLE"]);
		remove_zoom(settings.fadedelay); 
		gridlemenu_settings(); 
	end
	
	settings.iodispatch["MENU_SELECT"]  = function(iotbl) 
		play_audio(soundmap["LAUNCH_EXTERNAL"]);
		launch_target( current_game().title, LAUNCH_EXTERNAL); 
		move_cursor(0);
	end
	
	settings.iodispatch["LAUNCH_INTERNAL"] = function(iotbl)
		erase_grid(false);
		play_audio(soundmap["LAUNCH_INTERNAL"]);
		internal_vid, internal_aid = launch_target( current_game().title, LAUNCH_INTERNAL);
		audio_gain(internal_aid, settings.internal_again, NOW);
		gridle_oldinput = gridle_input;
		gridle_input = gridle_internalinput;
		gridlemenu_loadshader(settings.fullscreenshader);
	end

	imagery.black = fill_surface(1,1,0,0,0);
	imagery.white = fill_surface(1,1,255,255,255);
	
-- Animated background
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
	imagery.bgimage = load_image("background.png");
	resize_image(imagery.bgimage, VRESW, VRESH);
	image_scale_txcos(imagery.bgimage, VRESW / 32, VRESH / 32);
	image_shader(imagery.bgimage, bgshader);
	show_image(imagery.bgimage);
	switch_default_texmode( TEX_CLAMP, TEX_CLAMP );

-- Little star keeping track of games marked as favorites
	imagery.starimage    = load_image("star.png");
	imagery.magnifyimage = load_image("magnify.png");

	build_grid(settings.cell_width, settings.cell_height);
	build_fadefunctions();

	osd_visible = false;
	
	gridle_keyconf();
	gridle_ledconf();
	osdkbd = create_osdkbd();
end

function cell_coords(x, y)
    return (0.5 * borderw) + x * (settings.cell_width + settings.hspacing), (0.5 * borderh) + y * (settings.cell_height + settings.vspacing);
end

function build_fadefunctions()
	fadefunctions = {};

-- spin
	table.insert(fadefunctions, function(vid, col, row)
		rotate_image(vid, 270.0, settings.transitiondelay);
		scale_image(vid, 0.01, 0.01, settings.transitiondelay);
		return delay;
 	end);

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
		return settings.transitiondelay;
	end);
end

function got_asynchimage(source, status)
	local cursor_row = math.floor(settings.cursor / ncw);
	local gridcell_vid = cursor_vid();
	
	if (status == 1) then
		if (source == gridcell_vid) then
			blend_image(source, 1.0, settings.transitiondelay);
		else
			blend_image(source, 0.3, settings.transitiondelay);
		end
		
		resize_image(source, settings.cell_width, settings.cell_height);
	end
	
end

function zoom_cursor(speed)
	if (imagery.zoomed == BADID) then
-- calculate aspect based on initial properties, not current ones.
-- but make sure that the values are correct (block until loaded)
		image_pushasynch( cursor_vid() );
		local iprops = image_surface_initial_properties( cursor_vid() );
		local aspect = iprops.width / iprops.height;
		local vid = imagery.movie and instance_image(imagery.movie) or instance_image( cursor_vid() );

-- make sure it is on top
		order_image(vid, ZOOMLAYER);
		
-- we want to zoom using the global coordinate system
		image_mask_clear(vid, MASK_SCALE);
		image_mask_clear(vid, MASK_ORIENTATION);
		image_mask_clear(vid, MASK_OPACITY);
		image_mask_clear(vid, MASK_POSITION);

-- grab the parent dimensions so that we can use that
		local props = image_surface_properties( cursor_vid() );
		local destx = props.x;
		local desty = props.y;
		
		move_image(vid, destx, desty, 0);
		resize_image(vid, props.width, props.height, 0);

		settings.zoomp = {};
	-- depending on dominant axis (horizontal or vertical)
		if (aspect > 1.0) then
			settings.zoomp.width = VRESW;
			settings.zoomp.height = VRESH / aspect;
		else
			settings.zoomp.height = VRESH;
			settings.zoomp.width = VRESW * aspect;
		end
		resize_image(vid, settings.zoomp.width, settings.zoomp.height, speed);

-- now the location is partially out of frame,
-- figure out the end dimensions and then reposition
		if (destx + settings.zoomp.width > VRESW) then
			destx = VRESW - settings.zoomp.width;
		end
	
		if (desty + settings.zoomp.height > VRESH) then
			desty = VRESH - settings.zoomp.height;
		end

		blend_image(vid, 1.0, speed);
		move_image(vid, destx, desty, speed);

		imagery.zoomed = vid;
		settings.zoomp.x = destx;
		settings.zoomp.y = desty;
		settings.zoom_countdown = speed;
	end
end

function init_leds()
	if (ledconfig) then
		if (settings.ledmode == 1) then
			ledconfig:setall();
		else
			ledconfig:clearall();
			-- rest will be in toggle led
		end
	end
end

function toggle_led(players, buttons, label, pressed)
	if (ledconfig) then
		if (settings.ledmode == 0) then
			-- Do Nothing
		elseif (settings.ledmode == 1) then
			-- All On
		elseif (settings.ledmode == 2 and label == "") then
			-- Game All On
			ledconfig:toggle(players, buttons);
		end
	end
end

function remove_zoom(speed)
	if (imagery.zoomed ~= BADID) then
		local props = image_surface_properties( cursor_vid() );
		move_image(imagery.zoomed, props.x, props.y, speed);
		blend_image(imagery.zoomed, 0.0, settings.fadedelay);
		resize_image(imagery.zoomed,settings.cell_width, settings.cell_height, speed);
		expire_image(imagery.zoomed, settings.fadedelay);
		imagery.zoomed = BADID;
	end
end
	
function cursor_vid()
	local cursor_row = math.floor( settings.cursor / ncw);
	return grid[cursor_row][settings.cursor - cursor_row * ncw ];
end

function blend_gridcell(val, dt)
    local gridcell_vid = cursor_vid();

    if (gridcell_vid) then
	    instant_image_transform(gridcell_vid);
	    blend_image(gridcell_vid, val, dt);
    end
end

function move_cursor( ofs )
	local pageofs_cur = settings.pageofs;
	blend_gridcell(0.3, settings.fadedelay);
	remove_zoom(settings.fadedelay);

	settings.gameind = settings.gameind + ofs;

-- refit inside range
	while (settings.gameind < 1) do 
		settings.gameind = #settings.games + settings.gameind;
	end
	
	while (settings.gameind > #settings.games) do
		settings.gameind = settings.gameind - #settings.games;
	end

-- find new page / cursor position
	settings.pageofs, settings.cursor = page_calc( settings.gameind );

	local x,y = cell_coords(
		math.floor(settings.cursor % ncw), math.floor(settings.cursor / ncw)
	);

-- reload images of the page has changed
	if (pageofs_cur ~= settings.pageofs) then
		play_audio(soundmap["GRID_NEWPAGE"]);
		erase_grid(false);
		build_grid(settings.cell_width, settings.cell_height);
	end

	settings.cursorgame = settings.games[settings.gameind];
	
-- reset the previous movie
	if (imagery.movie) then
		instant_image_transform(imagery.movie);
		expire_image(imagery.movie, settings.fadedelay);
		blend_image(imagery.movie, 0.0, settings.fadedelay);
		imagery.movie = nil;
	end

-- just sweeps the matching PLAYERX_BUTTONY pattern, a more refined approach would take all the weird little
-- arcade game control quirks into proper account
	toggle_led(settings.cursorgame.players, settings.cursorgame.buttons, "");

-- reset the cooldown that triggers movie playback
	settings.cooldown = settings.cooldown_start;
	blend_gridcell(1.0, settings.fadedelay);
end

-- resourcetbl is quite large, check resourcefinder.lua for more info
function get_image( resourcetbl, setname )
	local rvid = BADID;
	if ( resourcetbl.screenshots[1] ) then
		rvid = load_image_asynch( resourcetbl.screenshots[1], got_asynchimage );
		blend_image(rvid, 0.0); -- don't show until loaded 
	end
	
	if (rvid == BADID) then
		rvid = render_text( [[\#000088\ffonts/default.ttf,96 ]] .. setname );
		blend_image(rvid, 0.3, settings.transitiondelay);
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
					expire_image(imagevid, settings.transitiondelay);
				end

				delete_image(whitegrid[row][col]);
				whitegrid[row][col] = nil;
				grid[row][col] = nil;
			end
		end
	end

	if (imagery.movie and imagery.movie ~= BADID) then
		delete_image(imagery.movie, settings.fadedelay);
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
			settings.games[gameno].resources = resourcefinder_search( settings.games[gameno], true);
			local vid = get_image(settings.games[gameno].resources, settings.games[gameno].setname);
			resize_image(vid, settings.cell_width, settings.cell_height);
			move_image(vid,cell_coords(col, row));
			order_image(vid, GRIDLAYER);

			local ofs = 0;
			if (settings.favorites[ settings.games[gameno].title ]) then
				settings.favorites[ settings.games[gameno].title ] = spawn_favoritestar( vid );
			end

			if (gridledetail_havedetails( settings.games[gameno] )) then
				ofs = ofs + spawn_magnify( vid, ofs );
			end
		
			gridbg = instance_image(imagery.white);
			resize_image(gridbg, settings.cell_width, settings.cell_height);
			move_image(gridbg, cell_coords(col, row));
			image_mask_clear(gridbg, MASK_OPACITY);
			order_image(gridbg, GRIDBGLAYER);
			show_image(gridbg);

			whitegrid[row][col] = gridbg;
			grid[row][col] = vid;
			settings.cellcount = settings.cellcount + 1;
		end
	end

	move_cursor(0);
end

function gridle_shutdown()
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

-- these should match those of 
-- (a) the standard settings table (all should be set),
-- (b) gridle_menus
function load_settings()
	local cellw   = get_key("cell_width");
	local cellh   = get_key("cell_height");
	local ledmode = get_key("ledmode");

	if (ledmode and tonumber(ledmode) < 4 and tonumber(ledmode) >= 0) then
		settings.ledmode = tonumber(ledmode);
	end	
	
	if (cellw and cellh and tonumber(cellw) >= 48 and tonumber(cellh) >= 48) then
		settings.cell_width = tonumber(cellw);
		settings.cell_height = tonumber(cellh);
	else
		settings.cell_width = 128;
		settings.cell_height = 128;
	end

	local setdelay = get_key("fadedelay");
	local transdelay = get_key("transitiondelay");
	if (setdelay) then settings.fadedelay = tonumber(setdelay); end
	if (transdelay) then settings.transitiondelay = tonumber(transdelay); end

	local sort = get_key("sortorder");
	if (sort and sort ~= "Default") then
		settings.sortlbl = sort;
	end

	local fullscreenshader = get_key("defaultshader");
	if (fullscreenshader) then
		settings.fullscreenshader = get_key("defaultshader");
	end
	
	local repeatrate = get_key("repeatrate");
	if (repeatrate) then settings.repeat_rate = tonumber(repeatrate); end

	if ( open_rawresource("lists/favorites") ) then
		line = read_rawresource();
		while line ~= nil do
			table.insert(settings.favorites, line);
			settings.favorites[line] = true;
			line = read_rawresource();
		end
	end
	
	local internalgain = get_key("internal_again");
	if (internalgain) then
		settings.internal_again = tonumber( get_key("internal_again") );
	end
	
	local internalinp = get_key("internal_input");
	if (internalinp ~= nil) then
		settings.internal_input = internalinp;
		settings.flipinputaxis = internalinp ~= "Normal";
	end
	
	local scalemode = get_key("internal_scalemode");
	if (scalemode ~= nil) then 
		settings.scalemode = scalemode; 
	end
end

function asynch_movie_ready(source, status)
	if (status == 1 and source == imagery.movie) then
		vid,aid = play_movie(source);
		audio_gain(aid, 0.0);
		audio_gain(aid, 1.0, settings.fadedelay);
		blend_image(vid, 1.0, settings.fadedelay);
		resize_image(vid, settings.cell_width, settings.cell_height);
		blend_image(cursor_vid(), 0.0, settings.fadedelay);
		
-- corner case, we're zooming or fully zoomed already and we need to replace the current image with
-- the frameserver session
		if (imagery.zoomed ~= BADID) then
			local cprops = image_surface_properties(imagery.zoomed);
			expire_image(imagery.zoomed, settings.zoom_countdown);
			blend_image(imagery.zoomed, 0.5, settings.zoom_countdown);
			
			imagery.zoomed = instance_image(source);
			image_mask_clear(imagery.zoomed, MASK_POSITION);
			image_mask_clear(imagery.zoomed, MASK_ORIENTATION);
			image_mask_clear(imagery.zoomed, MASK_OPACITY);
			image_mask_clear(imagery.zoomed, MASK_SCALE);

---- copy the static zoomed image properties and then set the same transform
			resize_image(imagery.zoomed, cprops.width, cprops.height);
			move_image(imagery.zoomed, cprops.x, cprops.y);
			blend_image(imagery.zoomed, cprops.opacity);
			blend_image(imagery.zoomed, 1.0, settings.zoom_countdown);
			
			move_image(imagery.zoomed, settings.zoomp.x, settings.zoomp.y, settings.zoom_countdown);
			resize_image(imagery.zoomed, settings.zoomp.width, settings.zoomp.height, settings.zoom_countdown);
			blend_image(imagery.zoomed, 1.0, settings.zoom_countdown);
			order_image(imagery.zoomed, ZOOMLAYER_MOVIE);
		end
	else
		delete_image(source);
	end
end

function gridle_clock_pulse()
-- used to account for a nasty race condition when zooming a screenshot with asynch movie loading mid-zoom
	if (settings.zoom_countdown > 0) then 
		settings.zoom_countdown = settings.zoom_countdown - 1; 
	end
	
-- the cooldown before loading a movie lowers the number of frameserver launches etc. in
-- situations with a high repeatrate and a button hold down. It also gives the soundeffect
-- change to play without being drowned by an audio track in the movie
	if (settings.cooldown > 0) then
		settings.cooldown = settings.cooldown - 1;

-- cooldown reached, check the current cursor position, use that to figure out which movie to launch
		if (settings.cooldown == 0) then
			local moviefile = settings.cursorgame.resources.movies[1];

			if (moviefile and cursor_vid() ) then
				imagery.movie = load_movie( moviefile, 1, asynch_movie_ready);
				if (imagery.movie) then
					local vprop = image_surface_properties( cursor_vid() );
					
					move_image(imagery.movie, vprop.x, vprop.y);
					order_image(imagery.movie, GRIDLAYER_MOVIE);
					props = image_surface_properties(imagery.movie);
					return
				end
			else
				moviefile = "";
				movietimer = nil;
			end
		end
	end
	
	if (settings.shutdown_timer) then
		settings.shutdown_timer = settings.shutdown_timer - 1;
		if (settings.shutdown_timer == 0) then shutdown(); end
	end
end

function gridle_internalcleanup()
	kbd_repeat(settings.repeat_rate);
	gridle_input = gridle_dispatchinput;

	if (in_internal) then
		order_image(internal_vid, ZOOMLAYER_MOVIE + 1); 
		expire_image(internal_vid, settings.transitiondelay);
		resize_image(internal_vid, 1, 1, settings.transitiondelay);
		audio_gain(internal_aid, 0.0, settings.transitiondelay);
		move_image(internal_vid, VRESW * 0.5, VRESH * 0.5, settings.transitiondelay);
		build_grid(settings.cell_width, settings.cell_height);
	else
		delete_image(internal_vid);
	end
	
	internal_vid = BADID;
	internal_aid = BADID;
	instant_image_transform(internal_vidborder);
	expire_image(internal_vidborder, settings.transitiondelay);
	blend_image(internal_vidborder, 0.0, settings.transitiondelay);
	in_internal = false;
end

function gridle_target_event(source, kind)
	gridle_internalcleanup();
end

-- slightly different from gridledetail
function gridle_internalinput(iotbl)
	local restbl = keyconfig:match(iotbl);
	
	if (restbl) then
		for ind, val in pairs(restbl) do
			if (val == "MENU_ESCAPE" and iotbl.active) then
				gridle_internalcleanup();
				return;
			elseif (val == "MENU_TOGGLE") then
				gridlemenu_internal(internal_vid);
				return;
			end
	
			if (settings.ledmode == 3) then
				ledconfig:set_led_label(val, iotbl.active);
			end
		end
	end
	
	if (settings.internal_input == "Normal") then
		target_input(iotbl, internal_vid);
	elseif (settings.internal_input == "Flip X/Y") then
		
	end
end

function gridle_dispatchinput(iotbl)
	local restbl = keyconfig:match(iotbl);
 
	if (restbl and iotbl.active) then
		for ind,val in pairs(restbl) do
			if (settings.iodispatch[val]) then
				settings.iodispatch[val](restbl, iotbl);
			end
		end
	end
end

gridle_input = gridle_dispatchinput;
