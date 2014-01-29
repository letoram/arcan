--
-- global (and view-local) configuration menus
--

local updatebgtrigger = nil;

local function animnums(i)
	if (i > 1) then
		return math.pow(2, i);
	else
		return 1;
	end
end

local function tilenums(i)
	if (i > 1) then
		return 4 * (i - 1);
	else
		return 1;
	end
end

local function cellhnum(i)
	if (i * 32 < VRESH) then
		return i * 32;
	end
end

local function cellwnum(i)
	if (i * 32 < VRESW) then
		return i * 32;
	end
end

-- hack around scoping and upvalue
local function bgtrig()
	updatebgtrigger();
end

local function reset_customview()
	zap_resource("customview.lay");

-- despawn menu
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	play_audio(soundmap["MENU_SELECT"]);

-- get rid of menus etc.
	pop_video_context();

-- keep server session
	push_video_context();

	gridle_customview();
end

local dispptrs = {};
local displbls = {};

local backgroundptrs = {};
local backgroundlbls = {};

local soundptrs = {};
local soundlbls = {};

local inputptrs = {};
local inputlbls = {
	"Reconfigure Keys (Full)",
	"Reconfigure Keys (Players)"
};

local gameptrs = {};
local gamelbls = {};

local bgeffmen, bgeffdesc = build_globmenu("shaders/bgeffects/*.fShader", efftrigger, ALL_RESOURCES);
local rebuild_grid = false;

local function forcerebuild()
	rebuild_grid = true;
end

if (settings.viewmode == "Grid") then
	add_submenu(displbls, dispptrs, "Image...", "bgname", gen_glob_menu("bgname", "backgrounds/*.png", ALL_RESOURCES, bgtrig, nil));
	add_submenu(displbls, dispptrs, "Background Effects...", "bgeffect", gen_glob_menu("bgeffect", "shaders/bgeffects/*.fShader", ALL_RESOURCES, bgtrig, nil));
	add_submenu(displbls, dispptrs, "Cell Background...", "tilebg", gen_tbl_menu("tilebg", {"None", "White", "Black", "Sysicons"}, bgtrig, true));
	add_submenu(displbls, dispptrs, "Cursor Scale...", "cursor_scale", gen_num_menu("cursor_scale", 1.0, 0.1, 5));
	add_submenu(displbls, dispptrs, "Cell Width...", "cell_width", gen_num_menu("cell_width", 1, cellwnum, 10, forcerebuild));
	add_submenu(displbls, dispptrs, "Cell Height...", "cell_height", gen_num_menu("cell_height", 1, cellhnum, 10, forcerebuild));
	add_submenu(displbls, dispptrs, "Tile (vertical)...", "bg_rh", gen_num_menu("bg_rh", 1, tilenums, 8, bgtrig));
	add_submenu(displbls, dispptrs, "Tile (horizontal)...", "bg_rw", gen_num_menu("bg_rw", 1, tilenums, 8, bgtrig));
	add_submenu(displbls, dispptrs, "Animate (horizontal)...", "bg_speedv", gen_num_menu("bg_speedv", 1, animnums, 8, bgtrig));
	add_submenu(displbls, dispptrs, "Animate (vertical)...", "bg_speedh", gen_num_menu("bg_speedh", 1, animnums, 8, bgtrig));
end

add_submenu(displbls, dispptrs, "Movie Playback Cooldown...", "cooldown_start", gen_num_menu("cooldown_start", 0, 15, 5));

add_submenu(displbls, dispptrs, "Fade Delay...", "fadedelay", gen_num_menu("fadedelay", 5, 5, 10));
add_submenu(displbls, dispptrs, "Transition Delay...", "transitiondelay", gen_num_menu("transitiondelay", 5, 5, 10));

-- we want to avoid having Reset first as a menu -> hold right would be destructive 
if (settings.viewmode ~= "Grid") then
	add_submenu(displbls, dispptrs, "Reset Configuration...", nil, {"Reset"}, {Reset = reset_customview});
end

add_submenu(displbls, dispptrs, "Default View Mode...", nil, gen_tbl_menu(nil, {"Switch"}, function() 
	dialog_option( "Changing view mode requires a restart, proceed?", {"Yes", "No"}, false, {Yes = flip_viewmode}, nil );
end, true));

