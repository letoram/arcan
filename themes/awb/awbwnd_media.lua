--
-- AWB Frameserver Media Window
-- For a 3D session, we set up a FBO rendertarget 
-- and connect the output to the canvas along with some buttons to
-- navigate and control basic lighting.
-- 
-- For Vidcap, we add a popup button to select device / index
-- and restart the frameserver each time.
--
-- Adds a "play/pause" and possibly others 
-- based on frameserver capabilities.
--
-- Drag to Desktop behavior is link to recreate / reopen 
-- or add a screenshot
--
-- Note: Should possibly split this into a video and audio player
-- since their featureset / usage pattern is starting to grow apart
--

local shader_seqn = 0;
local last_audshader = nil;
local global_aplayer = nil;

local crtcont = system_load("display/crt.lua")();
local upscaler = system_load("display/upscale.lua")();
local effect = system_load("display/glow.lua")();

local function seekstep(pwin)
	if (pwin.recv) then
		local tmpvol = awbwman_cfg().global_vol * pwin.mediavol; 
		audio_gain(pwin.recv, tmpvol); -- reset chain 
		audio_gain(pwin.recv, 0.0, 5); -- fade out / fade in to dampen "screech"
		tmpvol = tmpvol < 0 and 0 or tmpvol;
		audio_gain(pwin.recv, tmpvol, 20);
	end
end

