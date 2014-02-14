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

local crtcont = system_load("display/crt.lua")();
local upscaler = system_load("display/upscale.lua")();
local effect = system_load("display/glow.lua")();

local animtexco_vshader = [[
uniform mat4 modelview;
uniform mat4 projection;
uniform int timestamp;

uniform vec2 speedfact;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
        texco.s = texcoord.s + fract(float(timestamp) / speedfact.x);
        texco.t = texcoord.t + fract(float(timestamp) / speedfact.y);

        gl_Position = (projection * modelview) * vertex;
}
]];

function awbwnd_breakdisplay(wnd)
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
	wnd:update_canvas(random_surface(128, 128));
  switch_default_texmode( TEX_CLAMP, TEX_CLAMP );
	wnd.broken = true;

	if (wnd.dir.tt) then
		wnd.dir.tt:destroy();
	end

	wnd.rebuild_chain = function() end
	wnd.shid = build_shader(animtexco_vshader, nil, "vid_" .. wnd.wndid);
	if (wnd.shid ~= nil) then
		shader_uniform(wnd.shid, "speedfact", "ff", PERSIST, 12.0, 12.0);
		image_shader(wnd.canvas.vid, wnd.shid);
	end

	wnd:resize(wnd.canvasw, wnd.canvash, true);
end

function awbmedia_seekstep(pwin)
	if (pwin.recv) then
		local tmpvol = awbwman_cfg().global_vol * pwin.mediavol; 
		audio_gain(pwin.recv, tmpvol); -- reset chain 
		audio_gain(pwin.recv, 0.0, 5); -- fade out / fade in to dampen "screech"
		tmpvol = tmpvol < 0 and 0 or tmpvol;
		audio_gain(pwin.recv, tmpvol, 20);
	end
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

function awbmedia_update_streamstats(win, stat)
	if (win.broken) then
		return;
	end

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

function awbmedia_add_fsrvctrl(pwin, bar)
	local cfg = awbwman_cfg();

	bar.hoverlut[
		(bar:add_icon("pause", "l", cfg.bordericns["pause"], 
	function(self) 
		if (pwin.paused) then
			pwin.paused = nil;
			resume_movie(pwin.controlid);
			image_sharestorage(cfg.bordericns["pause"], self.vid);
		else
			pwin.paused = true;
			pause_movie(pwin.controlid);
			image_sharestorage(cfg.bordericns["play"], self.vid);
		end
	end)).vid] = MESSAGE["HOVER_PLAYPAUSE"];

	bar:add_icon("volume", "r", cfg.bordericns["volume"], 
	function(self)
		pwin:focus();
		awbwman_popupslider(0.01, pwin.mediavol, 1.0, 
			function(val)
				pwin:set_mvol(val);
			end, {ref = self.vid}
		);
	end);

-- seek UI bar
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
		awbmedia_seekstep(pwin);
	end);

	pwin.mediavol = 1.0;
	
	pwin.on_resize = 
	function(wnd, winw, winh, cnvw, cnvh)
		if (wnd.laststat ~= nil) then
			awbmedia_update_streamstats(wnd, wnd.laststat);
		end
	end
	
-- seek controls
	pwin.input = 
	function(self, iotbl)
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
			awbmedia_seekstep(pwin);
		end
	end

	pwin.set_mvol = 
	function(self, val)
		pwin.mediavol = val;
		local tmpvol = awbwman_cfg().global_vol * pwin.mediavol;
		tmpvol = tmpvol < 0 and 0 or tmpvol;
		if (pwin.recv ~= nil) then
			audio_gain(pwin.recv, tmpvol);	
		end
	end

	link_image(caretcol, fillicn.vid);
	show_image(caretcol);
	image_inherit_order(caretcol, true);
	image_mask_set(caretcol, MASK_UNPICKABLE);
	pwin.poscaret = caretcol;

	delete_image(fillcol);
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
						pwin:resize(status.width, status.height, true);
					end

				elseif (status.kind == "frameserver_terminated") then
					pwin:break_display();
				end
			end);
		end, {ref = icn.vid});
	end);

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

	image_shader(dstres, pwin.def_shader ~= nil and 
		pwin.def_shader or "DEFAULT");

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
	local cfg = awbwman_cfg();
	if (cfg.fullscreen and cfg.fullscreen.vid) then
		image_sharestorage(dstres, cfg.fullscreen.vid);
	end

	pwin.on_fullscreen = function(self, vid, state)
		if (pwin.filters.effect == "Glow" or 
			pwin.filters.effect == "GlowTrails") then
			image_mask_clear(pwin.controlid, MASK_OPACITY);
			show_image(pwin.controlid);
		end
	end

