function set1_4(arguments)
	if (#arguments ~= 1) then
		return shutdown("missing argument, filename (images/icons/arcanicon.png)")
	end

	if (not resource(arguments[1])) then
		return shutdown("couldn't find resource (" .. arguments[1] .. ")")
	end

	load_image_asynch(arguments[1], function(source, status)
		if (status.kind == "loaded") then
			show_image(source);
			zap_resource("set1_4.dump");
			system_snapshot("set1_4.dump");
		elseif (status.kind == "failed") then
			shutdown("couldn't load image: " .. arguments[1]);
		end
	end);
end
