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
	MENU_TOGGLE       = load_asample("sounds/menu_toggle.wav"),
	MENU_FADE         = load_asample("sounds/menu_fade.wav"),
	MENU_SELECT       = load_asample("sounds/menu_select.wav"),
	MENU_FAVORITE     = load_asample("sounds/launch_external.wav"),
	MENUCURSOR_MOVE   = load_asample("sounds/move.wav"),
	GRIDCURSOR_MOVE   = load_asample("sounds/gridcursor_move.wav"),
	GRID_NEWPAGE      = load_asample("sounds/grid_newpage.wav"),
	GRID_RANDOM       = load_asample("sounds/click.wav"),
	SUBMENU_TOGGLE    = load_asample("sounds/menu_toggle.wav"),
	SUBMENU_FADE      = load_asample("sounds/menu_fade.wav"),
	LAUNCH_INTERNAL   = load_asample("sounds/launch_internal.wav"),
	LAUNCH_EXTERNAL   = load_asample("sounds/launch_external.wav"),
	SWITCH_GAME       = load_asample("sounds/switch_game.wav"),
	DETAILVIEW_TOGGLE = load_asample("sounds/detailview_toggle.wav"),
	DETAILVIEW_FADE   = load_asample("sounds/detailview_fade.wav"),
  DETAILVIEW_SWITCH = load_asample("sounds/detailview_switch.wav");
	SET_FAVORITE      = load_asample("sounds/set_favorite.wav"),
	CLEAR_FAVORITE    = load_asample("sounds/clear_favorite.wav"),
	OSDKBD_TOGGLE     = load_asample("sounds/osdkbd_show.wav"),
	OSDKBD_MOVE       = load_asample("sounds/gridcursor_move.wav"),
	OSDKBD_ENTER      = load_asample("sounds/osdkb.wav"),
	OSDKBD_ERASE      = load_asample("sounds/click.wav"),
	OSDKBD_SELECT     = load_asample("sounds/osdkbd_select.wav"),
	OSDKBD_HIDE       = load_asample("sounds/osdkbd_hide.wav")
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
	
	bgname = "smstile.png",
	bg_rh = VRESH / 32,
	bg_rw = VRESW / 32,
	bg_speedh = 64,
	bg_speedv = 64,
	tilebg = "White",
	
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
	movieagain = 1.0,

	favorites = {},
	detailvids = {},
	favvids = {},
	
	repeatrate = 250,
	cell_width = 128,
	cell_height = 128,
	
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

function string.split(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
	
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end
	
	table.insert(res, string.sub(instr, strt));
	return res;
end

function gridle()
-- grab all dependencies;
	settings.colourtable = system_load("scripts/colourtable.lua")();    -- default colour values for windows, text etc.

	system_load("scripts/calltrace.lua")();      -- debug features Trace() and Untrace()
	system_load("scripts/listview.lua")();       -- used by menus (_menus, _intmenus) and key/ledconf
	system_load("scripts/resourcefinder.lua")(); -- heuristics for finding media
	system_load("scripts/dialog.lua")();         -- dialog used for confirmations 
	system_load("scripts/keyconf.lua")();        -- input configuration dialoges
	system_load("scripts/keyconf_mame.lua")();   -- convert a keyconf into a mame configuration
	system_load("scripts/ledconf.lua")();        -- associate input labels with led controller IDs
	system_load("scripts/3dsupport.lua")();      -- used by detailview, simple model/material/shader loader
	system_load("scripts/osdkbd.lua")();         -- on-screen keyboard using only MENU_UP/DOWN/LEFT/RIGHT/SELECT/ESCAPE
	system_load("gridle_menus.lua")();           -- in-frontend configuration options
	system_load("gridle_detail.lua")();          -- detailed view showing either 3D models or game- specific scripts
	
-- make sure that the engine API version and the version this theme was tested for, align.
	if (API_VERSION_MAJOR ~= 0 and API_VERSION_MINOR ~= 5) then
		msg = "Engine/Script API version match, expected 0.5, got " .. API_VERSION_MAJOR .. "." .. API_VERSION_MINOR;
		error(msg);
		shutdown();
	end

-- make sure that we don't have any weird resolution configurations
	if (VRESW < 256 or VRESH < 256) then
	  error("Unsupported resolution (" .. VRESW .. " x " .. VRESH .. ") requested. Check -w / -h arguments.");
	end

-- We'll reduce stack layers (since we don't use them) and increase number of elements on the default one
-- make sure that it fits the resolution of the screen with the minimum grid-cell size, including the white "background"
-- instances etc. Tightly minimizing this value help track down leaks as overriding it will trigger a dump.
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

