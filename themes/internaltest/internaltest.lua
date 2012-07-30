--
-- Keyconfiguration + launch of a semi-random (target can be chose from cmdargs)
--

function table.join(a, b)

	for ind, val in ipairs(b) do 
		table.insert(a, val);
	end

	return a;
end

function internaltest()
	system_load("scripts/keyconf.lua")();
	args = {};
	
	targets = list_targets();
	valid_tgts = {};

	if (arguments[1] ~= nil and arguments[2] == nil) then
		targets = { arguments[1] };
	end

	for ind, val in ipairs(targets) do
		caps = launch_target_capabilities(val);
		if (caps and caps.internal_launch) then
			print("target:" .. val .. " got internal launch capabilities, adding.");
			table.insert(valid_tgts, val);
		end
	end

	if (#valid_tgts == 0) then
		error("No capable targets found.");
		shutdown();
	end


	local filters = {target = val};
	if (arguments[2] ~= nil) then
		filters.title = arguments[2];
	end

	games = {};
	for ind, val in ipairs(valid_tgts) do
		local tgtgames = list_games( filters );
		games = table.join(games, tgtgames); 
	end

	
	if (#games == 0) then
		error("No games matching capable targets found.");
		shutdown();
	end
	
	game = games[ math.random(1, #games) ];

	kbd_repeat(0);
	keyconfig = keyconf_create(keylabels);

	if (keyconfig.active == false) then
		internaltest_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				internaltest_input = dispatch_input;
			end
		end
	end	

	caps = launch_target_capabilities( game.target );	
	print(" game picked: " .. game.title);
	print(" internal_launch: " .. tostring(caps.internal_launch) );
	print(" snapshot(" .. tostring(caps.snapshot) .. "), rewind(" .. tostring(caps.rewind) .. "), suspend("..tostring(caps.suspend)..") "); 
	
	target_id = launch_target( game.gameid, LAUNCH_INTERNAL, target_update);
	if (target_id == nil) then
		error("Couldn't launch target, aborting.");
		shutdown();
	end
end

function target_update(source, status)
	print("update: " .. status.kind );
	if (status.kind == "resized") then
		resize_image(target_id, VRESW, VRESH);
		show_image(target_id);
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