local function set_shader(modelv)
	local lshdr = load_shader("shaders/dir_light.vShader", 
		"shaders/dir_light.fShader", "media3d_" .. tostring(shader_seqn));

	shader_uniform(lshdr, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(lshdr, "wlightdir", "fff", PERSIST, 1, 0, 0);
	shader_uniform(lshdr, "wambient",  "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(lshdr, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6); 

	image_shader(modelv, lshdr);
	return lshdr;
end

local function playlistwnd(wnd)
	local x, y = mouse_xy();
	local props = image_surface_properties(wnd.anchor);
	local speed = awbwman_cfg().animspeed;

	if (wnd.playlistwnd) then
		if (wnd.playlistwnd.minimized) then
			awbwman_restore(wnd.playlistwnd);
		else
			move_image(wnd.playlistwnd.anchor, x, y, speed);
			wnd.playlistwnd:focus();
		end
		return;
	end

	local nwin = awbwman_listwnd(menulbl("Playlist"), 
		deffont_sz, linespace, {1.0}, wnd.playlist_full, 
		desktoplbl);
	if (nwin == nil) then
		return;
	end

	wnd.playlistwnd = nwin;
	nwin.name = "Playlist";

	nwin:add_handler("on_destroy", function(self)
		wnd.playlistwnd = nil;
	end
	);

	nwin.input = function(self, iotbl)
		if (iotbl.active == false) then
			return;
		end

		if (iotbl.lutsym == "DELETE" and #wnd.playlist > 1 and
			nwin.selline ~= nil) then
			table.remove(wnd.playlist_full, nwin.selline);
			table.remove(wnd.playlist, nwin.selline);
			nwin:force_update();

			if (nwin.selline == wnd.playlist_ofs) then
				wnd.playlist_ofs = wnd.playlist_ofs > 1 
				and wnd.playlist_ofs - 1 or 1;
				wnd.callback(wnd.recv, {kind = "frameserver_terminated"});

			elseif (nwin.selline < wnd.playlist_ofs) then
				wnd.playlist_ofs = wnd.playlist_ofs - 1;
			end

			nwin:update_cursor();
		end
	end

	local sel = color_surface(1, 1, 40, 128, 40);
	nwin.activesel = sel;
	link_image(sel, nwin.anchor);
		
-- need one cursor to indicate currently playing
	link_image(sel, nwin.canvas.vid);
	image_inherit_order(sel, true);
	order_image(sel, 1);
	blend_image(sel, 0.4);
	image_clip_on(sel, CLIP_SHALLOW);
	image_mask_set(sel, MASK_UNPICKABLE);
	
	nwin.update_cursor = function()
-- find y
		local ind = wnd.playlist_ofs - (nwin.ofs - 1);
		if (ind < 1 or ind > nwin.capacity) then
			hide_image(sel);
			return;
		end

		blend_image(sel, 0.4);
		move_image(sel, 0, nwin.line_heights[ind]);
		resize_image(sel, nwin.canvasw, nwin.lineh + nwin.linespace);
	end

	nwin.on_resize = nwin.update_cursor;

	local bar = nwin:add_bar("tt", wnd.dir.tt.activeimg, wnd.dir.tt.activeimg, 
		wnd.dir.t.rsize, wnd.dir.t.bsize);

	wnd:add_cascade(nwin);
end

local function datashare(wnd)
	local res  = awbwman_setup_cursortag(sysicons.floppy);
	res.kind   = "media";
	res.source = wnd;
	res.audio  = wnd.recv;
	res.name   = wnd.name;
	return res;
end

local function submenupop(wnd, list, trig, key, reficn)
	local lbllist = {};

	for i,j in ipairs(list) do
		if (j == wnd.filters[key]) then
			lbllist[i] = "\\#00ff00" .. list[i] .. "\\#ffffff";
		else
			lbllist[i] = list[i];
		end
	end		

	local cbtbl = {};
	local cprops = image_surface_properties(wnd.canvas.vid);

	for i,j in ipairs(list) do
		cbtbl[i] = function(btn)
			if (btn == false and trig[i] ~= nil) then
				wnd.filters[key] = list[i];
				wnd:rebuild_chain(cprops.width, cprops.height);
				trig[i](wnd);
			else
				if (wnd.filters[key] == list[i]) then
					wnd.filters[key] = nil; 
				else
					wnd.filters[key] = list[i];
				end
				wnd:rebuild_chain(cprops.width, cprops.height);
			end
		end;
	end

	local vid, lines = desktoplbl(table.concat(lbllist, "\\n\\r"));
	awbwman_popup(vid, lines, cbtbl, {ref = reficn});
end

local function fltpop(wnd, ctx)
	local newwnd = ctx:confwin(wnd);
end

-- is to add multiline editor and a graphing shader-stage
-- configuration.
--
-- Each group represents a distinct category to configure.
--
function awbwmedia_filterpop(wnd, icn)
	local fltdlg = {
		"Display",
		"Upscaler",
		"Effect"
	};

	local dlgtbl = {
		function() submenupop(wnd, {"CRT"}, {function() fltpop(wnd,
		wnd.filters.displayctx); end}, "display", icn.vid); end,
		function() submenupop(wnd, 
			{"SABR", "xBR", "Linear", "Bilinear", "Trilinear"},
			{function() fltpop(wnd, wnd.filters.upscalerctx); end,
			 function() fltpop(wnd, wnd.filters.upscalerctx); end},
			 "upscaler", icn.vid); end,
		function() submenupop(wnd,
			{"Glow", "Trails", "GlowTrails"}, {function() fltpop(wnd,
				wnd.filters.effectctx); end, function() fltpop(wnd,
				wnd.filters.effectctx); end, function() fltpop(wnd,
				wnd.filters.effectctx); end}, "effect", icn.vid); end
	};

	local vid, lines = desktoplbl(table.concat(fltdlg, "\\n\\r"));
	awbwman_popup(vid, lines, dlgtbl, {ref = icn.vid});
end

local function awbamedia_filterpop(wnd, icn)
	local opts = glob_resource("shaders/audio/*.fShader");
	if (opts == nil or #opts == 0) then
		return;
	end

	local labels = {};
	for i=1,#opts do
		table.insert(labels, string.sub(opts[i], 1, string.len(opts[i]) - 8)); 
	end

	local vid, lines = desktoplbl(table.concat(labels, "\\n\\r"));
	awbwman_popup(vid, lines, function(ind)
		last_audshader = "shaders/audio/" .. labels[ind] .. ".fShader";
		local shid = load_shader(nil, last_audshader, "aud_" .. wnd.wndid); 
		if (shid) then
			image_shader(wnd.canvas.vid, shid);
		end
	end, {ref = icn.vid});
end

local function add_vmedia_top(pwin, active, inactive, fsrv, kind)
	local bar = pwin:add_bar("tt", active, inactive,
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	bar.name = "vmedia_ttbarh";

	local cfg = awbwman_cfg();

	if (kind ~= "frameserver_music") then
	pwin.hoverlut[ 
	(bar:add_icon("clone", "r", cfg.bordericns["clone"],
		function() datashare(pwin); end)).vid] = 
	MESSAGE["HOVER_CLONE"];

	pwin.hoverlut[
	(bar:add_icon("filters", "r", cfg.bordericns["filter"], 
		function(self) awbwmedia_filterpop(pwin, self); end)).vid] = 
	MESSAGE["HOVER_FILTER"];

	else
		pwin:add_handler("on_destroy", function()
			global_aplayer = nil;
		end);

		global_aplayer = pwin;

		pwin.hoverlut[
		(bar:add_icon("filters", "r", cfg.bordericns["filter"],
			function(self) awbamedia_filterpop(pwin, self); end)).vid] = 
		MESSAGE["HOVER_AUDIOFILTER"];
	end

	if (fsrv) then
		pwin.hoverlut[
		(bar:add_icon("pause", "l", cfg.bordericns["pause"],  function(self) 
			if (pwin.paused) then
				pwin.paused = nil;
				resume_movie(pwin.canvas.vid);
				image_sharestorage(cfg.bordericns["pause"], self.vid);
			else
				pwin.paused = true;
				pause_movie(pwin.canvas.vid);
				image_sharestorage(cfg.bordericns["play"], self.vid);
			end
		end)).vid] = MESSAGE["HOVER_PLAYPAUSE"];

		bar:add_icon("volume", "r", cfg.bordericns["volume"], function(self)
			pwin:focus();
			awbwman_popupslider(0.01, pwin.mediavol, 1.0, function(val)
				pwin:set_mvol(val);
			end, {ref = self.vid});
		end);

		local fillcol = null_surface(32, 32);
		image_sharestorage(bar.activeimg, fillcol);
		local caretcol = color_surface(8, 16, cfg.col.dialog_caret.r,
			cfg.col.dialog_caret.g, cfg.col.dialog_caret.b);
	
		local fillicn = bar:add_icon("status", "fill", fillcol,
			function(self, x, y, bx, by)
				local props = image_surface_properties(self.vid);
				local rel = (x - props.x) / image_surface_properties(self.vid).width;

				if (valid_vid(pwin.controlid)) then
					target_seek(pwin.controlid, rel, 0);
				else
					target_seek(pwin.canvas.vid, rel, 0); 
				end
			seekstep(pwin);
		end);

		link_image(caretcol, fillicn.vid);
		show_image(caretcol);
		image_inherit_order(caretcol, true);
		image_mask_set(caretcol, MASK_UNPICKABLE);
		pwin.poscaret = caretcol;

		delete_image(fillcol);
	end

	bar.hover = function(self, vid, x, y, state)
		if (state == false) then
			awbwman_drophover();
		elseif (pwin.hoverlut[vid]) then
			awbwman_hoverhint(pwin.hoverlut[vid]);
		end
	end

	bar.click = function()
		pwin:focus();
	end

	mouse_addlistener(bar, {"click", "hover"});
	table.insert(pwin.handlers, bar);
end

local function slide_lightr(caller, status)
	local pwin = caller.parent.parent;

	awbwman_popupslider(0.01, pwin.amb_r, 1.0, function(val)
		pwin.amb_r = val;
		shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	end, {ref = caller.vid});
	return true;
end
local function slide_lightg(caller, status)
	local pwin = caller.parent.parent;
	pwin:focus();

	awbwman_popupslider(0.01, pwin.amb_g, 1.0, function(val)
		pwin.amb_g = val;
		shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	end, {ref = caller.vid});
	return true;
end

local function slide_lightb(caller, status)
	local pwin = caller.parent.parent;
	pwin:focus();

	awbwman_popupslider(0.01, pwin.amb_b, 1.0, function(val)
		pwin.amb_b = val;
		shader_uniform(pwin.shader, "wambient", "fff", PERSIST,
			pwin.amb_r, pwin.amb_g, pwin.amb_b);
	end, {ref = caller.vid});
	return true;
end

local function zoom_in(self)
	local pwin = self.parent.parent;
	pwin:focus();

	props = image_surface_properties(pwin.model.vid);
	move3d_model(pwin.model.vid, props.x, props.y, props.z + 1.0, 
		awbwman_cfg().animspeed);
end

local function zoom_out(self)
	local pwin = self.parent.parent;
	pwin:focus();

	props = image_surface_properties(pwin.model.vid);
	move3d_model(pwin.model.vid, props.x, props.y, props.z - 1.0,
		awbwman_cfg().animspeed);
end

local function add_3dmedia_top(pwin, active, inactive)
	local bar = pwin:add_bar("tt", active, inactive, 
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	local cfg = awbwman_cfg();

	bar:add_icon("zoom_in", "l", cfg.bordericns["plus"], zoom_in); 
	bar:add_icon("zoom_out", "l", cfg.bordericns["minus"], zoom_out);

	bar:add_icon("light_r", "l", cfg.bordericns["r1"], slide_lightr);
	bar:add_icon("light_g", "l", cfg.bordericns["g1"], slide_lightg);
	bar:add_icon("light_b", "l", cfg.bordericns["b1"], slide_lightb);

	pwin.hoverlut[
	(bar:add_icon("clone", "r", cfg.bordericns["clone"], 
		function() datashare(pwin); end)).vid
	] = MESSAGE["HOVER_CLONE"];

	bar.click = function()
		pwin:focus(true);
	end

	bar.hover = function(self, vid, x, y, state)
		if (state == false) then
			awbwman_drophover();
		elseif (pwin.hoverlut[vid]) then
			awbwman_hoverhint(pwin.hoverlut[vid]);
		end
	end
	
	mouse_addlistener(bar, {"click", "hover"});
	table.insert(pwin.handlers, bar);
end

local function vcap_setup(pwin)
	pwin.name = "Video Capture";
	local bar = pwin.dir.tt;
	local tbl = {};
	for i=0,9 do
		table.insert(tbl, tostring(i));
	end
	local msg = table.concat(tbl, [[\n\r]]);
	local capstr = "capture:device=%d";

	bar:add_icon("add", "l", awbwman_cfg().bordericns["plus"], function(icn)
		local vid, lines = desktoplbl(msg);
		awbwman_popup(vid, lines, function(ind)
			local running = false;
			local vid = load_movie(string.format(capstr, ind), FRAMESERVER_NOLOOP,
			function(source, status)
				if (status.kind == "resized") then
					if (running) then
						pwin:rebuild_chain();
					else
						running = true;
						pwin:update_canvas(source);
					end
				end
			end);
		end, {ref = icn.vid});
	end);

end

local function update_streamstats(win, stat)
	if (win.laststat == nil or win.ctime ~= win.laststat.ctime or
		win.progr_label == nil) then
		if (win.progr_label) then
			delete_image(win.progr_label);
		end

		win.progr_label = desktoplbl(
			string.format("%s / %s", string.gsub(stat.ctime, "\\", "\\\\"),
			string.gsub(stat.endtime, "\\", "\\\\"))
		);
	end

	win.laststat = stat;
	local props = image_surface_properties(win.progr_label);
	local w = image_surface_properties(win.dir.tt.fill.vid).width - 10;

	move_image(win.progr_label, math.floor(0.5 * (w - props.width)), 2);

	image_clip_on(win.progr_label, CLIP_SHALLOW);
	link_image(win.progr_label, win.dir.tt.fill.vid);
	image_inherit_order(win.progr_label, true);
	show_image(win.progr_label, 1);
	image_mask_set(win.progr_label, MASK_UNPICKABLE);

	resize_image(win.poscaret, w * stat.completion, 
		image_surface_properties(win.poscaret).height);
end

local function input_3dwin(self, iotbl)
	if (iotbl.active == false or iotbl.lutsym == nil) then
		return;
	end

	if (iotbl.lutsym) then
		if (iotbl.lutsym == "UP" or 
			iotbl.lutsym == "PAGEUP" or iotbl.lutsym == "w") then
			zoom_in({parent = {parent = self}});	

		elseif (iotbl.lutsym == "DOWN" or 
			iotbl.lutsym ==" PAGEDOWN" or iotbl.lutsym == "s") then
			zoom_out({parent = {parent = self}});
	
		elseif (iotbl.lutsym == "LEFT") then
			rotate3d_model(self.model.vid, 0.0, 0.0, -15, 5, ROTATE_RELATIVE);

		elseif (iotbl.lutsym == "RIGHT") then
			rotate3d_model(self.model.vid, 0.0, 0.0, 15, 5, ROTATE_RELATIVE);
		end
	end	
end

--
-- Due to the possiblity of having to sharestorage etc.
-- the final canvas composition must be a FBO
--
function awbwmedia_filterchain(pwin)
-- first time calling, and this will need 
-- to be managed / deleted manually
	if (pwin.controlid == nil) then
		pwin.controlid  = pwin.canvas.vid;
		hide_image(pwin.controlid);
		pwin.canvas.vid = BADID;
	end

-- trail effects may mess with these so revert back on each build
	image_framesetsize(pwin.controlid, 0, ARCAN_FRAMESET_SPLIT);
	image_framecyclemode(pwin.controlid, 0);
	image_mask_set(pwin.controlid, MASK_POSITION);
	image_mask_clear(pwin.controlid, MASK_MAPPING);
	hide_image(pwin.controlid);
	image_shader(pwin.controlid, "DEFAULT");

-- upscalers etc. can modify these as they affect the next one in the chain
	local store_sz = image_storage_properties(pwin.controlid);
	local in_sz    = image_surface_initial_properties(pwin.controlid);
	local out_sz   = {width = pwin.canvasw, height = pwin.canvash};

	if (pwin.filtertmp ~= nil) then
		for k,v in ipairs(pwin.filtertmp) do
			if (valid_vid(v)) then
				delete_image(v);
			end
		end
	end

	pwin.filtertmp = {};

--
-- Every effect here uses dstres as basis, and if additional
-- FBO chains etc. are set up, they are linked to dstres in
-- someway, and then replaces the referenced vid.
--
-- The last one gets attached to the canvas.
--
	local dstres = null_surface(store_sz.width, store_sz.height);
	local dstres_base = dstres;
	image_tracetag(dstres, "filterchain_core");
	image_sharestorage(pwin.controlid, dstres);

	table.insert(pwin.filtertmp, dstres);

-- 1. upscaler, this may modify what the other filters / effect.
-- see as the internal/storage/source resolution will be scaled.
	image_texfilter(dstres, FILTER_NONE, FILTER_NONE);

	if (pwin.filters.upscaler and pwin.filters.effect ~= "Trails" and
		pwin.filters.effect ~= "GlowTrails") then
		local f = pwin.filters.upscaler;

		if (f == "Linear") then
			image_texfilter(dstres, FILTER_LINEAR);

		elseif (f == "Bilinear") then
			image_texfilter(dstres, FILTER_BILINEAR);

		elseif (f == "Trilinear") then
			image_texfilter(dstres, FILTER_TRILINEAR);

-- since shaders are "per target" 
-- we need to load / rebuild and tagging with the wndid
		elseif (f == "SABR") then
			dstres, ctx = upscaler.sabr.setup(pwin.filters.upscalerctx, 
				dstres, "SABR_"..tostring(pwin.wndid),
				store_sz, in_sz, out_sz, pwin.filters.upscaleopt);
			pwin.filters.upscalerctx = ctx;
			table.insert(pwin.filtertmp, dstres);
	
		elseif (f == "xBR") then
 			dstres, ctx = upscaler.xbr.setup(pwin.filters.upscalerctx,
				dstres, "XBR_"..tostring(pwin.wndid),
				store_sz, in_sz, out_sz, pwin.filters.upscaleopt);
			pwin.filters.upscalerctx = ctx;
			table.insert(pwin.filtertmp, dstres);
		end
	end

	if (dstres == nil) then
		dstres = dstres_base;
	end

-- 2. effect (glow, ...)
	if (pwin.filters.effect) then
		local f = pwin.filters.effect;
		if (f == "Glow") then
			dstres, ctx = effect.glow.setup(pwin.filters.effectctx,
				dstres, "GLOW_" .. tostring(pwin.wndid), 
				store_sz, in_sz, out_sz, pwin.filters.effectopt);
			pwin.filters.effectctx = ctx;
			if (ctx == nil) then pwin.filters.effect = nil; end

		elseif (f == "Trails") then
			dstres, ctx = effect.trails.setup(pwin.filters.effectctx,
				pwin.controlid, -- need access to the original source				
				dstres, "TRAILS_" .. tostring(pwin.wndid), 
				store_sz, in_sz, out_sz, pwin.filters.effectopt);
			pwin.filters.effectctx = ctx;
			if (ctx == nil) then pwin.filters.effect = nil; end

		elseif (f == "GlowTrails") then
			print("set trails");
			dstres, ctx = effect.glowtrails.setup(pwin.filters.effectctx,
				pwin.controlid, "GLOWTRAILS_" .. tostring(pwin.wndid), 
				store_sz, in_sz, out_sz, pwin.filters.effectopt);
			pwin.filters.effectctx = ctx;
			if (ctx == nil) then pwin.filters.effect = nil; end
		end

		table.insert(pwin.filtertmp, dstres);
	end

	if (dstres == nil) then
		dstres = dstres_base;
	end

-- 3. display
	if (pwin.filters.display) then
		local f = pwin.filters.display;

		if (f == "CRT") then
			dstres, ctx = crtcont.setup(pwin.filters.displayctx, 
				dstres, "CRT_"..tostring(pwin.wndid),store_sz,
				in_sz, out_sz, pwin.filters_displayopt);
	
			pwin.filters.displayctx = ctx;
			table.insert(pwin.filtertmp, dstres);
		end
	end

	pwin:update_canvas(dstres, pwin.mirrored);
end

local function awnd_setup(pwin, bar)
	pwin.callback = function(source, status)
		if (pwin.alive == false) then
			return;
			end

-- update_canvas will delete this one
		if (status.kind == "frameserver_terminated") then
			pwin.playlist_ofs = pwin.playlist_ofs + 1;
			pwin.playlist_ofs = pwin.playlist_ofs > #pwin.playlist and 1 or
				pwin.playlist_ofs;

			if (pwin.playlistwnd) then
				pwin.playlistwnd:update_cursor();
			end

			pwin.recv = nil;
			pwin:update_canvas( load_movie(pwin.playlist_full[pwin.playlist_ofs].name, 
				FRAMESERVER_NOLOOP, pwin.callback, 1, "novideo=true") );
		end

		if (status.kind == "resized") then
			pwin.name = pwin.playlist[pwin.playlist_ofs];
			pwin:update_canvas(source);
			pwin.recv = status.source_audio;
			pwin:set_mvol(pwin.mediavol);

			if (pwin.shid == nil) then
				pwin.shid = load_shader(nil,
					last_audshader, "aud_" .. pwin.wndid);
			end

			image_shader(pwin.canvas.vid, pwin.shid);
			image_texfilter(pwin.canvas.vid, FILTER_NONE, FILTER_NONE);

		elseif (status.kind == "streamstatus") then
			update_streamstats(pwin, status);
		end
	end

	pwin.on_fullscreen = function(self, dstvid)
		if (pwin.shid) then
			image_shader(dstvid, pwin.shid);
		end
	end

	local canvash = {
		name  = "musicplayer" .. "_canvash",
		own   = function(self, vid) 
							return vid == pwin.canvas.vid; 
						end,
		click = function() pwin:focus(); end
	};

--
-- keep them separate so we can reuse for listwindow
-- 
	pwin.playlist = {};
	pwin.playlist_full = {};

	pwin.playtrig = function(self)
		for i,v in ipairs(pwin.playlist_full) do
			if (self.name == v.name) then
				pwin.playlist_ofs = i - 1;
				pwin.callback(pwin.recv, {kind = "frameserver_terminated"});
			end
		end
	end

	pwin.add_playitem = function(self, caption, item)
		table.insert(pwin.playlist, caption);
		local ind = #pwin.playlist;
-- this will be used for the playlist window as well, hence the formatting.
		table.insert(pwin.playlist_full, {
			name = item,
			cols = {caption},
			trigger = pwin.playtrig
		});

-- if not playing, launch a new session
		if (pwin.recv == nil) then
			pwin.playlist_ofs = 1;
			local vid = 
				load_movie(item, FRAMESERVER_NOLOOP, pwin.callback, 1, "novideo=true");
			pwin:update_canvas(vid);
		end

		if (pwin.playlistwnd) then
			pwin.playlistwnd:force_update();
		end
	end

	local bar = pwin.dir.tt;
	local cfg = awbwman_cfg();

	pwin.hoverlut[
	(bar:add_icon("playlist", "l", cfg.bordericns["list"], 
		function() playlistwnd(pwin); end)).vid
	] = MESSAGE["HOVER_PLAYLIST"];

	mouse_addlistener(canvash, {"click"});
	table.insert(pwin.handlers, canvash);

	pwin.canvas_iprops = function(self)
		local ar = VRESW / VRESH;
		local w  = math.floor(0.3 * VRESW);
		local h  = math.floor( w / ar );

		return {
			width = w,
			height = h
		};
	end

end

--
-- Usually there's little point in having many music players running
-- (same can not be said for video however) so we track the one that
-- is running and add to the playlist if one already exists
--
function awbwnd_globalmedia(newmedia)
	if (global_aplayer == nil) then
		return;
	end

	return global_aplayer;
end

local seektbl = {
	LEFT = -10, 
	RIGHT = 10, 
	UP = 30,
	DOWN = -30,
	PGUP = 600,
	PGDN = -600,
	SHIFTLEFT = -100,
	SHIFTRIGHT = 100,
	SHIFTUP = 300,
	SHIFTDOWN = -300
};

function awbwnd_media(pwin, kind, source, active, inactive)
	local callback;
	pwin.filters = {};
	pwin.hoverlut = {};

	pwin.rebuild_chain = awbwmedia_filterchain;

	pwin:add_handler("on_destroy", function(self)
		if (pwin.filtertmp ~= nil) then
			for i, v in ipairs(pwin.filtertmp) do
				if (valid_vid(v)) then delete_image(v); end
			end
		end

		if (valid_vid(pwin.controlid)) then
			delete_image(pwin.controlid);
			pwin.controlid = nil;
		end
	end);

	if (kind == "frameserver" or 
		kind == "capture" or kind == "static") then
	
-- resized for the costly functions
		pwin.on_resized = 
		function(wnd, winw, winh, cnvw, cnvh)
			awbwmedia_filterchain(pwin, cnvw, cnvh);
		end;

		local canvash = {
			name  = kind .. "_canvash",
			own   = function(self, vid) 
								return vid == pwin.canvas.vid; 
							end,
			click = function() pwin:focus(); end
		}

		mouse_addlistener(canvash, {"click"});
		table.insert(pwin.handlers, canvash);
	end

	if (kind == "frameserver" or kind == "frameserver_music") then
		add_vmedia_top(pwin, active, inactive, true, kind);
		pwin.mediavol = 1.0;
	
		pwin.on_resize = 
		function(wnd, winw, winh, cnvw, cnvh)
			if (wnd.laststat ~= nil) then
				update_streamstats(wnd, wnd.laststat);
			end
		end
	
-- seek controls
		pwin.input = function(self, iotbl)
			if (iotbl.active == false or iotbl.lutsym == nil) then
				return;
			end
			
			local id = pwin.controlid ~= nil 
				and pwin.controlid or pwin.canvas.vid;

			local sym = iotbl.lutsym;
			if (awbwman_cfg().meta.shift) then
				sym = "SHIFT" .. sym;
			end
			
			local step = seektbl[sym];
			if (step ~= nil) then
				target_seek(id, step, 1);
				seekstep(pwin);
			end
		end

		pwin.set_mvol = function(self, val)
			pwin.mediavol = val;
			local tmpvol = awbwman_cfg().global_vol * pwin.mediavol;
			tmpvol = tmpvol < 0 and 0 or tmpvol;
			if (pwin.recv ~= nil) then
				audio_gain(pwin.recv, tmpvol);	
			end
		end

		if (kind == "frameserver") then
			if (pwin.alive == false) then
				return;
			end

			callback = function(source, status)
				if (pwin.alive == false) then
					return;
				end

				if (pwin.controlid == nil) then
					pwin:update_canvas(source);
				end

				if (status.kind == "resized") then
					local vid, aud = play_movie(source);
					pwin.recv = aud;
					pwin:set_mvol(pwin.mediavol);
					pwin:resize(status.width, status.height, true);

				elseif (status.kind == "streamstatus") then
					update_streamstats(pwin, status);
				end
			end
		else
-- music-player specific setup
			awnd_setup(pwin);
		end
	elseif (kind == "capture") then
		add_vmedia_top(pwin, active, inactive);
		vcap_setup(pwin);

	elseif (kind == "static") then
		add_vmedia_top(pwin, active, inactive);
	
		callback = function(source, status)
			if (pwin.alive == false) then
				return;
			end

			if (status.kind == "loaded") then
				pwin:update_canvas(source);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "3d" and source) then
		local dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
		image_tracetag(dstvid, "3dmedia_rendertarget");
		pwin.shader = set_shader(source.vid);
		show_image(source.vid);

		define_rendertarget(dstvid, {source.vid}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, RENDERTARGET_FULL);
	
		local camera = null_surface(1, 1);
		scale3d_model(camera, 1.0, -1.0, 1.0);
		rendertarget_attach(dstvid, camera, RENDERTARGET_DETACH);
		camtag_model(camera, 0.01, 100.0, 45.0, 1.33); 
		image_tracetag(camera, "3dcamera");

		pwin:update_canvas(dstvid);
		pwin.name = "3d model";
		pwin.model = source;
		pwin.input = input_3dwin;
		pwin.amb_r = 0.3;
		pwin.amb_g = 0.3;
		pwin.amb_b = 0.3;

		local mh = {
			name = "3dwindow_canvas",
			own = function(self, vid) return vid == dstvid; end,
	
			drag = function(self, vid, dx, dy)
				pwin:focus();
				rotate3d_model(source.vid, 0.0, dy, dx, 0, ROTATE_RELATIVE);
			end,

			over = function(self, vid)
				local tag = awbwman_cursortag();
				if (tag and tag.kind == "media" and vid == pwin.canvas.vid) then
					tag:hint(true);
				end
			end,

			out = function()
				local tag = awbwman_cursortag();
				if (tag and tag.kind == "media") then
					tag:hint(false);
				end
			end,

			click = function()
				local tag = awbwman_cursortag();
				pwin:focus();

				if (tag and tag.kind == "media") then
					local newdisp = null_surface(32, 32);
					image_tracetag(newdisp, "media_displaytag");
					image_sharestorage(tag.source.canvas.vid, newdisp);
					pwin.model:update_display(newdisp, true);
					tag:drop();
				end
			end
		};
	
		mouse_addlistener(mh, {"drag", "click", "over", "out"});
		add_3dmedia_top(pwin, active, inactive);
		table.insert(pwin.handlers, mh);
	else
		warning("awbwnd_media() media type: " .. kind .. "unknown\n");
	end

	return callback; 
end