if (settings.sortfunctions[settings.sortlbl]) then
		table.sort(settings.games, settings.sortfunctions[settings.sortlbl]);
	end
	
-- enable key-repeat events AFTER we've done possible configuration of label->key mapping
	kbd_repeat(settings.repeatrate);

-- setup callback table for input events
	settings.iodispatch["ZOOM_CURSOR"]  = function(iotbl)
		if imagery.zoomed == BADID then
			zoom_cursor(settings.fadedelay);
		else
			remove_zoom(settings.fadedelay);
		end
	end

-- the dispatchtable will be manipulated throughout the theme, simply used as a label <-> function pointer lookup table
-- check gridle_input / gridle_dispatchinput for more detail
	settings.iodispatch["MENU_UP"]      = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 * ncw); end
	settings.iodispatch["MENU_DOWN"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( ncw ); end
	settings.iodispatch["MENU_LEFT"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 ); end
	settings.iodispatch["MENU_RIGHT"]   = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( 1 ); end
	settings.iodispatch["RANDOM_GAME"]  = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( math.random(-#settings.games, #settings.games) ); end
	settings.iodispatch["MENU_ESCAPE"]  = function(iotbl) confirm_shutdown(); end
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

	settings.iodispatch["OSD_KEYBOARD"]  = function(iotbl)
		play_audio(soundmap["OSDKBD_TOGGLE"]);
		osdkbd:show();
		settings.inputfun = gridle_input;
		gridle_input = osdkbd_inputcb;
	end

	settings.iodispatch["DETAIL_VIEW"]  = function(iotbl)
		local gametbl = current_game();
		local key = gridledetail_havedetails(gametbl);
		
		if (key) then
			remove_zoom(settings.fadedelay);
			local gameind = 0;
			blend_image( cursor_vid(), 0.3 );
			play_audio( soundmap["DETAILVIEW_TOGGLE"] ); 
			
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
	set_background(settings.bgname, settings.bg_rw, settings.bg_rh, settings.bg_speedv, settings.bg_speedh);

-- Little star keeping track of games marked as favorites
	imagery.starimage    = load_image("star.png");
	imagery.magnifyimage = load_image("magnify.png");

	build_grid(settings.cell_width, settings.cell_height);
	build_fadefunctions();

	osd_visible = false;
	
	gridle_keyconf();
	gridle_ledconf();
	osdkbd = osdkbd_create();
end

function set_background(name, tilefw, tilefh, hspeed, vspeed)
	if (imagery.bgimage and imagery.bgimage ~= BADID) then
		delete_image(imagery.bgimage);
		imagery.bgimage = nil;
	end

-- shader for an animated background (tiled with texture coordinates aligned to the internal clock)
	local bgshader = load_shader("shaders/anim_txco.vShader", "shaders/diffuse_only.fShader", "background");
	shader_uniform(bgshader, "speedfact", "ff", PERSIST, hspeed, vspeed);
	
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
	imagery.bgimage = load_image("backgrounds/" .. name);
	
	resize_image(imagery.bgimage, VRESW, VRESH);
	image_scale_txcos(imagery.bgimage, VRESW / (VRESW / tilefw), VRESH / (VRESH / tilefh) );
	image_shader(imagery.bgimage, bgshader);
	show_image(imagery.bgimage);
	switch_default_texmode( TEX_CLAMP, TEX_CLAMP );
	
end

function confirm_shutdown()
	local shutdown_dialog = dialog_create("Shutdown Arcan/Gridle?", {"NO", "YES"}, true);
	local asamples = {MENU_LEFT = "MENUCURSOR_MOVE", MENU_RIGHT = "MENUCURSOR_MOVE", MENU_ESCAPE = "MENU_FADE", MENU_SELECT = "MENU_FADE"};
	shutdown_dialog:show();
	play_audio(soundmap["MENU_TOGGLE"]);
	
-- temporarily replace the input function with one that just resolves LABEL and forwards to
-- the shutdown_dialog, if the user cancels (MENU_ESCAPE) or MENU_SELECT on NO, reset the table.
	gridle_input = function(iotbl)
		local restbl = keyconfig:match(iotbl);
		if (restbl and iotbl.active) then
			for ind,val in pairs(restbl) do
				if (asamples[val]) then play_audio(soundmap[asamples[val]]); end
				local iores = shutdown_dialog:input(val);
				if (iores ~= nil) then
						if (iores == "YES") then
							shutdown();
						else
							gridle_input = gridle_dispatchinput;
						end
				end
			end -- more input needed
		end
	end -- of inputfunc.
	
end

-- When OSD keyboard is to be shown, remap the input event handler,
-- Forward all labels that match, but also any translated keys (so that we
-- can use this as a regular input function as well) 	
function osdkbd_inputcb(iotbl)
	if (iotbl.active) then
		local restbl = keyconfig:match(iotbl);
		local resstr = nil;
		local done   = false;

		if (restbl) then
			for ind,val in pairs(restbl) do
				if (val == "MENU_ESCAPE") then
					play_audio(soundmap["OSDKBD_HIDE"]);
					return osdkbd_filter(nil);

				elseif (val == "MENU_SELECT" or val == "MENU_UP" or val == "MENU_LEFT" or 
					val == "MENU_RIGHT" or val == "MENU_DOWN") then
					resstr = osdkbd:input(val);
					play_audio(val == "MENU_SELECT" and soundmap["OSDKBD_SELECT"] or soundmap["OSDKBD_MOVE"]);
							
-- also allow direct keyboard input
				elseif (iotbl.translated) then
					resstr = osdkbd:input_key(iotbl);
				else
				end

-- input/input_key returns the filterstring when finished
				if (resstr) then
					return osdkbd_filter(resstr); 
				end

-- stop processing labels immediately after we get a valid filterstring
			end
		end
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
			blend_image(imagery.bgimage, 0.0, settings.transitiondelay);
			
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
			order_image(internal_vid, 1);
			
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
		
	keyconfig = keyconf_create(keylabels);
	
	if (keyconfig.active == false) then
		kbd_repeat(0);

-- keep a listview in the left-side behind the dialog to show all the labels left to configure
		keyconf_labelview = listview_create(listlbls, VRESH, VRESW / 4);
		keyconf_labelview:show();
		
		local props = image_surface_properties(keyconf_labelview.window, 5);
		if (props.height < VRESH) then
			move_image(keyconf_labelview.anchor, 0, VRESH * 0.5 - props.height* 0.5);
		end
		
		keyconfig:to_front();

-- replace the current input function until we have a working keyconfig
		gridle_input = function(iotbl) -- keyconfig io function hook
			if (keyconfig:input(iotbl) == true) then
				keyconf_tomame(keyconfig, "_mame/cfg/default.cfg"); -- should be replaced with a more generic export interface
				zap_resource("ledsym.lua"); -- delete this one and retry ledconf
				
				gridle_input = gridle_dispatchinput;
				kbd_repeat(settings.repeatrate);
				if (keyconf_labelview) then keyconf_labelview:destroy(); end
				gridle_ledconf();
				
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
	if (keyconfig.active == false) then return; end -- defer ledconf
	
	local ledconflabels = {};

	for ind, val in ipairs(keyconfig:labels()) do
		if (string.match(val, "PLAYER%d") ~= nil) then
			table.insert(ledconflabels, val);
		end
	end

	ledconfig = ledconf_create( ledconflabels );

-- LED config, use a subset of the labels defined in keyconf
	if (ledconfig.active == false) then
		ledconf_labelview = listview_create(ledconflabels, VRESH, VRESW / 4);
		ledconf_labelview:show();
		
		local props = image_surface_properties(ledconf_labelview.window, 5);
		if (props.height < VRESH) then
			move_image(ledconf_labelview.anchor, 0, VRESH * 0.5 - props.height* 0.5);
		end

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

function move_cursor( ofs, absolute )
	local pageofs_cur = settings.pageofs;
	blend_gridcell(0.3, settings.fadedelay);
	remove_zoom(settings.fadedelay);

	settings.gameind = settings.gameind + ofs;
	if (absolute) then settings.gameind = ofs; end
	
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

function zap_whitegrid()
	if (whitegrid == nil) then 
		return; 
	end
	
	for row=0, nch-1 do
		for col=0, ncw-1 do
			if (whitegrid[row] and whitegrid[row][col]) then 
				delete_image(whitegrid[row][col]); 
			end
		end
	end
	
end


function build_whitegrid()
	whitegrid = {};
	
	for row=0, nch-1 do
		whitegrid[row] = {};
		for col=0, ncw-1 do
-- only build new cells if there's a corresponding one in the grid 
			if (settings.tilebg ~= "None" and grid[row][col] ~= nil and grid[row][col] > 0) then
				local gridbg = instance_image(settings.tilebg ~= "Black" and imagery.white or imagery.black);
				
				resize_image(gridbg, settings.cell_width, settings.cell_height);
				move_image(gridbg, cell_coords(col, row));
				image_mask_clear(gridbg, MASK_OPACITY);
				order_image(gridbg, GRIDBGLAYER);
				show_image(gridbg);
			
				whitegrid[row][col] = gridbg;
			end
			
		end
	end
	
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

				grid[row][col] = nil;
			end
		end
	end

	if (imagery.movie and imagery.movie ~= BADID) then
		expire_image(imagery.movie, settings.fadedelay);
		imagery.movie = BADID;
	end
end

function build_grid(width, height)
--  figure out how many full cells we can fit with the current resolution
	zap_whitegrid();
	
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
		
			grid[row][col] = vid;
			settings.cellcount = settings.cellcount + 1;
		end
	end

	build_whitegrid();
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

function load_key_num(name, val, opt)
	local kval = get_key(name)
	if (kval) then
		settings[val] = tonumber(kval);
	else
		settings[val] = opt;
	end
end

function load_key_str(name, val, opt)
	local kval = get_key(name)
	settings[val] = kval or opt
end

-- these should match those of 
-- (a) the standard settings table (all should be set),
-- (b) gridle_menus
function load_settings()
	load_key_num("ledmode", "ledmode", settings.ledmode);
	load_key_num("cell_width", "cell_width", settings.cell_width);
	load_key_num("cell_height", "cell_height", settings.cell_height);
	load_key_num("fadedelay", "fadedelay", settings.fadedelay);
	load_key_num("transitiondelay", "transitiondelay", settings.transitiondelay);
	load_key_str("sortorder", "sortlbl", settings.sortlbl);
	load_key_str("defaultshader", "fullscreenshader", settings.fullscreenshader);
	load_key_num("repeatrate", "repeatrate", settings.repeatrate);
	load_key_num("internal_again", "internal_again", settings.internal_again);
	load_key_str("internal_scalemode", "internal_scalemode", settings.scalemode);
	load_key_num("movieagain", "movieagain", settings.movieagain);
	load_key_str("tilebg", "tilebg", settings.tilebg);
	load_key_num("bg_rh", "bg_rh", settings.bg_rh);
	load_key_num("bg_rw", "bg_rw", settings.bg_rw);
	load_key_num("bg_speedv", "bg_speedv", settings.bg_speedv);
	load_key_num("bg_speedh", "bg_speedh", settings.bg_speedh);
		
-- special handling for a few settings, modeflag + additional processing
	local internalinp = get_key("internal_input");
	if (internalinp ~= nil) then
		settings.internal_input = internalinp;
		settings.flipinputaxis = internalinp ~= "Normal";
	end

-- each shader argument is patched into a boolean table of #defines to tiggle
if (get_key("defaultshader_defs")) then
		settings.fullscreenshader_opts = {};

		local args = string.split(get_key("defaultshader_defs"), ",");
		for ind, val in ipairs(args) do
			settings.fullscreenshader_opts[val] = true;
		end
	end

-- the list of favorites is stored / restored on every program open/close cycle
	if ( open_rawresource("lists/favorites") ) then
		line = read_rawresource();
		while line ~= nil do
			table.insert(settings.favorites, line);
			settings.favorites[line] = true;
			line = read_rawresource();
		end
	end
end

function asynch_movie_ready(source, status)
	if (status == 1 and source == imagery.movie) then
		vid,aid = play_movie(source);
		audio_gain(aid, 0.0);
		audio_gain(aid, settings.movieagain, settings.fadedelay);
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
		if (settings.cooldown == 0 and settings.cursorgame and settings.cursorgame.resources
		and settings.cursorgame.resources.movies[1]) then
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
	kbd_repeat(settings.repeatrate);
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
	blend_image(imagery.bgimage, 1.0, settings.transitiondelay);
	in_internal = false;
end

function gridle_target_event(source, kind)
	gridle_internalcleanup();
end

-- PLAYERn_UP, PLAYERn_DOWN, PLAYERn_LEFT, playern_RIGHT
function rotate_label(label, cw)
	local dirtbl_cw = {UP = "RIGHT", RIGHT = "DOWN", DOWN = "LEFT", LEFT = "UP"};
	local dirtbl_ccw= {UP = "LEFT", RIGHT = "UP", DOWN = "RIGHT", LEFT = "DOWN"};
	
	if (string.sub(label, 1, 6) == "PLAYER") then
		local num = string.sub(label, 7, 7);
		local dir = cw and dirtbl_cw[ string.sub(label, 9) ] or dirtbl_ccw[ string.sub(label, 9) ];
		return dir and ("PLAYER" .. num .."_" .. dir) or nil;
	end
	
	return nil;
end

-- slightly different from gridledetails version
function gridle_internalinput(iotbl)
	local restbl = keyconfig:match(iotbl);

-- We don't forward / allow the MENU_ESCAPE or the MENU TOGGLE buttons at all. 
	if (restbl) then
		for ind, val in pairs(restbl) do
			if (val == "MENU_ESCAPE" and iotbl.active) then
				gridle_internalcleanup();
				return;
			elseif (val == "MENU_TOGGLE") then
				gridlemenu_internal(internal_vid);
				return;
			end
			
			if (settings.internal_input == "Rotate CW" or settings.internal_input == "Rotate CCW") then
				val = rotate_label(val, settings.internal_input == "Rotate CW");
				
				if (val ~= nil) then
					res = keyconfig:buildtbl(val, iotbl);

					if (res) then
						target_input(res, internal_vid);
						return;
					end
				end
			end
		
-- toggle corresponding button LEDs if we want to light only on push
			if (settings.ledmode == 3) then
				ledconfig:set_led_label(val, iotbl.active);
			end
		end
	end	

	-- negate analog axis values 
	if (settings.internal_input == "Invert Axis (analog)") then
		if (iotbl.kind == "analog") then
			iotbl.subid = iotbl.subid == 0 and 1 or 0;
		end

-- figure out the image center, calculate offset and negate that
	elseif (settings.internal_input == "Mirror Axis (analog)") then
		if (iotbl.kind == "analog") then
			if ( (iotbl.subid + 1) % 2 == 0 ) then -- treat as Y
				local center = image_surface_initial_properties(internal_vid).height * 0.5;
				iotbl.samples[1] = center + (center - iotbl.samples[1]);
			else -- treat as X 
				local center = image_surface_initial_properties(internal_vid).width * 0.5;
				iotbl.samples[1] = center + (center - iotbl.samples[1]);
			end
		end
	end

	target_input(iotbl, internal_vid);
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
