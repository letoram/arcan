-- generate a shader that mixes frames [each cell means weight] 
function create_weighted_fbo( frames )
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");
	
	for i=0,#frames-1 do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i) .. ";");
	end

	table.insert(resshader, "void main(){");

	local mixl = "gl_FragColor = "
	for i=0,#frames-1 do
		table.insert(resshader, "vec4 col" .. tostring(i) .. " = texture2D(map_tu" .. tostring(i) .. ", texco);");

		local strv = tostring(frames[i+1]);
		local coll = "vec4(" .. strv .. ", " .. strv .. ", " .. strv .. ", 1.0)";
		mixl = mixl .. "col" .. tostring(i) .. " * " .. coll;
		
		if (i == #frames-1) then 
			mixl = mixl .. ";\n}\n";
		else
			mixl = mixl .. " + ";
		end
	end

	table.insert(resshader, mixl);
	return resshader; 
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

function vector_setupblur(targetw, targeth, blurw, blurh, hamp, vamp)
	local blurshader_h = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianH.fShader", "blur_horiz", {});
	local blurshader_v = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianV.fShader", "blur_vert", {});
	shader_uniform(blurshader_h, "blur", "f", PERSIST, 1.0 / blurw);
	shader_uniform(blurshader_v, "blur", "f", PERSIST, 1.0 / blurh);
	shader_uniform(blurshader_h, "ampl", "f", PERSIST, hamp);
	shader_uniform(blurshader_v, "ampl", "f", PERSIST, vamp);	

	local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
	local blur_vbuf = fill_surface(targetw, targeth, 1, 1, 1, blurw, blurh);

	image_shader(blur_hbuf, blurshader_h);
	image_shader(blur_vbuf, blurshader_v);

	show_image(blur_hbuf);
	show_image(blur_vbuf);

	return blur_hbuf, blur_vbuf;
end

-- additive blend with blur
function vector_lightmode(source, targetw, targeth, blurw, blurh)
	local blur_hbuf, blur_vbuf = vector_setupblur(targetw, targeth, blurw, blurh, 1.2, 1.1);
	show_image(source);

	local node = instance_image(source);
	resize_image(node, blurw, blurh);
	show_image(node);
	define_rendertarget(blur_hbuf, {node}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	blend_image(blur_vbuf, 0.95);
	force_image_blend(blur_vbuf, BLEND_ADD);
	order_image(blur_vbuf, max_current_image_order() + 1);

	local comp_outbuf = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	define_rendertarget(comp_outbuf, {blur_vbuf, source}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(comp_outbuf);

	return comp_outbuf;	
end

function vector_heavymode(parent, frames, delay, targetw, targeth, blurw, blurh)
-- create an instance of the parent that won't be multitextured 
	local normal = instance_image(parent);
	image_mask_set(normal, MASK_FRAMESET);
	show_image(normal);
	resize_image(normal, targetw, targeth);	

-- set frameset for parent to work as a round robin with multitexture,
-- build a shader that blends the frames according with user-defined weights	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", create_weighted_fbo(frames) , "history_mix", {});
	image_framesetsize(parent, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(parent, delay);
	image_shader(parent, mixshader);
	show_image(parent);
	resize_image(parent, blurw, blurh);

-- generate textures to use as round-robin store
	for i=1,#frames-1 do
		local vid = fill_surface(targetw, targeth, 0, 0, 0, targetw, targeth);
		set_image_as_frame(parent, vid, i, FRAMESET_DETACH);
	end

-- render this to a FBO that will be used for input to blurring
	rendertgt = fill_surface(targetw, targeth, 0, 0, 0, targetw, targeth);
	define_rendertarget(rendertgt, {parent}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(rendertgt);

-- this part is the same as lightmode, use the normal instance as background, then blend the blur result
	local blur_hbuf, blur_vbuf = vector_setupblur(targetw, targeth, blurw, blurh, 1.2, 1.1);
	define_rendertarget(blur_hbuf, {rendertgt}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	blend_image(blur_vbuf, 0.95);
	force_image_blend(blur_vbuf, BLEND_ADD);
	order_image(blur_vbuf, max_current_image_order() + 1);

-- one last FBO for output to CRT etc.
	local comp_outbuf = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	define_rendertarget(comp_outbuf, {blur_vbuf, normal}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(comp_outbuf);

	return comp_outbuf;
end

local function grab_shaderconf(basename)
	local vdef, vcond = parse_shader("shaders/fullscreen/" .. basename .. ".vShader");
	local fdef, fcond = parse_shader("shaders/fullscreen/" .. basename .. ".fShader");
	
	local resdef = {};
	local rescond = {};
	
-- remap the tables into hash/LUT, doesn't separate namespaces in v/f shaders 
	for ind, val in ipairs( vdef ) do resdef[val] = true; end
	for ind, val in ipairs( fdef ) do resdef[val] = true; end
	for ind, val in ipairs( vcond ) do rescond[val] = true; end
	for ind, val in ipairs( fcond ) do rescond[val] = true; end

	return resdef, rescond;
end

function crt_toggle(source)
	local resdef, rescond = grab_shaderconf("crt");
	
	local crtshader = load_shader("shaders/fullscreen/crt.vShader", "shaders/fullscreen/crt.fShader", "CRT", resdef);
	local sprops = image_storage_properties(source);
	local dprops = image_surface_initial_properties(source);
	
	shader_uniform(crtshader, "rubyInputSize", "ff", PERSIST, sprops.width, sprops.height); -- need to reflect actual texel size
	shader_uniform(crtshader, "rubyTextureSize", "ff", PERSIST, dprops.width, dprops.height); -- since target is allowed to resize at more or less anytime, we need to update this
	shader_uniform(crtshader, "rubyOutputSize", "ff", PERSIST, VRESW, VRESH);
	shader_uniform(crtshader, "rubyTexture", "i", PERSIST, 0);
	
	image_shader(source, crtshader);
	resize_image(source, VRESW, VRESH);
	
	backdrop = load_image("astdelux.png");
	resize_image(backdrop, VRESW, VRESH);
	blend_image(backdrop, 0.3);

	hide_image( source );
	order_image(source, 1);
	force_image_blend(source, BLEND_ADD);
	blend_image(source, 0.98);
end

function target_update(source, status)
	if (status.kind == "resized") then
		local props = image_storage_properties(source);
--		outp = vector_lightmode(source, props.width, props.height, props.width * 0.2, props.height * 0.2);
		outp = vector_heavymode(source, {0.6, 0.5, 0.4, 0.2}, -3, props.width, props.height, props.width * 0.6, props.height * 0.6)
		resize_image(outp, VRESW, VRESH);
		crt_toggle(outp);
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
