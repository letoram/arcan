--
-- VidCompare Built-in Tool
--
-- Missing; 
--  dynamic buttons defining channel weights
--  register and handle dynamic source updates based on on_update (se 3dmodel)
--
local function sample_prelude(weights)
	local resshader = {};

	table.insert(resshader, "varying vec2 texco;");
	table.insert(resshader, "uniform float obj_opacity");

	for i=1, #weights do
		table.insert(resshader, "uniform sampler2D map_tu" .. 
			tostring(i-1) .. ";");
	end

	table.insert(resshader, "void main(){");

	for i=1, #weights do
		table.insert(resshader, string.format(
			"vec3 col%d = %f * texture2D(map_tu%d, texco).rgb;", 
				i-1, weights[i], i-1));
	end

	return resshader;
end

-- basic mode, just add the samples together
local function build_blendshader(weights)
	local resshader = sample_prelude(weights);
	local colvs = {};

	for i=1, #weights do
		table.insert(colvs, "col" .. tostring(i-1));
	end

	table.insert(resshader,
		"vec3 finalc = %s;", table.concat(colvs, "+"));
	table.insert(resshader, "gl_FragColor = vec4(finalc, obj_opacity);}");

	return table.concat(resshader, "\n");
end

--
-- Matching mode, only show colors with an 
-- accumulated deviation within a threshold
--
local function build_matchshader(weights, mode)
	local resshader = sample_prelude(weights);
	local colvs = {"r", "g", "b"};

	table.insert(resshader, 
		string.format("float diff_%s = 0.0f;", colv));

	for k=2, #weights do
		table.insert(resshader, string.format(
			"if (absf(col%d.%s - col%d.%s) < 0.1) diff_%s = col%d.%s;",
				0, colv, k-1, colv, colv, 0, colv));
	end

	return table.concat(resshader, "\n");
end

local function build_deltashader(weights, mode)
	local resshader = sample_prelude(weights);
	local colvs = {"r", "g", "b"};

	table.insert(resshader, 
		string.format("float diff_%s = 0.0f;", colv));

	for k=2, #weights do
		table.insert(resshader, string.format(
			"if (absf(col%d.%s - col%d.%s) < %f) diff_%s = col%d.%s;",
				0, colv, k-1, colv, 0.1, colv, 0, colv));
	end

	return table.concat(resshader, "\n");
end

local shdrtbl = {
	blend = build_blendshader,
	match = build_matchshader,
	delta = build_deltashader
};

local function rebuild(wnd)
-- first, prune	
	for i=#wnd.sources,1,-1 do
		if (not valid_vid(wnd.sources[i])) then
			table.remove(wnd.sources, i);
		end
	end

-- then create a container target and an aggregation storage with
-- a frameset that fits all the sources. 
	if (#wnd.sources > 1) then
		local vid = fill_surface(wnd.w, wnd.h, 0, 0, 0, wnd.w, wnd.h);
		local agg = fill_surface(wnd.w, wnd.h, 0, 0, 0, wnd.w, wnd.h);
		show_image({vid, agg});
		image_framesetsize(agg, #wnd.sources, FRAMESET_MULTITEXTURE);

		for i=1,#wnd.sources do
			local inst = null_surface(1, 1);
			image_sharestorage(wnd.sources[i], inst);
			show_image(inst);
			image_texfilter(inst, FILTER_NONE);
			set_image_as_frame(agg, inst, i - 1, FRAMESET_DETACH);
		end

		define_rendertarget(vid, {agg}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

		local weights = {};
		for i=1,#wnd.sources do
			weights[i] = 1.0;
		end

-- Then generate a shader that applies the comparison function 
-- (according to set mode) and associate with the aggregation store.

		local mode = string.lower(wnd.mode);
		local shid = build_shader(nil,  shdrtbl[mode](weights), 
			"cmpshader_" .. tostring(wnd.wndid));
		image_shader(agg, shid);
		image_texfilter(agg, FILTER_NONE);
	
-- also takes care of deleting previous rendertarget
		wnd:update_canvas(vid);

	elseif (#wnd.sources == 1 and valid_vid(wnd.sources[1])) then
		local inst = null_surface(1, 1);
		image_sharestorage(wnd.sources[1], inst);
		wnd:update_canvas(inst); 

	else
-- show infographic about > 1 sources needed
		wnd:update_canvas( fill_surface(wnd.w, wnd.h, 100, 100, 100) );
	end
end

local function add_source(wnd, tag)
-- No point in adding duplicates
	for i, v in ipairs(wnd.sources) do
		if (v == tag.source.canvas.vid) then
			return;
		end
	end

	table.insert(wnd.sources, tag.source.canvas.vid);
	rebuild(wnd);
end

local function popup_options(wnd)
	local optlist = {
		"Blend",
		"Delta",
		"Matching"
	};


	vid, lines = desktoplbl(table.concat(optlist, "\\n\\r"));
	awbwman_popup(vid, lines, function(ind, left)
		wnd.mode = string.lower(optlist[ind]);
		rebuild(wnd);
	end);
end

local function vidcmp_setup(wnd, options)
	wnd.sources = {};
	wnd.name = "Video Compare";
	wnd.mode = "Delta";

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", wnd.ttbar_bg, wnd.ttbar_bg, cfg.topbar_sz);

	bar:add_icon("play", "l", cfg.bordericns["play"], 
		function(self)
			wnd:focus();
			popup_options(wnd, self.vid); 
		end
	);

	bar.click = function() wnd:focus(); end

	local mh = {
		own = function(self, vid) return vid == wnd.canvas.vid; end,
		name = "vidcmp_mh",
		over = function(self, vid)
			local tag = awbwman_cursortag();
			if (tag and tag.kind == "media" and vid == wnd.canvas.vid) then
				tag:hint(true);
			end
		end,

		out = function(self, vid)
			local tag = awbwman_cursortag();
			if (tag and tag.kind == "media" and vid == wnd.canvas.vid) then
				tag:hint(false);
			end
		end,

		click = function(self, vid)
			wnd:focus();
			local tag = awbwman_cursortag();
			if (tag and tag.kind == "media") then
				add_source(wnd, tag);
				tag:drop();
			end
		end
	};

	mouse_addlistener(mh, {"click", "over", "out"});
	mouse_addlistener(bar, {"click"});

	table.insert(wnd.handlers, bar);
	table.insert(wnd.handlers, mh);

	wnd:resize(wnd.w, wnd.h);
	return wnd;
end

function spawn_vidcmp()
	local wnd = awbwman_customwnd(vidcmp_setup, menulbl("Compare"), 
		nil, {refid = "vidcmp"});

	if (wnd == nil) then
		return;
	end
end

local descrtbl = {
	name = "vidcmp",
	caption = "Compare",
	icon = "vidcmp",
	trigger = spawn_vidcmp
};

return descrtbl;
