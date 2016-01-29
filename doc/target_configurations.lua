-- target_configurations
-- @short: List all configurations associated with a target
-- @inargs: targetname
-- @outargs: configlist, tag
-- @group: database
-- @cfunction: getconfigs
-- @related:
function main()
#ifdef MAIN
	for k, v in pairs(list_targets()) do
		print(string.format("target ( %s ) configurations : \n\t:", v));

		for l, m in pairs(target_configurations(v)) do
			print("\t" .. m);
		end

		print("\n");
	end
#endif

#ifdef ERROR
	target_configurations(list_targets());
#endif
end
