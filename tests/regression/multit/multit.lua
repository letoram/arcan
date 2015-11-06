function multit(args)
	arguments = args
	math.randomseed(1);

-- automatic stepping
	autoc = fill_surface(128, 128, 255, 0, 0);
	show_image(autoc);
	image_framesetsize(autoc, 100, FRAMESET_SPLIT);
	for i=1,99 do
		set_image_as_frame(autoc, fill_surface(32, 32, math.random(255),
			math.random(255), math.random(255)), i, FRAMESET_DETACH);
	end
	image_framecyclemode(autoc, -1);

-- stepping with a different clock
	step_m = fill_surface(128, 128, 0, 255, 0);
	move_image(step_m, 128, 0);
	show_image(step_m);
	image_framesetsize(step_m, 100, FRAMESET_SPLIT);
	for i=1,99 do
		set_image_as_frame(step_m, fill_surface(32, 32, math.random(255),
			math.random(255), math.random(255)), i, FRAMESET_DETACH);
	end

-- multitextured storage
	local frag = [[
		uniform sampler2D map_tu0;
		uniform sampler2D map_tu1;
		uniform sampler2D map_tu2;
		uniform sampler2D map_tu3;

		varying vec2 texco;

		void main(){
			vec3 col1 = texture2D(map_tu0, texco).rgb;
			vec3 col2 = texture2D(map_tu1, texco).rgb;
			vec3 col3 = texture2D(map_tu2, texco).rgb;
			vec3 col4 = texture2D(map_tu3, texco).rgb;
			vec3 comp = col1 + col2 + col3 + col4;
			gl_FragColor = vec4(comp.r, comp.g, comp.b, 1.0);
		}
	]];

	local obj = fill_surface(128, 128, 128, 128, 128);
	image_shader(obj, build_shader(nil, frag, "test"));
	show_image(obj);
	move_image(obj, 0, 128);

	local c1 = fill_surface(32, 32, 64, 0, 0);
	local c2 = fill_surface(32, 32, 0, 96, 0);
	local c3 = fill_surface(32, 32, 0, 0, 128);

	image_framesetsize(obj, 4, FRAMESET_MULTITEXTURE);
	set_image_as_frame(obj, c1, 1, FRAMESET_DETACH);
	set_image_as_frame(obj, c2, 2, FRAMESET_DETACH);
	set_image_as_frame(obj, c3, 3, FRAMESET_DETACH);
end

count = 1;
function multit_clock_pulse()
	count = count + 1;
	if (count == 50) then
		image_framecyclemode(autoc, 0);
	end

	if (count == 100) then
		save_screenshot(arguments[1]);
		return shutdown();
	end
	image_active_frame(step_m, count);
end
