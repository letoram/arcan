--
-- Recorder Built-in Tool
-- Some regular configuration popups, e.g. resolution, framerate, 
-- and a drag-n-drop composition canvas
--

--
-- Missing;
-- Activation
-- Aspect Enforcing in Resize.

local function sweepcmp(vid, tbl)
	for k,v in ipairs(tbl) do
		if (v == vid) then
			return true;
		end
	end

	return false;
end


local function add_rectarget(wnd, tag)
	local tmpw, tmph = wnd.w * 0.4, wnd.h * 0.4;
	local source = {};

	source.data  = tag.source;
	source.dmode = nil;
	source.vid   = null_surface(tmpw, tmph);
	source.own   = function(self, vid) return vid == source.vid; end
	source.drag  = function(self, vid, dx, dy)

--
-- Add mouse handlers for moving / scaling, which one it'll be depends
-- on if the click point is closer to the center or the edge of the object
		if (source.dmode == nil) then
			local props = image_surface_properties(source.vid);
			source.start = props;

			local mx, my = mouse_xy();
			local rprops = image_surface_resolve_properties(source.vid);
			rprops.width = rprops.width * 0.5;
			rprops.height= rprops.height * 0.5;
			local cata  = math.abs(rprops.x + rprops.width - mx);
			local catb  = math.abs(rprops.y + rprops.height - my);
			local dist  = math.sqrt( cata * cata + catb * catb );
			local hhyp  = math.sqrt( rprops.width * rprops.width +
				rprops.height * rprops.height ) * 0.5;

			if (dist < hhyp) then
				source.dmode = "move";
			else
				source.dmode = "scale"; 
			end
		elseif (source.dmode == "move") then
			if (awbwman_cfg().meta.shift) then
				source.start.angle = source.start.angle + dx;
				rotate_image(source.vid, source.start.angle);
			else
				source.start.x = source.start.x + dx;
				source.start.y = source.start.y + dy;
				move_image(source.vid, source.start.x, source.start.y);
			end
		elseif (source.dmode == "scale") then
			source.start.width  = source.start.width  + dx;
			source.start.height = source.start.height + dy;
			resize_image(source.vid, source.start.width, source.start.height);
		end
	end

-- update selected for wnd so 'del' input key works
	source.click = function(self, vid)
		local tag = awbwman_cursortag();
		
		if (wnd.selected ~= source) then
			if (wnd.selected) then
				image_shader(wnd.selected.vid, "DEFAULT");
			end

			wnd.selected = source;
			image_shader(wnd.selected.vid, "awb_selected");

		else	
			image_shader(wnd.selected.vid, "DEFAULT");
			wnd.selected = nil;
		end

		if (tag and tag.kind == "media") then
			add_rectarget(wnd, tag);
		end
	end

	source.dblclick = function(self, vid)
		resize_image(source.vid, wnd.w, wnd.h);
		move_image(source.vid, 0, 0);
	end

	source.rclick = function(self, vid)
		local dind = 0;

		for i=1,#wnd.sources do
			if (wnd.sources[i] == source) then
				dind = i;
				break;
			end
		end

		if (dind > 1) then
			local tbl = table.remove(wnd.sources, dind);
			table.insert(wnd.sources, dind - 1, tbl);
		end

		for i=1,#wnd.sources do
			order_image(wnd.sources[i].vid, 1);
		end
	end

	source.drop = function(self, vid)
		source.dmode = nil;
		source.start = nil;
	end

	image_sharestorage(tag.source.canvas.vid, source.vid);
	table.insert(wnd.sources, source);
	show_image(source.vid);
	image_inherit_order(source.vid, true);
	link_image(source.vid, wnd.canvas.vid);
	image_clip_on(source.vid);

	source.name = "vidrec_source";
	mouse_addlistener(source, {"click", "rclick", "drag", "drop", "dblclick"});
	tag:drop();
end

local function change_selected(vid)
	print("change selected");
end

