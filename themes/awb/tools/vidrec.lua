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

local function add_asource(wnd, tag)
	local icnw, icnh = 64, 64;
	local source = {};

	for i=1,#wnd.sources do
		if (wnd.sources[i].kind == "recaudio" and
			wnd.sources[i].data == tag) then
			return;
		end
	end

	if (tag.vid) then
		source.vid = null_surface(icnw, icnh);
		image_sharestorage(tag.vid, source.vid);
		local overlay = load_image("awbicons/audsrc.png");
		link_image(overlay, source.vid);
		image_inherit_order(overlay, true);
		blend_image(overlay, 0.80);
		image_mask_set(overlay, MASK_UNPICKABLE);
	else
		source.vid = load_image("awbicons/audsrc.png");
	end

	show_image(source.vid);

-- green dot to show WHERE the balance will be calculated from
	local anchorp = color_surface(8, 8, 0, 255, 0);
	link_image(anchorp, source.vid);
	show_image(anchorp);
	image_inherit_order(anchorp, true);
	order_image(anchorp, 1);

	source.anchorp = anchorp;
	source.kind = "recaudio";
	source.data  = tag;
	source.audio = tag.audio;

	source.own   = function(self, vid) return vid == source.vid; end
	
--
-- Use the tag.data storage as basis for the icon,
-- then add the speaker- symbol to indicate that it's a connected
-- audio source
--

-- position here represents gain and balance L/R
	local mh = {};
	mh.own = source.own;
	mh.name = "audio_source";

	mh.drag = function(self, vid, mx, my)
		local props = image_surface_properties(source.vid);
		if (props.x + mx + 64 > wnd.canvasw or
			props.x + mx < 0) then mx = 0; end
		if (props.y + my + 64 > wnd.canvash or
			props.y + my < 0) then my = 0; end

		move_image(source.vid, props.x + mx, props.y + my);
		props = image_surface_properties(source.vid);
		local opa = 0.1 + 0.9 * ((wnd.canvash - props.y) / wnd.canvash);
		blend_image(anchorp, opa);

		if (props.x < 0.5 * wnd.canvasw) then
			move_image(source.anchorp, 0, 0);
		else
			move_image(source.anchorp, 64 - 8, 0);
		end
	end

	mh.drop = function()
		local props = image_surface_properties(source.vid);
		if (math.abs(wnd.canvasw * 0.5 - (props.x + 32)) < wnd.canvasw * 0.1) then
			move_image(source.vid, math.floor(wnd.canvasw * 0.5) - 32, props.y);
			move_image(source.anchorp, 32 - 4, 0);
		end
	end

	link_image(source.vid, wnd.canvas.vid);
	image_inherit_order(source.vid, true);
	order_image(source.vid, 2);
	image_clip_on(source.vid);

	source.name = "audrec_name";
	mouse_addlistener(mh, {"drag", "drop"});
	table.insert(wnd.handlers, mh);

	table.insert(wnd.sources, source);
end

local function advsettings(icn)
	local pwnd = icn.parent.parent;
	local settbl = {
	{
		name = "aptsofs",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, pwnd, "aptsofs", nil, nil, 0, 100, 1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, pwnd, "aptsofs", nil, nil, 0, 100, -1);
		end,
		cols = {"APTS Ofset", tostring(pwnd.aptsofs)}
	},
	{
		name = "vptsofs",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, pwnd, "vptsofs", nil, nil, 0, 100, 1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, pwnd, "vptsofs", nil, nil, 0, 100, -1);		
		end,
		cols = {"VPTS Ofset", tostring(pwnd.vptsofs)}
	}
	};

	local newwnd = awbwman_listwnd(
		menulbl("Advanced..."), deffont_sz, linespace, {0.7, 0.3}, 
		settbl, desktoplbl, {double_single = true});

	if (newwnd ~= nil) then
		pwnd:add_cascade(newwnd);
	end
end

local function add_rectarget(wnd, tag)
	local tmpw, tmph = wnd.w * 0.4, wnd.h * 0.4;
	local source = {};

	if (wnd.recording) then
		return;
	end

	source.kind  = "rectarget";
	source.data  = tag.source;
	source.audio = tag.audio;
	source.dmode = nil;
	source.vid   = null_surface(tmpw, tmph);
	source.own   = function(self, vid) return vid == source.vid; end
	source.drag  = function(self, vid, dx, dy)
		wnd:focus();
		source.name  = tag.name;

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
				source.start.opacity = source.start.opacity + dx * 0.01;
				blend_image(source.vid, source.start.opacity);
			else
				source.start.x = source.start.x + dx;
				source.start.y = source.start.y + dy;
				move_image(source.vid, source.start.x, source.start.y);
			end
		elseif (source.dmode == "scale") then
			if (awbwman_cfg().meta.shift) then
				source.start.angle = source.start.angle + dx;
				rotate_image(source.vid, source.start.angle);
			else
				source.start.width  = source.start.width  + dx;
				source.start.height = source.start.height + dy;
				resize_image(source.vid, source.start.width, source.start.height);
			end
		end
	end

