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

-- macro defaults, parsing factorstring projects values overrides
cont.opts = {};
cont.opts["CURVATURE"] = true;
cont.opts["USEGAUSSIAN"] = true;
cont.opts["LINEAR_PROCESSING"] = true;
cont.opts["OVERSAMPLE"] = true;

cont.confwin = function(pwin)
-- left: increment, right: decrement
-- create listview and link to parent
end

--
-- Similar to the one used in gridle,
-- but always uses an 1:1 FBO
--
cont.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shaderopts = {};

-- rebuild shader and define uniforms
	local s = load_shader("display/crt.vShader", 
		"display/crt.fShader", shid, shaderopts);

	print("store:", sprops.width, sprops.height);
	print("in:", inprops.width, inprops.height);
	print("out:", outprops.width, outprops.height);

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

	return newobj;
end

return cont;
