--
-- AWB Frameserver Media Window
-- For a 3D session, we set up a FBO rendertarget and connect
-- the output to the canvas.
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
	return lshdr;
end

local function datashare(wnd)
	local res  = awbwman_setup_cursortag(sysicons.floppy);
	res.kind   = "media";
	res.source = wnd;
	return res;
end

local function add_vmedia_top(pwin, active, inactive)
	local bar = pwin:add_bar("tt", active, inactive,
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("l", cfg.bordericns["pause"], function() end);
	bar:add_icon("r", cfg.bordericns["clone"], function() datashare(pwin); end);
--	bar:add_icon("r", cfg.bordericns["filter"],  slide_pop);
	pwin.click = function() end
	pwin.name = "3dmedia_topbar";
	mouse_addlistener(pwin, {"click"});
end

local function slide_lightr(caller, status)
	awbwman_popupslider(0.01, pwin.amb_r, 1.0, function(val)
		local pwin = caller.pwin;
		pwin.amb_r = val;
		shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	
	end, nil);
	return true;
end
local function slide_lightg(caller, status)
	awbwman_popupslider(0.01, pwin.amb_g, 1.0, function(val)
		local pwin = caller.pwin;
		pwin.amb_g = val;
		shader_uniform(pwin.shader, "wambinet", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	end, nil);
	return true;
end

local function slide_lightb(caller, status)
	awbwman_popupslider(0.01, pwin.amb_b, 1.0, function(val)
		local pwin = caller.pwin;
		pwin.amb_b = val;
		shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	end, nil);
	return true;
end

local function zoom_in(self)
	props = image_surface_properties(self.parent.parent.model.vid);
	move3d_model(self.parent.parent.model.vid, props.x, props.y, props.z + 1.0, 
		awbwman_cfg().animspeed);
end

local function zoom_out(self)
	props = image_surface_properties(self.parent.parent.model.vid);
	move3d_model(self.parent.parent.model.vid, props.x, props.y, props.z - 1.0,
		awbwman_cfg().animspeed);
end

local function add_3dmedia_top(pwin, active, inactive)

	local bar = pwin:add_bar("tt", active, inactive, 
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("l", cfg.bordericns["plus"], zoom_in); 
	bar:add_icon("l", cfg.bordericns["minus"], zoom_out);

	bar:add_icon("l", cfg.bordericns["r1"], slide_lightr).pwin = pwin;
	bar:add_icon("l", cfg.bordericns["g1"], slide_lightg).pwin = pwin;
	bar:add_icon("l", cfg.bordericns["b1"], slide_lightb).pwin = pwin;

	bar:add_icon("r", cfg.bordericns["clone"], function() datashare(pwin); end);

-- click gets sneakily implemented in own()
	pwin.click = function() end
	pwin.name = "3dmedia_topbar";
	mouse_addlistener(pwin, {"click"});
end

local function vcap_setup(pwin)
	local bar = pwin.dir.tt;
end

function input_3dwin(self, iotbl)
	if (iotbl.active == false or iotbl.lutsym == nil) then
		return;
	end

	if (iotbl.lutsym) then
		if (iotbl.lutsym == "UP" or 
			iotbl.lutsym == "PAGEUP" or iotbl.lutsym == "w") then
			zoom_in({parent = {parent = self}});	

		elseif (iotbl.lutsym == "DOWN" or 
			iotbl.lutsym ==" PAGEDOWN" or iotbl.lutsym == "s") then
			zoom_out({parent = {parent = self}});
	
		elseif (iotbl.lutsym == "LEFT") then
			rotate3d_model(self.model.vid, 0.0, 0.0, -15, 5, ROTATE_RELATIVE);

		elseif (iotbl.lutsym == "RIGHT") then
			rotate3d_model(self.model.vid, 0.0, 0.0, 15, 5, ROTATE_RELATIVE);
		end
	end	
end

function awbwnd_media(pwin, kind, source, active, inactive)
	local callback;

	if (kind == "frameserver") then
		add_vmedia_top(pwin, active, inactive);
	
		callback = function(source, status)
			if (status.kind == "resized") then
				play_movie(source);
				pwin:update_canvas(source, false);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "capture") then
		add_vmedia_top(pwin, active, inactive);


	elseif (kind == "static") then
		callback = function(source, status) 
			if (status.kind == "loaded") then
				pwin:update_canvas(source, false);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "3d" and source) then
		local dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
		image_tracetag(dstvid, "3dmedia_rendertarget");
		pwin.shader = set_shader(source.vid);
		show_image(source.vid);
		define_rendertarget(dstvid, {source.vid}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
		pwin:update_canvas(dstvid, false);
		pwin.model = source;
		pwin.input = input_3dwin;
		pwin.amb_r = 0.3;
		pwin.amb_g = 0.3;
		pwin.amb_b = 0.3;

		local mh = {
			name = "3dwindow_canvas",
			own = function(self, vid) return vid == dstvid; end,
			drag = function(self, vid, dx, dy)
				rotate3d_model(source.vid, 0.0, dy, -1 * dx, 0, ROTATE_RELATIVE);
			end,

			over = function(self, vid)
				local tag = awbwman_cursortag();
				if (tag and tag.kind == "media" and vid == pwin.canvas.vid) then
					tag:hint(true);
				end
			end,

			out = function()
				local tag = awbwman_cursortag();
				if (tag and tag.kind == "media") then
					tag:hint(false);
				end
			end,

			click = function()
				local tag = awbwman_cursortag();
				if (tag and tag.kind == "media") then
					pwin.model:update_display(instance_image(tag.source.canvas.vid));	
					tag:drop();
				end
			end
		};
	
		rotate_image(pwin.canvas.vid, 180);
		mouse_addlistener(mh, {"drag", "click", "over", "out"});
		add_3dmedia_top(pwin, active, inactive);

		pwin.on_destroy = function()
			mouse_droplistener(mh);
		end
	else
		warning("awbwnd_media() media type: " .. kind .. "unknown\n");
	end

	return callback; 
end
