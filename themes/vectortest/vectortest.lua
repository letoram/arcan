-- generate a shader that mixes frames [each cell means weight] 
function create_weighted_fbo( frames )
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");
	
	for i=1,#frames do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i-1) .. ";");
	end

	table.insert(resshader, "void main(){");

	local mixl = "gl_FragColor = "
	for i=1,#frames do
		table.insert(resshader, "vec4 col" .. tostring(i) .. " = texture2D(map_tu" .. tostring(i-1) .. ", texco);");

		local strv = tostring(frames[i]);
		local coll = "vec4(" .. strv .. ", " .. strv .. ", " .. strv .. ", 1.0)";
		mixl = mixl .. "col" .. tostring(i) .. " * " .. coll;
		
		if (i == #frames) then 
			mixl = mixl .. ";\n}\n";
		else
			mixl = mixl .. " + ";
		end
	end

	table.insert(resshader, mixl);
	return resshader; 
end

-- light version:
-- generate an output buffer that does a weighted blend of a variable number of spaced frames
-- apply a low-res gaussian filter and upscale this to full res and blend additively.
-- lastly, multiply with overlay.
--
-- heavy version:
-- store the additive blend into a new FBO, use this FBO as input shader and map to the CRT shader
-- lastly, blend with overlay
function setup_history_buffer(parent, frames, delay, targetwidth, targetheight, blurwidth, blurheight)
	local mixshader = load_shader("shaders/fullscreen/default.vShader", create_weighted_fbo(frames),  "history_mix", {});
	image_framesetsize(parent, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(parent, delay);
	
	for i=1,#frames do
		local vid = fill_surface(VRESW, VRESH, 0, 0, 0, targetwidth, targetheight);
		set_image_as_frame(parent, vid, i-1, FRAMESET_DETACH);
	end

	local normal_out = instance_image(parent);
	resize_image(normal_out, targetwidth, targetheight);
	show_image(normal_out);

	image_shader(parent, mixshader);

	local blur_buf_a = fill_surface(blurwidth, blurheight, 0, 0, 0, blurwidth, blurheight);
	local blur_buf_b = fill_surface(blurwidth, blurheight, 0, 0, 0, blurwidth, blurheight);
--	local last_frame = fill_surface(targetwidth, targetheight, 0, 0, 0, targetwidth, targetheight);
	
--	resize_image(clone, VRESW, VRESH);
--	force_image_blend(last_frame, BLEND_NONE);

	show_image(blur_buf_a);
	show_image(blur_buf_b);
	resize_image(blur_buf_b, targetwidth, targetheight);
--	blend_image(last_frame, 0.5);
	
	show_image(parent);
--	show_image(clone);
	
	define_rendertarget(blur_buf_a, {parent}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_buf_b, {blur_buf_a}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	
	image_shader(parent, mixshader);

	image_shader(blur_buf_a, blurshader_h);
	image_shader(blur_buf_b, blurshader_v);
end

function vectortest()
	system_load("scripts/keyconf.lua")();
	system_load("scripts/3dsupport.lua")();
	
	games = list_games( {title = arguments[1]} );
	if (#games == 0) then
	    error("No matching games found.");
	    shutdown();
	end

	kbd_repeat(0);
	keyconfig = keyconf_create(keylabels);

	if (keyconfig.active == false) then
		vectortest_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				vectortest_input = dispatch_input;
			end
		end
	end

	game = games[1];
	local caps = launch_target_capabilities( game.target );
	print(" game picked: " .. game.title);
	print(" internal_launch: " .. tostring(caps.internal_launch) );
	print(" snapshot(" .. tostring(caps.snapshot) .. "), rewind(" .. tostring(caps.rewind) .. "), suspend("..tostring(caps.suspend)..") "); 
	
	target_id = launch_target( game.gameid, LAUNCH_INTERNAL, target_update);
	if (target_id == nil) then
		error("Couldn't launch target, aborting.");
		shutdown();
	end

end

-- only gaussian, no history.
function vector_lightmode(source, targetw, targeth, blurw, blurh)
	local blurshader_h = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianH.fShader", "blur_horiz", {});
	local blurshader_v = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianV.fShader", "blur_vert", {});
	shader_uniform(blurshader_h, "blur", "f", PERSIST, 1.0 / blurw);
	shader_uniform(blurshader_v, "blur", "f", PERSIST, 1.0 / blurh);
	shader_uniform(blurshader_h, "ampl", "f", PERSIST, 1.2);
	shader_uniform(blurshader_v, "ampl", "f", PERSIST, 1.2);	

	local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
	local blur_vbuf = fill_surface(targetw, targeth, 1, 1, 1, blurw, blurh);
	show_image(source);

-- clone that will be passed through the blur stages
	local node = instance_image(source);
	resize_image(node, blurw, blurh);
	show_image(node);
	show_image(blur_hbuf);
	show_image(blur_vbuf);

	define_rendertarget(blur_hbuf, {node}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	image_shader(blur_hbuf, blurshader_h);
	image_shader(blur_vbuf, blurshader_v);

	blend_image(blur_vbuf, 0.95);
	force_image_blend(blur_vbuf, BLEND_ADD);
	order_image(blur_vbuf, max_current_image_order() + 1);
--	define_rendertarget(blur_vbuf, {blur_hbuf},  RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
end

function target_update(source, status)
	if (status.kind == "resized") then
		local props = image_storage_properties(source);
		vector_lightmode(source, props.width, props.height, props.width * 0.5, props.height * 0.5);
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

vectortest_input = dispatch_input;