add_submenu(soundlbls, soundptrs, "Soundmaps...", "soundmap", gen_glob_menu("soundmap", "soundmaps/*", ALL_RESOURCES, function(label) load_soundmap(label); end, nil));
add_submenu(soundlbls, soundptrs, "Sample Gain...", "effect_gain", gen_num_menu("effect_gain", 0.0, 0.1, 11));
add_submenu(soundlbls, soundptrs, "Movie Audio Gain...", "movie_gain", gen_num_menu("movie_gain", 0.0, 0.1, 11));

local bgmusiclbls = {};
local bgmusicptrs = {};

add_submenu(bgmusiclbls, bgmusicptrs, "Playback...", "bgmusic", gen_tbl_menu("bgmusic", {"Disabled", "Menu Only", "Always"},
	function(label)
		if (label == "Disabled") then
			if (valid_vid(imagery.musicplayer)) then
				delete_image(imagery.musicplayer);
        imagery.source_audio = nil;
			end
		else
			music_start_bgmusic(settings.bgmusic_playlist);
		end
	end, true));

add_submenu(bgmusiclbls, bgmusicptrs, "Order...", "bgmusic_order", gen_tbl_menu("bgmusic_order", {"Sequential", "Randomized"}, function(label)
	music_load_playlist(settings.bgmusic_playlist);
	if (label == "Randomized") then
		music_randomize_playlist();
	end
	
end, true));

add_submenu(soundlbls, soundptrs, "Background Gain...", "bgmusic_gain", gen_num_menu("bgmusic_gain", 0.0, 0.1, 11, function()
  if (imagery.source_audio ~= nil) then
    audio_gain(imagery.source_audio, settings.bgmusic_gain);
  end
end ));
add_submenu(soundlbls, soundptrs, "Background Music...", nil, bgmusiclbls, bgmusicptrs);

local tmpfun = soundptrs["Background Music..."];
soundptrs["Background Music..."] = function()
add_submenu(bgmusiclbls, bgmusicptrs, "Playlists...", "bgmusic_playlist", gen_glob_menu("bgmusic_playlist", "music/playlists/*.m3u", ALL_RESOURCES, 
	function() music_start_bgmusic(settings.bgmusic_playlist); end, 
	function() spawn_warning({"No playlists could be found", "check resources/music/playlists for .m3us"}); end));

	tmpfun();
end

add_submenu(inputlbls, inputptrs, "Repeat Rate...", "repeatrate", 
	gen_num_menu("repeatrate", 0, 100, 6, function() kbd_repeat(settings.repeatrate); end));

add_submenu(inputlbls, inputptrs, "Network Remote...", "network_remote", 
	gen_tbl_menu("network_remote", {"Disabled", "Passive", "Active"},	function(label)
		if (label == "Disabled" and valid_vid(imagery.server)) then
			net_disconnect(imagery.server, 0);
		end
	end, true));

