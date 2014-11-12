function constdump()
	zap_resource("consts.list");
	open_rawresource("consts.list");

	for k,v in pairs(_G) do

		if string.match(k, "%u%u") then
			write_rawresource(string.format("%s\n", k));
		end
	end

	shutdown();
end
