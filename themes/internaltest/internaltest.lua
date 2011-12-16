-- Basic testcase for internal launch
mx = 0;
my = 0; -- store last known mouse coordinates
cellsize = 160;  

function internaltest()
-- sanity test
	print(INTERNALMODE);
	if (string.match(INTERNALMODE, "NO SUPPORT") ~= nil) then
		print("Internal mode not supported, aborting.");
		shutdown();
	end

	local keyfun = system_load("scripts/keyconf.lua");
	keyconfig = keyfun();
	target_locked = false;
	ofs_x = 0;
	ofs_y = 0;
	cursor = fill_surface(16, 16, 200, 50, 50);
		force_image_blend(cursor);
		image_mask_set(cursor, MASK_UNPICKABLE);
	show_image(cursor);
	
	build_grid();
	
	games = list_games( {target = "mame"} );
	current_target = nil;
	iodispatch = {}

-- no reason to continue if we have no games setup
	if (# games == 0) then
		error "No games found";
		shutdown();
		return;
	end

    iodispatch["MENU_ESCAPE"] = 
    function(iotbl)
	if (target_locked == false) then
	    for i=1, #gridslots do
		if gridslots[i].free == false then
		    delete_image(gridslots[i].vid);
		end
	    end
	   
	    shutdown();
	    return;
	end

	target_locked = false;

-- move to the grid
	reset_image_transform(current_target.vid);
	resize_image(current_target.vid, cellsize, cellsize, 20);
	local x, y = grab_gridslot(current_target.vid, current_target.aid);
	move_image(current_target.vid, x, y, 20);
	blend_image(current_target.vid, 0.7, 20);
	audio_gain(current_target.aid, 0.2, 20);

-- make sure the minimized target is not immediately selected
	movingtgt = current_target.vid;
	image_mask_set(movingtgt, MASK_UNPICKABLE);
	selected_item = nil;
	current_target = nil;
	show_image(cursor);
    end

    iodispatch["CURSOR_X"] = function(tbl)
        mx = tbl.samples[1];
        move_image(cursor, mx, my);
    end
	
    iodispatch["CURSOR_Y"] = function(tbl)
        my = tbl.samples[1];
        move_image(cursor, mx, my);
    end

    iodispatch["MENU_DELETE"] = function(tbl)
	if (selected_item) then
		expire_image(selected_item, 40);
		blend_image(selected_item, 0, 40);

		release_gridslot(selected_item);
		selected_item = nil;
	end
    end

    iodispatch["MENU_SUSPEND"] = function(tbl)
        if (selected_item) then
	    suspend_target( selected_item );
	    selected_item = nil;
	end
    end

    iodispatch["MENU_RESUME"] = function(tbl)
        if (selected_item) then
    	    resume_target( selected_item );
	    selected_item = nil;
	end
    end
	
    iodispatch["MENU_LAUNCH"] = function(tbl)
	gameind = math.random(1, #games);
		
	vid, aud = launch_target( games[ gameind ].title, 1);
	if (vid > 0) then
	    insert_target(vid, aud);
	else
	    print("Couldn't launch: " .. games[gameind].title);
	end
    end
    
    iodispatch["MENU_SELECT"] = function(tbl)
	if (selected_item) then
		vid, aid = release_gridslot( selected_item );
		maximize_target( vid, aid );
	end
    end

    if (keyconfig.match("MENU_ESCAPE") == nil) then
	local menu_group = {
	    "rMENU_ESCAPE",
	    "rMENU_LAUNCH",
	    "rMENU_SELECT",
	    "rMENU_DELETE",
	    "rMENU_SUSPEND",
	    "rMENU_RESUME",
	    "ACURSOR_X",
	    "ACURSOR_Y"
	};
		
    	keyconfig.new(1, menu_group, nil);
	configkeys = true;
    end
end

function maximize_target(vid, aid)
	props = image_surface_initial_properties(vid);
	if (current_target == nil) then
		current_target = {};
	end
	current_target.vid = vid;
	current_target.aid = aid;

	gaspect = props.width / props.height;
	waspect = VRESW / VRESH;
	print("props: " .. props.width .. " , " .. props.height);
	print("VRES:" .. VRESW .. " , " .. VRESH .. ":" .. waspect);
 
-- there's probably a decent formulae for this,
-- too tired atm.
	reset_image_transform(vid);

	-- wide- perspective game, wide- perspective screen	
	if (gaspect > 1 and waspect > 1) then
		neww, newh = resize_image(vid, VRESW, 0, 20);
-- tall- perspective game, wide- perspective screen
	elseif(gaspect < 1 and waspect > 1) then
		neww, newh = resize_image(vid, 0, VRESH, 20);
-- wide- perspective game, tall perspective screen
	elseif (gaspect > 1 and waspect < 1) then
		neww, newh = resize_image(vid, VRESW, 0, 20);
	end
	
-- move, expensive little trick, "which properties will the obj. have in n ticks"
	print("thus: " .. neww .. " x " ..newh);
	move_image(vid, (VRESW - neww) / 2, (VRESH - newh) / 2, 20);
	blend_image(vid, 1.0, 20);
	movingtgt = vid;
	
	audio_gain(current_target.aid, 1.0, 20);
	resume_target(vid);
	hide_image(cursor);
	target_locked = true;
end

function build_grid()
	n_rows = math.floor( VRESH / cellsize );
	n_cols = math.floor( VRESW / cellsize );
	crow = 0;
	ccol = 0;
	gridslots = {};
	
	
	for cell=1, (n_rows * n_cols) do
		gridslots[cell] = {
			x = ccol * cellsize,
			y = crow * cellsize,
			free = true
		};

		ccol = ccol + 1;
		if (ccol > n_cols-1) then
			ccol = 0;
			crow = crow + 1;
		end
	end
end

function release_gridslot(vid)
	i = find_gridslot(vid);

	if (i ~= nil) then
		gridslots[i].free = true;
		return gridslots[i].vid, gridslots[i].aid;
	end
	
	return BADID, BADID;
end

function find_gridslot(vid)
	for i=1,#gridslots do
		if (gridslots[i].free == false and gridslots[i].vid == vid) then
			return i;
		end
	end
	
	return nil;
end

function grab_gridslot(vid, aid)
	j = find_gridslot(vid);

	if (j == nil) then
		for i=1,#gridslots do
			if (gridslots[i].free) then
				gridslots[i].free = false;
				gridslots[i].aid = aid;
				gridslots[i].vid = vid;
				j = i;
				break;
			end
		end
	end

	if (j ~= nil) then 
		return gridslots[j].x, gridslots[j].y;
	else 
		return 0, 0;
	end
end

-- use a grid with ref != nil approach,
-- divide screen width with cellsize or sth,
-- for suspend, just find first hole, for delete, just set to nil and delete.

function insert_target(vid, aud)
	props = image_surface_properties(vid);
	current_target = {};
	current_target.grid_position = {};
	
	hide_image(cursor);
	target_locked = true;
	
	current_target.vid = vid;
	current_target.aid = aud;
	current_target.gridx, current_target.gridy = grab_gridslot(vid, aud);
	show_image(vid);
end

------ Event Handlers ----------
function internaltest_input( iotbl )
-- input- keys 
	if (configkeys) then
		if (keyconfig.input( iotbl ) ) then
			return;
		else
			keyconfig.save();
			configkeys = false;
		end
	end

    forward = true;

    res = keyconfig.match(iotbl);
    if (res ~= nil) then
	for i,v in pairs(res) do
	    iofun = iodispatch[ v ];

	    if (iotbl.active and iofun ~= nil and 
		(target_locked == false or v == "MENU_ESCAPE")) then
		    iofun(iotbl);
	    end
	end
    end
    
    
    if (target_locked and current_target ~= nil) then
    -- translate mouse coordinates into target space
	if (iotbl.source == "mouse" and iotbl.kind == "analog") then 
		local props = image_surface_initial_properties(current_target.vid);
		local cprops = image_surface_properties(current_target.vid);
		
		if (iotbl.subid == 0) then
		    local xr = props.width / VRESW;
    
		    iotbl.samples[1] = math.abs ( math.floor( (iotbl.samples[1] - cprops.x) * xr) );
		    iotbl.samples[2] = math.floor( iotbl.samples[2] * xr);

		elseif (iotbl.subid == 1) then
		    local yr = props.height / VRESH;
		    
		    iotbl.samples[1] = math.abs( math.floor( (iotbl.samples[1] - cprops.y) * yr) );
		    iotbl.samples[2] = math.floor( iotbl.samples[2] * yr);
		end
	end
	
	target_input(iotbl, current_target.vid);
    end
end

function internaltest_clock_pulse(stamp, count)
-- hack to get around the minimizing app- being selected immediately
	if (target_locked == false) then
		local items = pick_items(mx, my);

		if (#items >= 1) then
-- nothing selected
			if (selected_item == nil) then
				selected_item = items[1];
				reset_image_transform(selected_item);
				blend_image(selected_item, 1.0, 20);
				
-- new item selected, fade the old one
			elseif (selected_item and selected_item ~= items[1]) then
				reset_image_transform(selected_item);
				blend_image(selected_item, 0.7, 20);
				selected_item = items[1];
				blend_image(selected_item, 1.0, 20);
			else
			end
-- cursor moved away, nothing new selected
		elseif (selected_item ~= nil and movingtgt ~= selected_item) then
			reset_image_transform(selected_item);
			blend_image(selected_item, 0.7, 20);
			selected_item = nil;
		end
	end
end

function internaltest_video_event( source, argtbl )
	if (source == movingtgt and argtbl.kind == "moved") then
		image_mask_clear(movingtgt, MASK_UNPICKABLE);
		movingtgt = nil
	end	
	
	if (argtbl.kind == "resized") then
		if (source == current_target.vid) then
			print("resizing");
			current_target.width, current_target.height = resize_image(source, argtbl.width, argtbl.height, 0);
			current_target.x = VRESW / 2 - current_target.width / 2;
			current_target.y = VRESH / 2 - current_target.height / 2;
			move_image(current_target.vid, current_target.x, current_target.y, 0);
			maximize_target(current_target.vid, current_target.aid);
		end
	end
end
