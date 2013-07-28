--
-- AWB Frameserver Media Window
-- For a 3D session, we set up a FBO rendertarget and connect the output to the canvas.
-- Adds a "play/pause" and possibly others based on frameserver capabilities.
-- Also adds the option to instance and set shaders.
--
local shader_seqn = 0;

local function set_shader(modelv)
	local lshdr = load_shader("shaders/dir_light.vShader", 
		"shaders/dir_light.fShader", "media3d_" .. tostring(shader_seqn));

	shader_uniform(lshdr, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(lshdr, "wlightdir", "fff", PERSIST, 1, 0, 0);
	shader_uniform(lshdr, "wambient",  "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(lshdr, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6); 

	image_shader(modelv, lshdr);
end

local function add_vmedia_top()
	local bar = pwin:add_bar("tt", active, inactive,
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("l", cfg.bordericns["play"],    vplay);
	bar:add_icon("r", cfg.bordericns["clone"],   slide_pop);
	bar:add_icon("r", cfg.bordericns["filter"],  slide_pop);
end

local function slide_pop(caller, status)
	print("slide_pop");
	return true;
end

local function zoom_in(self)
	props = image_surface_properties(self.parent.parent.model);
	move3d_model(self.parent.parent.model, props.x, props.y, props.z + 1.0, 
		awbwman_cfg().animspeed);
end

local function zoom_out(self)
	props = image_surface_properties(self.parent.parent.model);
	move3d_model(self.parent.parent.model, props.x, props.y, props.z - 1.0,
		awbwman_cfg().animspeed);
end

local function add_3dmedia_top(pwin, active, inactive)

	local bar = pwin:add_bar("tt", active, inactive, 
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("l", cfg.bordericns["plus"], zoom_in); 
	bar:add_icon("l", cfg.bordericns["minus"], zoom_out);

	bar:add_icon("l", cfg.bordericns["r1"], slide_pop);
	bar:add_icon("l", cfg.bordericns["g1"], slide_pop);
	bar:add_icon("l", cfg.bordericns["b1"], slide_pop);

	bar:add_icon("r", cfg.bordericns["clone"], clone);

-- click gets sneakily implemented in own()
	pwin.click = function() end
	pwin.name = "3dmedia_topbar";
	mouse_addlistener(pwin, {"click"});
end

function input_3dwin(self, iotbl)
	if (iotbl.active == false or iotbl.keysym == nil) then
		return;
	end

	if (iotbl.keysym) then
		if (iotbl.keysym == "UP" or 
			iotbl.keysym == "PAGEUP" or iotbl.keysym == "w") then
			zoom_in({parent = {parent = self}});	

		elseif (iotbl.keysym == "DOWN" or 
			iotbl.keysym ==" PAGEDOWN" or iotbl.keysym == "s") then
			zoom_out({parent = {parent = self}});
		end
	end	
end

function awbwnd_media(pwin, kind, source, active, inactive)
	local callback;

	if (kind == "frameserver") then
		callback = function(source, status)
			if (status.kind == "resized") then
				play_movie(source);
				pwin:update_canvas(source, false);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "static") then
		callback = function(source, status) 
			if (status.kind == "loaded") then
				pwin:update_canvas(source, false);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "3d" and source) then
		dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
		image_tracetag(dstvid, "3dmedia_rendertarget");
		set_shader(source);
		show_image(source);
		define_rendertarget(dstvid, {source}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
		pwin:update_canvas(dstvid, false);
		pwin.model = source;
		pwin.input = input_3dwin;
		
		local mh = {
			name = "3dwindow_canvas",
			own = function(self, vid) return vid == dstvid; end,
			drag = function(self, vid, dx, dy)
				rotate3d_model(source, 0.0, dy, -1 * dx, 0, ROTATE_RELATIVE);
			end
		};
	
		rotate_image(pwin.canvas.vid, 180);
		mouse_addlistener(mh, {"drag"});
		add_3dmedia_top(pwin, active, inactive);

		pwin.on_destroy = function()
			mouse_droplistener(mh);
		end
	else
		warning("awbwnd_media() media type: " .. kind .. "unknown\n");
	end

	return callback; 
end
