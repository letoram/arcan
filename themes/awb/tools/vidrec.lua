--
-- Recorder Built-in Tool
-- Some regular configuration popups, e.g. resolution, framerate, 
-- and a drag-n-drop composition canvas
--

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

local function dotbl(icn, tbl, dstkey, convert, hook)
	for i=1,#tbl do
		if (tbl[i] == tostring(icn.parent.parent[dstkey])) then
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

	dotbl(icn, lst, "fps", true);
end

local function destpop(icn)
	local buttontbl = {
		{
		caption = desktoplbl("OK"), 
		trigger = function(own)
			icn.parent.parent:set_destination(own.inputfield.msg);
		end
		}, 
		{
			caption = desktoplbl("Cancel"),
			trigger = function(own) end
		}
	};

	local lst = {
		"Specify...",
		"Stream..."
	};

	local funtbl = {
		function() 
		awbwman_dialog(desktoplbl("Save As (recordings/*.mkv):"), 
			buttontbl, { input = { w = 100, h = 20, limit = 32,
			accept = 1, cancel = 2} }, false);
		end,
		function()
		end
	};

	local vid, lines = desktoplbl(table.concat(lst, "\\n\\r"));
	awbwman_popup(vid, lines, funtbl, {ref = icn.vid});
end

local function getasp(str)
	local res = 1;

	if (str == "4:3") then
		res = 4 / 3;
	elseif (str == "5:3") then
		res = 5 / 3;
	elseif (str == "3:2") then
		res = 3 / 2;
	elseif (str == "16:9") then
		res = 16 / 9;
	end

	return res;
end

local function record(wnd)
-- detach all objects, use video recording surface as canvas
	local aspf = getasp(wnd.aspect);
	local height = wnd.resolution;
	local width  = height * aspf;
	width = width - math.fmod(width, 2);

	local streamstr = "libvorbis:vcodec=libx264:container" ..
		"=stream:acodec=libmp3lame:streamdst=" -- gsub(: to tab)
	
	local fmtstr = string.format("vcodec=%s:acodec=%s:vpreset=%d:" ..
		"apreset=%d:fps=%d:container=%s%s",
		wnd.vcodec, wnd.acodec, wnd.vquality, wnd.aquality, 
			wnd.fps, wnd.container, wnd.nosound ~= nil and ":noaudio" or "");

	local vidset = {};
	local baseprop = image_surface_properties(wnd.canvas.vid);

-- translate each surface and add to the final recordset
-- speaker icons will be added to vidset with corresponding mixing settings
	for i,j in ipairs(wnd.sources) do
		if (j.icon == nil) then
			local props = image_surface_properties(j.vid);
			table.insert(vidset, j.vid);
			link_image(j.vid, j.vid);
			local relw = math.ceil(props.width / baseprop.width * width);
			local relh = math.ceil(props.height / baseprop.height * height);
			local relx = math.ceil(props.x / baseprop.width * width);
			local rely = math.ceil(props.y / baseprop.height * height);
			resize_image(j.vid, relw, relh);
			move_image(j.vid, relx, rely);
		else
-- find corresponding AID, calculate mixing properties
		end
	end

	local dstvid = fill_surface(width, height, 0, 0, 0, width, height);
	define_recordtarget(dstvid, wnd.destination, fmtstr, vidset, wnd.nosound ~= nil and {} or
		WORLDID, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, tonumber(wnd.fps) > 30 and -1 or -2, 
		function(src, status)
		end);

	show_image(dstvid);
	wnd:set_border(2, 255, 0, 0);
	wnd:update_canvas(dstvid);
	wnd.recording = true;
end

function spawn_vidrec()
	local wnd = awbwman_spawn(menulbl("Recorder"), {refid = "vidrec"});
	wnd.hoverlut = {};

	if (wnd == nil) then 
		return;
	end

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", cfg.ttactiveres, 
		cfg.ttinactvres, cfg.topbar_sz); 
	
	local barrecfun = function()
		bar:destroy();

		wnd.dir.r.right[1]:destroy();
