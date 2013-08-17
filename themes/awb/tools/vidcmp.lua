--
-- VidCompare Built-in Tool
-- Can be used as a prefilter to VideoRecord 
--

local function build_cmpshader(ntus, mode)
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");

	for i=0, ntus-1 do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i) .. ";");
	end

	table.insert(resshader, "void main(){");
	table.insert(resshader, "vec4 col0 = 0.5 * texture2D(map_tu0, texco);");

-- basic mode, delta all other maps 
-- against the first one and only show the changes
	for i=1, ntus-1 do
		table.insert(resshader, 
			string.format("col0 = col0 + 0.2 * texture2D(map_tu%d, texco);", i));
	end
	
	table.insert(resshader, "gl_FragColor = vec4(col0.rgb, 1.0);}");
--	for i=1, ntus-1 do
--		line = line .. string.format("col%d+", i);
--	end
--	line = line:sub(1, line:len() - 1) .. ";}";
--	table.insert(resshader, line);

	return table.concat(resshader, "\n");
end

local function rebuild(wnd)
-- first, prune	
	for i=#wnd.sources,1,-1 do
		if (not valid_vid(wnd.sources[i])) then
			table.remove(wnd.sources, i);
		end
	end

-- then create a container target and an aggregation storage with
-- a frameset that fits all the sources. Then generate a shader
-- that applies the comparison function (according to set mode) 
-- and associate with the agg store.
	if (#wnd.sources > 1) then
		local vid = fill_surface(wnd.w, wnd.h, 0, 0, 0, wnd.w, wnd.h);
		local agg = fill_surface(wnd.w, wnd.h, 0, 0, 0, wnd.w, wnd.h);
		show_image({vid, agg});

		image_framesetsize(agg, #wnd.sources, FRAMESET_MULTITEXTURE);
		local shid = build_shader(nil, 
			build_cmpshader(#wnd.sources, wnd.mode), 
				"cmpshader_" .. tostring(wnd.wndid));
		image_shader(agg, shid);
		image_texfilter(agg, FILTER_NONE);
	
		for i=1,#wnd.sources do
			local inst = null_surface(1, 1);
			image_sharestorage(wnd.sources[i], inst);
			show_image(inst);
			image_texfilter(inst, FILTER_NONE);
			set_image_as_frame(agg, inst, i - 1, FRAMESET_DETACH);
		end

		define_rendertarget(vid, {agg}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- also takes care of deleting previous rendertarget
		wnd:update_canvas(vid);

	elseif (#wnd.sources == 1 and valid_vid(wnd.sources[1])) then
		local inst = null_surface(1, 1);
		image_sharestorage(wnd.sources[1], inst);
		wnd:update_canvas(inst); 

	else
-- show infographic
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
		"Matching",
		"Delta",
		"Trails"
	};
end

function spawn_vidcmp()
	local wnd = awbwman_spawn(menulbl("Compare"), {refid = "vidrec"});
	if (wnd == nil) then
		return;
	end

	wnd.sources = {};
	wnd.name = "Video Compare";
	wnd.mode = "Delta";

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", cfg.ttactiveres, 
		cfg.ttinactvres, cfg.topbar_sz);

	bar:add_icon("l", cfg.bordericns["play"], 
		function(self)
			wnd:focus();
			popup_options(wnd, self.vid); 
		end
	);

	bar.click = function() wnd:focus(); end

	local mh = {
		own = function(self, vid) return vid == wnd.canvas.vid; end,
		over = function(self, vid)
			local tag = awbwman_cursortag();
			if (tag and tag.kind == "media" and vid == wnd.canvas.vid) then
				tag:hint(true);
			end
		end,

		out = function(self, vid)
			local tag = awbwman_cursortag();
			if (tag and tag.kind == "mediaQ" and vid == wnd.canvas.vid) then
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
