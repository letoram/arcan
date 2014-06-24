-- launch_target_capabilities
-- @short: Query the engine for capabilities of a specific target.
-- @inargs: targetname
-- @outargs: restbl
-- @longdescr: Valid restbl properties are: external_launch, internal_launch,
-- snapshot, rewind, suspend, reset, dynamic_input, ports.
-- @related: target_launch
-- @group: targetcontrol
-- @cfunction: arcan_lua_targetlaunch_capabilities
function main()
#ifdef MAIN
	a = list_targets();
	if (a and #a > 0) then
		for k,v in pairs(launch_target_capabilities(a[1])) do
			print(k, v);
		end
	else
		warning("no viable targets found.");
	end
#endif
end
