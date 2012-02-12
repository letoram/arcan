-- Space theme
-- Written as a more "crazy" example, mouse only theme
--
-- Features demonstrated;
-------------------------
-- External launchmode
-- Minimal-set I/O config
-- Picking (hovering and clicking over an object)
-- Object masks (disable picking for particular objects)
-- Chaining several transformations for motion sequences
-- Mouse "cursor" (just an image hooked up to the mouse motion event)
-- Instance and hierarchical coordinates (the particle system underneath the cursor)
-- Music playback (background music, stored in theme)
-- Only games with a matching screenshot/movie 
-- (resources/screenshots/setname.png or resources/moviesd/setname.avi)
-- will be shown.. 
-------------------------

local background;
local bgmusic;
local menu;

local games = { };

-- mouse-cursor data
local hotspot = {x = 41, y = 2};
local step = {x = 20, y = -20}; -- non-mouse axis devices, manual orientation.
local mx = 0;
local my = 0; 

local images = { };

-- starfield of screenshots / movies
local bglayer = {};
local bglayer_d = 50;

-- rough estimate on number of reasonable images (~avg. 160x160 screenshots in relation to display)
local bglayer_limit = (VRESW / 80 + VRESH / 80);
local alive = 0;

-- reposition an image for the "starfield scroller"
local ydistr = 0;

function position_image(vid)
    distance = math.random(1, 5) / 10;
    props = image_surface_properties(vid);

-- wider or taller?
	if (props.width / props.height) > 1 then
		resize_image(vid, VRESW * 0.2, 0, NOW);
	else
		resize_image(vid, 0, VRESH * 0.2, NOW);
	end

-- scale and position based on "distance"
    order_image(vid, distance * 254.0);

-- add downwards and wrap around
	ydistr = ydistr + 10 + math.random(50);
    props = image_surface_properties(vid);
	if (ydistr + props.height > VRESH) then 
		ydistr = math.random(50);
	end

-- start just outside display, move just outside the display at a randomized speed
    move_image(vid, VRESW + 60, ydistr, NOW);
    local lifetime = 500 + math.random(100, 1000);
    move_image(vid, 0 - props.width, ydistr, lifetime);
    expire_image(vid, lifetime);

	ydistr = ydistr + props.height;
    show_image(vid);
end

function have_video(setname)
	local moviefn = "movies/" .. setname .. ".avi";
	if (resource(moviefn)) then
		return moviefn;
	else
		return nil;
	end
end

-- find a random game, load relevant resources and queue. 
function random_game()
    vid = 0;
    
    if (alive >= bglayer_limit) then
		return;
    end
    
	gameid = math.random(1, #games);
    game = games[ gameid ];
    fn = "screenshots/" .. game["setname"] .. ".png";
    vid = load_image_asynch(fn);

	if (vid ~= BADID) then
		-- keep track of number of "background objects" alive
		alive = alive + 1;
		bglayer[vid] = game;
	end

end

function space()
-- pre-generated table of SDL keysyms, LED light remaps, .. 
    keyfun = system_load("scripts/keyconf.lua")();

-- tile rather than clamp
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT);

    images.background = load_image("space.png", 0);
    images.cursor = load_image("images/mouse_cursor.png", 255);

 -- used as the basis for all particles
    images.emitter = fill_surface(12, 12, 200, 200, 200);

-- if this is changed, the hot-spot need to be changed as well
    resize_image(images.cursor, 64, 64, 0);

--  we want the cursor opaque, but should still have alpha-channel used
    force_image_blend(images.cursor);

-- don't want these to appear on hit detection
    image_mask_set(images.emitter, MASK_UNPICKABLE);
    image_mask_set(images.cursor, MASK_UNPICKABLE);
    image_mask_set(images.background, MASK_UNPICKABLE);

    resize_image(images.background, VRESW, VRESH, 0); -- scale to fit screen
    show_image(images.background);
    show_image(images.cursor);

-- add all games that have a corresponding snapshot
	local tmptbl = {};
    games = list_games( {} );

    for i, v in pairs(games) do
		if resource("screenshots/" .. v.setname .. ".png") == false then
		    table[i] = nil;
		else
			table.insert(tmptbl, v);
		end
    end
	games = tmptbl;

