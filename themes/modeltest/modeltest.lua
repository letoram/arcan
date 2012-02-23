vshader = [[
	uniform mat4 modelview;
	uniform mat4 projection;

	attribute vec4 vertex;
	attribute vec2 texcoord;

	varying vec2 txco;
	
void main(){
	txco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}
]];

fshader = [[
	uniform sampler2D mat_diffuse;
	varying vec2 txco;

	void main() {
		vec4 col = texture2D(mat_diffuse, txco);
		if (col.a < 0.01){
			discard;
		}
		
		gl_FragColor = col;
	}
]];

function modeltest()
	symtable = system_load("scripts/symtable.lua")();
	local confun = system_load("scripts/console.lua")();
	system_load("scripts/3dsupport.lua")();
	
	sens = 0.1;
	yaw = 0.0;
	pitch = 0.0;
	roll = 0.0;
	ystepsize = 0.0;
	sidestepsize = 0.0;
	fwdstepsize = 0.0;
	
	shdr = build_shader(vshader, fshader);
	
	model = load_model(arguments[1]);
	scale_3dvertices(model.vid);
	show_image(model.vid);
	move3d_camera(-1.0, 1.0, -5.0);

	image_shader(model.vid, shdr);
	mousex = VRESW * 0.5;
	mousey = VRESH * 0.5;

--	plane = build_3dplane(-5.0, -5.0, 5.0, 5.0, -1.0, 0.1, 0.1);

	toggle_mouse_grab();
	kbd_repeat(2);
--	show_image(plane);

--	rotate3d_model(model.vid, 0.0, 270.0, 0.0);
	show_image(model.vid);
	contbl = create_console(VRESW , VRESH / 4, "fonts/default.ttf", 18);
	console_enabled = false;
	contbl:hide();
	mpvid, aid = launch_target(arguments[2], 1);
	hide_image(mpvid);
	move3d_camera(-1.0, 1.0, -5.0);
	set_image_as_frame(model.vid, mpvid, model.labels["display"]);
end

function load_material(modelname, meshname)
  local rvid = BADID;
  local fnameb = "models/" .. modelname .. "/textures/" .. meshname;
  if (resource(fnameb .. ".png")) then
	rvid = load_image(fnameb .. ".png");
  elseif (resource(fnameb .. ".jpg")) then
	rvid = load_image(fnameb .. ".jpg");
  else
	print("Couldn't find a texture matching " .. modelname .. ":" .. meshname);
	rvid = fill_surface(8,8, 255, math.random(1,255), math.random(1,255));
  end
  
  return rvid;
end

function generic_load(modelname)
  local basep = "models/" .. modelname .. "/";
  local meshes   = glob_resource(basep .. "*.ctm", THEME_RESOURCE);

  if (#meshes == 0) then
	print("couldn't find any meshes for the model '" .. modelname .. "'");
	return nil
  end
  
  local model = {}
  model.labels = {}
  model.vid = load_3dmodel( basep .. meshes[1] );
  if (model.vid == BADID) then
	print("error loading model from mesh: " .. meshes[1]);
	return nil
  end
  
  image_framesetsize(model.vid, #meshes);

  for i=1, #meshes do
	if (i > 1) then
	  add_3dmesh(model.vid, basep .. meshes[i]);
	end
	
	local vid = load_material(modelname, string.sub(meshes[i], 1, -5));
	model.labels[string.sub(meshes[i], 1, -5)] = i-1;
	set_image_as_frame(model.vid, vid, i-1, 1);
  end
  
  return model;
end

function modeltest_clock_pulse()
	strafe3d_camera(sidestepsize);
	forward3d_camera(fwdstepsize);
	orient3d_camera(roll, pitch, yaw);
end

function modeltest_input(iotable)
	if (mpvid and mpvid ~= BADID) then
		target_input(iotable, mpvid);
	end

	if (iotable.kind == "digital") then
		if (console_enabled) then
		if (iotable.active) then
			key = symtable[iotable.keysym];
			if (key == "F12") then
				console_enabled = false;
				contbl:hide();
				kbd_repeat(2);
			else
				local cmd = contbl:input(iotable);
				if (cmd ~= "") then
					print(" exec: " .. cmd);
					assert(loadstring(cmd))();
				end
			end
		end
		else
			key = symtable[iotable.keysym];
			if key == "w" then
			  forward3d_camera(0.05);
			elseif key == "s" then
			  forward3d_camera(-0.05);
			elseif key == "a" then
			  strafe3d_camera(0.05);
			elseif key == "d" then
			  strafe3d_camera(-0.05);
			elseif key == "q" then
				ystepsize = iotable.active and 0.5 or 0.0;
			elseif key == "e" then
				ystepsize = iotable.active and -0.5 or 0.0;
			elseif key == "ESCAPE" then
				shutdown();
			elseif iotable.active and key == "F12" then
				contbl:show();
				kbd_repeat(0);
				console_enabled = true;
			end
		end
	else
		if (console_enabled == false) then
			if iotable.subid == 1 then
				pitch = (pitch + iotable.samples[2] * sens) % 360;
			else
				yaw = (yaw + iotable.samples[2] * sens) % 360;
			end	
		end	
	end
end