-- propagate to other recipients 
	for k,v in ipairs(pwin.on_update) do
		v(v, pwin, dstres);	
	end
end

local function vmedia_callback(pwin, source, status)
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
		local tbl = image_surface_properties(pwin.anchor);

		if (tbl.x + status.width > VRESW) then
			pwin:resize(VRESW - tbl.x, (VRESW - tbl.x) * 
				(status.height / status.width), true);
	
		elseif (tbl.y + status.height > VRESH) then
			pwin:resize(VRESW - tbl.x, (VRESW - tbl.x) * 
					(status.height / status.width), true);
	
		else
			pwin:resize(status.width, status.height, true);
		end

	elseif (status.kind == "frameserver_terminated") then
		pwin:break_display();

	elseif (status.kind == "streamstatus") then
		awbmedia_update_streamstats(pwin, status);
	end
end

function awbwnd_media(pwin, source, options) 
	local callback;
	local kind = pwin.kind; 
	
	pwin.filters = {};
	pwin.hoverlut = {};

	pwin.rebuild_chain = awbwmedia_filterchain;
	pwin.break_display = awbwnd_breakdisplay;

	pwin:add_handler("on_destroy", 
		function(self)
			if (pwin.filtertmp ~= nil) then
				for i, v in ipairs(pwin.filtertmp) do
					if (valid_vid(v)) then delete_image(v); end
				end
			end

			if (valid_vid(pwin.controlid)) then
				delete_image(pwin.controlid);
				pwin.controlid = nil;
			end
		end
	);

-- resized for the costly functions
	pwin.on_resized = 
	function(wnd, winw, winh, cnvw, cnvh)
		pwin:rebuild_chain();
	end;

	local canvash = {
		name  = kind .. "_canvash",
		own   = function(self, vid) 
							return vid == pwin.canvas.vid; 
						end,
		click = function() 
							pwin:focus(); 
						end
	}

	mouse_addlistener(canvash, {"click"});
	table.insert(pwin.handlers, canvash);

-- add topbar for vmedia
	local bar = pwin:add_bar("tt", pwin.ttbar_bg, pwin.ttbar_bg,
		pwin.dir.t.rsize, pwin.dir.t.bsize);
	bar.name = "vmedia_ttbarh";

	local cfg = awbwman_cfg();

	bar.hoverlut[ 
	(bar:add_icon("clone", "r", cfg.bordericns["clone"],
		function() datashare(pwin); end)).vid] = 
	MESSAGE["HOVER_CLONE"];

	bar.hoverlut[
	(bar:add_icon("filters", "r", cfg.bordericns["filter"], 
		function(self) awbwmedia_filterpop(pwin, self); end)).vid] = 
	MESSAGE["HOVER_FILTER"];

	if (kind == "capture") then
		vcap_setup(pwin);

	elseif (kind == "static") then
		pwin.callback = 
		function(source, status)
			if (pwin.alive == false) then
				return;
			end

			if (status.kind == "loaded") then
				pwin:update_canvas(source);
				pwin:resize(status.width, status.height);
			end
		end

	elseif (kind == "frameserver") then
		awbmedia_add_fsrvctrl(pwin, bar);
	
		pwin.callback = 
		function(source, status)
			vmedia_callback(pwin, source, status);
		end

		pwin.helpmsg = MESSAGE["HELP_VMEDIA"];
	end

	return pwin.callback; 
end
