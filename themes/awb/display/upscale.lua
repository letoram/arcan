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

	newwnd.name = "Upscaler Settings";
	newwnd:move(mx, my);
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

	newwnd.name = "Upscaler Settings";
	newwnd:move(mx, my);
end

local function add_ddt(c, newobj, shid, inw, inh, outw, outh)
	local ddtshader = load_shader("display/ddt.vShader", 
		"display/ddt.fShader", shid .. "_ddt", {},
		"#version 120");

	shader_uniform(ddtshader, "texture_size", "ff", PERSIST, outw, outh); 
	local ddtsurf = fill_surface(outw, outh, 0, 0, 0, inw, inh); 
	show_image(ddtsurf);
	image_tracetag(ddtsurf, "DDT_step");

	define_rendertarget(ddtsurf, {newobj}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	return ddtsurf;
end

local function gen_factstr(c)
	if (c.tag == "xbr") then
		return string.format(
			"xbrattr:method=%s:upscale_ineq=%s:factor=%d:post=%s%s",
			c.method, tostring_rdx(c.upscale_ineq), c.factor, c.post,
			c.ddt == true and ":ddt=1" or ":ddt=0"
		);

	elseif (c.tag == "sabr") then
		return string.format(
			"sabrattr:post=%s",
			c.post, c.ddt == true and ":ddt=1" or ":ddt=0"
		);
	end
end

-- works for both sabr and xbr
local function set_factstr(c, str)

	local tbl = string.split(str, ":");
	for i=2,#tbl do
		local argt = string.split(tbl[i], "=");
		if (#argt == 2) then
			local opc = string.lower(argt[1]);
			local opv = argt[2];
			local num = tonumber_rdx(opv);
			if (num) then
				c[opc] = num;
			else
				c[opc] = opv;
			end
		end
	end

	if (c.ddt == 1) then
		c.ddt = true;
	else
		c.ddt = false;
	end
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

-- just for tracetagging
	if (c.rebuildcount == nil) then
		c.rebuildcount = 1;
	else
		c.rebuildcount = c.rebuildcount + 1;
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
-- and engine resolution restrictions 
	local intw = sprops.width * c.factor;
	local inth = sprops.height * c.factor;

	while ( (intw > 2048 or inth > 2048) and c.factor >= 1) do
		intw = sprops.width * c.factor;
		inth = sprops.height * c.factor;
		c.factor = c.factor - 1;
	end

-- Can't clamp? then skip this filter 
	if (intw > 2048 or inth > 2048 or intw == 0 or inth == 0) then
		return srcimg, c;
	end

-- rebuild shader, setup internal storage matching scalefactor etc.
	local s = load_shader("display/xbr.vShader", 
		"display/xbr.fShader", shid, shaderopts,
		"#version 120");

	shader_uniform(s, "storage_size", "ff", PERSIST, intw, inth); 
	shader_uniform(s, "texture_size", "ff", PERSIST, inprops.width, inprops.height);
	shader_uniform(s, "eq_threshold","ffff",PERSIST, c.upscale_ineq, c.upscale_ineq,
		c.upscale_ineq, c.upscale_ineq);

-- figure out max scale factor, scale to that and then let the output stretch.
	local newobj = fill_surface(intw, inth, 0, 0, 0, intw, inth);
	image_texfilter(newobj, FILTER_NONE, FILTER_NONE);
	show_image(newobj);
	image_tracetag(newobj, "xbr_main_" .. tostring(c.rebuildcount));

-- detach, reset and setup rendertarget matching the scalefactor 
	show_image(srcimg);
	resize_image(srcimg, intw, inth); 
	move_image(srcimg, 0, 0);
	image_shader(srcimg, s);
	define_rendertarget(newobj, {srcimg}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- data-dependent triangulation
	if (c.ddt) then
		newobj = add_ddt(c, newobj, shid, 
			intw, inth, intw, inth); 
		resize_image(newobj, outprops.width, outprops.height); 
	end

-- size we resize the output to canvas size, 
-- additional filtering may be needed here
	if (post == "none") then
		image_texfilter(newobj, FILTER_NONE);
	elseif (post == "linear") then
		image_texfilter(newobj, FILTER_LINEAR);
	elseif (post == "bilinear") then
		image_texfilter(newobj, FILTER_BILINEAR);
	end

	c.factorystr  = gen_factstr;
	c.set_factstr = set_factstr;

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
		"display/sabr.fShader", shid, {}, "#version 120");

	shader_uniform(shid, "storage_size", "ff", PERSIST, 
		outprops.width, outprops.height);

	shader_uniform(shid, "texture_size", "ff", PERSIST,
		inprops.width, inprops.height);

	local newobj = fill_surface(outprops.width, outprops.height, 0, 0, 0,
		outprops.width, outprops.height);
	image_tracetag(newobj, "sabr_container");
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

	c.factorystr = gen_factstr;
	c.set_factstr = set_factstr;

	return newobj, c;
end

return cont;
