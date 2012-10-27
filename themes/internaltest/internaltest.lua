--
-- Keyconfiguration + launch of a semi-random (target can be chose from cmdargs)
--

function table.join(a, b)

	for ind, val in ipairs(b) do 
		table.insert(a, val);
	end

	return a;
end

function target_random_game(target)
	filter = {};
	filter["target"] = target;
	res = list_games( filter );
	if (#res > 0) then
		return res[math.random(1, #res)];
	else
		print("Couldn't find any games matching target:", target);
		shutdown();
	end
end

function target_game(target, title)
	filter = {};
	filter["target"] = target;
	filter["game"] = title;

	res = list_games( filter );
	if (#res > 0) then
		return res[1];
	else
		print("Couldn't find any target/game combination matching:", target, title);
		shutdown();
	end	
end

function random_game()
	local valid_targets = {};
	
	for ind, val in ipairs( list_targets() ) do
		caps = launch_target_capabilities( val );
		if (caps and caps.internal_launch) then
			table.insert(valid_targets, val)
		end
	end

	if (#valid_targets > 0) then
		local games = {};
		
		for ind, val in ipairs(valid_targets) do
			list = list_games({ target = val });
			games = table.join(games, list);
		end

		if (#games > 0) then
			return games[math.random(1, #games)];
		end
	end

	print("Couldn't find any internal- launch capable targets, giving up.\n");
	shutdown();
end

function target_update(source, status)
	print("update: " .. status.kind );
	if (status.kind == "resized") then
		resize_image(target_id, VRESW, VRESH);
		show_image(target_id);
	elseif (status.kind == "frameserver_terminated") then
		shutdown();
	end
end

function launch_internal(game)
	caps = launch_target_capabilities( game.target );
	print(" game picked: " .. game.title);
	print(" internal_launch: " .. tostring(caps.internal_launch) );
	print(" snapshot(" .. tostring(caps.snapshot) .. "), suspend("..tostring(caps.suspend)..") ");
	
	target_id = launch_target( game.gameid, LAUNCH_INTERNAL, target_update);

	if (not valid_vid(target_id)) then
		shutdown("couldn't launch, giving up.\n");
	end
end

function internaltest()
	system_load("scripts/keyconf.lua")();
	print("Internal Test, arguments:", "target:", arguments[1], "game:", arguments[2]);

	local game = nil;
	if (arguments[1] ~= nil and arguments[2] == nil) then
		game = target_random_game(arguments[1]);
	elseif (arguments[1] == nil and arguments[2] == nil) then
		game = random_game();
	else
		game = target_game(arguments[1], arguments[2]);
	end

	kbd_repeat(0);
	keyconfig = keyconf_create(keylabels);

	if (keyconfig.active == false) then
		internaltest_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				internaltest_input = dispatch_input;
				launch_internal(game);
			end
		end
	else
		launch_internal(game);
	end 
	
end

function dispatch_input(iotbl)
	local match = false;
	local restbl = keyconfig:match(iotbl);
	if (restbl) then 
		for ind, val in pairs(restbl) do
			iotbl.label = val;
			target_input(target_id, iotbl);
			match = true;
		end
	end

	if (match == false) then
		target_input(target_id, iotbl);
	end
end

internaltest_input = dispatch_input;