--		if (wnd.selected ~= nil) then
--			image_transform_cycle(wnd.selected, 0);
--			show_image(wnd.selected);
--		end

		wnd.input = nil;
		wnd:resize(wnd.w, wnd.h);
		record(wnd);	
	end
	
	wnd.sources = {};
	wnd.asources = {};

	wnd.nosound = true;
	wnd.name = "Video Recorder";
	wnd.aquality = 7;
	wnd.vquality = 7;
	wnd.resolution = 480;
	wnd.aspect = "4:3";
	wnd.container = "MKV";
	wnd.vcodec = "MP3";
	wnd.acodec = "H264";
	wnd.fps = 30;

	wnd.set_destination = function(wnd, name, stream)
		if (name == nil or string.len(name) == 0) then
			return false;
		end

		if (stream) then 
			wnd.streaming = true;
			wnd.destination = name;
		else
			wnd.destination = string.format("recordings/%s.mkv", name);
		end

		if (wnd.ready == nil) then
			bar:add_icon("record", "r", cfg.bordericns["record"], barrecfun);
			wnd.ready = true;
		end
	end

	wnd.update_aspect = function()
		local aspw = getasp(wnd.aspect);
		wnd:resize(wnd.w, wnd.h / aspw, true);
	end

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

	wnd.hoverlut[
	(bar:add_icon("res", "l", cfg.bordericns["resolution"], respop)).vid
	] = MESSAGE["VIDREC_RES"];  

	wnd.hoverlut[
	(bar:add_icon("aspect", "l", cfg.bordericns["aspect"], aspectpop)).vid
	] = MESSAGE["VIDREC_ASPECT"];
	
	wnd.hoverlut[
	(bar:add_icon("vcodec", "l", cfg.bordericns["vcodec"], vcodecpop)).vid
	] = MESSAGE["VIDREC_CODEC"];

	wnd.hoverlut[
	(bar:add_icon("vqual", "l", cfg.bordericns["vquality"], function(self)
		qualpop(self, "vquality"); end)).vid
	] = MESSAGE["VIDREC_QUALITY"];

	wnd.hoverlut[
	(bar:add_icon("acodec", "l", cfg.bordericns["acodec"], acodecpop)).vid
	] = MESSAGE["VIDREC_ACODEC"];

	wnd.hoverlut[
	(bar:add_icon("aqual", "l", cfg.bordericns["aquality"], function(self)
		qualpop(self, "aquality"); end)).vid
	] = MESSAGE["VIDREC_AQUALITY"];

	wnd.hoverlut[
	(bar:add_icon("fps", "l", cfg.bordericns["fps"], fpspop)).vid
	] = MESSAGE["VIDREC_FPS"];

	wnd.hoverlut[
	(bar:add_icon("save", "l", cfg.bordericns["save"], destpop)).vid
	] = MESSAGE["VIDREC_SAVE"];

	bar.hover = function(self, vid, x, y, state)
		if (state == false) then
			awbwman_drophover();
		elseif (wnd.hoverlut[vid]) then
			awbwman_hoverhint(wnd.hoverlut[vid]);
		end
	end
	
	bar.click = function()
		wnd:focus(true);
	end
	bar.name = "vidrec_ttbar";
	mouse_addlistener(bar, {"click", "hover"});
	table.insert(wnd.handlers, bar);

-- add ttbar, icons for; 
-- resolution (popup, change vidres, preset values)
-- framerate
-- codec
-- vcodec
-- muxer
-- possibly name
-- start recording (purge all icons, close button stops.)
	wnd:update_canvas(fill_surface(32, 32, 60, 60, 60) ); 

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
		end
	end,
	}

	mh.name = "vidrec_mh";
	mouse_addlistener(mh, {"click", "over", "out"});

	table.insert(wnd.handlers, mh);
	table.insert(wnd.handlers, bar);

	wnd:resize(wnd.w, wnd.h);
end
