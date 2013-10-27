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

local function inputlay_sel(icn, wnd)
	if (awbwman_ispopup(icn.vid)) then
		wnd:focus();
		return nil;
	end

	wnd:focus();
	local lst = inputed_configlist();
	local lst2 = {};
	table.insert(lst, 1, "Disable");

	for ind, val in ipairs(lst) do
		if (val == wnd.inp_val) then
			table.insert(lst2, [[\#00ff00]] .. val);
		else
			table.insert(lst2, [[\#ffffff]] .. val);
		end	
	end

	local str = table.concat(lst2, [[\n\r]]);
	local vid, lines = desktoplbl(str);

	awbwman_popup(vid, lines, function(ind)
		wnd.inp_val = lst[ind];
		wnd.inp_cfg = inputed_getcfg(lst[ind]); 
	end, {ref = icn.vid});
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
		},
		{
		name = "mouse_accel",
		trigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "mouse_accel", nil, nil, 0.1, 4.0, 0.1);
		end,
		rtrigger = function(self, wnd)
			stepfun_num(self, wnd, tgtwin, "mouse_accel", nil, nil, 0.1, 4.0, -0.1);
		end,
		cols = {"Mouse Accel.", tostring(tgtwin.mouse_accel)}
		}
	};

	local newwnd = awbwman_listwnd(
		menulbl("Advanced..."), deffont_sz, linespace,
		{0.7, 0.3}, conftbl, desktoplbl, {double_single = true});
	if (newwnd == nil) then
		return;
	end

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

		if (newwnd == nil) then
			return;
		end
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

	pwin.hoverlut[
	(bartt:add_icon("save", "l", cfg.bordericns["save"], function(self)
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
	end)).vid] = MESSAGE["HOVER_STATESAVE"];

	pwin.hoverlut[
	(bartt:add_icon("load", "l", cfg.bordericns["load"], function(self)
		awbtarget_listsnaps(pwin, pwin.gametbl);
	end)).vid] = MESSAGE["HOVER_STATELOAD"];
	
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
	if (newwnd == nil) then
		return;
	end
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

--
-- Could really use some refactoring into something slightly more sensible
--
local function factrest(wnd, str)
-- split and index on group
-- lineattr : skipping / mediavol
-- inputcfg : try and load (if it exists)
-- ntscattr : unpack and toggle ntscon
-- statectl : try and load/ restore

	local lines = string.split(str, "\n");

-- foreach group of attributes
	for i=2,#lines do
		local opts = string.split(lines[i], ":");

-- depending on group, treat arg:argv differently 
		if (opts[1]) then
			if (opts[1] == "ntscattr") then
				for i=2,#opts do
					local arg = string.split(opts[i], "=");
					if (#arg == 2) then
						wnd[arg[1]] = tonumber_rdx(arg[2]);
					end
				end
			
			wnd.ntsc_state = true;
			wnd:set_ntscflt();

-- general opts, split into k-v tbl then map known 
-- attributes and run respective triggers
			elseif (opts[1] == "lineattr") then
				for i=2,#opts do
					local arg = string.split(opts[i], ":");
					for ind, argv in ipairs(arg) do
						local argg = string.split(argv, "=");
						local opc, oper; 

						if (argg ~= nil and #argg > 1) then
							opc  = argg[1];
							oper = argg[2];
						else
							opc = arg;
						end

						if (opc == "skipmode") then
							wnd.skipmode = oper; 
						elseif (opc == "framealign") then
							wnd.framealign = tonumber(oper);
						elseif (opc == "preaud") then
							wnd.preaud = tonumber(oper);
						elseif (opc == "mediavol") then
							wnd:set_mvol(tonumber_rdx(oper));
						else
							warning("unhandled linattr(" .. arg[1] ..")");
						end
					end

					wnd:set_frameskip();
				end

			elseif (opts[1] == "mouse_remap") then
				for i=2,#opts do
					local arg = string.split(opts[i], ":");
					for ind, argv in ipairs(arg) do
						local argg = string.split(argv, "=");
						local opc, oper;
						if (argg ~= nil and #argg > 1) then
							opc = argg[1];
							oper = argg[2];
						else
							opc = arg;
						end

						if (opc == "x_player") then
							wnd.mouse_x[1] = tonumber(oper);
						elseif (opc == "x_axis") then
							wnd.mouse_x[2] = tonumber(oper);
						elseif (opc == "y_player") then
							wnd.mouse_y[1] = tonumber(oper);
						elseif (opc == "y_axis") then
							wnd.mouse_y[2] = tonumber(oper);
						elseif (opc == "lmb_player") then
							wnd.mouse_l[1] = tonumber(oper);
						elseif (opc == "lmb_button") then
							wnd.mouse_l[2] = tonumber(oper);
						elseif (opc == "rmb_player") then
							wnd.mouse_r[1] = tonumber(oper);
						elseif (opc == "rmb_button") then
							wnd.mouse_r[2] = tonumber(oper);
						elseif (opc == "accelf") then
							wnd.mouse_accel = tonumber_rdx(oper);
						end
					end
				end
	
			elseif (opts[1] == "inputcfg") then
				if (resource("keyconfig/" .. opts[2])) then
					wnd.inp_cfg = inputed_getcfg(opts[2]); 
					if (wnd.inp_cfg) then
						wnd.inp_val = opts[2];
					end
				end
			elseif (opts[1] == "crtattr") then
				wnd.filters.display = "CRT";
				wnd:rebuild_chain(); -- make sure the context is right
				wnd.filters.displayctx:set_factstr(lines[i]);
				wnd:rebuild_chain(); -- enforce settings

			elseif (opts[1] == "xbrattr") then
				wnd.filters.upscaler = "xBR";
				wnd:rebuild_chain();
				wnd.filters.upscalerctx:set_factstr(lines[i]);
				wnd:rebuild_chain();

			elseif (opts[1] == "sabrattr") then
				wnd.filters.upscaler = "SABR";
				wnd:rebuild_chain();
				wnd.filters.upscalerctx:set_factstr(lines[i]);
				wnd:rebuild_chain();

			elseif (opts[1] == "fltattr") then
				wnd.filters.upscaler = opts[2]; 
				wnd:rebuild_chain();

			elseif (opts[1] == "glowattr") then
				wnd.filters.effect = "Glow";
				wnd:rebuild_chain();
				wnd.filters.effectctx:set_factstr(lines[i]);
				wnd:rebuild_chain();

			elseif (opts[1] == "trailattr") then
				wnd.filters.effect = "Trails";
				wnd:rebuild_chain();
				wnd.filters.effectctx:set_factstr(lines[i]);
				wnd:rebuild_chain();

			elseif (opts[1] == "glowtrailattr") then
				wnd.filters.effect = "GlowTrails";
				wnd:rebuild_chain();
				wnd.filters.effectctx:set_factstr(lines[i]);
				wnd:rebuild_chain();

			elseif (opts[1] == "statectl") then
				wnd.laststate = string.sub(opts[2], #wnd.snap_prefix+1);
				restore_target(wnd.controlid, opts[2]); 
					
-- rest, send to parent (mediawnd) and have it rebuild chain
			else
				print("unhandled group:", opts[1]);
			end
		end
	end

end

local function gen_factorystr(wnd)
	if (wnd.factory_base == nil) then
		return nil;
	end

-- the value that the desktop-env needs to create this window,
-- format:
-- group:arg1,arg2=val,arg3\n
-- group2:arg1,arg2=\n
-- etc.
	local lines = {};
	table.insert(lines, wnd.factory_base);

	table.insert(lines, string.format("lineattr:skipmode=%s:" ..
		"framealign=%d:preaud=%d:mediavol=%s", 
		wnd.skipmode, wnd.framealign, wnd.preaud, tostring_rdx(wnd.mediavol)));

	if (wnd.inp_val ~= nil) then
		table.insert(lines, string.format("inputcfg:%s", wnd.inp_val));
	end

	if (wnd.laststate ~= nil) then
		table.insert(lines, 
			string.format("statectl:%s", wnd.snap_prefix .. wnd.laststate));
	end

	if (wnd.ntsc_state == true) then
		line = string.format("ntscattr:ntsc_hue=%s:" ..
		"ntsc_saturation=%s:ntsc_contrast=%s:" ..
		"ntsc_brightness=%s:ntsc_gamma=%s:ntsc_sharpness=%s:" ..
		"ntsc_resolution=%s:ntsc_artifacts=%s:" ..
		"ntsc_bleed=%s:ntsc_fringing=%s", 
		tostring_rdx(wnd.ntsc_hue), tostring_rdx(wnd.ntsc_saturation),
		tostring_rdx(wnd.ntsc_contrast), tostring_rdx(wnd.ntsc_brightness),
		tostring_rdx(wnd.ntsc_gamma), tostring_rdx(wnd.ntsc_sharpness),
		tostring_rdx(wnd.ntsc_resolution), tostring_rdx(wnd.ntsc_artifacts),
		tostring_rdx(wnd.ntsc_bleed), tostring_rdx(wnd.ntsc_fringing));
		line = string.gsub(line, ',', '.');
		table.insert(lines, line);
	end

	if (wnd.filters.displayctx and wnd.filters.displayctx.factorystr) then
		table.insert(lines, wnd.filters.displayctx:factorystr());
	end

	if (wnd.filters.upscalerctx and wnd.filters.upscalerctx.factorystr) then
		table.insert(lines, wnd.filters.upscalerctx:factorystr());

	elseif (wnd.filters.upscaler) then
		table.insert(lines, "fltattr:" .. wnd.filters.upscaler);
	end

	if (wnd.filters.effectctx and wnd.filters.effectctx.factorystr) then
		table.insert(lines, wnd.filters.effectctx:factorystr());
	end

	table.insert(lines, string.format("mouse_remap:x_player=%d:x_axis=%d" ..
	":y_player=%d:y_axis=%d:lmb_player=%d:lmb_button=%d:rmb_player=%d:" ..
	"rmb_button=%d:accelf=%s",
		wnd.mouse_x[1], wnd.mouse_x[2], wnd.mouse_y[1], wnd.mouse_y[2],
		wnd.mouse_l[1], wnd.mouse_l[2], wnd.mouse_r[1], wnd.mouse_r[2],
		tostring_rdx(wnd.mouse_accel)));

	return table.concat(lines, "\n");
end

local function datashare(wnd)
	local res = awbwman_setup_cursortag(sysicons.floppy);
	res.kind = "media";
	res.name = wnd.name;
	res.audio = wnd.reca;

	if (res.name == nil) then
		res.name = wnd.gametbl.title;
	end

	res.factory = gen_factorystr(wnd);
	res.caption = wnd.gametbl.title;
	res.icon = wnd.gametbl.target;
	res.source = wnd;
	return res;
end

--
-- Target window
-- Builds upon a spawned window (pwin) and returns a 
-- suitable callback for use in launch_target- style commands.
-- Assumes a bar already existing in the "tt" spot to add icons to.
--
function awbwnd_target(pwin, caps, factstr)
	local cfg = awbwman_cfg();
	local bartt = pwin.dir.tt;

	pwin.cascade = {}; 
	pwin.snap_prefix = caps.prefix and caps.prefix or "";
	pwin.mediavol = 1.0;
	pwin.filters = {};
	pwin.hoverlut = {};
	pwin.helpmsg = MESSAGE["HELP_TARGET"];

-- options part of the "factory string" (along with filter)
	pwin.graphdbg   = false;
	pwin.skipmode   = "Automatic";
	pwin.framealign = 6;
	pwin.preaud     = 1;
	pwin.jitterstep = 0; -- just for debugging
	pwin.jitterxfer = 0; -- just for debugging
	pwin.ntsc_state = false;

	pwin.mouse_accel = 1.0;
	pwin.mouse_x = {1, 1};
	pwin.mouse_y = {1, 2};
	pwin.mouse_l = {1, 1};
	pwin.mouse_r = {1, 2};

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
	pwin.factory_restore = factrest;

	pwin:add_handler("on_destroy", function()
		if (pwin.filtertmp ~= nil) then
			for k, v in ipairs(pwin.filtertmp) do
				if (valid_vid(v)) then
					delete_image(v);
				end
			end
		end

		if (valid_vid(pwin.controlid)) then
			delete_image(pwin.controlid);
			pwin.controlid = nil;
		end
	end);

	pwin.set_frameskip = function(self, req)
		local val = getskipval(self.skipmode);
		if (req ~= nil) then
			val = req;
		end
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
	
	pwin.hoverlut[
	(bartt:add_icon("clone", "r", cfg.bordericns["clone"], 
		function() datashare(pwin); end)).vid] = MESSAGE["HOVER_CLONE"];

	pwin.hoverlut[
	(bartt:add_icon("volume", "r", cfg.bordericns["volume"], function(self)
		if (not awbwman_ispopup(self)) then
			pwin:focus();
			awbwman_popupslider(0.01, pwin.mediavol, 1.0, function(val)
				pwin:set_mvol(val);
			end, {ref = self.vid});
		end
	end)).vid] = MESSAGE["HOVER_VOLUME"];

	pwin.hoverlut[
	(bartt:add_icon("filters", "r", cfg.bordericns["filter"], 
		function(self) awbwmedia_filterpop(pwin, self); end)).vid
	] = MESSAGE["HOVER_FILTER"];

	pwin.hoverlut[
	(bartt:add_icon("settings", "r", cfg.bordericns["settings"],
		function(self) awbtarget_settingswin(pwin); end)).vid
	] = MESSAGE["HOVER_TARGETCFG"];

	pwin.hoverlut[
	(bartt:add_icon("ntsc", "r", cfg.bordericns["ntsc"],
		function(self) awbtarget_ntscpop(pwin, self);	end)).vid
	] = MESSAGE["HOVER_CPUFILTER"];

	local pausebtn = 
	bartt:add_icon("pause", "l", cfg.bordericns["pause"], function(self) 
		if (pwin.paused or pwin.ffstate ~= nil) then
			pwin.paused = nil;
			pwin.ffstate = nil;
			resume_target(pwin.controlid);
			pwin:set_frameskip();
			image_sharestorage(cfg.bordericns["pause"], self.vid);
		else
			pwin.paused = true;
			suspend_target(pwin.controlid);
			image_sharestorage(cfg.bordericns["play"], self.vid);
		end
	end);

	pwin.hoverlut[pausebtn.vid] = MESSAGE["HOVER_PLAYPAUSE"];

--
-- Set frameskip mode, change icon to play
--
	pwin.hoverlut[
	(bartt:add_icon("ffwd", "l", cfg.bordericns["fastforward"], function(self)
		if (pwin.ffstate ~= nil) then
			pwin.ffstate = pwin.ffstate + 1;
			if (pwin.ffstate > 14) then
				pwin.ffstate = 10;
			end
		else
			pwin.ffstate = 10;
		end
		image_sharestorage(cfg.bordericns["play"], pausebtn.vid);
		pwin:set_frameskip(pwin.ffstate);
	end)).vid] = MESSAGE["HOVER_FASTFWD"];

--
-- Missing: popup frameskip mode
-- popup filter mode
--
	pwin.hoverlut[
	(bartt:add_icon("ginput", "r", cfg.bordericns["ginput"],
		function(self) 
			if (awbwman_reqglobal(pwin)) then
				image_shader(self.vid, "awb_selected"); 
			else
				image_shader(self.vid, "DEFAULT"); 
			end
		end)).vid] = MESSAGE["HOVER_GLOBALINPUT"];

	pwin.hoverlut[
	(bartt:add_icon("input", "r", cfg.bordericns["input"],
		function(self) inputlay_sel(self, pwin); end)).vid
	] = MESSAGE["HOVER_INPUTCFG"];

-- Forced remapping of mouse in / out 
	pwin.minput = function(self, iotbl)
		if (iotbl.kind == "digital") then
			if (iotbl.subid == 0) then
				iotbl.label = string.format("PLAYER%d_BUTTON%d", 
				pwin.mouse_l[1], pwin.mouse_r[2]);
			else
				iotbl.label = string.format("PLAYER%d_BUTTON%d", 
					pwin.mouse_r[1], pwin.mouse_r[2]);
			end
		else
			local tbl = iotbl.subid == 0 and pwin.mouse_x or pwin.mouse_y;
			iotbl.label = string.format("PLAYER%d_AXIS%d", tbl[1], tbl[2]); 
				
-- scale both absolute and relative (if provided)
			iotbl.samples[1] = iotbl.samples[1] * pwin.mouse_accel;
			if (iotbl.samples[2]) then
				iotbl.samples[2] = iotbl.samples[2] * pwin.mouse_accel;
			end
		end
	
		target_input(pwin.controlid, iotbl);
	end

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

	local callback = function(source, status)
		if (pwin.alive == false) then
			return;
		end

		if (status.kind == "frameserver_terminated") then
			pwin:update_canvas( color_surface(1, 1, 0, 0, 0) );

		elseif (status.kind == "message") then
--			print("show message:", status.message);

		elseif (status.kind == "ident") then
--			print("ident", status.message);

		elseif (status.kind == "resource_status") then
--			print("resstat", status.message);

		elseif (status.kind == "loading") then
			print("show loading info..");

		elseif (status.kind == "frame") then
-- do nothing
		elseif (status.kind == "resized") then
			pwin.mirrored = status.mirrored;
	
			if (pwin.updated == nil) then
				pwin:update_canvas(source, pwin.mirrored);
				pwin:resize(pwin.w, pwin.h, true);
-- unpack settings
				if (factstr ~= nil) then
					pwin:factory_restore(factstr);
				end
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
			print(status.kind);
		end
	end

	bartt.hover = function(self, vid, x, y, state)
		if (state == false) then
			awbwman_drophover();
		else
			awbwman_hoverhint(pwin.hoverlut[vid]);
		end
	end

	bartt.click = function() 
		pwin:focus(); 
	end

	local canvash = {
		own = function(self, vid) return vid == pwin.canvas.vid; end,
		click = function() pwin:focus(); end,
		dblclick = function()
				awbwman_mousefocus(pwin);
		end
	};

	bartt.name = "target_ttbar";
	canvash.name = "target_canvas";

	mouse_addlistener(bartt, {"click", "hover"});
	mouse_addlistener(canvash, {"click", "dblclick"});
	table.insert(pwin.handlers, bartt);
	table.insert(pwin.handlers, canvash);

	pwin.canvas_iprops = function(self)
		return image_surface_initial_properties(self.controlid);
	end

	pwin:update_canvas( fill_surface(pwin.w, pwin.h, 100, 100, 100) );
	pwin.factorystr = awbtarget_factory;
	return callback;
end
