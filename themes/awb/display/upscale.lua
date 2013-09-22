--
-- Setup- and option- wrapper for CGWGs CRT filter
--

local cont = {
	xbr = {
		method = "rounded",
		ddt = false
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

local function add_ddt(neww, newh, outw, outh)
	local ddtshader = load_shader("display/ddt.vShader", 
		"display/ddt.fShader", shid .. "_ddt", {});
		
		shader_uniform(ddtshader, "texture_size", "ff", 
			PERSIST, outprops.width, outprops.height);

	local ddtsurf = fill_surface(neww, newh, 0, 0, 0, neww, newh);
	show_image(ddtsurf);
	define_rendertarget(ddtsurf, {newobj}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
end

--
-- Similar to the one used in gridle,
-- but always uses an 1:1 FBO
--
cont.xbr.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shaderopts = {};

-- rebuild shader and define uniforms
	local s = load_shader("display/crt.vShader", 
		"display/crt.fShader", shid, shaderopts);

-- figure out max scale factor, scale to that and then let the output stretch.
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

	if (c.ddt) then
		newobj = add_ddt(neww, newh, outprops.width, outprops.height);
	
		image_texfilter(ddtsurf, FILTER_NONE);
			newobj = ddtsurf;
	end

	return newobj, c;
end

cont.sabr.setup = function(c, srcimg, sprops, inprops, outprops, optstr)
	
end

return cont;
