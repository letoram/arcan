--
-- Setup- and option- wrapper for CGWGs CRT filter
--

local cont = {
	gamma = 2.4,
	mongamma = 2.2,
	hoverscan = 1.02,
	voverscan = 1.02,
	haspect = 1.0,
	vaspect = 0.75,
	curvrad = 1.5,
	distance = 2.0,
	tilth = 0.0,
	tiltv = -0.10,
	cornersz = 0.03,
	cornersmooth = 1000
};

local function stepfun_num(trig, wnd, c, name, shsym, shtype, min, max, step)
	c[name] = c[name] + step;
	c[name] = c[name] < min and min or c[name];
	c[name] = c[name] > max and max or c[name];

	trig.cols[2] = tostring(c[name]);

	wnd:force_update();
	if (shsym) then
		shader_uniform(c.shid, shsym, shtype, PERSIST, c[name]);
	end
end

cont.confwin = function(c, pwin)
	local conftbl = {
		{
			name = "crtgamma",
			trigger = function(self, wnd)
				stepfun_num(self, wnd, c, "gamma", "CRTgamma", "f", 1.0, 3.0, -0.2);
			end,
			rtrigger = function(self, wnd)
				stepfun_num(self, wnd, c, "gamma", "CRTgamma", "f", 1.0, 3.0, 0.2);
			end,
			cols = {"Gamma (CRT)", tostring(c.gamma)}
		},
		{
			name = "mongamma",
			trigger = function(self, wnd)
				stepfun_num(self, wnd, c, "mongamma", 
					"monitorgamma", "f", 1.0, 3.0, -0.2);
			end,
			rtrigger = function(self, wnd)
				stepfun_num(self, wnd, c, "mongamma", 
					"monitorgamma", "f", 1.0, 3.0, 0.2);
			end,
			cols = {"Gamma (Monitor)", tostring(c.mongamma)}
		},
		{
		name = "hoverscan",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hoverscan", nil, nil, 0.8, 1.2, -0.02);
			shader_uniform(c.shid, "overscan", "ff", 
				PERSIST, c.hoverscan, c.voverscan);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hoverscan", nil, nil, 0.8, 1.2, 0.02); 
			shader_uniform(c.shid, "overscan", "ff", 
				PERSIST, c.hoverscan, c.voverscan);
			end,
		cols = {"Overscan (H)", tostring(c.hoverscan)}
		},
		{
		name = "voverscan",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "voverscan", nil, nil, 0.8, 1.2, -0.02); 
			shader_uniform(c.shid, "overscan", "ff", 
				PERSIST, c.hoverscan, c.voverscan);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "voverscan", nil, nil, 0.8, 1.2, 0.02);
			shader_uniform(c.shid, "overscan", "ff", 
				PERSIST, c.hoverscan, c.voverscan);
			end,
		cols = {"Overscan (V)", tostring(c.voverscan)}
		},
		{
		name = "haspect",
			trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "haspect", nil, nil, 0.75, 1.25, -0.05);
			shader_uniform(c.shid, "aspect", "ff", 
				PERSIST, c.haspect, c.vaspect);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "haspect", nil, nil, 0.75, 1.25, 0.05);
			shader_uniform(c.shid, "aspect", "ff", 
				PERSIST, c.haspect, c.vaspect);
			end,
		cols = {"Aspect (H)", tostring(c.haspect)}
		},
		{
		name = "vaspect",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vaspect", nil, nil, 0.75, 1.25, -0.05);
			shader_uniform(c.shid, "aspect", "ff", 
				PERSIST, c.haspect, c.vaspect);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vaspect", nil, nil, 0.75, 1.25, 0.05); 
			shader_uniform(c.shid, "aspect", "ff", 
				PERSIST, c.haspect, c.vaspect);
			end,
		cols = {"Aspect (H)", tostring(c.vaspect)}
		},
		{
		name = "curvrad",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "curvrad", "curv_radius", 
				"f", 0.6, 2.0, -0.1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "curvrad", "curv_radius", 
				"f", 0.6, 2.0, 0.1);
		end,
		cols = {"Radius", tostring(c.curvrad)}
		},
		{
		name = "distance",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "distance", "distance", 
				"f", 0.6, 1.6, -0.1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "distance", "distance", 
				"f", 0.6, 1.6, 0.1);
		end,
		cols = {"Distance", tostring(c.distance)}
		},
		{
		name = "cornersz",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "cornersz", "cornersize", "f", 0.1, 5.0, -0.1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "cornersz", "cornersize", "f", 0.1, 5.0, 0.1);
		end,
		cols = {"Corner Size", tostring(c.cornersz)}
		},
		{
		name = "cornersmooth",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "cornersmooth", 
				"cornersmooth", "f", 80, 1500, -100);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "cornersmooth", 
				"cornersmooth", "f", 80, 1500, 100);
		end,
		cols = {"Corner Smooth", tostring(c.cornersmooth)}
		},
		{
		name = "curvaturetog",
		trigger = function(self, wnd)
			c.opts["CURVATURE"] = not c.opts["CURVATURE"];
			self.cols[1] = tostring(c.opts["CURVATURE"]);
			pwin:rebuild_chain();
		end,
		rtrigger = trigger,
		cols = {"Curvature", tostring(c.opts["CURVATURE"])}
		}
