local function getskipval(str)
	if (str == "Automatic") then
		return 0;
	elseif (str == "None") then
		return -1;
	elseif (str == "Skip 1") then
		return 1;
	elseif (str == "Skip 2") then
		return 2;
	elseif (str == "Skip 3") then
		return 3;
	elseif (str == "Skip 4") then
		return 4;
	end
end

local function datashare(wnd)
	local res = awbwman_setup_cursortag(sysicons.floppy);
	res.kind = "media";
	res.source = wnd;
	return res;
end

local function inputlay_sel(icn, wnd)
	if (awbwman_ispopup(icn.vid)) then
		wnd:focus();
		return nil;
	end

	wnd:focus();
	local lst = inputed_configlist();

	table.insert(lst, 1, "Disable");
	local str = table.concat(lst, [[\n\r]]);
	local vid, lines = desktoplbl(str);

	awbwman_popup(vid, lines, function(ind)
		wnd.inp_cfg = inputed_getcfg(lst[ind]); 
	end, {ref = icn.vid});
end

function stepfun_tbl(trig, wnd, c, name, tbl, up)
	local ind = 1;
	for i=1, #tbl do
		if (tbl[i] == c[name]) then
			ind = i;
			break;
		end
	end

	if (up) then
		ind = ind + 1;
		ind = ind > #tbl and 1 or ind;
	else
		ind = ind - 1;
		ind = ind == 0 and #tbl or ind;
	end

	trig.cols[2] = tbl[ind];
	c[name] = tbl[ind];
end

function stepfun_num(trig, wnd, c, name, shsym, shtype, min, max, step)
	c[name] = c[name] + step;
	c[name] = c[name] < min and min or c[name];
	c[name] = c[name] > max and max or c[name];

	trig.cols[2] = tostring(c[name]);

	wnd:force_update();
	if (shsym) then
		shader_uniform(c.shid, shsym, shtype, PERSIST, c[name]);
	end
end

