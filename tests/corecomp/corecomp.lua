-- 
-- Core Comparator script
--
-- Used to run multiple cores in parallel, feeding them the same input and recording the output.
-- Could also be adapted to compare effects of shaders side by side and other little cute effects.
-- 

settings = {};
settings.iodispatch = {};
settings.placeholders = {};
settings.target_list = {};
settings.vid_info = {};

corecomp_keyconf = nil;
corecomp_setuptargets = nil;

function corecomp()
	settings.colourtable = system_load("scripts/colourtable.lua")();    -- default colour values for windows, text etc.
	system_load("scripts/listview.lua")();                              -- used by menus (_menus, _intmenus) and key/ledconf
	system_load("scripts/keyconf.lua")();
	system_load("scripts/keyconf_mame.lua")();
	
	system_load("corecomp_menus.lua")();

	games = list_games({});
	if not games or #games == 0 then
		error("No games found, giving up.");
	end
	
	corecomp_keyconf(corecomp_setuptargets);
end

function corecomp_updategrid(source, status)
	found = false
	for ind, val in ipairs(settings.target_list) do
		if (val == source) then
			found = true
			break
		end
	end
	
	if (found == false) then
		table.insert(settings.target_list, source);
	end
	
	cellw = math.floor(VRESW / #settings.target_list);
	x = 0;

	for ind, val in ipairs(settings.target_list) do
		resize_image(val, cellw, 0);
		props = image_surface_properties(val);
		move_image(val, x, 0.5 * (VRESH - props.height));
		x = x + cellw;
	end

	show_image(source);
end

function corecomp_allinp(tbl)

	for ind, val in ipairs(settings.target_list) do
		if (valid_vid(val)) then 
			target_input(val, tbl); 
		end 
	end
	
end

function corecomp_tgtinput(iotbl)
-- translate via keyconf
	local restbl = keyconfig:match(iotbl);	

-- if it match to a label, project it into the iotable (if possible) and then insert
	if restbl then
		for ind, val in pairs(restbl) do
			if (val) then
				res = keyconfig:buildtbl(val, iotbl);

				if (res) then
					res.label = val;
					corecomp_allinp(res);
				else
					iotbl.label = val;
					corecomp_allinp(iotbl);
				end -- if (res)
			end -- if (val)
		end -- for(ind, val)
-- if it doesn't resolve, just inject anyway (hijack targets)
	else
		corecomp_allinp(iotbl);
	end -- if (restbl)
	
	return nil;
end

function corecomp_start()
	if #settings.target_list == 0 then
		print("Setup targets first.\n");
		return
	end
	
	for ind, val in ipairs(settings.placeholders) do delete_image(val); end

	for ind, val in ipairs(settings.target_list) do 
		vid, aid = launch_target(val.gameid, LAUNCH_INTERNAL, function(source, status)
		if (status.kind == "resized") then
			corecomp_updategrid(source, status);
		elseif (status.kind == "frame") then
			if (not settings.vid_info[tostring(source)]) then
				settings.vid_info[tostring(source)] = {};
			end
			settings.vid_info[tostring(source)].lastframe = status.frame;
		end
	end);

	end
	
	settings.target_list = {};
	current_menu:destroy();

-- simple input function that resolves labels ( for the libretro targets )
-- or just wildcard forwards for hijacks.
	corecomp_input = corecomp_tgtinput;
end

function update_targetsplit()
	local nsplit = #settings.target_list
	if nsplit == 0 then return end
	
-- just use X as the dominant axis so we can maintain aspects.. 
	cellw = math.floor(VRESW / nsplit);
	x = 0;
	
	for ind, val in ipairs(settings.placeholders) do delete_image(val); end
	settings.placeholders = {};
	
	for i=0,nsplit do
		if i < #settings.target_list then 
			local surf = fill_surface(cellw, cellw, math.random(32, 255), math.random(32, 255), math.random(32, 255));

			move_image(surf, x, y);
			show_image(surf);
			table.insert(settings.placeholders, surf);

			x = x + cellw;
		end
	end
	
end

function corecomp_clock_pulse()
	for ind, val in pairs(settings.vid_info) do
		if (val.textid) then delete_image(val.textid); end
		if (val.lastframe) then
			local props = image_surface_properties(tonumber(ind));
			val.textid = render_text( settings.colourtable.fontstr .. " " .. tostring(val.lastframe) );
			show_image(val.textid);
			move_image(val.textid, props.x, props.y);
		end
	end
end

function setup_game(source)
	filter = {};
	filter.target = settings.current_target;
	filter.title  = source;
	
	game = list_games(filter);

	if (game == nil or #game == 0) then
		print("Couldn't add game, something broken in the database?", filter.target, filter.title);
		return;
	end
	
	table.insert(settings.target_list, game[1]);
	update_targetsplit();
end

function list_targetgames(label)
	gamelist = {};
	games = list_games({target = label});

	if not games or #games == 0 then return; end
	for ind, tbl in ipairs(games) do table.insert(gamelist, tbl.title); end
	
	settings.current_target = label;
	lbls, ptrs = gen_tbl_menu("_notinuse", gamelist, setup_game, true);
	menu_spawnmenu(lbls, ptrs, {});
end

function corecomp_setuptargets()
	lbls = {};
	ptrs = {};

	add_submenu(lbls, ptrs, "Setup target...", "notinuse", gen_tbl_menu("_notinuse", list_targets(), list_targetgames, true));
	corecomp_defaultdispatch(function() shutdown(); end);

	table.insert(lbls, "Go");
	ptrs["Go"] = corecomp_start;

	current_menu = listview_create(lbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	
	current_menu:show();
end

function corecomp_dispatchinput(iotbl)
	local restbl = keyconfig:match(iotbl);
 
	if (restbl and iotbl.active) then
		for ind,val in pairs(restbl) do
			if (settings.iodispatch[val]) then
				settings.iodispatch[val](restbl, iotbl);
			end
		end
	end
	
	return nil;
end

function corecomp_keyconf(hook)
	local keylabels = { "", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT" };
	local listlbls = {};
	local lastofs = 1;
	
	for ind, key in ipairs(keylabels) do
		table.insert(listlbls, string.sub(key, 2));
	end
		
	keyconfig = keyconf_create(keylabels);
	
	if (keyconfig.active == false) then
		kbd_repeat(0);

		keyconfig:to_front();

		corecomp_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				keyconf_tomame(keyconfig, "_mame/cfg/default.cfg"); 
				corecomp_input = corecomp_dispatchinput;
				hook();
			end
		end
	else
		hook();
	end
	return nil;
end
 
corecomp_input = corecomp_dispatchinput;