-- update selected for wnd so 'del' input key works
	source.click = function(self, vid)
		local tag = awbwman_cursortag();
		wnd:focus();

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
		wnd:focus();

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

-- align to nearest 45 degrees if we're close enough to get
-- less filtering artifacts
	source.drop = function(self, vid)
		local ang = math.floor(image_surface_properties(source.vid).angle);
		if (ang % 45 < 10) then
			ang = ang - (ang % 45);
		end
		rotate_image(source.vid, ang);
	
		source.dmode = nil;
		source.start = nil;
	end

	image_sharestorage(tag.source.canvas.vid, source.vid);

	tag.source:add_handler("on_update", 
		function(self, srcwnd)
			image_sharestorage(srcwnd.canvas.vid, source.vid);
		end);

	table.insert(wnd.sources, source);
	show_image(source.vid);
	image_inherit_order(source.vid, true);
	link_image(source.vid, wnd.canvas.vid);
	image_clip_on(source.vid);

	source.name = "vidrec_source";
	mouse_addlistener(source, {"click", "rclick", "drag", "drop", "dblclick"});
	table.insert(wnd.handlers, source);
	tag:drop();
end

local function dotbl(icn, tbl, dstkey, convert, hook)
	local wnd = icn.parent.parent;

	local list = {};

	for i=1,#tbl do
		if (tbl[i] == tostring(wnd[dstkey])) then
			list[i] = [[\#00ff00]] .. tbl[i] .. [[\#ffffff ]];
		else
			list[i] = tbl[i];
		end
	end

	local str = table.concat(list, [[\n\r]]);
	local vid, lines = desktoplbl(str);

	awbwman_popup(vid, lines, function(ind)
		wnd[dstkey] = (convert == true) and tonumber(tbl[ind]) or tbl[ind];
		if (hook) then
			hook(icn.parent.parent);
		end
	end, {ref = icn.vid});
end

--
-- Filter output resolution so that we don't exceed that of the display
-- This shouldn't really be a problem since the internal FBOs use 2048
-- but ...
--
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
		"H264",
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

local function cformatpop(icn)
	local lst = {
		"MKV",
		"MP4",
		"AVI"
	};

	dotbl(icn, lst, "cformat", false);
end

local cformat_ext = {
	MKV = ".mkv",
	MP4 = ".mp4",
	AVI = ".avi"
};

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

local function audiopop(icn)
	local wnd = icn.parent.parent;

	local lbltbl = {
		"Global Monitor",
		"Capture Sources...",
		"Playback Sources..."
	};

	if (wnd.global_amon) then
		lbltbl[1] = "\\#00ff00" .. lbltbl[1] .. "\\#ffffff";
		table.remove(lbltbl, 3);
		table.remove(lbltbl, 2);
	end

	local trigtbl = {
		function() 
			wnd:drop_audio();
			wnd.global_amon = not wnd.global_amon;
		end,
-- grab a list of possible audio capture sources (microphones etc.)
-- crop the string (as they can get tediously long) 
		function()
			local lst = list_audio_inputs();
			if (lst == nil or #lst == 0) then
				return;
			else
				local indtbl = {};
				for k,v in ipairs(lst) do
					table.insert(indtbl, string.sub(v, 1, 32));
				end
				local vid, lines = desktoplbl(table.concat(indtbl, "\\n\\r"));
				awbwman_popup(vid, lines, 
					function(ind) 
						wnd.global_amon = false;
						wnd:add_audio(lst[ind]);
					end, {ref = icn.vid}
				);
			end
		end,

-- sweep all the video sources added and add those that also has
-- an audio source connected, this will not work for music playback
-- windows but should work fine for the rest.
		function()
			local list = {};
			local refs = {};
			for i=1,#wnd.sources do
				local v = wnd.sources[i];

				if (v.audio ~= nil and v.kind ~= "recaudio") then
					table.insert(refs, v);
					table.insert(list, v.name ~= nil and 
						string.sub(v.name, 1,32) or tostring(v.audio));
				end
			end

			if (#list == 0) then
				return;
			end

			local vid, lines = desktoplbl(table.concat(list, "\\n\\r"));
			awbwman_popup(vid, lines, function(ind)
				wnd:add_audio(refs[ind]);
			end, {ref = icn.vid});
		end
	};
	
	local vid, lines = desktoplbl(table.concat(lbltbl, "\\n\\r"));
	awbwman_popup(vid, lines, trigtbl, {ref = icn.vid});
end

local function destpop(icn)
	local wnd = icn.parent.parent;
	local buttontbl = {
		{
		caption = desktoplbl("OK"), 
		trigger = function(own)
			wnd:set_destination(own.inputfield.msg);
		end
		}, 
		{
			caption = desktoplbl("Cancel"),
			trigger = function(own) end
		}
	};

	local lst = {
		"Specify...",
	};

--
-- This should be complemented with proper cut'n'paste from external
-- problems and with manually typing a key
--
	if (resource("stream.key")) then
		table.insert(lst, "Stream (stream.key)");
	else
		local msg = desktoplbl(MESSAGE["VIDREC_NOKEY"]);
		local props = image_surface_properties(msg);
		show_image(msg);
		link_image(msg, wnd.canvas.vid);
		image_clip_on(msg, CLIP_SHALLOW);
		image_inherit_order(msg, true);
		order_image(msg, 5);
		expire_image(msg, 100);
		blend_image(msg, 1.0, 90);
		blend_image(msg, 0.0, 10);
		move_image(msg, 0, wnd.canvash - props.height);
	end

	local funtbl = {
		function() 
		awbwman_dialog(desktoplbl("Save As (recordings/*.mkv):"), 
			buttontbl, { input = { w = 100, h = 20, limit = 32,
			accept = 1, cancel = 2} }, false);
		end,

		function()
			if (open_rawresource("stream.key")) then
				local line = read_rawresource();
				if (line ~= nil and string.len(line) > 0) then
					wnd:set_destination(line, true);
				end
			close_rawresource();
			end
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

-- disabled selected
	if (wnd.selected) then
		image_shader(wnd.selected.vid, "DEFAULT");
	end
	wnd.selected = nil;

	local fmtstr = "";
	if (wnd.streaming) then
		fmtstr = string.format("libvorbis:vcodec=libx264:container" ..
		"=stream:acodec=libmp3lame:vpreset=%d:apreset=%d:vptsofs=%d:" ..
		"aptsofs=%d:streamdst=%s", wnd.vquality, wnd.aquality, 
		wnd.vptsofs, wnd.aptsofs, string.gsub(wnd.destination, ":", "\t"));
	else
		fmtstr = string.format("vcodec=%s:acodec=%s:vpreset=%d:" ..
		"apreset=%d:fps=%d:container=%s:vptsofs=%d:aptsofs=%d", wnd.vcodec, 
			wnd.acodec, wnd.vquality, wnd.aquality, wnd.fps, wnd.cformat, 
			wnd.vptsofs, wnd.aptsofs);
	end

	local asources = {};

	if (wnd.global_amon == false) then
		for i=1,#wnd.sources do
			if (wnd.sources[i].kind == "recaudio") then
				if (wnd.sources[i].audio == nil) then
					wnd.sources[i].audio = capture_audio(wnd.sources[i].data);		
				end

-- device open may have failed
				if (wnd.sources[i].audio ~= nil) then
					table.insert(asources, wnd.sources[i].audio);
				end
			end
		end
		if (#asources == 0 and wnd.global_amon == false) then
			fmtstr = fmtstr .. ":noaudio";
		end
	else
		asources = WORLDID;
	end
	
	local vidset = {};
	local baseprop = image_surface_properties(wnd.canvas.vid);

-- translate each surface and add to the final recordset,
-- take care of the audio mixing in the next stage
	for i,j in ipairs(wnd.sources) do
		if (j.kind ~= "recaudio") then
			local props = image_surface_properties(j.vid);
			table.insert(vidset, j.vid);
			link_image(j.vid, j.vid);
			local relw = math.ceil(props.width / baseprop.width * width);
			local relh = math.ceil(props.height / baseprop.height * height);
			local relx = math.ceil(props.x / baseprop.width * width);
			local rely = math.ceil(props.y / baseprop.height * height);
			resize_image(j.vid, relw, relh);
			move_image(j.vid, relx, rely);
		end
	end

	local dstvid = fill_surface(width, height, 0, 0, 0, width, height);
	define_recordtarget(dstvid, wnd.destination, fmtstr, vidset, asources,
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, 
		tonumber(wnd.fps) > 30 and -1 or -2, 
			function(src, status)
		end
	);

-- set the channel weights based on icon positions 
-- (if we're not capturing globally) 
	if (type(asources) == "table") then
		for i, v in ipairs(wnd.sources) do
			if (v.kind == "recaudio" and v.audio ~= nil) then
				local props  = image_surface_properties(v.vid);
				local hw     = math.floor(props.width * 0.5);
				local fact   = (wnd.canvash - props.y) / wnd.canvash;
				local srcpos = (props.x + hw) / wnd.canvasw;

				if (srcpos > 0.5) then
					local rf = 1.0 - (((srcpos + hw / wnd.canvasw) - 0.5) / 0.5);
					recordtarget_gain(dstvid, v.audio, fact * rf, fact);	

				elseif (srcpos < 0.5) then
					local rf = 1.0 - ((0.5 - (srcpos - hw / wnd.canvasw)) / 0.5);
					recordtarget_gain(dstvid, v.audio, fact, fact * rf); 

				else
					recordtarget_gain(dstvid, v.audio, fact, fact);
				end
			end
		end
	end

	show_image(dstvid);
	wnd:set_border(2, 255, 0, 0);
	wnd:update_canvas(dstvid);
	wnd.recording = true;
end

local function load_settings(wnd)
	wnd.aquality = 7;
	wnd.vquality = 7;
	wnd.resolution = 480;
	wnd.aspect = "4:3";
	wnd.cformat = "MKV";
	wnd.acodec = "MP3";
	wnd.vcodec = "H264";
	wnd.fps = 30;
	wnd.aptsofs = 1;
	wnd.vptsofs = 12;
end

local function save_settings(wnd)
	
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

		wnd.input = nil;
		wnd:resize(wnd.w, wnd.h);
		record(wnd);	
	end
	
	wnd.sources = {};
	wnd.asources = {};

	wnd.helpmsg = MESSAGE["HELP_VIDREC"];
	load_settings(wnd);

	wnd.global_amon = false;
	wnd.nosound = true;
	wnd.name = "Video Recorder";

	wnd.set_destination = function(wnd, name, stream)
		if (name == nil or string.len(name) == 0) then
			return false;
		end

		if (stream) then 
			wnd.streaming = true;
			wnd.destination = name;
		else
			wnd.destination = string.format("recordings/%s%s", 
				name, cformat_ext[wnd.cformat]);
		end

		if (wnd.ready == nil) then
			bar:add_icon("record", "r", cfg.bordericns["record"], barrecfun);
			wnd.ready = true;
		end
	end

-- generate a decent representation icon
	wnd.add_audio = add_asource;

	wnd.update_aspect = function()
		local aspw = getasp(wnd.aspect);
		wnd:resize(wnd.w, wnd.w / aspw, true);
	end

	wnd.drop_audio = function()
		for i=#wnd.sources,1,-1 do
			if (wnd.sources[i].kind == "recaudio") then
				delete_image(wnd.sources[i].vid);
				table.remove(wnd.sources, i);
			end
		end
	end

	wnd.on_destroy = function()
		save_settings(wnd);
	end

	wnd.input = function(self, val)
		if (wnd.recording == true) then
			return;
		end
	
		if (val.active and val.lutsym == "DELETE" and wnd.selected) then
			for i=#wnd.sources,1,-1 do

				if (wnd.sources[i] == wnd.selected or 
					(wnd.sources[i].kind == "recaudio" and 
						wnd.sources[i].data == wnd.selected)) then
					delete_image(wnd.sources[i].vid);
					table.remove(wnd.sources, i);
				end
			end
	
			wnd.selected = nil;
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
	(bar:add_icon("cformat", "l", cfg.bordericns["cformat"], cformatpop)).vid
	] = MESSAGE["VIDREC_CFORMAT"];

	wnd.hoverlut[
	(bar:add_icon("aqual", "l", cfg.bordericns["aquality"], function(self)
		qualpop(self, "aquality"); end)).vid
	] = MESSAGE["VIDREC_AQUALITY"];

	wnd.hoverlut[
	(bar:add_icon("fps", "l", cfg.bordericns["fps"], fpspop)).vid
	] = MESSAGE["VIDREC_FPS"];

	wnd.hoverlut[
	(bar:add_icon("asource", "l", cfg.bordericns["list"], audiopop)).vid
	] = MESSAGE["VIDREC_ASOURCE"];

	wnd.hoverlut[
	(bar:add_icon("settings", "l", cfg.bordericns["settings"], advsettings)).vid
	] = MESSAGE["VIDREC_ADVANCED"];

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

local descrtbl = {
	name = "vidrec",
	caption = "Recorder",
	icon = "vidrec",
	trigger = spawn_vidrec
};

return descrtbl;
