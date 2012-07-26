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

-- associate this with the frameset of the launch_target, keep one as the "sharp source"
-- and then split off two FBOs and use a two-phase gaussian blur kernel
-- 
-- if we have an overlay, draw that first and additive blend the main-frame and the blurred FBO output
-- with a modified CRT shader attached

-- generate n target sized buffer to contain the output from the different frames, 
-- one screen sized "sharp" output buffer and two FBOs used for separated gaussian blurs (horiz -> vert)
-- for CRT mode, add an additional FBO with a mix shader that combines the sharp and the two blurs and 
-- set the CRT shader as the outer-most output.
function setup_history_buffer(parent, frames, delay, targetwidth, targetheight, blurwidth, blurheight)
	image_framesetsize(parent, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(parent, delay);
	
	for i=1,#frames do
		local vid = fill_surface(VRESW, VRESH, 0, 0, 0, targetwidth, targetheight);
		set_image_as_frame(parent, vid, i-1);
	end
	
	local blur_buf_a = fill_surface(blurwidth, blurheight, 0, 0, 0, blurwidth, blurheight);
	local blur_buf_b = fill_surface(VRESW, VRESH, 0, 0, 0, blurwidth, blurheight);
	local last_frame = fill_surface(targetwidth, targetheight, 0, 0, 0, targetwidth, targetheight);
	
	local clone = instance_image(parent);
	resize_image(clone, VRESW, VRESH);
	force_image_blend(last_frame, BLEND_NONE);

	show_image(blur_buf_a);
--	show_image(blur_buf_b);
--	blend_image(last_frame, 0.5);
	
	show_image(parent);
	show_image(clone);
	
	define_rendertarget(blur_buf_a, {parent}, RENDERTARGET_DETACH, RENDERTARGET_SCALE);
	define_rendertarget(blur_buf_b, {blur_buf_a}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", create_weighted_fbo(frames),  "history_mix", {});
	local blurshader_h = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianH.fShader", "blur_horiz", {});
	local blurshader_v = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianV.fShader", "blur_vert", {});
	
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

function target_update(source, status)
	if (status.kind == "resized") then
		local props = image_storage_properties(source);
		setup_history_buffer( target_id, {0.8, 0.6, 0.4, 0.2}, -1, props.width, props.height, props.width * 0.4, props.height * 0.4);
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