--		c.opts["USEGAUSSIAN"]       = true;
--		c.opts["LINEAR_PROCESSING"] = true;
--		c.opts["OVERSAMPLE"]        = true;
	};

	local newwnd = awbwman_listwnd(
		menulbl("CRT Settings.."), deffont_sz, linespace, 
			{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

	pwin:add_cascade(newwnd);

-- left: increment, right: decrement
-- create listview and link to parent
end

--
-- Similar to the one used in gridle,
-- but always uses an 1:1 FBO
--
cont.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shaderopts = {};

	if (c == nil) then
		c = {};
		for k,v in pairs(cont) do
			c[k] = v;
		end

-- macro defaults, parsing factorstring projects values overrides
		c.opts = {};
		c.opts["CURVATURE"]         = false;
		c.opts["USEGAUSSIAN"]       = true;
		c.opts["LINEAR_PROCESSING"] = true;
		c.opts["OVERSAMPLE"]        = true;
	end

-- rebuild shader and define uniforms
	local s = load_shader("display/crt.vShader", 
		"display/crt.fShader", shid, c.opts);

-- could make this cheaper and simply encode the values into the shader
-- before uploading ..
	shader_uniform(s, "input_size", "ff", PERSIST, inprops.width, inprops.height);
	shader_uniform(s, "output_size", "ff",PERSIST,outprops.width,outprops.height);
	shader_uniform(s, "storage_size", "ff", PERSIST, sprops.width, sprops.height);
	shader_uniform(s, "CRTgamma", "f", PERSIST, c.gamma);
	shader_uniform(s, "overscan", "ff", PERSIST, c.hoverscan, c.voverscan);
	shader_uniform(s, "monitorgamma", "f", PERSIST, c.mongamma);
	shader_uniform(s, "aspect", "ff", PERSIST, c.haspect, c.vaspect);
	shader_uniform(s, "distance", "f", PERSIST, c.distance);
	shader_uniform(s, "curv_radius", "f", PERSIST, c.curvrad);
	shader_uniform(s, "tilt_angle", "ff", PERSIST, c.tilth, c.tiltv);
	shader_uniform(s, "cornersize", "f", PERSIST, c.cornersz);
	shader_uniform(s, "cornersmooth", "f", PERSIST, c.cornersmooth);

	local newobj = fill_surface(outprops.width, outprops.height, 0, 0, 0,
		outprops.width, outprops.height);
	
	image_texfilter(newobj, FILTER_NONE, FILTER_NONE);

	show_image(newobj);

-- completely detach and fit
	show_image(srcimg);
	resize_image(srcimg, outprops.width, outprops.height);
	link_image(srcimg, srcimg);
	move_image(srcimg, 0, 0);

	image_shader(srcimg, s);

	define_rendertarget(newobj, {srcimg}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	c.shid = s;

	return newobj, c;
end

return cont;
