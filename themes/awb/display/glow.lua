--
-- Glow (just two-pass gaussian)
-- Trails (logging history trails and weighing in)
--

local cont = {
	glow = {
		hbias = 1.0,
		vbias = 1.0,
		hscale = 0.6,
		vscale = 0.6
	},
	trails = {
		trailstep = -2,
		trailfall =  2,
		trails    =  4,
		deltam = "off"
	},
	glowtrails = {
		hbias  = 1.0,
		vbias  = 1.0,
		hscale = 0.6,
		vscale = 0.6,
		trailstep  = -2,
		trailfall  =  2,
		trails     =  4,
		deltam = "off"
	}
};

local function add_glowopts(dsttbl, c, pwin)
	table.insert(dsttbl, {
		name = "hbias",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hbias", nil, nil, 0.1, 2.0, -0.1); 
			c:update_uniforms();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hbias", nil, nil, 0.1, 2.0, 0.1);
			c:update_uniforms();
		end,
		cols = {"Bias (Horiz.)", tostring_rdx(c.hbias)}
	});

	table.insert(dsttbl, {
		name = "vbias",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vbias", nil, nil, 0.1, 2.0, -0.1); 
			c:update_uniforms();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vbias", nil, nil, 0.1, 2.0,  0.1);
			c:update_uniforms();
		end,
		cols = {"Bias (Vert.)", tostring_rdx(c.vbias)}
	});

	table.insert(dsttbl, {
		name = "hscale",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hscale", nil, nil, 0.1, 1.0, -0.1);
			pwin:rebuild_chain();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "hscale", nil, nil, 0.1, 1.0,  0.1);
			pwin:rebuild_chain();
		end,
		cols = {"Scale (Horiz.)", tostring_rdx(c.hscale)}
	});

	table.insert(dsttbl, {
		name = "vscale",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vscale", nil, nil, 0.1, 1.0, -0.1); 
			pwin:rebuild_chain();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "vscale", nil, nil, 0.1, 1.0,  0.1);
			pwin:rebuild_chain();
		end,
		cols = {"Scale (Vert.)", tostring_rdx(c.vscale)}
	});
end

local function add_trailopts(dsttbl, c, pwin)
	table.insert(dsttbl, {
		name = "trailstep",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trailstep", nil, nil, -10, 10, -1.0); 
			pwin:rebuild_chain();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trailstep", nil, nil, -10, 10,  1.0);
			pwin:rebuild_chain();
		end,
		cols = {"Trail step", tostring_rdx(c.trailstep)}
	});

	table.insert(dsttbl, {
		name = "trailfall",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trailfall", nil, nil, -10, 10, -1.0); 
			pwin:rebuild_chain();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trailfall", nil, nil, -10, 10,  1.0);
			pwin:rebuild_chain();
		end,
		cols = {"Trailfall", tostring_rdx(c.trailfall)}
	});

	table.insert(dsttbl, {
		name = "trails",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trails", nil, nil, 1, 8, -1); 
			pwin:rebuild_chain();
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, c, "trails", nil, nil, 1, 8,  1);
			pwin:rebuild_chain();
		end,
		cols = {"Trails", tostring_rdx(c.trails)}
	});

	table.insert(dsttbl, {
		name = "deltam",
		trigger = function(self, wnd)
			stepfun_tbl(self, wnd, c, "deltam", 
				{"off", "delta", "delta only"}, true);
			wnd:force_update();
			pwin:rebuild_chain();
		end,
		rtrigger = trigger,
		cols = {"Delta Method", tostring_rdx(c.deltam)}
	});
end

