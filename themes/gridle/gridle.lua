grid = {};
filter_label_statetbl = {};

internal_vid = BADID;
internal_aid = BADID;

-- shared images, statebased vids etc.
imagery = {
	movie = nil,
	black = BADID,
	white = BADID,
	bgimage = BADID, 
	temporary = {}
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

 BGLAYER = 0;
 GRIDBGLAYER = 1;
 GRIDLAYER = 3;
 GRIDLAYER_MOVIE = 4;
 GRIDLAYER_ZOOM  = 5;
 ICONLAYER = 7;

settings = {
	filters = {
	},
	
	bgname = "smstile.png",
	bg_rh = VRESH / 32,
	bg_rw = VRESW / 32,
	bg_speedh = 64,
	bg_speedv = 64,
	tilebg = "Sysicons",
	
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
	cursor_scale = 1.2,
	
	cooldown = 15,
	cooldown_start = 15,
	
	default_launchmode = "Internal",

	crt_gamma = 2.4,
	crt_mongamma = 2.2,
	crt_hoverscan = 1.02,
	crt_voverscan = 1.02,
	crt_haspect = 1.0,
	crt_vaspect = 0.75,
	crt_curvrad = 1.5, 
	crt_distance = 2.0,
	crt_tilth = 0.0,
	crt_tiltv = -0.15, 
	crt_cornersz = 0.03,
	crt_cornersmooth = 1000,
	crt_curvature = true,
	crt_gaussian = true,
	crt_oversample = true,
	crt_linearproc = false,
	
	vector_linew = 1,
	vector_pointsz = 2,
	vector_hblurscale = 0.6,
	vector_vblurscale = 0.6,
	vector_vblurofs = 0, 
	vector_hblurofs = 0,
	vector_vbias = 1.0,
	vector_hbias = 1.2,
	vector_trailstep = -4,
	vector_trailfall = 1,
	vector_glowtrails = 0,

	ntsc_hue        = 0.0,
	ntsc_saturation = 0.0,
	ntsc_contrast   = 0.0,
	ntsc_brightness = 0.0,
	ntsc_gamma      = 0.2,
	ntsc_sharpness  = 0.0,
	ntsc_resolution = 0.7,
	ntsc_artifacts  =-1.0,
	ntsc_bleed      =-1.0,
	ntsc_fringing   =-1.0,
	
	record_qual = 10,
	record_res  = 240,
	record_fps  = 30,
	record_format = "WebM (VP8/Vorbis)",
	
	imagefilter = "Bilinear",
	
-- All settings that pertain to internal- launch fullscreen modes
	internal_input = "Normal",
	internal_toggles = {crt = false, vector = false, backdrop = false, ntsc = false, upscale = false, overlay = false, antialias = false},
	internal_notoggles = {crt = false, vector = false, backdrop = false, ntsc = false, upscale = false, overlay = false, antialias = false}, -- used by detailview
	
	flipinputaxis = false,
	filter_opposing= false, 
	internal_again = 1.0,
	fullscreenshader = "default",
	in_internal = false,
	cocktail_mode = "Disabled",
	autosave = "On",
	view_mode = "Grid",
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

function gridle_launchexternal()
	erase_grid(true);
	play_audio(soundmap["LAUNCH_EXTERNAL"]);
	launch_target( current_game().gameid, LAUNCH_EXTERNAL);
	move_cursor(0);
	build_grid(settings.cell_width, settings.cell_height);
end

function gridle_launchinternal()
	play_audio(soundmap["LAUNCH_INTERNAL"]);

	if (valid_vid(internal_vid)) then
		delete_image(internal_vid);
	end
	
	internal_vid = launch_target( current_game().gameid, LAUNCH_INTERNAL, gridle_internal_status );
end

error_nogames = nil;

local function menu_bgupdate() 
	grab_sysicons();
	zap_whitegrid();
	build_whitegrid();
	set_background(settings.bgname, settings.bg_rw, settings.bg_rh, settings.bg_speedv, settings.bg_speedh)	
end

function gridle()
-- grab all dependencies;
	settings.colourtable = system_load("scripts/colourtable.lua")(); -- default colour values for windows, text etc.

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
	system_load("gridle_contmenus.lua")();       -- context menus (quickfilter, database manipulation, ...)
	system_load("gridle_detail.lua")();          -- detailed view showing either 3D models or game- specific scripts
	system_load("gridle_customview.lua")();      -- customizable list view
	
	if (DEBUGLEVEL > 1) then
		Trace();
	end
	
-- make sure that the engine API version and the version this theme was tested for, align.
	if (API_VERSION_MAJOR ~= 0 and API_VERSION_MINOR ~= 6) then
		msg = "Engine/Script API version match, expected 0.6, got " .. API_VERSION_MAJOR .. "." .. API_VERSION_MINOR;
		error(msg);
		shutdown();
	end

-- make sure that we don't have any weird resolution configurations
	if (VRESW < 240 or VRESH < 180) then
	  error("Unsupported resolution (" .. VRESW .. " x " .. VRESH .. ") requested (minimum 240x180). Check -w / -h arguments.");
	end

-- We'll reduce stack layers (since we don't use them) and increase number of elements on the default one
-- make sure that it fits the resolution of the screen with the minimum grid-cell size, including the white "background"
-- instances etc. Tightly minimizing this value help track down leaks as overriding it will trigger a dump.
	local contextlim = ( VRESW * VRESH ) / (48 * 48) * 4;
	contextlim = contextlim > 1024 and contextlim or 1024
	system_context_size(contextlim);

-- make sure the current context runs with the new limit
	pop_video_context();

-- keep an active list of available games, make sure that we have something to play/show
-- since we want a custom sort, we'll have to keep a table of all the games (expensive)
	settings.games = list_games( {} );

	if (not settings.games or #settings.games == 0) then
		error_nogames();
		return;
	end

-- any 3D rendering (models etc.) should happen after any 2D surfaces have been drawn as to not be occluded
	video_3dorder(ORDER_LAST); 

-- use the DB theme-specific key/value store to populate the settings table
	load_settings();
	
	if (settings.sortfunctions[settings.sortlbl]) then
		table.sort(settings.games, settings.sortfunctions[settings.sortlbl]);
	end
	
-- enable key-repeat events AFTER we've done possible configuration of label->key mapping
	kbd_repeat(settings.repeatrate);
	
-- the dispatchtable will be manipulated throughout the theme, simply used as a label <-> function pointer lookup table
-- check gridle_input / gridle_dispatchinput for more detail
	settings.iodispatch["MENU_UP"]      = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 * ncw); end
	settings.iodispatch["MENU_DOWN"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( ncw ); end
	settings.iodispatch["MENU_LEFT"]    = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( -1 ); end
	settings.iodispatch["MENU_RIGHT"]   = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( 1 ); end
	settings.iodispatch["RANDOM_GAME"]  = function(iotbl) play_audio(soundmap["GRIDCURSOR_MOVE"]); move_cursor( math.random(-#settings.games, #settings.games) ); end
	settings.iodispatch["MENU_ESCAPE"]  = function(iotbl) confirm_shutdown(); end
	settings.iodispatch["QUICKSAVE"]    = function(iotbl) end
	settings.iodispatch["QUICKLOAD"]    = function(iotbl) end
	
	settings.iodispatch["FLAG_FAVORITE"]= function(iotbl)
		local ind = table.find(settings.favorites, current_game().title);
		
		if (ind == nil) then -- flag
			table.insert(settings.favorites, current_game().title);
			local props = image_surface_properties( cursor_bgvid() );
			settings.favorites[current_game().title] = spawn_favoritestar(props.x, props.y);
			play_audio(soundmap["SET_FAVORITE"]);

		else -- unflag
			fvid = settings.favorites[current_game().title];
			if (valid_vid(fvid)) then
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

	settings.iodispatch["SWITCH_VIEW"] = function(iotbl)
		play_audio( soundmap["DETAILVIEW_TOGGLE"] );
		imagery.sysicons = nil;
		gridle_customview();
	end
	
	settings.iodispatch["DETAIL_VIEW"]  = function(iotbl)
		local gametbl = current_game();
		local key = find_cabinet_model(gametbl);

		if (key) then
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
		gridlemenu_settings(gridlemenu_filterchanged, menu_bgupdate); 
	end
	
	settings.iodispatch["CONTEXT"] = function(iotbl)
		play_audio(soundmap["MENU_TOGGLE"]);
		gridlemenu_context( current_game() );
	end
	
	settings.iodispatch["LAUNCH"] = function(iotbl)
		local launch_internal = (settings.default_launchmode == "Internal" or current_game().capabilities.external_launch == false)
			and current_game().capabilities.internal_launch;

-- can also be invoked from the context menus
		if (launch_internal) then
			gridle_launchinternal();
		else
			gridle_launchexternal();
		end
	end

	build_fadefunctions();
	osd_visible = false;

-- slightly complicated, we cannot activate the respective grid mode in the case of customview etc. 
-- as it will pop context, manipulate I/O handlers etc. so let the keyconf / ledconf set it all up.
	local lfun = settings.view_mode == "Grid" and setup_gridview or gridle_customview;
	
	gridle_keyconf(lfun);
	gridle_ledconf(lfun);
end

-- to save resources when going from customview to grid view
-- the entire context is poped meaning that all involved resources need to be rebuilt
function setup_gridview()
	grab_sysicons();
	setup_3dsupport();
	set_background(settings.bgname, settings.bg_rw, settings.bg_rh, settings.bg_speedv, settings.bg_speedh);

	imagery.black = fill_surface(1,1,0,0,0);
	image_tracetag(imagery.black, "black");
	
	imagery.white = fill_surface(1,1,255,255,255);
	image_tracetag(imagery.white, "white");
	
-- Little star keeping track of games marked as favorites
	imagery.starimage    = load_image("images/star.png");
	image_tracetag(imagery.starimage, "favorite icon");

-- shown when a framserver / internal launch crashes
	imagery.crashimage   = load_image("images/terminated.png");
	image_tracetag(imagery.crashimage, "terminated");

	resize_image(imagery.crashimage, VRESW * 0.5, VRESH * 0.5);
	move_image(imagery.crashimage, 0.5 * (VRESW - (VRESW * 0.5)), 0.5 * (VRESH - (VRESH * 0.5)));

	imagery.magnifyimage = load_image("images/magnify.png");
	image_tracetag(imagery.magnifyimage, "detailview icon");

	settings.cleanup_toggle = gridle_internalcleanup;
	build_grid(settings.cell_width, settings.cell_height);

	current_game = function() 
		return settings.games[settings.cursor + settings.pageofs + 1];
	end
	
	osdkbd = osdkbd_create();
	osdkbd:hide();
end

function set_background(name, tilefw, tilefh, hspeed, vspeed)
	if (imagery.bgimage and valid_vid(imagery.bgimage)) then
		delete_image(imagery.bgimage);
		imagery.bgimage = nil;
	end

-- shader for an animated background (tiled with texture coordinates aligned to the internal clock)
	local bgshader = load_shader("shaders/anim_txco.vShader", "shaders/anim_txco.fShader", "background");
	shader_uniform(bgshader, "speedfact", "ff", PERSIST, hspeed, vspeed);
	
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );

	imagery.bgimage = load_image("backgrounds/" .. name);
	image_tracetag(imagery.bgimage, "background");
	
	resize_image(imagery.bgimage, VRESW, VRESH);
	image_scale_txcos(imagery.bgimage, VRESW / (VRESW / tilefw), VRESH / (VRESH / tilefh) );
	image_shader(imagery.bgimage, bgshader);
	show_image(imagery.bgimage);
	order_image(imagery.bgimage, GRIDBGLAYER); 
	switch_default_texmode( TEX_CLAMP, TEX_CLAMP );
end

function dialog_option( message, buttons, samples, canescape, valcbs, cleanuphook )
	local asamples = {MENU_LEFT = "MENUCURSOR_MOVE", MENU_RIGHT = "MENUCURSOR_MOVE", MENU_ESCAPE = "MENU_FADE", MENU_SELECT = "MENU_FADE"};
	if (samples == nil) then samples = asamples; end
	local dialogwin = dialog_create(message, buttons, canescape );
	
	play_audio(soundmap["MENU_TOGGLE"]);
	dialogwin:show();
	
	gridle_input = function(iotbl)
		local restbl = keyconfig:match(iotbl);
		if (restbl and iotbl.active) then
			for ind, val in pairs(restbl) do
				if (samples[ val ]) then play_audio(soundmap[samples[val]]); end
				local iores = dialogwin:input(val);

				if (iores ~= nil) then
					gridle_input = gridle_dispatchinput;
					if (valcbs[iores]) then
						valcbs[iores]();
					end

					if (cleanuphook) then
						cleanuphook();
					end
				end
			end
		end

	end

end

function confirm_shutdown()
	local valcbs = {};
	valcbs["YES"] = function() shutdown(); end

	video_3dorder(ORDER_NONE);
	dialog_option(settings.colourtable.fontstr .. "Shutdown Arcan/Gridle?", {"NO", "YES"}, nil, true, valcbs, function() video_3dorder(ORDER_LAST); end);
end

-- also used in intmenus for savestate naming
function osdkbd_inputfun(iotbl, dstkbd)
	if (iotbl.active) then
		local restbl = keyconfig:match(iotbl);
		local done   = false;
		local resstr = nil;

		if (restbl) then
			for ind,val in pairs(restbl) do
				if (val == "MENU_ESCAPE") then
					play_audio(soundmap["OSDKBD_HIDE"]);
					return true, nil

				elseif (val == "MENU_SELECT" or val == "MENU_UP" or val == "MENU_LEFT" or 
					val == "MENU_RIGHT" or val == "MENU_DOWN") then
					resstr = dstkbd:input(val);
					
					play_audio(val == "MENU_SELECT" and soundmap["OSDKBD_SELECT"] or soundmap["OSDKBD_MOVE"]);
							
-- also allow direct keyboard input
				elseif (iotbl.translated) then
					resstr = dstkbd:input_key(iotbl);
				end
-- stop processing labels immediately after we get a valid filterstring
			end
		else -- still need to try and input even if we didn't find a matching value
			if (iotbl.translated) then
				resstr = dstkbd:input_key(iotbl);
			end
		end

		if (resstr) then
			return true, resstr; 
		end	
	end
	
	return false, nil
end

function osdkbd_inputcb(iotbl)
	local complete, resstr = osdkbd_inputfun(iotbl, osdkbd);
	
	if (complete) then
		osdkbd_filter(resstr);
	end
end

function gridle_delete_internal_extras()
if (valid_vid(imagery.backdrop)) then 
			delete_image(imagery.backdrop); 
			imagery.backdrop = BADID;
		end
	
		if (valid_vid(imagery.overlay)) then 
			delete_image(imagery.overlay); 
			imagery.overlay = BADID;
		end
		
		if (valid_vid(imagery.bezel)) then
			delete_image(imagery.bezel);
			imagery.bezel = BADID;
		end
end
	
function gridle_load_internal_extras(restbl, tgt)
	if (restbl) then
		if (restbl.bezels and restbl.bezels[1]) then 
			imagery.bezel = load_image_asynch(restbl.bezels[1]);
			image_tracetag(imagery.bezel, "bezel");
		elseif (resource("bezels/" .. tgt .. ".png")) then
			imagery.bezel = load_image_asynch("bezels/" .. tgt .. ".png");
			image_tracetag(imagery.bezel, "bezel");
		end
			
		if (restbl.overlays and restbl.overlays[1]) then
			imagery.overlay = load_image_asynch(restbl.overlays[1]); 
			image_mask_clear(imagery.overlay, MASK_LIVING);
			image_tracetag(imagery.overlay, "overlay");
		end 
		if (restbl.backdrops and restbl.backdrops[1]) then
			imagery.backdrop = load_image_asynch(restbl.backdrops[1]);
			image_mask_clear(imagery.backdrop, MASK_LIVING);
			image_tracetag(imagery.backdrop, "backdrop");
		end
	end
end

function gridle_setup_internal(video, audio)
	settings.in_internal = true;
	toggle_mouse_grab(MOUSE_GRABON);

	gridle_load_internal_extras(current_game().resources, current_game().target);
	
	if (settings.autosave == "On") then
		internal_statectl("auto", false);
	end
	
	internal_aid = audio;
	internal_vid = video;
	
	settings.internal_toggles.bezel = false;
	settings.internal_toggles.overlay = false;
	settings.internal_toggles.backdrops = false;

	order_image(internal_vid, max_current_image_order());
	audio_gain(internal_aid, settings.internal_again, NOW);

-- remap input function to one that can handle forwarding and have access to context specific menu
	gridle_oldinput = gridle_input;
	gridle_input = gridle_internalinput;
	
	gridlemenu_rebuilddisplay();
	
-- don't need these running in the background 
	erase_grid(true);
	zap_whitegrid();

	blend_image(imagery.bgimage, 0.0, settings.transitiondelay);
	blend_image(video, 1.0, settings.transitiondelay);
	
	if (imagery.movie and imagery.movie ~= BADID) then 
		delete_image(imagery.movie); 
		imagery.movie = nil; 
	end

	settings.keyconftbl = keyconfig.table;
	set_internal_keymap();
end

function keyconf_helper(message)
	if (infowin) then
		infowin:destroy();
	end

	if (message == nil) then return; end
	
-- use a quadrant away from the current item
	infowin = listview_create( message, VRESW, VRESH / 2 );
	infowin:show();
	infowin:move_cursor(0);
	
	hide_image(infowin.cursorvid);
	local props = image_surface_properties(infowin.border, 100);
	move_image(infowin.anchor, math.floor( 0.5 * (VRESW - props.width)), VRESH - props.height);
end

function gridle_keyconf(defer_fun)
	local keylabels = {
		"rMENU_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT", "rLAUNCH", " CONTEXT", "rMENU_TOGGLE", " DETAIL_VIEW", " SWITCH_VIEW", " FLAG_FAVORITE",
		" RANDOM_GAME", " OSD_KEYBOARD", " QUICKSAVE", " QUICKLOAD" };

	local helplabels = {};
	helplabels["FLAG_FAVORITE"] = {"(grid-view) Mark game as a favorite.", "(menus) Toggle and save a setting."};
	helplabels["MENU_TOGGLE"  ] = {"(grid-view) Show global settings, filter options.", "(internal-launch) Show display options, record video, remap keys."};
	helplabels["CONTEXT"      ] = {"(grid-view) Use selected game as filter, force specific launch-mode.", 
			"(detail view) Zoom in/out, switch between 3D model and full-screen.", 
			"(internal-launch) Show game-specific options, state saving, reconfigure game-specific input.",
			"(internal-launch-menus) (Spyglass options), show option details."
	};
	helplabels["DETAIL_VIEW"  ] = {"(grid-view) If a spyglass icon is present, switch to a 3D model of the selected game."};
	helplabels["SWITCH_VIEW"  ] = {"(grid-view) Switch to customized view mode.", "(customview-setup) When placing an item, switch active property."};
	helplabels["OSD_KEYBOARD" ] = {"(grid-view) Use an on-screen keyboard to filter current list of games."};
	helplabels["RANDOM_GAME"  ] = {"(grid-view, custom-view) Move the cursor to a random location.", "(internal-launch) Toggle fast-forward on/off (where applicable)."};
	
	local listlbls = {};
	local lastofs = 1;
	
	system_load("gridle_intmenus.lua")();

	for ind, key in ipairs(keylabels) do
		table.insert(listlbls, string.sub(key, 2));
	end
		
	keyconfig = keyconf_create(keylabels);
	
	if (keyconfig.active == false) then
		kbd_repeat(0);

-- keep a listview in the left-side behind the dialog to show all the labels left to configure
		keyconf_labelview = listview_create(listlbls, VRESH * 0.9, VRESW / 4);
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
				gridle_ledconf(defer_fun);

			else -- more keys to go, labelview MAY disappear but only if the user defines PLAYERn_BUTTONm > 0
				if (keyconfig.ofs ~= lastofs and keyconf_labelview) then 
					lastofs = keyconfig.ofs;
					keyconf_labelview:move_cursor(1, 1); 
					keyconf_helper( helplabels[ keyconf_labelview:select() ] );

				elseif (keyconfig.playerconf and keyconf_labelview) then
					keyconf_labelview:destroy();
					keyconf_helper();
					keyconf_labelview = nil;
				end
			end
		end

		return false;
	else
		return true;
	end
end
 
-- very similar to gridle_keyconf, only real difference is that the labels are a subset
-- of the output from keyconf (PLAYERn)
function gridle_ledconf(defer_fun)
	if (keyconfig.active == false) then 
		return; 
	end -- defer ledconf

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
			move_image(ledconf_labelview.anchor, 0, math.floor(VRESH * 0.5 - props.height* 0.5));
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
					if (defer_fun) then
						defer_fun();
					end
				else -- more input
					if (ledconfig.lastofs ~= ledconfig.labelofs) then
							ledconfig.lastofs = ledconfig.labelofs;
							ledconf_labelview:move_cursor(1, 1);
					end
				end
			end
		end

-- already got working LEDconf, or no point in trying to configure one.
	else
		init_leds();
		if (defer_fun) then 
			defer_fun();
		end
	end
end

function current_game_cellid()
	return settings.cursor + settings.pageofs + 1;
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

function spawn_magnify( x, y )
	local maginst = instance_image(imagery.magnifyimage);
	image_tracetag(maginst, "magnify image instance");

	image_mask_clear(maginst, MASK_OPACITY);
	force_image_blend(maginst);

	order_image(maginst, ICONLAYER);
	show_image(maginst, 1.0);
	resize_image(maginst, 1, 1, NOW);
	resize_image(maginst, settings.cell_width * 0.1, settings.cell_width * 0.1, settings.fadedelay);
	move_image(maginst, x, y, NOW);
	
	table.insert(settings.detailvids, maginst);
	
	return maginst;
end

function spawn_warning( message )
-- render message and make sure it is on top
	local vid = render_text(settings.colourtable.alert_fontstr .. string.gsub(message, "\\", "\\\\") );
	image_tracetag(vid, "warning message");
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
	expire_image(vid, 125);
	blend_image(vid, 0.0, 125);
end

function spawn_favoritestar( x, y )
	local vid = instance_image(imagery.starimage);
	image_tracetag(vid, "favorite instance");
	
	image_mask_clear(vid, MASK_SCALE);
	image_mask_clear(vid, MASK_OPACITY);
	force_image_blend(vid);

	move_image(vid, x, y, 0);
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
		
		if (gamelist and #gamelist > 0) then
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
	
	if (status.kind == "loaded") then
		if (source == gridcell_vid) then
			blend_image(source, 1.0, settings.transitiondelay);
		else
			blend_image(source, 0.3, settings.transitiondelay);
		end
		
		local neww = source == cursor_vid() and (settings.cell_width * settings.cursor_scale) or settings.cell_width;
		local newh = source == cursor_vid() and (settings.cell_height * settings.cursor_scale) or settings.cell_height;

		order_image(source, GRIDLAYER);
		order_image(cursor_vid(), GRIDLAYER_ZOOM);
		resize_image(source, neww, newh);
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

function cursor_vid()
	local cursor_row = math.floor( settings.cursor / ncw);
	return grid[cursor_row][settings.cursor - cursor_row * ncw ];
end

function cursor_bgvid()
	local cursor_row = math.floor( settings.cursor / ncw );
	return whitegrid[cursor_row][settings.cursor - cursor_row * ncw];
end

function blend_gridcell(val, dt)
	local gridcell_vid = cursor_vid();

	if (gridcell_vid) then
		instant_image_transform(gridcell_vid);
		blend_image(gridcell_vid, val, dt);
		
		if (settings.cursor_scale > 1.0) then
			if (val < 0.9) then
				local x,y = cell_coords( math.floor(settings.cursor % ncw), math.floor(settings.cursor / ncw) );
			
				local neww = settings.cell_width / settings.cursor_scale;
				local newh = settings.cell_height / settings.cursor_scale;
				local props = image_surface_properties(gridcell_vid);
				
				move_image(gridcell_vid, x, y, dt);
				resize_image(gridcell_vid, settings.cell_width, settings.cell_height, dt);
				order_image(gridcell_vid, GRIDLAYER); 
-- Fading out, reposition / rescale
			else
-- Fading in, reposition / rescale
				local neww  = settings.cell_width * settings.cursor_scale;
				local newh  = settings.cell_height * settings.cursor_scale;
				local x,y = cell_coords( math.floor(settings.cursor % ncw), math.floor(settings.cursor / ncw) )	;
				move_image(gridcell_vid, x - 0.5 * (neww - settings.cell_width), y - 0.5 * (newh - settings.cell_height), dt);
				resize_image(gridcell_vid, settings.cell_width * settings.cursor_scale, settings.cell_height * settings.cursor_scale, dt);
				order_image(gridcell_vid, GRIDLAYER_ZOOM); 
			end

		end
	end
end

function move_cursor( ofs, absolute )
	local pageofs_cur = settings.pageofs;
	blend_gridcell(0.3, settings.fadedelay);

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
function get_image( resourcetbl, gametbl )
	local rvid     = BADID;
	local mediares = resourcetbl:find_identity_image()
	
	if ( mediares ) then
		rvid = load_image_asynch( mediares, got_asynchimage );
		image_tracetag(rvid, "get_image(" .. mediares .. ")");
		blend_image(rvid, 0.0); -- don't show until loaded 
	end
	
	return rvid;
end

function grab_sysicons()
	if (imagery.sysicons ~= nil) then return; end

	list = glob_resource("images/systems/*.png", ALL_RESOURCES);

	imagery.sysicons = {};
	for ind, val in ipairs(list) do
		local sysname = string.sub(val, 1, -5);
		local imgid = load_image("images/systems/" .. val);
			
		if (imgid) then
			imagery.sysicons[sysname] = imgid;
			image_tracetag(imgid, "system icon");
		end
	end
end

function zap_whitegrid()
	if (whitegrid == nil) then 
		return; 
	end
	
	for row=0, nch-1 do
		for col=0, ncw-1 do
			if (whitegrid[row] and whitegrid[row][col] and valid_vid(whitegrid[row][col])) then 
				delete_image(whitegrid[row][col]); 
			end
		end
	end
	
	whitegrid = nil;
end

function build_whitegrid()
	whitegrid = {};
	
	for row=0, nch-1 do
		whitegrid[row] = {};
		for col=0, ncw-1 do
-- only build new cells if there's a corresponding one in the grid 
			if (grid[row][col] ~= nil and grid[row][col] > 0) then
				local gameno = (row * ncw + col + settings.pageofs + 1);
				local gametbl = settings.games[gameno];
				local gridbg = BADID;
	
				if (gametbl and gametbl.system and settings.tilebg == "Sysicons") then
					local icon = imagery.sysicons[ string.lower(gametbl.system) ];
					if (icon) then 
						gridbg = instance_image(icon); 
						image_tracetag(gridbg, "system icon instance");
					end
				end
				
				if (gridbg == BADID) then
					gridbg = instance_image(settings.tilebg == "Black" and imagery.black or imagery.white);
					image_tracetag(gridbg, "background tile instance");
				end
				
				resize_image(gridbg, settings.cell_width, settings.cell_height);
				move_image(gridbg, cell_coords(col, row));
				image_mask_clear(gridbg, MASK_OPACITY);
				order_image(gridbg, GRIDBGLAYER);
				
-- we have hidden images for the "None" mode to use the positioning for snapshots etc.
-- so we attach other images to the "right" vid position.
				if (settings.tilebg == "None") then
					hide_image(gridbg);
				else
					show_image(gridbg);
				end
				
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

-- try to fit msg into a cell
local function titlestr(msg)
	local basemsg = string.gsub(msg, "\\", "\\\\");
	local fontheight = math.ceil( settings.cell_height * 0.5 );
	local bgcolor = settings.tilebg == "Black" and [[\#ffffff]] or [[\#0000ff]];
	local fontstr = settings.colourtable.font .. tostring(fontheight) .. "\\b" .. bgcolor;
	
	local vid, lines = render_text(fontstr .. basemsg);
	resize_image(vid, settings.cell_width, settings.cell_height);
	image_tracetag(vid, "title_string");
	
	return vid;
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
			local cx, cy = cell_coords(col, row);

			if (settings.games[gameno] == nil) then break; end
			settings.games[gameno].resources = resourcefinder_search( settings.games[gameno], true);
			settings.games[gameno].capabilities = launch_target_capabilities( settings.games[gameno].target );
		
			local vid = get_image(settings.games[gameno].resources, settings.games[gameno]);
			if (vid == BADID) then
				vid = titlestr( settings.games[gameno].title );
				local props = image_surface_properties(vid);
				move_image(vid, cx + 0.5 * (settings.cell_width - props.width), cy + 0.5 * (settings.cell_height - props.height));
				blend_image(vid, 0.3);
			else
				resize_image(vid, settings.cell_width, settings.cell_height);
				move_image(vid, cell_coords(col, row));
			end
			
			order_image(vid, GRIDLAYER);

			if (settings.favorites[ settings.games[gameno].title ]) then
				settings.favorites[ settings.games[gameno].title ] = spawn_favoritestar( cx, cy );
			end

			if (find_cabinet_model( settings.games[gameno] )) then
				spawn_magnify(cx, cy + settings.cell_height * 0.1 );
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
				warning("Couldn't save favorites in lists/favorites. Check permissions.");
				break;
			end
		end

		close_rawresource();
	end
end

function load_key_num(name, val, opt)
	local kval = get_key(name);
	if (kval) then
		settings[val] = tonumber(kval);
	else
		settings[val] = opt;
	end
end

function load_key_bool(name, val, opt)
	local kval = get_key(name);
	
	if (kval) then
		settings[val] = tonumber(kval) > 0;
	else
		settings[val] = false;
	end
end

function load_key_str(name, val, opt)
	local kval = get_key(name);
	settings[val] = kval or opt
end


function asynch_movie_ready(source, statustbl)
	if (imagery.movie == source) then
		if (statustbl.kind == "resized") then
-- capture loop events .. 
			if (imagery.playing == source) then
				return;
			end
			if (valid_vid(imagery.zoomed)) then
				local newinst = instance_image(source);
				image_tracetag(newinst, "movie zoom");
	
				image_mask_clear(newinst, MASK_POSITION);
				copy_image_transform(imagery.zoomed, newinst);
				reset_image_transform(newinst);
				delete_image(imagery.zoomed);

				imagery.zoomed = newinst;
				gridlemenu_setzoom(newinst, source); -- use new aspect ratio
			end

			vid, aid = play_movie(source);
			audio_gain(aid, 0.0);
			audio_gain(aid, settings.movieagain, settings.fadedelay);

			copy_image_transform( cursor_vid(), source );
			blend_image(cursor_vid(), 0.0, settings.fadedelay);

			imagery.playing = vid;
		end
	else
		delete_image(source);
	end
end

function gridle_clock_pulse()
-- the cooldown before loading a movie lowers the number of frameserver launches etc. in
-- situations with a high repeatrate and a button hold down. It also gives the soundeffect
-- change to play without being drowned by an audio track in the movie
	if (settings.cooldown > 0 and settings.cooldown_start > 0) then
		settings.cooldown = settings.cooldown - 1;

-- cooldown reached, check the current cursor position, use that to figure out which movie to launch
		if (settings.cooldown == 0 and settings.cursorgame and settings.cursorgame.resources
		and settings.cursorgame.resources.movies[1]) then
			local moviefile = settings.cursorgame.resources.movies[1];

			if (moviefile and cursor_vid() ) then
				imagery.movie = load_movie( moviefile, FRAMESERVER_LOOP, asynch_movie_ready);
				if (imagery.movie) then
					local vprop = image_surface_properties( cursor_bgvid() );
					
					move_image(imagery.movie, vprop.x, vprop.y);
					order_image(imagery.movie, GRIDLAYER_MOVIE);
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
	hide_image(imagery.crashimage);
	keyconfig.table = settings.keyconftbl;
	
	
	if (settings.in_internal) then
		gridle_delete_internal_extras();
		
		if (settings.autosave == "On") then
-- note, this is currently not blocking, and the frameserver termination can be quite
-- aggressive, so there is a possibility for a race-condition here, hacking a safeguard in the meantime.
-- the real solution would be to wait for frameserver to flush event buffer or 'n' seconds, whatever comes first. 
			internal_statectl("auto", true);
			expire_image(internal_vid, 20);
		else
			expire_image(internal_vid, settings.transitiondelay);
		end
		undo_displaymodes();
		
		resize_image(internal_vid, 1, 1, settings.transitiondelay);
		blend_image(internal_vid, 0.0, settings.transitiondelay);
		audio_gain(internal_aid, 0.0, settings.transitiondelay);
		move_image(internal_vid, VRESW * 0.5, VRESH * 0.5, settings.transitiondelay);

		if (valid_vid(imagery.bezel)) then
			blend_image(imagery.bezel, 0.0, settings.transitiondelay);
			expire_image(imagery.bezel, settings.transitiondelay);
		end
		
		if (valid_vid(imagery.cocktail_vid)) then
			image_mask_clear(imagery.cocktail_vid, MASK_POSITION);
			expire_image(imagery.cocktail_vid, settings.transitiondelay);
			resize_image(imagery.cocktail_vid, 1, 1, settings.transitiondelay);
			blend_image(imagery.cocktail_vid, 0.0, settings.transitiondelay);
			move_image(imagery.cocktail_vid, VRESW * 0.5, VRESH * 0.5, settings.transitiondelay);
			imagery.cocktail_vid = BADID;
		end

		build_grid(settings.cell_width, settings.cell_height);
	else
		delete_image(internal_vid);
	end
	
	internal_vid = BADID;
	internal_aid = BADID;
	blend_image(imagery.bgimage, 1.0, settings.transitiondelay);
	settings.in_internal = false;
	
-- since the user might have added screenshots or recorded a snapshot,
-- we need to invalidate the cache and rescan the globs in question 
	resourcefinder_cache.invalidate = true;
		local gameno = current_game_cellid();
		settings.games[gameno].resources = resourcefinder_search( settings.games[gameno], true);
	resourcefinder_cache.invalidate = false;
end

function gridle_internal_status(source, datatbl)
	if (datatbl.kind == "resized") then
		if (not settings.in_internal) then
			gridle_setup_internal(source, datatbl.source_audio);
			image_tracetag(source, "internal_launch(" .. current_game().title ..")");
		else

			gridlemenu_rebuilddisplay();
		end
			
	elseif (datatbl.kind == "frameserver_terminated") then
		order_image(imagery.crashimage, max_current_image_order());
		blend_image(imagery.crashimage, 0.8);
		if (not settings.in_internal) then
			blend_image(imagery.crashimage, 0.0, settings.fadedelay + 10);
		end
	end
end


function internal_statectl(suffix, save)
	local cg = current_game();

	if (cg and cg.capabilities.snapshot) then
		local label = cg.target .. "_" .. cg.setname .. "_" .. suffix;
		if (save) then
			snapshot_target( internal_vid, label );
		else
			restore_target( internal_vid, label );
		end
	end
	
end

-- PLAYERn_UP, PLAYERn_DOWN, PLAYERn_LEFT, playern_RIGHT
dirtbl_cw  = {UP = "RIGHT", RIGHT = "DOWN", DOWN = "LEFT", LEFT = "UP"};
dirtbl_ccw = {UP = "LEFT", RIGHT = "UP", DOWN = "RIGHT", LEFT = "DOWN"};

local function rotate_label(label, cw)

	if (string.sub(label, 1, 6) == "PLAYER") then
		local num = string.sub(label, 7, 7);
		local dir = cw and dirtbl_cw[ string.sub(label, 9) ] or dirtbl_ccw[ string.sub(label, 9) ];
		return dir and ("PLAYER" .. num .."_" .. dir) or nil;
	end
	
	return nil;
end

-- keep track of active directions for each player,
-- if a label representing a direction opposite of level is activated, 
filter_label_dirtbl = {UP = "DOWN", DOWN = "UP", LEFT = "RIGHT", RIGHT = "LEFT"};
local function filter_label(label, iotbl)
	
	if (string.sub(label, 1, 6) == "PLAYER") then
		local num = tonumber( string.sub(label, 7, 7) );
		local dir = string.sub(label, 9);
	
		if (num == nil) then return label; end
		if (filter_label_statetbl[ num ] == nil) then 
			local emptytbl = {};
			emptytbl["UP"] = false;
			emptytbl["DOWN"] = false;
			emptytbl["LEFT"] = false;
			emptytbl["RIGHT"] = false;
			filter_label_statetbl[ num ] = emptytbl;
		end

-- lookup the opposite direction, check if that one is active, if it is, ignore this input
-- else have the state table updated with the state from the iotable 
		if (filter_label_dirtbl[ dir ] ) then
			if (filter_label_statetbl[ filter_label_dirtbl[ dir ] ]) then 
				return nil;
			else
				filter_label_statetbl[ dir ] = iotbl.active;
			end
		end
	end
	
	return label;
end

function gridle_internaltgt_analoginput(val, iotbl)
-- negate analog axis values 
	if (settings.internal_input == "Invert Axis (analog)") then
		iotbl.subid = iotbl.subid == 0 and 1 or 0;

-- figure out the image center, calculate offset and negate that
	elseif (settings.internal_input == "Mirror Axis (analog)") then
		if ( (iotbl.subid + 1) % 2 == 0 ) then -- treat as Y
			local center = image_surface_initial_properties(internal_vid).height * 0.5;
			iotbl.samples[1] = center + (center - iotbl.samples[1]);
		else -- treat as X 
			local center = image_surface_initial_properties(internal_vid).width * 0.5;
			iotbl.samples[1] = center + (center - iotbl.samples[1]);
		end
	end

	iotbl.label = val;
	target_input(internal_vid, iotbl);
end

function gridle_internaltgt_input(val, iotbl)
-- toggle corresponding button LEDs if we want to light only on push
	if (settings.ledmode == 3) then
		ledconfig:set_led_label(val, iotbl.active);
	end

-- strip all input events for which there is an opposing, active, PLAYERn_UP/DOWN/LEFT/RIGHT
	if (settings.filter_opposing) then
		val = filter_label(val, iotbl); 
	end

-- useful for horiz/vertical game switching
	if (val and settings.internal_input == "Rotate CW" or settings.internal_input == "Rotate CCW") then
		val = rotate_label(val, settings.internal_input == "Rotate CW");
	end

-- now, the "new" iotbl doesn't necessarily correspond to the values from the original iotable (think axis values)
-- so have keyconfig try to rebuild a useful one.
	if (val) then
		res = keyconfig:buildtbl(val, iotbl);
	
		if (res) then
			res.label = val;
			target_input(res, internal_vid);
		else
			iotbl.label = val;
			target_input(iotbl, internal_vid);
		end
	end
	
end

-- slightly different from gridledetails version
function gridle_internalinput(iotbl)
	local restbl = keyconfig:match(iotbl);

-- We don't forward / allow the MENU_ESCAPE or the MENU TOGGLE buttons at all. 
-- the reason for looping the restbl is simply that the iotbl can be set to match several labels
	
	if (restbl) then
		for ind, val in pairs(restbl) do
			if (val == "MENU_ESCAPE" and iotbl.active) then
				if (valid_vid(imagery.record_target)) then
					disable_record()
				elseif escape_locked == nil or escape_locked == false then 
					settings.cleanup_toggle();
				end

			elseif (val == "RANDOM_GAME") then
				target_framemode(internal_vid, iotbl.active and 1 or 0);
	
			elseif (val == "MENU_TOGGLE") then
				disable_record()
				gridlemenu_internal(internal_vid, false, true);
				toggle_mouse_grab(MOUSE_GRABOFF);

			elseif (val == "CONTEXT") then
				disable_record()
				gridlemenu_internal(internal_vid, true, false);
				toggle_mouse_grab(MOUSE_GRABOFF);

-- iotbl.active filter here is just to make sure we don't save twice (press and release) 
			elseif ( (val == "QUICKSAVE" or val == "QUICKLOAD") and iotbl.active) then
				internal_statectl("quicksave", val == "QUICKSAVE");

-- since we want similar behavior in detailview, the rest is split.
			else

				if (iotbl.kind == "analog") then 
					gridle_internaltgt_analoginput(val, iotbl);
				else
					gridle_internaltgt_input(val, iotbl);
				end

			end
		end
	else
-- default behavior is to forward even unmapped keys, the frameserver will simply ignore
-- and hijack target then allows for local use even when input hasn't been set up correctly
		target_input(iotbl, internal_vid);
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

function error_nogames()
	bg = fill_surface(VRESW, VRESH, 255, 255, 255);
	dbhelp = load_image("dbhelp.png");
	
	local props = image_surface_properties(dbhelp);
	if (VRESW > props.width and VRESH > props.height) then
		move_image(dbhelp, 0.5 * (VRESW - props.width), 0.5 * (VRESH - props.height));
	else
		resize_image(dbhelp, VRESW, VRESH);
	end
	
	show_image(bg);
	show_image(dbhelp);
	
	gridle_input = nil;
end

-- these should match those of 
-- (a) the standard settings table (all should be set),
-- (b) gridle_menus
function load_settings()
	load_key_str("view_mode", "view_mode", settings.view_mode);
	load_key_num("ledmode", "ledmode", settings.ledmode);
	load_key_num("cell_width", "cell_width", settings.cell_width);
	load_key_num("cell_height", "cell_height", settings.cell_height);
	load_key_num("fadedelay", "fadedelay", settings.fadedelay);
	load_key_str("default_launchmode", "default_launchmode", settings.default_launchmode);
	load_key_num("transitiondelay", "transitiondelay", settings.transitiondelay);
	load_key_str("sortorder", "sortlbl", settings.sortlbl);
	load_key_str("defaultshader", "fullscreenshader", settings.fullscreenshader);
	load_key_num("repeatrate", "repeatrate", settings.repeatrate);
	load_key_num("internal_again", "internal_again", settings.internal_again);
	load_key_str("scalemode", "scalemode", settings.scalemode);
	load_key_num("movieagain", "movieagain", settings.movieagain);
	load_key_num("moviecooldown", "cooldown_start", settings.cooldown_start);
	load_key_str("tilebg", "tilebg", settings.tilebg);
	load_key_str("bgname", "bgname", settings.bgname);
	load_key_num("bg_rh", "bg_rh", settings.bg_rh);
	load_key_num("bg_rw", "bg_rw", settings.bg_rw);
	load_key_num("bg_speedv", "bg_speedv", settings.bg_speedv);
	load_key_num("bg_speedh", "bg_speedh", settings.bg_speedh);
	load_key_str("cocktail_mode", "cocktail_mode", settings.cocktail_mode);
	load_key_bool("filter_opposing", "filter_opposing", settings.filter_opposing);
	load_key_str("autosave", "autosave", settings.autosave);
	load_key_num("cursor_scale", "cursor_scale", settings.cursor_scale);

	load_key_num("vector_linew",      "vector_linew",      settings.vector_linew);
	load_key_num("vector_pointsz",    "vector_pointsz",    settings.vector_pointsz);
	load_key_num("vector_hblurscale", "vector_hblurscale", settings.vector_hblurscale);
	load_key_num("vector_vblurscale", "vector_vblurscale", settings.vector_vblurscale);
	load_key_num("vector_hblurofs",   "vector_hblurofs",   settings.vector_hblurofs);
	load_key_num("vector_vblurofs",   "vector_vblurofs",   settings.vector_vblurofs);
	load_key_num("vector_vbias",      "vector_vbias",      settings.vector_vbias);
	load_key_num("vector_hbias",      "vector_hbias",      settings.vector_hbias);
	load_key_num("vector_glowtrails", "vector_glowtrails", settings.vector_glowtrails);
	load_key_num("vector_trailstep",  "vector_trailstep",  settings.vector_trailstep);
	load_key_num("vector_trailfall",  "vector_trailfall",  settings.vector_trailfall);

	load_key_num("ntsc_hue",        "ntsc_hue",        settings.ntsc_hue); 
	load_key_num("ntsc_saturation", "ntsc_saturation", settings.ntsc_saturation);
	load_key_num("ntsc_contrast",   "ntsc_contrast",   settings.ntsc_contrast);
	load_key_num("ntsc_brightness", "ntsc_brightness", settings.ntsc_brightness); 
	load_key_num("ntsc_gamma",      "ntsc_gamma",      settings.ntsc_brightness);
	load_key_num("ntsc_sharpness",  "ntsc_sharpness",  settings.ntsc_sharpness); 
	load_key_num("ntsc_resolution", "ntsc_resolution", settings.ntsc_resolution); 
	load_key_num("ntsc_artifacts",  "ntsc_artifacts",  settings.ntsc_artifacts);
	load_key_num("ntsc_bleed",      "ntsc_bleed",      settings.ntsc_bleed);
	load_key_num("ntsc_fringing",   "ntsc_fringing",   settings.ntsc_fringing); 

	load_key_num("crt_gamma",       "crt_gamma",       settings.crt_gamma);
	load_key_num("crt_mongamma",    "crt_mongamma",    settings.crt_mongamma);
	load_key_num("crt_hoverscan",   "crt_hoverscan",   settings.crt_hoverscan);
	load_key_num("crt_voverscan",   "crt_voverscan",   settings.crt_voverscan);
	load_key_num("crt_haspect",     "crt_haspect",     settings.crt_haspect);
	load_key_num("crt_vaspect",     "crt_vaspect",     settings.crt_vaspect);
	load_key_num("crt_curvrad",     "crt_curvrad",     settings.crt_curvrad); 
	load_key_num("crt_distance",    "crt_distance",    settings.crt_distance);
	load_key_num("crt_tilth",       "crt_tilth",       settings.crt_tilth); 
	load_key_num("crt_tiltv",       "crt_tiltv",       settings.crt_tiltv); 
	load_key_num("crt_cornersz",    "crt_cornersz",    settings.crt_cornersz); 
	load_key_num("crt_cornersmooth","crt_cornersmooth",settings.crt_cornersmooth); 

	load_key_bool("crt_curvature",  "crt_curvature",   settings.curvature); 
	load_key_bool("crt_gaussian",   "crt_gaussian",    settings.gaussian); 
	load_key_bool("crt_oversample", "crt_oversample",  settings.oversample); 
	load_key_bool("crt_linearproc", "crt_linearproc",  settings.linearproc); 
	
	load_key_str("record_format",   "record_format",   settings.record_format);
	load_key_num("record_fps",      "record_fps",      settings.record_fps);
	load_key_num("record_qual",     "record_qual",     settings.record_qual);
	load_key_num("record_res",      "record_res",      settings.record_res);
	
-- special handling for a few settings, modeflag + additional processing
	local internalinp = get_key("internal_input");
	if (internalinp ~= nil) then
		settings.internal_input = internalinp;
		settings.flipinputaxis = internalinp ~= "Normal";
	end

-- each shader argument is patched into a boolean table of #defines to tiggle
	local defshdrkey = get_key("defaultshader_defs");
	if (defshdrkey) then
		settings.shader_opts = {};
		if (string.len(defshdrkey) > 0) then
			local args = string.split(defshdrkey, ",");
			for ind, val in ipairs(args) do settings.shader_opts[val] = true; end
		end
	end

-- the list of favorites is stored / restored on every program open/close cycle
	if ( open_rawresource("lists/favorites") ) then
		line = read_rawresource();
		while line ~= nil do
			line = string.trim(line);
			table.insert(settings.favorites, line);
			settings.favorites[line] = true;
			line = read_rawresource();
		end
	end
end

gridle_input = gridle_dispatchinput;
