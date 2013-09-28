--
-- Setup- and option- wrapper for hyllian et. als upscalers. 
--

local cont = {
	xbr = {
		method = "rounded",
		ddt = false,
		factor = 5,
		upscale_ineq = 15,
		post = "none" 
	},
	sabr = {
		ddt = false,
		post = "none" 
	},
};

cont.xbr.confwin = function(c, pwin)
	local conftbl = {
		{
			name = "method",
			trigger = function(self, wnd)
				stepfun_tbl(self, wnd, c, "method", {"rounded", 
					"semi-rounded", "square", "level3"}, true); 
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = function(self, wnd)
				stepfun_tbl(self, wnd, c, "method", {"rounded", 
					"semi-rounded", "square", "level3"}, false); 
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			cols = {"Method", c.method}
		},
		{
			name = "factor",
			trigger = function(self, wnd)
				stepfun_num(self, wnd, c, "factor", nil, nil, 1, 5, 1);
				pwin:rebuild_chain();
			end,
			rtrigger = function(self, wnd)
				stepfun_num(self, wnd, c, "factor", nil, nil, 1, 5, -1);
				pwin:rebuild_chain();
			end,
			cols = {"Scale Factor", c.factor}
		},
		{
			name = "upscale_ineq",
			trigger = function(self, wnd)
				stepfun_num(self, wnd, c, "upscale_ineq", nil, nil, 1, 15, 1);
				pwin:rebuild_chain();
			end,
			rtrigger = function(self, wnd)
				stepfun_num(self, wnd, c, "upscale_ineq", nil, nil, 1, 15, -1);
				pwin:rebuild_chain();
			end,
			cols = {"Upscale Inequality", tostring(c.upscale_ineq)}
		},
		{
			name = "ddt",
			trigger = function(self, wnd)
				c.ddt = not c.ddt;
				self.cols[2] = tostring(c.ddt);
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"DDT- Stage", tostring(c.ddt)} 
		},
		{
			name = "post",
			trigger = function(self, wnd)
				stepfun_tbl(self, wnd, c, "post", {"none", "linear", "bilinear"},
					true); 
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"Postfilter", "none"};
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("XBR Settings..."), deffont_sz, linespace,
		{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

		pwin:add_cascade(newwnd);
		newwnd:move(mouse_xy());
end

cont.sabr.confwin = function(c, pwin)
	local conftbl = {
		{
			name = "ddt",
			trigger = function(self, wnd)
				c.ddt = not c.ddt;
				self.cols[2] = tostring(c.ddt);
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"DDT- Stage", tostring(c.ddt)} 
		},
		{
			name = "post",
			trigger = function(self, wnd)
				stepfun_tbl(self, wnd, c, "post", {"none", "linear", "bilinear"},
					true); 
				wnd:force_update();
				pwin:rebuild_chain();
			end,
			rtrigger = trigger,
			cols = {"Postfilter", "none"};
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("SABR Settings..."), deffont_sz, linespace,
		{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

		pwin:add_cascade(newwnd);
		newwnd:move(mouse_xy());
end

local function add_ddt(c, newobj, shid, inw, inh, outw, outh)
	local ddtshader = load_shader("display/ddt.vShader", 
		"display/ddt.fShader", shid .. "_ddt", {});

	shader_uniform(ddtshader, "texture_size", "ff", PERSIST, inw, inh); 
	local ddtsurf = fill_surface(outw, outh, 0, 0, 0, outw, outh); 
	show_image(ddtsurf);

	define_rendertarget(ddtsurf, {newobj}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	return ddtsurf;
end

--
-- Similar to the one used in gridle,
-- but always uses an 1:1 FBO
--
cont.xbr.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	local shaderopts = {};

	if (c == nil or c.tag ~= "xbr") then
		c = {};
		for k, v in pairs(cont.xbr) do
			c[k] = v;
		end
		c.tag = "xbr";
	end

	if (c.method == "rounded") then
		shaderopts["METHOD_A"] = true;
	elseif (c.method == "semi-rounded") then
		shaderopts["METHOD_B"] = true;
	elseif (c.method == "square") then
		shaderopts["METHOD_C"] = true;
		shaderopts["REVAA_HYBRID"] = true;
	elseif (c.method == "level3") then
		shaderopts["LEVEL_3A"] = true;
	end

-- clamp scale factor based on input source

	local intw = sprops.width * c.factor;
	local inth = sprops.height * c.factor;

	while ( (intw > 2048 or inth > 2048) and c.factor >= 1) do
		intw = sprops.width * c.factor;
		inth = sprops.height * c.factor;
		c.factor = c.factor - 1;
	end

-- Can't clamp? then skip this filter 
	if (intw > 2048 or inth > 2048) then
		return srcimg, c;
	end

-- rebuild shader, setup internal storage matching scalefactor etc.
	local s = load_shader("display/xbr.vShader", 
		"display/xbr.fShader", shid, shaderopts);

	shader_uniform(s, "storage_size", "ff", PERSIST, intw, inth); 
	shader_uniform(s, "texture_size", "ff",PERSIST,inprops.width, inprops.height);
	shader_uniform(s, "eq_threshold","ffff",PERSIST,c.upscale_ineq,c.upscale_ineq,
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
		newobj = add_ddt(c, newobj, shid, 
			intw, inth, outprops.width, outprops.height);
	end

	if (post == "none") then
		image_texfilter(newobj, FILTER_NONE);
	elseif (post == "linear") then
		image_texfilter(newobj, FILTER_LINEAR);
	elseif (post == "bilinear") then
		image_texfilter(newobj, FILTER_BILINEAR);
	end

	return newobj, c;
end

cont.sabr.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	if (c == nil or c.tag ~= "sabr") then
		c = {};
		for k, v in pairs(cont.sabr) do
			c[k] = v;
		end
		c.tag = "sabr";
	end

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
		newobj = add_ddt(c, newobj, shid, outprops.width, outprops.height,
			outprops.width, outprops.height);
	end

	if (post == "none") then
		image_texfilter(newobj, FILTER_NONE);
	elseif (post == "linear") then
		image_texfilter(newobj, FILTER_LINEAR);
	elseif (post == "bilinear") then
		image_texfilter(newobj, FILTER_BILINEAR);
	end

	return newobj, c;
end

return cont;