local mnavlbls = {"On", "Off"};
local mnavptrs = {};
local mnavfmts = {};
mnavptrs["On"] = function(lbl, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.mouse_enabled = lbl == "On";
	if (save) then 
		store_key("mouse_trails", lbl == "On" and 1 or 0);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
end
mnavptrs["Off"] = mnavptrs["On"];

if (get_key("mouse_enabled")) then
	mnavfmts["On"] = settings.colourtable.notice_fontstr;
else
	mnavfmts["Off"] = settings.colourtable.notice_fontstr;
end

-- add_submenu(inputlbls, inputptrs, "Mouse Navigation...", "mouse_enabled", 
--	mnavlbls, mnavptrs, mnavfmts);
-- add_submenu(inputlbls, inputptrs, "Mouse Trails...", "mouse_trails", 
--	gen_num_menu("mouse_trails", 0, 10, 5, function() end, true));

local mainlbls = {};
local mainptrs = {};
add_submenu(mainlbls, mainptrs, "Display...", nil, displbls, dispptrs, {});
add_submenu(mainlbls, mainptrs, "Input...", nil, inputlbls, inputptrs, {});
add_submenu(mainlbls, mainptrs, "Sound / Music...", nil, soundlbls, soundptrs, {});

local gamelbls = {};
local gameptrs = {};
add_submenu(gamelbls, gameptrs, "Launch Mode...", "default_launchmode", gen_tbl_menu("default_launchmode", {"Internal", "External"}, function() end, true));
add_submenu(gamelbls, gameptrs, "Autosave...", "autosave", gen_tbl_menu("autosave", {"On", "On (No Warning)", "Off"}, function() end, true));
add_submenu(mainlbls, mainptrs, "Gaming...", nil, gamelbls, gameptrs);

if (LEDCONTROLLERS > 0) then
	table.insert(inputlbls, "LED display mode...");
	table.insert(inputlbls, "Reconfigure LEDs");
end
	
local ledmodelbls = {
	"Disabled",
	"All toggle",
	"Game setting (always on)"
};

if INTERNALMODE ~= "NO SUPPORT" then
	table.insert(ledmodelbls, "Game setting (on push)");
end

local ledmodelut = {};
ledmodelut["Disabled"] = 0;
ledmodelut["All toggle"] = 1;
ledmodelut["Game setting (always on)"] = 2;
ledmodelut["Game setting (on push)"] = 3;
	
local ledmodeptrs = {};
local ledmodefun = function(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
	settings.ledmode = ledmodelut[label];
	if (save) then 
		store_key("ledmode", settings.ledmode);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

for key, val in pairs(ledmodelut) do
	ledmodeptrs[key] = ledmodefun;
end

inputptrs["Reconfigure Keys (Full)"] = function()
	if (settings.privileged ~= true) then
		return;
	end
	
	zap_resource("keysym.lua");
	gridle_keyconf();
end

inputptrs["LED display mode..."] = function() 
	local fmts = {};

	fmts[ ledmodelbls[ tonumber(settings.ledmode) + 1] ] = settings.colourtable.notice_fontstr;
	if (get_key("ledmode")) then
		fmts[ ledmodelbls[ tonumber(get_key("ledmode")) + 1] ] = settings.colourtable.alert_fontstr;
	end
	
	menu_spawnmenu(ledmodelbls, ledmodeptrs, fmts); 
end

inputptrs["Reconfigure LEDs"] = function()
	zap_resource("ledsym.lua");
	gridle_ledconf();
end

inputptrs["Reconfigure Keys (Players)"] = function()
	if (settings.privileged ~= true) then
		return;
	end
	
	keyconfig:reconfigure_players();
	kbd_repeat(0);

	dispatch_push({}, "reconfigure player keys", function(iotbl)
		if (keyconfig:input(iotbl) == true) then
			keyconf_tomame(keyconfig, "_mame/cfg/default.cfg"); -- should be replaced with a more generic export interface
			kbd_repeat(settings.repeatrate);
			dispatch_pop();
		end
	end);
end

function gridlemenu_settings(cleanup_hook, filter_hook)
-- first, replace all IO handlers
	local imenu = {};
	rebuild_grid = false;
	
	imenu["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();

		if (current_menu.parent ~= nil) then
			if (silent == nil or silent == false) then play_audio(soundmap["SUBMENU_FADE"]); end
			current_menu = current_menu.parent;
		else -- top level
			if (#settings.games == 0) then
				settings.games = list_games( {} );
			end

		play_audio(soundmap["MENU_FADE"]);
		table.sort(settings.games, settings.sortfunctions[ settings.sortorder ]);

-- only rebuild grid if we have to
		if (cleanup_hook) then
			cleanup_hook(rebuild_grid);
		end

		dispatch_pop();
	end

		init_leds();
	end

	menu_defaultdispatch(imenu);
	if (filter_hook) then
		updatebgtrigger = filter_hook;
	else
		updatebgtrigger = function() end;
	end
	
-- hide the cursor and all selected elements
	if (movievid) then
		instant_image_transform(movievid);
		expire_image(movievid, settings.fadedelay);
		blend_image(movievid, 0.0, settings.fadedelay);
		movievid = nil;
	end

	current_menu = listview_create(mainlbls, math.floor(VRESH * 0.9), 
		math.floor(VRESW / 2));
	current_menu.ptrs = mainptrs;
	
	current_menu:show();
	dispatch_push(imenu);
	
	local spawny = VRESH * 0.5 - 
		image_surface_properties(current_menu.border, -1).height;
	spawny = spawny > 0 and spawny or 0;

	move_image(current_menu.anchor, 10, (VRESH * 0.5), 0);
end
