local frag = [[
	uniform float r;
	uniform float g;
	uniform float b;
	void main(){
		gl_FragColor = vec4(r, g, b, 1.0);
	}
]];

function shgrp(arg)
	arguments = arg
	local shid = build_shader(nil, frag, "block_1");
	shader_uniform(shid, "r", "f", 0.1);
	shader_uniform(shid, "g", "f", 0.2);
	shader_uniform(shid, "b", "f", 0.3);

	local sh2 = shader_ugroup(shid);
	shader_uniform(sh2, "r", "f", 1.0);
	local sh3 = shader_ugroup(shid);
	shader_uniform(sh3, "g", "f", 1.0);
	local sh4 = shader_ugroup(shid);
	shader_uniform(sh4, "b", "f", 1.0);

	local g1 = {shid, sh2, sh3, sh4};
	for i=1,4 do
		local surf = fill_surface(64, 64, 0, 0, 0);
		show_image(surf);
		image_shader(surf, g1[i]);
		move_image(surf, i * 64, 0);
	end

	shid = build_shader(nil, frag, "block_2");
	shader_uniform(shid, "r", "f", 1.0);
	shader_uniform(shid, "g", "f", 1.0);
	shader_uniform(shid, "b", "f", 1.0);

	sh2 = shader_ugroup(shid);
	shader_uniform(sh2, "r", "f", 0.0);
	sh3 = shader_ugroup(shid);
	shader_uniform(sh3, "g", "f", 0.0);
	sh4 = shader_ugroup(shid);
	shader_uniform(sh4, "b", "f", 0.0);

	g1 = {shid, sh2, sh3, sh4};
	for i=1,4 do
		local surf = fill_surface(64, 64, 0, 0, 0);
		show_image(surf);
		image_shader(surf, g1[i]);
		move_image(surf, i * 64, 64);
	end
end

clock = 0;
function shgrp_clock_pulse()
	clock = clock + 1;
	if (clock == 25) then
		save_screenshot(arguments[1]);
		return shutdown();
	end
end
