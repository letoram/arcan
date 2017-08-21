local frag = [[
	uniform float r;
	uniform float g;
	uniform float b;
	void main(){
		gl_FragColor = vec4(r, g, b, 1.0);
	}
]];

function refill(tbl, shid)
	while true do
		newsh = shader_ugroup(shid);
		if (not newsh) then
			return #tbl;
		end
		table.insert(tbl, newsh);
	end
end

function shgrprm(arg)
	arguments = arg

	local shid = build_shader(nil, frag, "block_1");
	shader_uniform(shid, "r", "f", 0.1);
	shader_uniform(shid, "g", "f", 0.2);
	shader_uniform(shid, "b", "f", 0.3);

	local newsh;
	print("filling namespace");
	local shtbl = {};
	local initial = refill(shtbl, shid);

	print("# groups created:", initial);
	for i=1,10 do
		local holes = math.random(1, #shtbl);
		print("iteration", i, "drop at random: ", holes);

		for j=1,math.random(1,#shtbl) do
			local id = table.remove(shtbl, math.random(1,#shtbl));
			delete_shader(id);
		end

		print("refill", refill(shtbl, shid), initial, #shtbl);
		if (#shtbl ~= initial) then
			return shutdown("iteration: " .. tostring(i) .. " failed", EXIT_FAILURE);
		end
	end

	return shutdown(EXIT_SUCCESS);
end
