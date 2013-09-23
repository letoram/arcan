--
-- Setup- and option- wrapper for CGWGs CRT filter
--

local cont = {
	xbr = {
		method = "rounded",
		ddt = false,
		factor = 5,
		upscale_ineq = 15,
		post = FILTER_NONE
	},
	sabr = {
		ddt = false,
		post = FILTER_NONE
	},
};

-- macro defaults, parsing factorstring projects values overrides

cont.xbr.confwin = function(pwin)
-- left: increment, right: decrement
-- create listview and link to parent
end

cont.sabr.confwin = function(pwin)
end

local function add_ddt(newobj, neww, newh, outw, outh)
	local ddtshader = load_shader("display/ddt.vShader", 
		"display/ddt.fShader", shid .. "_ddt", {});

	shader_uniform(ddtshader, "texture_size", "ff", PERSIST, neww, newh); 

	local ddtsurf = fill_surface(outw, outh, 0, 0, 0, neww, newh);
	show_image(ddtsurf);
	define_rendertarget(ddtsurf, {newobj}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	image_texfilter(ddtsurf, FILTER_NONE); 
	return ddtsurf;
end

--
-- Similar to the one used in gridle,
-- but always uses an 1:1 FBO
--
cont.xbr.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shaderopts = {};

-- MISSING; project optstr unto c
	if (c.method == "rounded") then
		shaderopts["METHOD_A"] = true;
		print("method a");
	elseif (c.method == "semi-rounded") then
		shaderopts["METHOD_B"] = true;
	elseif (c.method == "square") then
		shaderopts["METHOD_C"] = true;
		shaderopts["REVAA_HYBRID"] = true;
	elseif (c.method == "level3") then
		shaderopts["LEVEL_3A"] = true;
	end

-- clamp scale factor based on input source
	local intw = 4096;
	local inth = 4096;
	while ( (intw > 2048 or inth > 2048) and c.factor >= 1) do
		intw = sprops.width * c.factor;
		inth = sprops.height * c.factor;
		c.factor = c.factor - 1;
	end

-- Can't clamp? then skip this filter 
	if (intw > 2048 or inth > 2048) then
		return srcimg;
	end

-- rebuild shader, setup internal storage matching scalefactor etc.
	local s = load_shader("display/xbr.vShader", 
		"display/xbr.fShader", shid, shaderopts);

	shader_uniform(s, "storage_size", "ff", PERSIST, intw, inth); 
	shader_uniform(s, "texture_size", "ff", PERSIST, inprops.width, inprops.height);
	shader_uniform(s, "eq_threshold", "ffff", PERSIST, c.upscale_ineq, c.upscale_ineq,
		c.upscale_ineq, c.upscale_ineq);

-- figure out max scale factor, scale to that and then let the output stretch.
	local newobj = fill_surface(intw, inth, 0, 0, 0, intw, inth);
	image_texfilter(newobj, FILTER_NONE, FILTER_NONE);
	show_image(newobj);

-- detach, reset and setup rendertarget matching the scalefactor 
	show_image(srcimg);
	resize_image(srcimg, intw, inth); 
	link_image(srcimg, srcimg);
	move_image(srcimg, 0, 0);
	image_shader(srcimg, s);
	define_rendertarget(newobj, {srcimg}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	if (c.ddt) then
		newobj = add_ddt(newobj, intw, inth, outprops.width, outprops.height);
	end

	return newobj, c;
end

cont.sabr.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shid = load_shader("display/sabr.vShader", 
		"display/sabr.fShader", shid, {});

	shader_uniform(shid, "storage_size", "ff", PERSIST, 
		outprops.width, outprops.height);

	shader_uniform(shid, "texture_size", "ff", PERSIST,
		inprops.width, inprops.height);

	local newobj = fill_surface(outprops.width, outprops.height, 0, 0, 0,
		outprops.width, outprops.height);
	image_texfilter(newobj, FILTER_NONE);
	show_image({newobj, srcimg});
	image_shader(srcimg, shid);
	resize_image(srcimg, outprops.width, outprops.height);
	define_rendertarget(newobj, {srcimg}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	if (c.ddt) then
		newobj = add_ddt(newobj, outprops.width, outprops.height);
	end

	return newobj, c;
end

return cont;
