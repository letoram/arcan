--
-- Basic audio-player with a playlist
-- and some audio visualization
--

local global_aplayer = nil;
local shader_seqn = 0;
local last_audshader = nil;

--
-- Usually there's little point in having many music players running
-- (same can not be said for video however) so we track the one that
-- is running and add to the playlist if one already exists
--
function awbwnd_globalmedia(newmedia)
	return global_aplayer;
end

local function filterpop(wnd, icn)
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

	local bar = nwin:add_bar("tt", wnd.dir.tt.activeimg, wnd.dir.tt.activeimg,
		wnd.dir.t.rsize, wnd.dir.t.bsize);
	
	local cfg = awbwman_cfg();
	bar.hoverlut[
		(bar:add_icon("sortaz", "l", cfg.bordericns["sortaz"],
			function()
				table.sort(wnd.playlist, function(a, b) 
					return string.lower(a) < string.lower(b); 
				end);
				table.sort(wnd.playlist_full, function(a, b)
					return string.lower(a.name) < string.lower(b.name);
				end);
				nwin:force_update();
			end
		)).vid] = MESSAGE["HOVER_SORTAZ"];

	bar.hoverlut[
	(bar:add_icon("sortza", "l", cfg.bordericns["sortza"],
		function()
			table.sort(wnd.playlist, function(a, b) 
				return string.lower(a) > string.lower(b); 
			end);	
			table.sort(wnd.playlist_full, function(a, b)
				return string.lower(a.name) > string.lower(b.name);
			end);
			nwin:force_update();
		end
	)).vid] = MESSAGE["HOVER_SORTZA"];

	bar.hoverlut[
	(bar:add_icon("shuffle", "l", cfg.bordericns["shuffle"], 
		function()
			local newlist_wnd = {};
			local newlist_full = {};

			while #wnd.playlist_full > 0 do
				local ind = math.random(1, #wnd.playlist_full);
				local entry = table.remove(wnd.playlist_full, ind);
				table.insert(newlist_full, entry);
				entry = table.remove(wnd.playlist, ind);
				table.insert(newlist_wnd, entry); 
			end

			wnd.playlist_full = newlist_full;
			nwin.tbl = newlist_full; 
			wnd.playlist = newlist_wnd;
			wnd.playlist_ofs = 1;
			nwin:force_update();
		end)).vid] = MESSAGE["HOVER_SHUFFLE"];

	nwin:add_handler("on_destroy", function(self)
		wnd.playlistwnd = nil;
		warning("playlist destroyed");
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
	nwin:force_update();
	wnd:add_cascade(nwin);
end

--
-- Mapped to frameserver events,
-- includes chaining/spawning new frameservers when
-- the previous one died.
--
local function awnd_callback(pwin, source, status)
	if (pwin.alive == false) then
		return;
	end

	if (pwin.controlid == nil) then
		pwin.controlid = source;
	end

-- update_canvas will delete this one
	if (status.kind == "frameserver_terminated") then
		pwin.playlist_ofs = pwin.playlist_ofs + 1;
		pwin.playlist_ofs = pwin.playlist_ofs > #pwin.playlist and 1 or
			pwin.playlist_ofs;

		if (pwin.playlistwnd and pwin.playlistwnd.update_cursor) then
			pwin.playlistwnd:update_cursor();
		end

		pwin.recv = nil;
		pwin.controlid = load_movie(pwin.playlist_full[pwin.playlist_ofs].name, 
			FRAMESERVER_NOLOOP, pwin.callback, 1, "novideo=true");
		pwin:update_canvas(pwin.controlid);
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
		awbmedia_update_streamstats(pwin, status);
	end
end

local function awnd_setup(pwin, bar)
	pwin.callback = function(source, status)
		awnd_callback(pwin, source, status);
	end

	pwin.on_fullscreen = function(self, dstvid, active)
		if (pwin.shid and active) then
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

	mouse_addlistener(canvash, {"click"});
	table.insert(pwin.handlers, canvash);

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

	local cfg = awbwman_cfg();

	bar.hoverlut[
	(bar:add_icon("playlist", "r", cfg.bordericns["list"], 
		function() playlistwnd(pwin); end)).vid
	] = MESSAGE["HOVER_PLAYLIST"];

	pwin.canvas_iprops = function(self)
		local ar = VRESW / VRESH;
		local w  = math.floor(0.3 * VRESW);
		local h  = math.floor( w / ar );

		return {
			width = w,
			height = h
		};
	end

	pwin:add_handler("on_destroy", function() global_aplayer = nil; end);
	global_aplayer = pwin;

	local cfg = awbwman_cfg();

	bar.hoverlut[
	(bar:add_icon("filters", "r", cfg.bordericns["filter"],
		function(self) filterpop(pwin, self); end)).vid] = 
	MESSAGE["HOVER_AUDIOFILTER"];

-- shared with video windows etc.
	awbmedia_add_fsrvctrl(pwin, bar);

	pwin.helpmsg = MESSAGE["HELP_AMEDIA"];
end

function awbwnd_aplayer(pwin, source, options)
	local bar = pwin:add_bar("tt", pwin.ttbar_bg, pwin.ttbar_bg,
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	bar.name = "amedia_ttbarh";

	awnd_setup(pwin, bar);
	return pwin;
end
