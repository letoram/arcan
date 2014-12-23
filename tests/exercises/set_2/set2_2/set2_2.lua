function set2_2()
	local interps = {};

	for k,v in pairs(_G) do
		if (string.match(k, "INTERP_%w+") ~= nil) then
			table.insert(interps, v)
		end
	end

	local nb = #interps;
	local stepx = (VRESW - 64) / nb;

	for i=1,nb do
		box = color_surface(64, 64, math.random(191) + 64,
			math.random(191) + 64, math.random(191) + 64);
		show_image(box);
		move_image(box, stepx * (i - 1), 0);
		move_image(box, stepx * (i - 1), VRESH - 64, 100, interps[i]);
	end
end
