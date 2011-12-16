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

-- send to background, add downwards and wrap around
    props = image_surface_properties(vid);
    ydistr = ydistr + props["height"] + math.random(50,150);
    ydistr = ydistr % VRESH;

-- start just outside display, move just outside the display at a randomized speed
    move_image(vid, VRESW + 10, ydistr, 0);
    local lifetime = 500 + math.random(100, 1000);
    move_image(vid, 0 - props["width"] - 50, ydistr, lifetime);
    expire_image(vid, lifetime);
    
-- scale and position based on "distance"
    scale_image(vid, distance + 0.2, 0, 0);
    order_image(vid, distance * 255.0);

    show_image(vid);
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
    vid = load_image(fn);

	if (vid ~= BADID) then
		-- keep track of number of "background objects" alive
		alive = alive + 1;
    
		bglayer[vid] = game;
		position_image(vid);
	else
		table.remove( games, gameid);
	end

end

function space()
-- pre-generated table of SDL keysyms, LED light remaps, .. 
    keyfun = system_load("scripts/keyconf.lua");
    keyconfig = keyfun();

    images.background = load_image("space.png", 0);
    images.cursor = load_image("images/mouse_cursor.png", 255);
    images.emitter = fill_surface(12, 12, 200, 200, 200);

    resize_image(images.cursor, 64, 64, 0);
    force_image_blend(images.cursor);

    image_mask_set(images.emitter, MASK_UNPICKABLE);
    image_mask_set(images.cursor, MASK_UNPICKABLE);
    image_mask_set(images.background, MASK_UNPICKABLE);

    resize_image(images.background, VRESW, VRESH, 0); -- scale to fit screen
    show_image(images.background);
    show_image(images.cursor);


-- populate scale variables to make this resolution independent
    games = list_games( {} );

    for i, v in pairs(games) do
		if resource("screenshots/" .. v.setname .. ".png") == false then
		    print("space-theme, screenshot for set ( " .. v.setname " ) not found, ignoring game.");
		    table[i] = nil;
		end
    end

-- no reason to continue if we have no games setup
    if (# games == 0) then
        error "No games found";
        shutdown();
    else
        random_game();
    end
    
    if (keyconfig.match("MENU_SELECT") == nil) then
	configkeys = true;
	local menutbl = {
	    "rMENU_ESCAPE",
	    "ACURSOR_X",
	    "ACURSOR_Y",
	    "rMENU_SELECT",
	};
	
	keyconfig.new(0, menutbl, {});
    end
    
    iolut = {};
    iolut["MENU_SELECT"] = function(tbl) 
		if (grabbed_item ~= nil) then
		    stop_music();
			launch_target( bglayer[grabbed_item.vid].title, LAUNCH_EXTERNAL );
		    start_music();
		end
    end
    
    iolut["MENU_ESCAPE"] = function(tbl) shutdown(); end
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

function space_on_show()
    start_music();
end

function start_music()
    bgmusic = stream_audio("innerspace.ogg"); -- CCommons, grabbed from 8bc, (c)facundo, http://8bc.org/members/facundo

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

function check_cursor(x, y)
    if (grabbed_item ~= nil) then 
-- check if the cursor is still on the currently selected one, if not, let the game go.
        if (image_hit(grabbed_item.vid, x, y) == 0) then 
			move_image(grabbed_item.vid, 0 - grabbed_item.neww, grabbed_item.origy, 20);
			image_mask_set(grabbed_item.vid, MASK_UNPICKABLE);

		if (grabbed_item.movie) then
			expire_image(grabbed_item.movie, 20);
			audio_gain(grabbed_item.movieaud, 0.0, 20);
		    show_image(grabbed_item.vid);
			hide_image(grabbed_item.movie);
		end
		
		expire_image(grabbed_item.vid, 20);
        grabbed_item = nil;
        end
        
        return;
    end

-- look for new items to select
    items = pick_items(x, y);

    if (# items > 0) then
        props = image_surface_properties(items[1]);
        grabbed_item = {}
        grabbed_item.vid = items[1];
		if (grabbed_item.vid == nil) then
			return;
		end

        grabbed_item.origx = props.x;
        grabbed_item.origy = props.y;
        grabbed_item.origw = props.width;
        grabbed_item.origh = props.height;
	grabbed_item.neww = VRESW / 4;

-- abort "timed death" and stop movement..
	reset_image_transform(grabbed_item.vid);
	expire_image(grabbed_item.vid, 0);
	
	resize_image(grabbed_item.vid, grabbed_item.neww, 0, 0);
	newprops = image_surface_properties(items[1]);
	resize_image(grabbed_item.vid, props.width, props.height, 0, 0);

-- load movie if there is one
	grabbed_item.newh = newprops.height;
	local dx = newprops.width - props.width;
	local dy = newprops.height - props.height;
	
	if ( grabbed_item.vid ~= BADID and 
		bglayer[grabbed_item.vid] ~= nil and
		bglayer[grabbed_item.vid].setname) then
			local moviefn = "movies/" .. bglayer[grabbed_item.vid].setname .. ".avi";
	
		if resource(moviefn) then
			local vid, aid = load_movie(moviefn);
		    grabbed_item.movie = vid;
			grabbed_item.movieaud = aid;
	    
			if (grabbed_item.movie) then
			-- crossfade if we can load, reorient, reposition
			blend_image(grabbed_item.vid, 0.0, 20);
			order_image(grabbed_item.movie, 252);
			blend_image(grabbed_item.movie, 1.0, 20);
			audio_gain(grabbed_item.movieaud, 0.0);
			audio_gain(grabbed_item.movieaud, 1.0, 40);
			play_movie(grabbed_item.movie);
			resize_image(grabbed_item.movie, props.width, props.height, 0);
			resize_image(grabbed_item.movie, newprops.width, newprops.height, 10);
			move_image(grabbed_item.movie, props.x, props.y, 0);
				move_image(grabbed_item.movie, props.x - dx / 2, props.y - dy / 2, 20); -- freeze the image
			end
		else
			grabbed_item.movie = nil;
		end
	end

	resize_image(grabbed_item.vid, newprops.width, newprops.height, 20);
        move_image(grabbed_item.vid, props.x - dx / 2, props.y - dy / 2, 20); -- freeze the image
        order_image(grabbed_item.vid, 253); -- make sure nothing gets in front (except the current movie)
    end
end

function space_input( iotbl )	

    if (configkeys) then 
	if (keyconfig.input(iotbl)) then
	    return true;
	else 
	    keyconfig.save();
	    configkeys = false;
	end
    end

    match = keyconfig.match(iotbl);

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
    if (argtbl.kind == "expired") then
		if (bglayer[source] ~= nil) then
			alive = alive - 1;
			bglayer[source] = nil;
		end
    end
    
end

function spawn_particle()
	particle = instance_image(images.emitter);
	resize_image(particle, 16, 16, 0);
	force_image_blend(particle);
	life = math.random(30, 60);

	blend_image(particle, 1.0 - (math.random(1, 100) / 200));
	move_image(particle, mx+32, my+32, 0);
	move_image(particle, mx + math.random(-100, 100), my + math.random(-100, 100), life);
	blend_image(particle, 0.0, life);
	rotate_image(particle, math.random(-1080, 1080), life);
--	image_link_mask(particle, MASK_POSITION);
	expire_image(particle, life);
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
