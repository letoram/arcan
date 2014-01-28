--
-- AWB 3D Model Viewer
--
	
local shader_seqn = 1;
local function set_shader(modelv)
	local lshdr = load_shader("shaders/dir_light.vShader", 
		"shaders/dir_light.fShader", "media3d_" .. tostring(shader_seqn));
	shader_seqn = shader_seqn + 1;

	shader_uniform(lshdr, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(lshdr, "wlightdir", "fff", PERSIST, 1, 0, 0);
	shader_uniform(lshdr, "wambient",  "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(lshdr, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6); 

	image_shader(modelv, lshdr);
	return lshdr;
end

local function zoom_in(self)
	local pwin = self.parent.parent;
	pwin:focus();

	props = image_surface_properties(pwin.model.vid);
	move3d_model(pwin.model.vid, props.x, props.y, props.z + 1.0, 
		awbwman_cfg().animspeed);
end

local function zoom_out(self)
	local pwin = self.parent.parent;
	pwin:focus();

	props = image_surface_properties(pwin.model.vid);
	move3d_model(pwin.model.vid, props.x, props.y, props.z - 1.0,
		awbwman_cfg().animspeed);
end

local function datashare(wnd)
	local res  = awbwman_setup_cursortag(sysicons.floppy);
	res.kind   = "media";
	res.source = wnd;
	res.audio  = wnd.recv;
	res.name   = wnd.name;
	return res;
end

local function add_3dmedia_top(pwin)
	local bar = pwin:add_bar("tt", pwin.ttbar_bg, pwin.ttbar_bg, 
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("zoom_in", "l", cfg.bordericns["plus"], zoom_in); 
	bar:add_icon("zoom_out", "l", cfg.bordericns["minus"], zoom_out);

	bar:add_icon("light_r", "l", cfg.bordericns["r1"], 
	function(self)
		awbwman_popupslider(0.01, pwin.amb_r, 1.0, function(val)
			pwin.amb_r = val;
			shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
		end, {ref = self.vid})
	end);
	
	bar:add_icon("light_g", "l", cfg.bordericns["g1"], 
	function(self)
		awbwman_popupslider(0.01, pwin.amb_g, 1.0, function(val)
			pwin.amb_g = val;
			shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
		end, {ref = self.vid})
	end);

	bar:add_icon("light_b", "l", cfg.bordericns["b1"], 
	function(self)
		awbwman_popupslider(0.01, pwin.amb_b, 1.0, function(val)
			pwin.amb_b = val;
			shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
		end, {ref = self.vid})
	end);

	bar.hoverlut[
	(bar:add_icon("clone", "r", cfg.bordericns["clone"], 
		function() datashare(pwin); end)).vid
	] = MESSAGE["HOVER_CLONE"];

	bar.name = "3dmedia_top";	
end

local function input_3dwin(self, iotbl)
	if (iotbl.active == false or iotbl.lutsym == nil) then
		return;
	end

-- dropped the rotate functions from here as some want
-- to play using global input capture and game output on display
end

--
-- pwin is a previously set-up awbwnd,
-- source is a table populated by the load_model call.
--
function awbwnd_modelview(pwin, source)
	local dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
	image_tracetag(dstvid, "3dmedia_rendertarget");
	pwin.shader = set_shader(source.vid);
	show_image(source.vid);

-- render to texture for easier clipping, position etc.
-- but also for chaining onwards (using as recordtarget)
	define_rendertarget(dstvid, {source.vid}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, RENDERTARGET_FULL);

-- camera for the new rendertarget
	local camera = null_surface(1, 1);
	scale3d_model(camera, 1.0, -1.0, 1.0);
	rendertarget_attach(dstvid, camera, RENDERTARGET_DETACH);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33); 
	image_tracetag(camera, "3dcamera");

	pwin:update_canvas(dstvid);
	pwin.name = "3d model";
	pwin.model = source;
	pwin.input = input_3dwin;

	pwin.amb_r = 0.3;
	pwin.amb_g = 0.3;
	pwin.amb_b = 0.3;
	pwin.helpmsg = MESSAGE["HELP_3DMEDIA"];

-- this needs to be unique for each window as it's also
-- used as handler table for another window
	pwin.dispsrc_update = function(self, srcwnd)
		if (pwin.alive == false) then
			return;
		end

		local newdisp = null_surface(32, 32);
		image_tracetag(newdisp, "media_displaytag");
		image_sharestorage(srcwnd.canvas.vid, newdisp);
		pwin.model:update_display(newdisp, true);
	end

	local mh = {
	name = "3dwindow_canvas",
	own = function(self, vid) return vid == dstvid; end,
	
	drag = function(self, vid, dx, dy)
		pwin:focus();
		if (awbwman_cfg().meta.shift) then
			local props = image_surface_properties(pwin.model.vid);
			move3d_model(pwin.model.vid, props.x, 
				props.y + 0.01 * dy, props.z + 0.01 * dx); 
		else
			rotate3d_model(source.vid, 0.0, dy, dx, 0, ROTATE_RELATIVE);
		end
	end,

-- hint that this window accepts drag'n'drop for media
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

-- for drag'n'drop, also make sure to register as an update 
-- handler so the display will be changed 
-- whenever the source material does
	click = function()
		local tag = awbwman_cursortag();
		pwin:focus();

		if (tag and tag.kind == "media") then
			if (pwin.update_source and pwin.update_source.alive) then
				pwin.update_source:drop_handler("on_update", pwin.dispsrc_update);
			end

			pwin.update_source = tag.source;
			pwin.update_source:add_handler("on_update", pwin.dispsrc_update); 
			pwin:dispsrc_update(tag.source);

			tag:drop();
		end
	end};

	mouse_addlistener(mh, {"drag", "click", "over", "out"});
	add_3dmedia_top(pwin, active, inactive);
	table.insert(pwin.handlers, mh);
end