-- no reason to continue if we have no games setup
    if (# games == 0) then
        error "No games (with matching screenshots) could be found";
        shutdown();
    else
        random_game();
    end
    
	local menutbl = {
	    "rMENU_ESCAPE",
	    "ACURSOR_X",
	    "ACURSOR_Y",
	    "rMENU_SELECT",
	};
	
	keyconfig = keyconf_create(0, menutbl, {});
	if (keyconfig.active == false) then
		keyconfig.iofun = space_input;
		space_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				space_input = keyconfig.iofun;
			end
		end
	end
	
    iolut = {};
    iolut["MENU_SELECT"] = function(tbl) 
		if (grabbed_item) then
		    stop_music();
			launch_target( bglayer[grabbed_item.vid].title, LAUNCH_EXTERNAL );
		    start_music();
		end
    end
    
    iolut["MENU_ESCAPE"] = function(tbl) shutdown(); end

-- the analog conversion for devices other than mice is so-so atm.
    iolut["CURSOR_X"] = function(tbl) 
		if (tbl.source == "mouse") then
		    mx = tbl.samples[1];
		else
			mx = mx + (tbl.samples[1] / 32768) * step.x;
		end

		move_image(images.cursor, mx, my, 0);
    end

    iolut["CURSOR_Y"] = function(tbl)
		if (tbl.source == "mouse") then
			my = tbl.samples[1];
		elseif (tbl.samples[1] > 0) then
			my = my + (tbl.samples[1] / 32768) * step.y;
		else
			my = my - step.y;
		end
		
		move_image(images.cursor, mx, my, 0);
    end
end

function space_show()
    start_music();
end

function start_music()
-- CCommons, grabbed from 8bc, (c)facundo, http://8bc.org/members/facundo
    bgmusic = stream_audio("innerspace.ogg"); 
    if bgmusic ~= BADID then
		play_audio(bgmusic);
		audio_gain(bgmusic, 0.3, 0);
    end
end

function stop_music()
    if bgmusic ~= BADID then
        delete_audio(bgmusic);
    end
end

function release_item()
	local dvid = grabbed_item.vid;
	instant_image_transform(dvid);
	local props = image_surface_properties(grabbed_item.vid);
	image_mask_set(grabbed_item.vid, MASK_UNPICKABLE);

	move_image(dvid, -10, props.y, 40);
	expire_image(dvid, 40);

	if (grabbed_item.movie) then
		dvid = grabbed_item.movie;
		instant_image_transform(dvid);
		image_mask_set(dvid, MASK_UNPICKABLE);
		if (grabbed_item.movieaud) then 
			audio_gain(grabbed_item.movieaud, 0.0, 20); 
		end
	end

	resize_image(dvid, 1, 1, 40);
	blend_image(dvid, 0.0, 60);
	order_image(dvid, 3);
	grabbed_item = nil;
end

function check_cursor(x, y)
-- check if the cursor is still on the currently selected one, if not, let the game go.
    if (grabbed_item) then 
        if (image_hit(grabbed_item.vid, x, y) == 0) then 
			release_item();
		else
			return;
		end
	end

-- look for new items to select
    items = pick_items(x, y);

	if (# items > 0) then
        grabbed_item = {}
        grabbed_item.vid = items[1];
		reset_image_transform(grabbed_item.vid);

		local props = image_surface_properties(grabbed_item.vid);
		if (props.width / props.height > 1) then
			resize_image(grabbed_item.vid, VRESW * 0.3, 0, 20 );
		else
			resize_image(grabbed_item.vid, 0, VRESH * 0.3, 20 );
		end
		
		local fprops = image_surface_properties(grabbed_item.vid, 20);
		local dx = fprops.x;
		local dy = fprops.y;

		if (fprops.x + fprops.width > VRESW) then 
			dx = VRESW - fprops.width;
		end

		if (fprops.y + fprops.height > VRESH) then
			dy = VRESH - fprops.height;
		end

		move_image(grabbed_item.vid, dx, dy, 20);

-- load movie if there is one
		local fn = have_video(bglayer[grabbed_item.vid].setname);
		if (fn) then
			local vid = load_movie(fn);
		    grabbed_item.movie = vid;
	    
			if (grabbed_item.movie) then
				order_image(grabbed_item.movie, 252);
				link_image(grabbed_item.movie, grabbed_item.vid);
				image_mask_clear(grabbed_item.movie, MASK_OPACITY);
				image_mask_clear(grabbed_item.movie, MASK_SCALE);
			end
		else
			grabbed_item.movie = nil;
		end

-- scale and reposition
		order_image(grabbed_item.vid, 253);
    end
end

function space_input( iotbl )	
	match = keyconfig:match(iotbl);

    if (match ~= nil) then
		for i, v in pairs(match) do
			if (iolut[v]) then
				iolut[v](iotbl);
			end
		end
	end
end

function space_video_event( source, argtbl )
-- keep track of expired background- images so that new ones can be spawned
	if (argtbl.kind == "movieready") then
		if (grabbed_item and source == grabbed_item.movie) then
			local vid, aid = play_movie(source);
			local props = image_surface_properties(grabbed_item.vid, 40);
			audio_gain(aid, 0.0); audio_gain(aid, 1.0, 40);
			grabbed_item.movieaud = aid;
			 
			blend_image(grabbed_item.vid, 0.0, 40);
			resize_image(vid, props.width, props.height);
			blend_image(vid, 1.0, 20);
		else
			delete_image(source);
		end
	elseif (argtbl.kind == "loaded") then
		position_image(source);

	elseif (argtbl.kind == "expired") then
		if (bglayer[source] ~= nil) then
			alive = alive - 1;
			bglayer[source] = nil;
		end
    end
    
end

function spawn_particle()
	particle = instance_image(images.emitter);
	resize_image(particle, 16, 16, 0);
	life = math.random(30, 60);

	blend_image(particle, 1.0 - (math.random(1, 100) / 200));
	move_image(particle, mx + 32, my + 32, 0);
	move_image(particle, mx + math.random(-100, 100), my + math.random(-100, 100), life);
	rotate_image(particle, math.random(-360, 360), life);

	blend_image(particle, 0.0, life);
	expire_image(particle, life);

	image_mask_clear(particle, MASK_POSITION);
	image_mask_set(particle, MASK_UNPICKABLE);
	image_mask_clear(particle, MASK_OPACITY);
end

function space_clock_pulse()
    move_image(images.emitter, mx + 20, my + 20);
    check_cursor(mx + hotspot.x, my + hotspot.y);
	spawn_particle();

--  spawn a new game each ~50 ticks (with some randomness) up until the limit.
    bglayer_d = bglayer_d - 1;

    if (bglayer_d == 0) then 
        bglayer_d = 50 + math.random(1,50);
        random_game();
    end
end
