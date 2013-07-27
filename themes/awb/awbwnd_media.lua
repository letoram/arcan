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
	return true;
end

local function add_3dmedia_top(pwin, active, inactive)

	local bar = pwin:add_bar("tt", active, inactive, 
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	local mh = {
		function own(self, vid)
			for i,v in ipairs({"left", "right"}) do
				for j,h in ipairs(self[v]) do
					if (h.vid == vid) then
						return true;
					end
				end
			end
			return false;
		end

			return vid == self.vid; 
		end

	};

	bar:add_icon("l", cfg.bordericns["plus"],  function(zoom); 
	bad_add_icon("l", cfg.bordericns["minus"], zoom);

	bar:add_icon("l", cfg.bordericns["r1"], slide_pop);
	bar:add_icon("l", cfg.bordericns["g1"], slide_pop);
	bar:add_icon("l", cfg.bordericns["b1"], slide_pop);

	bar:add_icon("r", cfg.bordericns["clone"],   slide_pop);

	local mhs = {};
	
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

		local mh = {
			own = function(self, vid) return vid == dstvid; end,
			drag = function(self, vid, dx, dy)
				rotate3d_model(source, 0.0, dy, -1 * dx, 0, ROTATE_RELATIVE);
			end
		};
	
		rotate_image(pwin.canvas.vid, 180);
		mouse_addlistener(mh, {"drag"});
		add_3dmedia_top(pwin, active, inactive);

	else
		warning("awbwnd_media() media type: " .. kind .. "unknown\n");
	end

	return callback; 
end
