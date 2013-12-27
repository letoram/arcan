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
			stepfun_num(self, wnd, c, "dispdist", "distance", 
				"f", 0.6, 1.6, -0.1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "dispdist", "distance", 
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
			self.cols[2] = tostring(c.opts["CURVATURE"]);
			wnd:force_update();
			pwin:rebuild_chain();
		end,
		rtrigger = trigger,
		cols = {"Curvature", tostring(c.opts["CURVATURE"])}
		},
		{
			name = "lineartog",
			trigger = function(self, wnd)
				c.opts["LINEAR_PROCESSING"] = not c.opts["LINEAR_PROCESSING"];
				self.cols[2] = tostring(c.opts["LINEAR_PROCESSING"]);
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"Linear Processing", tostring(c.opts["LINEAR_PROCESSING"])}
		},
		{
			name = "oversampletog",
			trigger = function(self, wnd)
				c.opts["OVERSAMPLE"] = not c.opts["OVERSAMPLE"];
				self.cols[2] = tostring(c.opts["OVERSAMPLE"]);
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"Oversample", tostring(c.opts["OVERSAMPLE"])}
		},
		{
			name = "gaussiantog",
			trigger = function(self, wnd)
				c.opts["USEGAUSSIAN"] = not c.opts["USEGAUSSIAN"];
				self.cols[2] = tostring(c.opts["USEGAUSSIAN"]);
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"Gaussian", tostring(c.opts["USEGAUSSIAN"])}
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("CRT Settings.."), deffont_sz, linespace, 
			{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

	if (newwnd == nil) then
		return;
	end

	pwin:add_cascade(newwnd);
	local mx, my = mouse_xy();
	if (mx + newwnd.w > VRESW) then
		mx = VRESW - newwnd.w;
	end

	if (my + newwnd.y > VRESH) then
		my = VRESH - newwnd.h;
	end

	newwnd.name = "CRT settings";
	newwnd:move(mx, my);
end

local function gen_factstr(c)
	local res = "crtattr:" .. 
		(c.opts["CURVATURE"] == true and "curvature:" or "") ..
		(c.opts["USEGAUSSIAN"] == true and "gaussian:" or "") .. 
		(c.opts["LINEAR_POCESSING"] == true and "linear:" or "") .. 
		(c.opts["OVERSAMPLE"] == true and "oversample:" or "");

	return string.format("%sgamma=%s:hoverscan=%s:voverscan=%s:" ..
	"monitorgamma=%s:haspect=%s:vaspect=%s:distance=%s:curvrad=%s:" ..
	"tilth=%s:tiltv=%s:cornersz=%s:cornersmooth=%s", res,  
		tostring_rdx(c.gamma), tostring_rdx(c.hoverscan), tostring_rdx(c.voverscan),
		tostring_rdx(c.mongamma), tostring_rdx(c.haspect), tostring_rdx(c.vaspect), 
		tostring_rdx(c.distance), tostring_rdx(c.curvrad), tostring_rdx(c.tilth), 
		tostring_rdx(c.tiltv), tostring_rdx(c.cornersz), 
		tostring_rdx(c.cornersmooth));
end

local function push_uniforms(s, c)
	if (c.gamma == nil) then
		for k, v in pairs(cont) do
			if (c[k] == nil) then
				c[k] = v;
			end
		end
		return;
	end

	shader_uniform(s, "CRTgamma", "f", PERSIST, c.gamma);
	shader_uniform(s, "overscan", "ff", PERSIST, c.hoverscan, c.voverscan);
	shader_uniform(s, "monitorgamma", "f", PERSIST, c.mongamma);
	shader_uniform(s, "aspect", "ff", PERSIST, c.haspect, c.vaspect);
	shader_uniform(s, "dispdist", "f", PERSIST, c.distance);
	shader_uniform(s, "curv_radius", "f", PERSIST, c.curvrad);
	shader_uniform(s, "tilt_angle", "ff", PERSIST, c.tilth, c.tiltv);
	shader_uniform(s, "cornersize", "f", PERSIST, c.cornersz);
	shader_uniform(s, "cornersmooth", "f", PERSIST, c.cornersmooth);
end

local function set_factstr(c, str)
	local tbl = string.split(str, ":");

	c.opts["CURVATURE"]         = false;
	c.opts["USEGAUSSIAN"]       = false;
	c.opts["LINEAR_PROCESSING"] = false;
	c.opts["OVERSAMPLE"]        = false; 

	for i=2,#tbl do
		if (tbl[i] == "curvature") then
			c.opts["CURVATURE"] = true;
		elseif (tbl[i] == "gaussian") then
			c.opts["USEGAUSSIAN"] = true;
		elseif (tbl[i] == "linear") then
			c.opts["LINEAR_PROCESSING"] = true;
		elseif (tbl[i] == "oversample") then
			c.opts["OVERSAMPLE"] = true;
		else
			local argt = string.split(tbl[i], "=");
			if (#argt == 2) then
				local opc = argt[1];
				local opv = argt[2];
				c[opc] = tonumber_rdx(opv);
			end
		end
	end

	push_uniforms(c.shid, c);
end

--
-- Similar to the one used in gridle,
-- but always uses a 1:1 FBO
--
cont.setup = function(c, srcimg, shid, sprops, inprops, outprops)
	if (c == nil) then
		c = {};
		c.rebuildc = 0;

		for k,v in pairs(cont) do
			c[k] = v;
		end

-- macro defaults, parsing factorstring projects values overrides
		c.opts = {};
		c.opts["CURVATURE"]         = false;
		c.opts["USEGAUSSIAN"]       = true;
		c.opts["LINEAR_PROCESSING"] = true;
		c.opts["OVERSAMPLE"]        = true; 
	else
		c.rebuildc = c.rebuildc + 1;
	end

-- just keep the true flagged
	local shopts = {};
	for k,v in pairs(c.opts) do
		if (v) then
			shopts[k] = true;
		end
	end

-- rebuild shader and define uniforms
	local s = load_shader("display/crt.vShader", 
		"display/crt.fShader", shid, shopts, "#version 120");

-- could make this cheaper and simply encode the values into the shader
-- before uploading ..
	shader_uniform(s, "input_size", "ff", PERSIST, inprops.width, inprops.height);
	shader_uniform(s, "output_size", "ff",PERSIST,outprops.width,outprops.height);
	shader_uniform(s, "storage_size", "ff", PERSIST, sprops.width, sprops.height);
	push_uniforms(s, c);

	local newobj = fill_surface(outprops.width, outprops.height, 0, 0, 0,
		outprops.width, outprops.height);

	image_tracetag(newobj, "crt_filter_" .. tostring(c.rebuildc));
	image_texfilter(newobj, FILTER_NONE, FILTER_NONE);
	show_image(newobj);

-- completely detach and fit
	show_image(srcimg);
	resize_image(srcimg, outprops.width, outprops.height);
	move_image(srcimg, 0, 0);
	image_shader(srcimg, s);

	define_rendertarget(newobj, {srcimg}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	c.shid = s;
	c.factorystr = gen_factstr;
	c.set_factstr = set_factstr;

	return newobj, c;
end

return cont;