function awbtarget_settingswin(tgtwin)
	local conftbl = {
		{
		name = "graphdbg",
		trigger = function(self, wnd)
			tgtwin.graphdbg = not tgtwin.graphdbg;
			target_graphmode(tgtwin.controlid, tgtwin.graphdbg == true and 1 or 0);
			self.cols[2] = tostring(tgtwin.graphdbg);
			wnd:force_update();
		end,
		rtrigger = trigger,
		cols = {"Graph Debug", tostring(tgtwin.graphdbg)} 
		},
		{
		name = "preaud",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "preaud", nil, nil, 0, 6, 1);
			tgtwin:set_frameskip();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd, tgtwin, "preaud", nil, nil, 0, 6, -1);
			tgtwin:set_frameskip();
		end,
		cols = {"Pre-Audio", tostring(tgtwin.preaud)},
		},
		{
		name = "skipmode",
		trigger = function(self, wnd)
			stepfun_tbl(self, wnd, tgtwin, "skipmode", {"Automatic", "None",
			"Skip 1", "Skip 2", "Skip 3", "Skip 4"}, true);
			self.cols[2] = tgtwin.skipmode;
			tgtwin:set_frameskip();
			wnd:force_update();
		end,
		rtrigger = function(self, wnd)
			stepfun_tbl(self, wnd, tgtwin, "skipmode", {"Automatic", "None",
			"Skip 1", "Skip 2", "Skip 3", "Skip 4"}, false);
			self.cols[2] = tgtwin.skipmode;
			wnd:force_update();
			tgtwin:set_frameskip();
		end,
		cols = {"Skip Mode", tgtwin.skipmode}
		},
		{
		name = "framealign",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "framealign", nil, nil, 0, 10, 1);
			tgtwin:set_frameskip();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd, tgtwin, "framealign", nil, nil, 0, 10, -1);
			tgtwin:set_frameskip();
		end,
		cols = {"Frame Prealign", tostring(tgtwin.framealign)},
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("Advanced..."), deffont_sz, linespace,
		{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

		tgtwin:add_cascade(newwnd);
end

--
-- Re-uses the same patterns as gridle
-- If the user wants to load savestates with other names, 
-- he'll have to drag'n'drop from the desktop group
--
function awbtarget_listsnaps(tgtwin, gametbl)
	local base = glob_resource(string.format("savestates/%s*", 
		tgtwin.snap_prefix), SHARED_RESOURCE);

	if (base and #base > 0) then
-- The number of possible savestates make this one difficult 
-- to maintain as a popup, so use a list window
		local newwnd = awbwman_listwnd(
			menulbl(gametbl.title .. ":savestates"), deffont_sz, linespace, {1.0},
			function(filter, ofs, lim, iconw, iconh)
				local res = {};
				local ul  = ofs + lim;
				ul = ul > #base and #base or ul;
	
				for i=ofs, ul do
					table.insert(res, {
						name = base[i],
						trigger = function() 
							restore_target(tgtwin.controlid, base[i]); 
							tgtwin.laststate = string.sub(base[i], #tgtwin.snap_prefix+1);
						end, 
						name = base[i],
						cols = {string.sub(base[i], #tgtwin.snap_prefix+1)}
					});
				end
				return res, #base;
			end, desktoplbl);

		tgtwin:add_cascade(newwnd);
	end
end
	
local function awbtarget_save(pwin, res)
	if (res == nil) then
		local buttontbl = {
			{ caption = desktoplbl("OK"), trigger = function(own) 
				awbtarget_save(pwin, own.inputfield.msg); end },
			{ caption = desktoplbl("Cancel"), trigger = function(own) end }
		};

		local dlg = awbwman_dialog(desktoplbl("Save As:"), buttontbl, {
			input = { w = 100, h = 20, limit = 32, accept = 1, cancel = 2 }
		}, false);

		pwin:add_cascade(dlg);
	else
		snapshot_target(pwin.controlid, pwin.snap_prefix .. res);
		pwin.laststate = res; 
	end
end

local function awbtarget_addstateopts(pwin)
	local cfg = awbwman_cfg();
	local bartt = pwin.dir.tt;

	bartt:add_icon("save", "l", cfg.bordericns["save"], function(self)
		local list = {};

		if (pwin.laststate) then
			table.insert(list, pwin.laststate);
		end

		table.insert(list, "New...");
		if (not awbwman_ispopup(self)) then
			pwin:focus();

			local str = table.concat(list, [[\n\r]]);
			local vid, lines = desktoplbl(str);

			awbwman_popup(vid, lines, function(ind)
				awbtarget_save(pwin, (ind ~= #list) and list[ind] or nil);
			end, {ref = self.vid});
		end
	end);

	bartt:add_icon("load", "l", cfg.bordericns["load"], function(self)
		awbtarget_listsnaps(pwin, pwin.gametbl);
	end);
	
end

local function ntsc_dlg(tgtwin)
	local conftbl = {
		{
		name = "ntsc_artifacts",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_artifacts",nil,nil,-1.0,0.0,-0.1);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_artifacts", nil, nil,-1.0,0.0,0.1);
			tgtwin:set_ntscflt();
		end,
		cols = {"Artifacts", tostring(tgtwin.ntsc_artifacts)}
		},
		{
		name = "ntsc_hue",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "ntsc_hue",  nil, nil,-0.1, 0.1, -0.05);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd, tgtwin, "ntsc_hue",  nil, nil,-0.1, 0.1, 0.05);
			tgtwin:set_ntscflt();
		end,
		cols = {"Hue", tostring(tgtwin.ntsc_hue)}
		},
		{
		name = "ntsc_saturation",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_saturation",nil,nil,-1,1,0.2);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd,tgtwin,"ntsc_saturation",nil,nil,-1, 1,-0.2);
			tgtwin:set_ntscflt();
		end,
		cols = {"Saturation", tostring(tgtwin.ntsc_saturation)}
		},
		{
		name = "ntsc_contrast",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_contrast",nil,nil,-0.5,0.5,0.1);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd,tgtwin,"ntsc_contrast",nil,nil,-0.5,0.5,-0.1);
			tgtwin:set_ntscflt();
		end,
		cols = {"Contrast", tostring(tgtwin.ntsc_contrast)}
		},
		{
		name = "ntsc_brightness",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_brightness",nil,nil,-0.5,0.5,0.1);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd,tgtwin,"ntsc_brightness",nil,nil,-0.5,0.5,-0.1);
			tgtwin:set_ntscflt();
		end,
		cols = {"Brightness", tostring(tgtwin.ntsc_brightness)}
		},
		{
		name = "ntsc_gamma",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_gamma",nil,nil,-0.5,0.5,0.1);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd,tgtwin,"ntsc_gamma",nil,nil,-0.5,0.5,-0.1);
			tgtwin:set_ntscflt();
		end,
		cols = {"Gamma", tostring(tgtwin.ntsc_gamma)}
		},
		{
		name = "ntsc_sharpness",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_sharpness",nil,nil,-1.0,1.0,1.0);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self, wnd,tgtwin,"ntsc_sharpness",nil,nil,-1.0,1.0,-1.0);
			tgtwin:set_ntscflt();
		end,
		cols = {"Sharpness", tostring(tgtwin.ntsc_sharpness)}
		},
		{
		name = "ntsc_resolution",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_resolution", nil, nil, 0.0, 1.0, 0.2);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self,wnd,tgtwin,"ntsc_resolution",nil,nil,0.0, 1.0, -0.2);
			tgtwin:set_ntscflt();
		end,
		cols = {"Resolution", tostring(tgtwin.ntsc_resolution)}
		},
		{
		name = "ntsc_bleed",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin,"ntsc_bleed",nil, nil, -1.0, 0.0, 0.2);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self,wnd,tgtwin,"ntsc_bleed",nil,nil,-1.0,0.0,-0.2);
			tgtwin:set_ntscflt();
		end,
		cols = {"Bleed", tostring(tgtwin.ntsc_bleed)}
		},
		{
		name = "ntsc_fringing",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "ntsc_fringing", nil, nil,-1.0, 1.0, 1.0);
			tgtwin:set_ntscflt();
		end,
		rtrigger = function(self,wnd)
			stepfun_num(self,wnd,tgtwin,"ntsc_fringing",nil,nil,-1.0, 1.0, -1.0);
			tgtwin:set_ntscflt();
		end,
		cols = {"Fringing", tostring(tgtwin.ntsc_fringing)}
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("Advanced..."), deffont_sz, linespace,
		{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});

		tgtwin:add_cascade(newwnd);
end

local function awbtarget_ntscpop(wnd, icn)
	local fltdlg = {
		"NTSC"
	};

	if (wnd.ntsc_state == true) then
		fltdlg[1] = "\\#00ff00 NTSC";
	end

	local dlgtbl = {
		function(btn)
			if (btn == true) then
				wnd.ntsc_state = not wnd.ntsc_state;
				wnd:set_ntscflt();
			else
				wnd.ntsc_state = true;
				ntsc_dlg(wnd);
				wnd:set_ntscflt();	
			end
		end
	};

	local vid, lines = desktoplbl(table.concat(fltdlg, "\\n\\r"));
	awbwman_popup(vid, lines, dlgtbl, {ref = icn.vid});
end

local function awbtarget_dropstateopts(pwin)
	local cfg = awbwman_cfg();
	local bartt = pwin.dir.tt;
	
	for i=#bartt.left,1,-1 do
		if (bartt.left[i].name == "save") then
			bartt.left[i]:destroy();
		elseif (bartt.left[i].name == "load") then
			bartt.left[i]:destroy();	
		end
	end

end

local function gen_factorystr(wnd)
--
-- Generate a string that can be used to recreate this particular session,
-- down to savestate, input config and filter
--
-- track: gameid, graphdbg, skipmode, framealign, jitterstep, jitterxfer,
-- preaud
-- sweep each filtercategory and get the respective factorystr
--
end

--
-- Target window
-- Builds upon a spawned window (pwin) and returns a 
-- suitable callback for use in launch_target- style commands.
-- Assumes a bar already existing in the "tt" spot to add icons to.
--
function awbwnd_target(pwin, caps)
	local cfg = awbwman_cfg();
	local bartt = pwin.dir.tt;

	pwin.cascade = {}; 
	pwin.snap_prefix = caps.prefix and caps.prefix or "";
	pwin.mediavol = 1.0;
	pwin.filters = {};

-- options part of the "factory string" (along with filter)
	pwin.graphdbg   = false;
	pwin.skipmode   = "Automatic";
	pwin.framealign = 6;
	pwin.preaud     = 1;
	pwin.jitterstep = 0; -- just for debugging
	pwin.jitterxfer = 0; -- just for debugging
	pwin.ntsc_state = false;
	pwin.ntsc_hue        = 0.0;
	pwin.ntsc_saturation = 0.0;
	pwin.ntsc_contrast   = 0.0;
	pwin.ntsc_brightness = 0.0;
	pwin.ntsc_gamma      = 0.2;
	pwin.ntsc_sharpness  = 0.0;
	pwin.ntsc_resolution = 0.7;
	pwin.ntsc_artifacts  =-1.0;
	pwin.ntsc_bleed      =-1.0;
	pwin.ntsc_fringing   =-1.0;
-- end of factorystring options

	pwin.rebuild_chain = awbwmedia_filterchain;

	pwin.set_frameskip = function(self)
		local val = getskipval(self.skipmode);
		target_framemode(self.controlid, val, self.framealign, self.preaud,
			self.jitterstep, self.jitterxfer);
	end

	pwin.set_ntscflt = function(self)
		if (self.ntsc_state) then
			target_postfilter_args(pwin.controlid, 1, 
				pwin.ntsc_hue, pwin.ntsc_saturation, pwin.ntsc_contrast);
			target_postfilter_args(pwin.controlid, 2, 
				pwin.ntsc_brightness, pwin.ntsc_gamma, pwin.ntsc_sharpness);
			target_postfilter_args(pwin.controlid, 3, 
				pwin.ntsc_resolution, pwin.ntsc_artifacts, pwin.ntsc_bleed);
			target_postfilter_args(pwin.controlid, 4, pwin.ntsc_fringing);
			target_postfilter(pwin.controlid, POSTFILTER_NTSC);
		else
			target_postfilter(pwin.controlid, POSTFILTER_OFF);
		end
	end

-- these need to be able to be added / removed dynamically
	pwin.add_statectls  = awbtarget_addstateopts;
	pwin.drop_statectls = awbtarget_dropstateopts;

	pwin.on_resized = function(wnd, wndw, wndh, cnvw, cnvh) 
		pwin:rebuild_chain(cnvw, cnvh);
	end;

	pwin.set_mvol = function(self, val)
		pwin.mediavol = val;
		local tmpvol = awbwman_cfg().global_vol * pwin.mediavol; 
		tmpvol = tmpvol < 0 and 0 or tmpvol;
		if (pwin.reca ~= nil) then
			audio_gain(pwin.reca, tmpvol);	
		end
	end
	
	bartt:add_icon("clone", "r", cfg.bordericns["clone"], 
		function() datashare(pwin); end);

	bartt:add_icon("volume", "r", cfg.bordericns["volume"], function(self)
		if (not awbwman_ispopup(self)) then
			pwin:focus();
			awbwman_popupslider(0.01, pwin.mediavol, 1.0, function(val)
				pwin:set_mvol(val);
			end, {ref = self.vid});
		end
	end);

	bartt:add_icon("filters", "r", cfg.bordericns["filter"], 
		function(self) awbwmedia_filterpop(pwin, self); end);

	bartt:add_icon("settings", "r", cfg.bordericns["settings"],
		function(self) awbtarget_settingswin(pwin); end);

	bartt:add_icon("ntsc", "r", cfg.bordericns["ntsc"],
		function(self) awbtarget_ntscpop(pwin, self);	end);

	bartt:add_icon("pause", "l", cfg.bordericns["pause"], function(self) 
		if (pwin.paused) then
			pwin.paused = nil;
			resume_target(pwin.controlid);
			image_sharestorage(cfg.bordericns["pause"], self.vid);
		else
			pwin.paused = true;
			suspend_target(pwin.controlid);
			image_sharestorage(cfg.bordericns["play"], self.vid);
		end
	end);

--
-- Set frameskip mode, change icon to play
--
	bartt:add_icon("ffwd", "l", cfg.bordericns["fastforward"], function(self)
		pwin:focus();
	end);

--
-- Missing: popup frameskip mode
-- popup filter mode
--

	bartt:add_icon("ginput", "r", cfg.bordericns["ginput"],
		function(self) 
			if (awbwman_reqglobal(pwin)) then
				image_shader(self.vid, "awb_selected"); 
			else
				image_shader(self.vid, "DEFAULT"); 
			end
		end);

	bartt:add_icon("input", "r", cfg.bordericns["input"],
		function(self) inputlay_sel(self, pwin); end);

	pwin.input = function(self, iotbl)
		if (pwin.inp_cfg == nil) then
			return;
		end
	
		local restbl = inputed_translate(iotbl, pwin.inp_cfg);
		if (restbl) then 
			for i,v in ipairs(restbl) do
				target_input(pwin.controlid, v);
			end
		else -- hope that the hijacked target can do something with it anyway
			target_input(pwin.controlid, iotbl);
		end
	end

-- add_icon filter
-- add_icon fast-forward
-- add_icon save(slot)

	local callback = function(source, status)
		if (status.kind == "frameserver_terminated") then
			pwin:update_canvas( color_surface(1, 1, 0, 0, 0) );

		elseif (status.kind == "loading") then
			print("show loading info..");

		elseif (status.kind == "resized") then
			if (pwin.updated == nil) then
				pwin:update_canvas(source);
				pwin:resize(pwin.w, pwin.h, true);
			end

-- if we're in fullscreen, handle the resize differently
			pwin.updated = true;
	
		elseif (status.kind == "state_size") then
			pwin:drop_statectls();

			if (status.state_size > 0) then
				pwin:add_statectls();
				pwin.state_size = status.state_size;
			end
		else
--			print(status.kind);
		end
	end

	bartt.click = function() pwin:focus(); end
	local canvash = {
					own = function(self, vid) return vid == pwin.canvas.vid; end,
					click = function() pwin:focus(); end
	}

	bartt.name = "target_ttbar";
	canvash.name = "target_canvas";

	mouse_addlistener(bartt, {"click"});
	mouse_addlistener(canvash, {"click"});
	table.insert(pwin.handlers, bartt);
	table.insert(pwin.handlers, canvash);

	pwin:update_canvas( fill_surface(pwin.w, pwin.h, 100, 100, 100) );
	pwin.factorystr = awbtarget_factory;
	return callback;
end
