--
-- VidCompare Built-in Tool
--
local function sample_prelude(weights)
	local resshader = {};

	table.insert(resshader, "varying vec2 texco;");
	table.insert(resshader, "uniform float obj_opacity;");

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
		string.format("vec3 finalc = %s;", table.concat(colvs, "+")));
	
	table.insert(resshader, "finalc = clamp(finalc, 0.0, 1.0);");
	table.insert(resshader, "gl_FragColor = vec4(finalc, obj_opacity);\n}");

	return table.concat(resshader, "\n");
end

local function datashare(wnd)
	local res  = awbwman_setup_cursortag(sysicons.floppy);
	res.kind   = "media";
	res.source = wnd;
	res.name   = wnd.name;
	return res;
end

--
-- Accumulate differences between textures per channel
--
local function gen_rgb_abscomp(weights, evalstr)
	local resshader = sample_prelude(weights);
	local colvs = {"r", "g", "b"};

	table.insert(resshader, "vec3 finalc = vec3(0.0, 0.0, 0.0);");

	for k=1, #weights-1 do
		table.insert(resshader,
			string.format("float diff_%d = abs(col0.r - col%d.r) " ..
				"+ abs(col0.g - col%d.g) + abs(col0.b - col%d.b);",
				k, k, k, k));
		table.insert(resshader, string.format(
			evalstr .. "\n\t finalc = finalc + col0;", k));
	end

	table.insert(resshader, "finalc = clamp(finalc, 0.0, 1.0);");
	table.insert(resshader, "gl_FragColor = vec4(finalc, obj_opacity);\n}");

	return table.concat(resshader, "\n");
end


local function build_matchshader(weights, mode)
	return gen_rgb_abscomp(weights, "if (diff_%d < 0.05)");
end

local function build_deltashader(weights, mode)
	return gen_rgb_abscomp(weights, "if (diff_%d > 0.05)");
end

local shdrtbl = {
	blend = build_blendshader,
	delta = build_deltashader,
	matching = build_matchshader
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
	local ind = #wnd.sources;

-- replace the slot reference and force a rebuild
	tag.source:add_handler("on_update", 
		function(self, srcwnd)
			if (wnd.alive == false) then
				return;
			end

			wnd.sources[ind] = srcwnd.canvas.vid;	
			rebuild(wnd);
		end);

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
	wnd.mode = "Blend";

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", wnd.ttbar_bg, wnd.ttbar_bg, cfg.topbar_sz);

	bar:add_icon("filter", "l", cfg.bordericns["filter"], 
		function(self)
			wnd:focus();
			popup_options(wnd, self.vid); 
		end
	);

	bar.hoverlut[
	(bar:add_icon("clone", "r", cfg.bordericns["clone"], 
		function() datashare(wnd); end)).vid
	] = MESSAGE["HOVER_CLONE"];

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