local function dotbl(icn, tbl, dstkey, convert, hook)
	for i=1,#tbl do
		if (tbl[i] == icn.parent.parent[dstkey]) then
			tbl[i] = [[\#00ff00 ]] .. tbl[i] .. [[\#ffffff ]];
		end
	end

	local str = table.concat(tbl, [[\n\r]]);
	local vid, lines = desktoplbl(str);

	awbwman_popup(vid, lines, function(ind)
		icn.parent.parent[dstkey] = convert and tonumber(tbl[ind]) or tbl[ind];
		if (hook) then
			hook(icn.parent.parent);
		end
	end, {ref = icn.vid});
end

local function respop(icn)
	local lst = {
		"200",
		"240",
		"360",
		"480",
		"720",
		"1080"
	};

	for i=#lst,1,-1 do
		if (VRESH < tonumber(lst[i])) then
			table.remove(lst, i);
		else
			break;
		end
	end

	dotbl(icn, lst, "resolution", true);
end

local function aspectpop(icn)
	local lst = {
		"4:3",
		"5:3",
		"3:2", 
		"16:9"
	};

	dotbl(icn, lst, "aspect", false, icn.parent.parent.update_aspect);
end

local function vcodecpop(icn)
	local lst = {
		"H.264",
		"VP8",
		"FFV1"
	};

	dotbl(icn, lst, "vcodec", false); 
end

local function qualpop(icn, dstkey)
	awbwman_popupslider(1, icn.parent.parent[dstkey], 10, function(val)
		icn.parent.parent[dstkey] = math.ceil(val);
		end, {ref = icn.vid, win = icn.parent.parent});
end

local function acodecpop(icn)
	local lst = {
		"MP3",
		"OGG",
		"PCM",
		"FLAC"
	};

	dotbl(icn, lst, "acodec", false);
end

local function fpspop(icn)
	local lst = {
		"10",
		"24",
		"25",
		"30",
		"50",
		"60"
	};

	dotbl(icn, lst, "fps");
end

local function destpop(icn)
	local lst = {
		"Auto",
		"Specify...",
		"Stream..."
	};

--
-- Generate auto name .. 
--

	dotbl(icn, lst, "destination", false);
end

--
-- Resize window to fit aspect as a helper in positioning etc.
--
local function wnd_aspectchange()
end

local function wnd_dorecord()
end

function spawn_vidrec()
	local wnd = awbwman_spawn(menulbl("Recorder"), {refid = "vidrec"});
	if (wnd == nil) then 
		return;
	end

	wnd.sources = {};

	wnd.name = "Video Recorder";
	wnd.aquality = 7;
	wnd.vquality = 7;
	wnd.resolution = 480;
	wnd.aspect = "4:3";
	wnd.container = "MKV";
	wnd.vcodec = "VP8";
	wnd.acodec = "OGG";
	wnd.destination = "Auto";

	wnd.on_destroy = function()
		print("save vidrec settings");
	end

	wnd.input = function(self, val)
		if (val.active and val.lutsym == "DELETE" and wnd.selected) then
			for i=1,#wnd.sources do
				if (wnd.sources[i] == wnd.selected) then
					wnd.selected = nil;
					delete_image(wnd.sources[i].vid);
					table.remove(wnd.sources, i);
					break;
				end
			end
		end
	end

--
-- Load old settings
--
	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", cfg.ttactiveres, 
		cfg.ttinactvres, cfg.topbar_sz); 
	
	bar:add_icon("r", cfg.bordericns["record"], function()
		bar:destroy();

		wnd.dir.r.right[1]:destroy();
		if (wnd.selected ~= nil) then
			image_transform_cycle(wnd.selected, 0);
			show_image(wnd.selected);
		end

		wnd.input = nil;
		wnd:resize(wnd.w, wnd.h);
-- activate recording, add statuslabel, detach sources etc.
	end);

	bar:add_icon("l", cfg.bordericns["resolution"], respop);
	bar:add_icon("l", cfg.bordericns["aspect"], aspectpop);
	bar:add_icon("l", cfg.bordericns["vcodec"], vcodecpop);
	bar:add_icon("l", cfg.bordericns["vquality"], function(self)
		qualpop(self, "vquality"); end);
	bar:add_icon("l", cfg.bordericns["acodec"], acodecpop);
	bar:add_icon("l", cfg.bordericns["aquality"], function(self)
		qualpop(self, "aquality"); end);
	bar:add_icon("l", cfg.bordericns["fps"], fpspop);
	bar:add_icon("l", cfg.bordericns["save"], destpop);

	bar.click = function()
		wnd:focus(true);
	end
	bar.name = "vidrec_ttbar";
	mouse_addlistener(bar, {"click"});
	table.insert(wnd.handlers, bar);

-- add ttbar, icons for; 
-- resolution (popup, change vidres, preset values)
-- framerate
-- codec
-- vcodec
-- muxer
-- possibly name
-- start recording (purge all icons, close button stops.)
	wnd:update_canvas(fill_surface(32, 32, 60, 60, 60), false); 

	local mh = {
	own = function(self, vid)
		return vid == wnd.canvas.vid or sweepcmp(vid, wnd.sources);
	end,

	over = function(self, vid)
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			tag:hint(true);
		end
	end,

	out = function(self, vid)
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			tag:hint(false);
		end
	end,

	click = function(self, vid)
		wnd:focus();
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			add_rectarget(wnd, tag);
		else
			change_selected(vid);
		end
	end,
	}

	mh.name = "vidrec_mh";
	mouse_addlistener(mh, {"click", "over", "out"});

	table.insert(wnd.handlers, mh);
	table.insert(wnd.handlers, bar);

	wnd:resize(wnd.w, wnd.h);
end