cont.glow.confwin = function(c, pwin)
	local conftbl = {};
	add_glowopts(conftbl, c, pwin);

	local newwnd = awbwman_listwnd(
		menulbl("Glow Settings..."), deffont_sz, linespace,
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

	newwnd.name = "Trails Settings";
	newwnd:move(mx, my);
end

cont.trails.confwin = function(c, pwin)
	local conftbl = {};
	add_trailopts(conftbl, c, pwin);

	local newwnd = awbwman_listwnd(
		menulbl("Trails Settings..."), deffont_sz, linespace,
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

	newwnd.name = "Trails Settings";
	newwnd:move(mx, my);
end

cont.glowtrails.confwin = function(c, pwin)
	local conftbl = {};

	add_glowopts(conftbl, c, pwin);
	add_trailopts(conftbl, c, pwin);

	local newwnd = awbwman_listwnd(
		menulbl("Glowtrails Settings..."), deffont_sz, linespace,
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

	newwnd.name = "Glowtrails Settings";
	newwnd:move(mx, my);
end

local function gen_factstr(c)
	if (c.tag == "glow") then
		return string.format(
			"glowattr:hbias=%s:vbias=%s:hscale=%s:vscale=%s",
			tostring_rdx(c.hbias), tostring_rdx(c.vbias), 
			tostring_rdx(c.hscale), tostring_rdx(c.vscale));

	elseif (c.tag == "trails") then
		return string.format(
			"trailattr:trailstep=%d:trailfall=%d:trails=%d:deltam=%s",
			c.trailstep, c.trailfall, c.trails, c.deltam);

	elseif (c.tag == "glowtrails") then
		return string.format(
			"glowtrailattr:hbias=%s:vbias=%s:hscale=%s:vscale=%s" .. 
			":trailstep=%d:trailfall=%d:trails=%d:deltam=%s",
			tostring_rdx(c.hbias), tostring_rdx(c.vbias), 
			tostring_rdx(c.hscale), tostring_rdx(c.vscale),
			c.trailstep, c.trailfall, c.trails, c.deltam);

	end

	return factstr;
end

local function set_factstr(c, str)
	local tbl = string.split(str, ":");
	for i=2, #tbl do
		local argt = string.split(tbl[i], "=");
		if (#argt == 2) then
			local opc = argt[1];
			local opv = argt[2];
			c[opc] = tonumber_rdx(opv);
		end
	end
end

--
-- generates a shader with the purpose of mixing together history frames 
-- with the help of a set of weighhts
-- frames : array of #of frames and textures to be used
-- delta  : don't mix "everything" just the changes versus the first texture
-- deltaonly : only output the changes relative to the first frame (use with delta)
--
local function create_weighted_fbo( frames, delta, deltaonly )
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");

	for i=0,#frames-1 do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i) .. ";");
	end

	table.insert(resshader, "void main(){");
	table.insert(resshader, "vec4 col0 = texture2D(map_tu0, texco);");
		
	mixl = "";
	for i=1,#frames-1 do
		if (delta) then
			table.insert(resshader, "vec4 col" .. tostring(i) .. 
				" = clamp(col0 - texture2D(map_tu" .. tostring(i) .. 
				", texco), 0.0, 1.0);");

		else
			table.insert(resshader, "vec4 col" .. tostring(i) .. 
				" = texture2D(map_tu" .. tostring(i) .. ", texco);");
		end

		local strv = tostring_rdx(frames[i]);

		local coll = "vec4(" .. strv .. ", " .. strv .. ", " .. strv .. ", 1.0)";
		mixl = mixl .. "col" .. tostring(i) .. " * " .. coll;

		if (i == #frames-1) then
			mixl = mixl .. ";\n}\n";
		else
			mixl = mixl .. " + ";
		end
	end

	if (delta and deltaonly) then
		table.insert(resshader, 
			"gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0) + " ..mixl);
	else
		table.insert(resshader, "gl_FragColor = col0 + " ..mixl);
	end
	
	return resshader;
end

--
-- Set up a number of "spare" textures that act as storage 
-- for previous frames in the 'source' vid.
-- Will return the vid of the output rendertarget
-- trails    : number of history frames
-- trailstep : number of frames between each "step"
-- trailfall : >=0..9 (1.0-n then step to 0.1), 1+ exponential fade
-- targetw / targeth: down or upscale the output
--
function add_historybuffer(source, c, trails, 
	trailstep, trailfall, targetw, targeth)
	local frames = {};
	local base = 1.0;
	
	if (trailfall > 0) then
		local startv = 0.9 - (math.abs(trailfall) / 10.0);
		local endv   = 0.1;
		local step   = (startv - endv) / trails;
		
		for i=0, trails do
			frames[i+1] = startv - (step * i);
		end
	else
		trailfall = math.abs(trailfall);
-- exponential
		for i=0, trails do
			frames[i+1] = 1.0 / math.exp( trailfall * (i / trails) );
		end
	end
	
-- dynamically generate a shader that multitextures 
-- and blends using the above weights
	local fshader;
	if (c.deltam == "off") then
		fshader = create_weighted_fbo(frames, false, false);
	elseif (c.deltam == "on") then
		fshader = create_weighted_fbo(frames, true, false);
	else
		fshader = create_weighted_fbo(frames, true, true);
	end
	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", 
		fshader, "history_mix", {}, "#version 120");

	image_framesetsize(source, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(source, trailstep);
	image_shader(source, mixshader);
	show_image(source);
	move_image(source, 0, 0);
	image_mask_set(source, MASK_MAPPING);
	
-- generate textures to use as round-robin store, 
-- these need to match the storage size to avoid  a copy/scale each frame
	local props = image_surface_initial_properties(source);
	for i=1,trails do
		local vid = fill_surface(targetw, targeth, 0, 0, 0, props.width, props.height);
		image_texfilter(vid, FILTER_NONE);
		set_image_as_frame(source, vid, i, FRAMESET_DETACH);
	end

	image_texfilter(source, FILTER_NONE);
	rendertgt = fill_surface(targetw, targeth, 0, 0, 0, targetw, targeth);
	image_texfilter(rendertgt, FILTER_NONE);
	image_tracetag(rendertgt, "history_rtarget");
	define_rendertarget(rendertgt, {source}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	resize_image(source, targetw, targeth);
	show_image(rendertgt);
	image_tracetag(rendertgt, "vector(trailblur)");

	return rendertgt;
end

-- configure shaders for the blur / glow / bloom effect
local function glow_setup(c, id, blurw, blurh)
	if (c.shid_bh == nil) then
		c.shid_bh = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/fullscreen/gaussianH.fShader", id .. "blur_horiz", {},
		"#version 120");
 		c.shid_bv = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/fullscreen/gaussianV.fShader", id .. "blur_vert", {},
		"#version 120");
	end

	local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
	local blur_vbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);

	image_shader(blur_hbuf, c.shid_bh);
	image_shader(blur_vbuf, c.shid_bv);

	show_image(blur_hbuf);
	show_image(blur_vbuf);

	return blur_hbuf, blur_vbuf;
end

--
-- Add a two- stage gaussian blur and mix with the source image ("glow")
--
local function add_gaussian(c, src, inw, inh, outw, outh)
	local normal = null_surface(inw, inh);

-- link so cleanup goes smoothly
	link_image(normal, src);
	image_mask_clear(normal, MASK_POSITION);
	image_mask_clear(normal, MASK_OPACITY);
	image_sharestorage(src, normal);
	show_image(normal);

-- one horiz, one vertical blur step
	local blurw = inw * c.hscale;
	local blurh = inh * c.vscale;
	local blur_hbuf, blur_vbuf = glow_setup(c, c.shid, 
		blurw, blurh);

	c.update_uniforms = function()
		shader_uniform(c.shid_bh, "blur", "f", PERSIST, 1.0 / blurw);
		shader_uniform(c.shid_bv, "blur", "f", PERSIST, 1.0 / blurh);
		shader_uniform(c.shid_bh, "ampl", "f", PERSIST, c.hbias);
		shader_uniform(c.shid_bv, "ampl", "f", PERSIST, c.vbias);
	end

	c:update_uniforms();

	move_image(src, 0, 0);
	resize_image(src, blurw, blurh);
	show_image(src);
	define_rendertarget(blur_hbuf, {src},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- with bilinear filtering on blur_vbuf, 
-- we get a bigger kernel size "for free"
	local compbuf = fill_surface(outw, outh, 0, 0, 0, outw, outh); 
	blend_image(blur_vbuf, 0.99);
	resize_image(blur_vbuf, outw, outh); 
	resize_image(normal, outw, outh);

	image_tracetag(compbuf, "gaussian(composite)");

	force_image_blend(blur_vbuf, BLEND_ADD);
	force_image_blend(normal, BLEND_ADD);
	order_image(blur_vbuf, 2);
	order_image(normal, 3);
	define_rendertarget(compbuf, {blur_vbuf, normal}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	
	show_image(compbuf);
	return compbuf;	
end

cont.glow.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	if (c and c.tag and c.tag ~= "glow") then
		c = nil;
		return;
	end

	if (c == nil) then
		c = {};
		for k, v in pairs(cont.glow) do
			c[k] = v;
		end
	end
	
	c.shid = shid;
	c.tag = "glow";

	local res = add_gaussian(c, srcimg, inprops.width, 
		inprops.height, outprops.width, outprops.height);

	c.factorystr = gen_factstr;
	c.set_factstr = set_factstr;

	return res, c;
end

cont.trails.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	if (c and c.tag and c.tag ~= "trails") then
		c = nil;
		return;
	end

	if (c == nil) then
		c = {};
		for k, v in pairs(cont.trails) do
			c[k] = v;
		end
	end

	c.shid = shid;
	c.tag = "trails";

	image_mask_clear(srcimg, MASK_POSITION);
	image_mask_clear(srcimg, MASK_LIVING);

	local res = add_historybuffer(srcimg, c, c.trails, c.trailstep, 
		c.trailfall, inprops.width, inprops.height); 

	c.factorystr = gen_factstr;
	c.set_factstr = set_factstr;

	return res, c;
end

cont.glowtrails.setup = function(c, srcimg, shid, sprops, inprops, outprops, optstr)
	if (c and c.tag and c.tag ~= "glowtrails") then
		c = nil;
		return;
	end

	if (c == nil) then
		c = {};
		for k, v in pairs(cont.glowtrails) do
			c[k] = v;
		end
	end

	c.shid = shid;
	c.tag = "glowtrails";

	image_mask_clear(srcimg, MASK_POSITION);
	image_mask_clear(srcimg, MASK_LIVING);

	local res = add_historybuffer(srcimg, c, c.trails, c.trailstep, 
		c.trailfall, inprops.width, inprops.height); 

	c.factorystr = gen_factstr;
	c.set_factstr = set_factstr;

	res = add_gaussian(c, res, inprops.width, 
		inprops.height, outprops.width, outprops.height);

	return res, c;
end

return cont;
