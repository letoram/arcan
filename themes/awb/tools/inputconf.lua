--
-- Keyboard input here is similar to the more simple keyconf.lua
-- It uses the same translation mechanism from table to identity string
-- but uses the awbwman* class of functions to build the UI etc. functions 
--

--
-- fill tbl with PLAYERpc_AXISac   = analog:0:0:none
--          with PLAYERpc_BUTTONbc = translated:0:0:none
--          with PLAYERpc_other
--

local function splits(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
	
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end
	
	table.insert(res, string.sub(instr, strt));
	return res;
end

local function keyconf_idtotbl(self, idstr)
	local res = self.table[ idstr ];
	if (res == nil) then return nil; end
	
	restbl = splits(res, ":");
	if (restbl[1] == "digital") then
		restbl.kind = "digital";
		restbl.devid = tonumber(restbl[2]);
		restbl.subid = tonumber(restbl[3]);
		restbl.source = restbl[4];
		restbl.active = false;
		
	elseif (restbl[1] == "translated") then
		restbl.kind = "digital";
		restbl.translated = true;
		restbl.devid = tonumber(restbl[2]);
		restbl.keysym = tonumber(restbl[3]);
		restbl.modifiers = restbl[4] == nil and 0 or tonumber(restbl[4]);
		restbl.active = false;
		
	elseif (restbl[1] == "analog") then
		restbl.kind = "analog";
		restbl.devid = tonumber(restbl[2]);
		restbl.subid = tonumber(restbl[3]);
		restbl.source = restbl[4];
	else
		restbl = nil;
	end
	
	return restbl;
end

local function keyconf_tbltoid(self, itbl)
	if (itbl.kind == "analog") then
		return string.format("analog:%d:%d", 
			itbl.devid, itbl.subid);
	end

	if itbl.translated then
		if self.ignore_modifiers then
			return string.format("translated:%d:%s:0", 
				itbl.devid, itbl.keysym);
		else
			return string.format("translated:%d:%d:%s", 
				itbl.devid, itbl.keysym, itbl.modifiers);
		end
	else
		return string.format("digital:%d:%d",
			itbl.devid, itbl.subid);
	end
end

--
-- Try and reuse as much of scripts/keyconf.lua
-- as possible
--
local function set_tblfun(dst)
	dst.id = keyconf_tbltoid;
	dst.idtotbl = keyconf_idtotbl;
	dst.ignore_modifiers = true;
end

local function pop_deftbl(tbl, pc, bc, ac, other)
	local nulstr = "translated:0:0:none";

	tbl["QUICKLOAD"] = nulstr;
	tbl["QUICKSAVE"] = nulstr;
	tbl["FASTFORWARD"] = nulstr;

	for i=1,pc do
		for j=1,bc do 
			tbl["PLAYER" .. tostring(i) .. "_BUTTON" ..tostring(j)] = 
				nulstr;	
		end

		tbl["PLAYER" .. tostring(i) .. "_UP"]    = nulstr;
		tbl["PLAYER" .. tostring(i) .. "_DOWN"]  = nulstr;
		tbl["PLAYER" .. tostring(i) .. "_LEFT"]  = nulstr;
		tbl["PLAYER" .. tostring(i) .. "_RIGHT"] = nulstr; 

		for j=1,ac do
			tbl["PLAYER" .. tostring(i) .. "_AXIS" .. tostring(j)] = 
				"analog:0:0:none";
		end

		for k,v in pairs(other) do
			tbl["PLAYER" .. tostring(i) .. "_" .. v] = 
				"translated:0:0:none";
		end
	end
end

--
-- Translation functions just copied from keyconf,
-- and configurations generated here should be valid against
-- other scripts using keysym.lua
--
local function keyconf_buildtable(self, label, state)
-- matching label? else early out.
	local matchtbl = self:idtotbl(label);

	if (matchtbl == nil) then return nil; end
	
-- if we don't get a table from an input event, we build a small empty table,
-- with the expr-eval of state as basis 
	local worktbl = {};

	if (type(state) ~= "table") then
		worktbl.kind = "digital";
		worktbl.active = state and true or false;
	else
		worktbl = state;
	end

-- safety check, analog must be mapped to analog 
-- (translated is a subtype of digital so that can be reused)
	if (worktbl.kind == "analog" and matchtbl.kind ~= "analog") then
		return nil; 
	end
	
-- impose state / data values from the worktable unto the matchtbl
	if (matchtbl.kind == "digital") then
		matchtbl.active = worktbl.active;
		worktbl = matchtbl;
	else
-- for analog, swap the device/axis IDs and keep the samples
		worktbl.devid = matchtbl.devid;
		worktbl.subid = matchtbl.subid;
	end

	worktbl.label = label;
	return worktbl;
end

-- return the symstr that match inputtable, or nil.
local function keyconf_match(self, input, label)
	if (input == nil) then
		return nil;
	end

-- used for overrides à networked remotes etc.
	if (input.external) then
		kv = {};
		table.insert(kv, input.label);
		return kv;
	end

	if (type(input) == "table") then
		kv = self.table[ self:id(input) ];
	else
		kv = self.table[ input ];
	end

-- with a label set, we expect a boolean result
-- otherwise the actual matchresult will be returned
	if label ~= nil and kv ~= nil then
		if type(kv) == "table" then
			for i=1, #kv do
				if kv[i] == label then return true; end
			end
		else
			return kv == label;
		end
		
		return false;
	end

	return kv;
end

local function insert_unique(tbl, key)
	for key, val in ipairs(tbl) do
		if val == key then
			return;
		end
	end
	
	table.insert(tbl, key);
end

local function input_anal(edittbl, startofs)
	local cfg = awbwman_cfg();
	local devtbl = inputanalog_query();

	local btntbl = {
		{
			caption = cfg.defrndfun("Select"),
			trigger = function(owner)
				edittbl.parent.table[edittbl.name] = 
					string.format("analog:%d:%d", devtbl[owner.cur_ind].devid, 
					devtbl[owner.cur_ind].subid);

				edittbl.parent:update_list();
				edittbl.parent.wnd:force_update();
			end
		},	
		{
			caption = cfg.defrndfun("Cancel"),
			trigger = function(owner)
			end
		},
	};

	if (devtbl == nil or #devtbl == 0) then
		return;
	end

	local updatestr = function(ind, count, label)
		if (label == nil) then
			label = "";
		end

		local msg = string.format([[
(Arrow Keys to step Axis/Device)\n\r
Current(%d/%d):\t %d : %d\n\r
Sample Count:\t %d%s]], ind, #devtbl, devtbl[ind].devid, 
			devtbl[ind].subid, count, label); 
		return desktoplbl( msg );
	end

	local step = function(self, n)
		self.cur_ind = self.cur_ind + n;

		if (self.cur_ind <= 0) then
			self.cur_ind = #devtbl;
		elseif (self.cur_ind > #devtbl) then
			self.cur_ind = 1;
		end

		self.cur_count = 0;
		local ainf = inputanalog_query(devtbl[self.cur_ind].devid, 0);
		local label = nil;
		self.tmplabel = nil; 

		if (ainf and ainf.label ~= nil) then
			if (inputed_glut and 
				inputed_glut[ainf.label] and
				inputed_glut[ainf.label].analog and
				inputed_glut[ainf.label].analog[devtbl[self.cur_ind].subid+1]) then
				label = "\\n\\rIdentifer:\\t" .. 
					tostring(inputed_glut[ainf.label].analog[devtbl[self.cur_ind].subid+1]);
				self.tmplabel = label;
			end
		end

		self:update_caption( updatestr( self.cur_ind, 0, label ) );
	end

	local props = image_surface_resolve_properties(
		edittbl.parent.wnd.canvas.vid);

	local dlg = awbwman_dialog(updatestr(1, 0), btntbl, 
		{x = (props.x + 20), y = (props.y + 20), nocenter = true}, false);
	dlg.lastid = edittbl.bind;

	if (dlg == nil) then
		return;
	end

	dlg.cur_count = 0;
	dlg.cur_ind = 1;
	step(dlg, 0);

	edittbl.parent.wnd:add_cascade(dlg);

	dlg.input = function(self, iotbl)
		if (iotbl.active == false) then
			return;
		end
	
		if (iotbl.lutsym == "UP" or iotbl.lutsym == "RIGHT") then
			step(self, 1);
				
		elseif (iotbl.lutsym == "DOWN" or iotbl.lutsym == "LEFT") then
			step(self, -1);

		else
			return;
		end
	end

	dlg.ainput = function(self, iotbl)
		if (iotbl.devid == devtbl[self.cur_ind].devid and
			iotbl.subid == devtbl[self.cur_ind].subid) then
			
			self.cur_count = self.cur_count + 1;
			self:update_caption( updatestr( self.cur_ind, self.cur_count, self.tmplabel) );
		end
	end
end

local function input_dig(edittbl)
	local cfg = awbwman_cfg();

	local btntbl = {
		{
			caption = cfg.defrndfun("Save"),
			trigger = function(owner)
				edittbl.parent.table[edittbl.name] = owner.lastid;
				edittbl.parent:update_list();
				edittbl.parent.wnd:force_update();
			end,
		},
		{
			caption = cfg.defrndfun("Cancel"),
			trigger = function(owner) end
		}
	};
		
	local msg = cfg.defrndfun( string.format("Press a button for [%s]\\n\\r\t%s",
		edittbl.name, edittbl.bind) );

	local props = image_surface_resolve_properties(edittbl.parent.wnd.canvas.vid);

	local dlg = awbwman_dialog(msg, btntbl, 
		{x = (props.x + 20), y = (props.y + 20), nocenter = true}, false);
	dlg.lastid = edittbl.bind;

	edittbl.parent.wnd:add_cascade(dlg);

	dlg.input = function(self, iotbl)
		local tblstr = edittbl.parent:id(iotbl);

		if (tblstr) then
			dlg.lastid = tblstr;
			local alias = "";

			local ainf = inputanalog_query(iotbl.devid, 0);

			if (ainf and ainf.label ~= nil) then

			if (inputed_glut and 
				inputed_glut[ainf.label] and
				inputed_glut[ainf.label].digital and
				inputed_glut[ainf.label].digital[iotbl.subid+1]) then
				alias = "\\n\\r\\t" .. 
					tostring(inputed_glut[ainf.label].digital[iotbl.subid+1]);
			end

			end

			local msg = desktoplbl( 
				string.format("Press a button for [%s]\\n\\r\\t%s%s",
				edittbl.name, tblstr, alias ~= nil and alias or "") 
			);

			if (valid_vid(msg)) then
				dlg:update_caption(msg);
			end
		end
	end

	local real_dest = dlg.destroy;

--	dlg.destroy = function(self, speed)
--		if (edittbl.parent.wnd.drop_cascade) then
--			edittbl.parent.wnd:drop_cascade(dlg);
--		end
--		real_dest(self, speed);
--	end
--	awbwnd_dialog
end

--
-- Just copied from resources/scripts/keyconf.lua
--
local function inputed_saveas(tbl, dstname)
	local k,v = next(tbl);

	zap_resource("keyconfig/" .. dstname);
	open_rawresource("keyconfig/" .. dstname);
	write_rawresource("local keyconf = {};\n");

	for key, value in pairs(tbl) do
		if (type(value) == "table") then
			write_rawresource( "keyconf[\"" .. key .. "\"] = {\"");
			write_rawresource( table.concat(value, "\",\"") .. "\"};\n" );
		else
			write_rawresource( "keyconf[\"" .. key .. "\"] = \"" .. value .. "\";\n" );
		end
	end

   write_rawresource("return keyconf;");
   close_rawresource();
end

local function inputed_editlay(intbl, dstname)
	
	intbl.update_list = function(intbl)
		intbl.list = {};

		for k,v in pairs(intbl.table) do
			if (type(v) == "string") then
				local res = {};
				res.name = k;
				res.bind = v;
				res.parent = intbl;

				local bindstr = "";
				local procv = v;

				res.trigger = (string.sub(v, 1, 6) == "analog") 
					and input_anal or input_dig;
	
				if (v == "analog:0:0:none" or 
					v == "digital:0:0:none" or v == "translated:0:0:none") then
					res.cols = {k, "not bound"};
				else
					res.cols = {k, v};
				end
				table.insert(intbl.list, res);
			end
		end

		table.sort(intbl.list, function(a,b) 
			return string.lower(a.name) < string.lower(b.name); 
		end);

		if (intbl.wnd) then
			intbl.wnd.tbl = intbl.list;
		end
	end

	intbl:update_list();
-- and because *** intbl don't keep track of order, sort list..
	local wnd = awbwman_listwnd(menulbl("Input Editor"), 
		deffont_sz, linespace, {0.5, 0.5}, intbl.list, desktoplbl);
	if (wnd == nil) then
		return;
	end

	local cfg = awbwman_cfg();

	wnd.cascade = {};

	wnd.real_destroy = wnd.destroy;
	
	wnd.destroy = function(self, speed)
		local opt = {};
		if (dstname) then
			table.insert(opt, "Update");
		end
		table.insert(opt, "Save As");
		table.insert(opt, "Discard");

		local vid, lines = desktoplbl(table.concat(opt, "\\n\\r"));
	
		local btnhand = function(ind)
			if (opt[ind] == "Save As") then
				local buttontbl = {
					{ caption = desktoplbl("OK"), trigger = function(own)
						inputed_saveas(own.inptbl, own.inputfield.msg .. ".cfg");
					 end }
				};

				local dlg = awbwman_dialog(desktoplbl("Save As:"), buttontbl, {
					input = { w = 100, h = 20, limit = 32, accept = 1 } 
				});
				dlg.inptbl = intbl.table;

			elseif (opt[ind] == "Discard") then
				wnd:real_destroy(speed);

			elseif (opt[ind] == "Update") then
				inputed_saveas(intbl.table, dstname);
				wnd:real_destroy(speed);
			end
		end

		awbwman_popup(vid, lines, btnhand, {ref = wnd.dir.t.left[1].vid}); 
	end

	intbl.wnd = wnd;
	wnd.name = "Input Editor";
end

function inputed_translate(iotbl, cfg)
	if (cfg == nil) then
		return;
	end

	if (iotbl.source == nil) then
		iotbl.source = tostring(iotbl.devid);
	end

	local lbls = keyconf_match(cfg, iotbl);

	if (lbls == nil) then 
		return;
	end

	local res = {};

	for k,v in ipairs(lbls) do
		local tbl = keyconf_buildtable(cfg, v, iotbl);
		table.insert(res, tbl); 
	end

	return res;
end

function inputed_inversetbl(intbl)
	local newtbl = {};

	for k,v in pairs(intbl) do
		newtbl[k] = v;

		if (newtbl[v] == nil) then
			newtbl[v] = {};
		end

		local found = false;
		for h,j in ipairs(newtbl[v]) do
			if (j == k) then 
				found = true;
				break;
			end
		end

		if (not found) then
			table.insert(newtbl[v], k);
		end
	end

	return newtbl;
end

function inputed_getcfg(lbl)
	lbl = "keyconfig/" .. lbl;

	if (resource(lbl)) then
		local res = {};
		res.table = inputed_inversetbl(system_load(lbl)());
		set_tblfun(res);
		return res;
	end

	return nil;
end

local function setup_axismonitor()
	if (global_axismon == nil) then
		global_axismon.sample_count = 0;
		global_axismon = awbwman_spawn(
			menulbl("Analog Monitor"), {noresize = true}
		);

		awbwman_reqglobal(global_axismon);
		global_axismon.on_destroy = function() global_axismon = nil; end;
		global_axismon.axes = {};

-- one column for each axis, on mouse over on column shows id:axis
		global_axismon.ainput = function()
			global_axismon.sample_count = global_axismon.sample_count + 1;
		end
	end

end

local function analog_kernelpop(wnd, btn)
	local list = {
		"1",
		"2",
		"3",
		"4",
		"5",
		"6"
	};

	local olist = {};
	for ind, val in ipairs(list) do
		if (val == tostring(wnd.kernel_sz)) then
			olist[ind] = [[\#00ff00]] .. val .. [[\#ffffff]];
		else
			olist[ind] = val;
		end
	end

	local str = table.concat(olist, [[\n\r]]);
	local vid, lines = desktoplbl(str);
	awbwman_popup(vid, lines, function(ind)
		wnd.kernel_sz = tonumber(list[ind]);
			inputanalog_filter(wnd.dev, wnd.sub, wnd.deadzone, 
				wnd.ubound, wnd.lbound, wnd.kernel_sz, wnd.mode);
		end, {ref = btn.vid});
end

local function analog_filterpop(wnd, btn)
	local list = {
		"drop",
		"pass",
		"average",
		"latest"
	};

	local olist = {};

	for ind, val in ipairs(list) do
		if (val == wnd.mode) then
			olist[ind] = [[\#00ff00]] .. val .. [[\#ffffff]];
		else
			olist[ind] = val;
		end
	end

	local str = table.concat(olist, [[\n\r]]);
	local vid, lines = desktoplbl(str);

	awbwman_popup(vid, lines, function(ind)
		wnd.mode = list[ind];
		inputanalog_filter(wnd.dev, wnd.sub, wnd.deadzone, 
			wnd.ubound, wnd.lbound, wnd.kernel_sz, wnd.mode);
	end, {ref = btn.vid});
end

--
-- If we already have an axis view window, switch dev/axis
-- else spawn a new window.
-- Canvas is a graph view of current values (updated every n samples)
--
local function update_window(dev, sub)
	if (global_analwin == nil) then
		local wnd = awbwman_spawn(menulbl("Analog View"), {});

		global_analwin = wnd;
		wnd.hoverlut = {};
		wnd.deadzone = 0;
		wnd.ubound = 32767;
		wnd.lbound = -32768;
		wnd.mode = "none";
		wnd.kernel_sz = 1;
		wnd.name = string.format("Analog(%d:%d)", dev, sub);

		local cfg = awbwman_cfg();
		local bar = wnd:add_bar("tt", cfg.ttactiveres, cfg.ttactiveres,
			wnd.dir.t.rsize, wnd.dir.t.bsize);

		bar.hover = function(self, vid, x, y, state)
			if (state == false) then
				awbwman_drophover();
			elseif (wnd.hoverlut[vid] ~= nil) then
				awbwman_hoverhint(wnd.hoverlut[vid]);
			end
		end

		bar.click = function() 
			wnd:focus(); 
		end

		local canvash = {
			own = function(self, vid) return vid == wnd.canvas.vid; end,
			click = function() wnd:focus(); end
		};

		bar.name = "analog_ttbar";
		canvash.name = "analog_canvas";

		mouse_addlistener(bar, {"click", "hover"});
		mouse_addlistener(canvash, {"click"});
		table.insert(wnd.handlers, canvash);

		wnd.hoverlut[
		(bar:add_icon("filters", "l", cfg.bordericns["filter"],
			function(self) 
				analog_filterpop(wnd, self); 
			end)).vid] = MESSAGE["ANALOG_FILTERMODE"];

		wnd.hoverlut[
			(bar:add_icon("kernelsz", "l", cfg.bordericns["resolution"],
			function(self)
				analog_kernelpop(wnd, self);
			end)).vid] = MESSAGE["ANALOG_KERNELSIZE"];

		wnd.hoverlut[
			(bar:add_icon("deadzone", "l", cfg.bordericns["aspect"],
			function(self)
				awbwman_popupslider(0, wnd.deadzone, 10000, function(val)
					inputanalog_filter(wnd.dev, wnd.sub, val, 
						wnd.ubound, wnd.lbound, wnd.kernel_sz, wnd.mode);
					wnd:switch_device(wnd.dev, wnd.sub);
				end, {ref = self.vid});
		end)).vid] = MESSAGE["ANALOG_DEADZONE"];

		wnd.hoverlut[
		(bar:add_icon("ubound", "l", cfg.bordericns["uparrow"],
			function(self)
				print("ubound:", wnd.ubound);
				awbwman_popupslider(16536, wnd.ubound, 32767, function(val)
					inputanalog_filter(wnd.dev, wnd.sub, wnd.deadzone, 
						wnd.lbound, val, wnd.kernel_sz, wnd.mode);
					wnd:switch_device(wnd.dev, wnd.sub);
				end, {ref = self.vid});
			end)).vid] = MESSAGE["ANALOG_UBOUND"];

		wnd.hoverlut[
		(bar:add_icon("lbound", "l", cfg.bordericns["downarrow"],
			function(self)
				print("lbound:", wnd.lbound);
				awbwman_popupslider(-16536, wnd.lbound, -32767, function(val)
					inputanalog_filter(wnd.dev, wnd.sub, wnd.deadzone, 
						val, wnd.ubound, wnd.kernel_sz, wnd.mode);
					wnd:switch_device(wnd.dev, wnd.sub);
				end, {ref = self.vid});
			end)).vid] = MESSAGE["ANALOG_LBOUND"];

		wnd.invertvid = 
		bar:add_icon("invert", "l", cfg.bordericns["flip"],
			function(self)
				if (awbwman_flipaxis(wnd.dev, wnd.sub)) then
					image_shader(self.vid, "awb_selected");
				else
					image_shader(self.vid, "DEFAULT");
				end
			end).vid;

		wnd.hoverlut[wnd.invertvid] = MESSAGE["ANALOG_INVERT"];

		awbwman_reqglobal(wnd);
		wnd.on_destroy = function() global_analwin = nil; end;
		wnd.input = function() end

		wnd:update_canvas(fill_surface(8, 8, 0, 0, 0));
		
		local ubound = color_surface(2, 2,   0, 255,   0);
		local lbound = color_surface(2, 2,   0, 255, 255);
		local  dzone = color_surface(2, 2, 128,  32,  32);
	
		image_mask_set(ubound, MASK_UNPICKABLE);
		image_mask_set(lbound, MASK_UNPICKABLE);
		image_mask_set(dzone, MASK_UNPICKABLE);

		link_image(ubound, wnd.canvas.vid);
		link_image(lbound, wnd.canvas.vid);
		link_image(dzone,  wnd.canvas.vid);

		local group = {ubound, lbound, dzone};
		show_image(group);
		image_inherit_order(group, true);
		order_image(group, 1);

-- Map up scale and zones for the device in question 
-- (0 canvas, 1 bglabels, 2 samples, 3 notices)
		wnd.switch_device = function(self, dev, sub)
			local res = inputanalog_query(dev, sub);

			if (wnd.devsym ~= nil) then
				delete_image(wnd.devsym);
				wnd.devsym = nil;
			end

			if (res == nil) then
				wnd.dir.t:update_caption(menulbl("No Device Found"));
			else
				wnd.mode = res.mode;
				wnd.deadzone = res.deadzone;
				wnd.ubound = res.upper_bound;
				wnd.lbound = res.lower_bound;
				wnd.kernel_sz = res.kernel_size;
				wnd.devlbl = res.label;
				wnd.dev = dev;
				wnd.sub = sub;
				local lblcap = menulbl( 
					string.format("(%d:%d)", dev, sub, res.label), 10);
				image_tracetag(lblcap, "analog_detailcap");

				if (inputed_glut and inputed_glut[res.label] and 
					inputed_glut[res.label].analog[sub+1]) then
					wnd.devsym = desktoplbl(tostring(inputed_glut[res.label].analog[sub+1]));
					show_image(wnd.devsym);
					link_image(wnd.devsym, wnd.canvas.vid);
					image_inherit_order(wnd.devsym, true);
					order_image(wnd.devsym, 1);
					image_clip_on(wnd.devsym, CLIP_SHALLOW);
				end

				wnd.dir.t:update_caption(lblcap);
				local w = wnd.canvasw;
				local h = wnd.canvash;
				local step = h / 65536;
				resize_image(ubound, w, 2);
				resize_image(lbound, w, 2);
				move_image(ubound, 0, h * 0.5 + step * res.upper_bound);
				move_image(lbound, 0, h * 0.5 + step * res.lower_bound);
				if (res.deadzone == 0) then
					hide_image(dzone);
				else
					show_image(dzone);
					resize_image(dzone, w, res.deadzone * step);
				end

				move_image(dzone, 0, h * 0.5 - step * res.deadzone * 0.5);
			end

			local flipped = awbwman_flipaxis(wnd.dev, wnd.sub, true);
			image_shader(wnd.invertvid, flipped == true and "awb_selected" or "DEFAULT");
		end

		wnd.ainput = function(self, iotbl)
			if (iotbl.devid == self.dev and iotbl.subid == self.sub) then
				local h = wnd.canvash;
				local step = h / 65536;
				local box = color_surface(3, 3, 255, 255, 255);
				show_image(box);
				link_image(box, wnd.canvas.vid);
				image_inherit_order(box, true);
				order_image(box, 2);
				expire_image(box, 5);
				move_image(box, wnd.canvasw * 0.5, 
					h * 0.5 - step * iotbl.samples[1]);
			end
		end

		wnd.on_resize = function()
			wnd:switch_device(wnd.dev, wnd.sub);
		end

		wnd.dev = dev;
		wnd.sub = sub;
	end

	global_analwin:switch_device(dev, sub);
	global_analwin:focus();
end

local function inputed_anallay(devtbl)
	local devs = {};

		for i,j in ipairs(devtbl) do
		local newent = {
			trigger = function(self, wnd)
				update_window(j.devid, j.subid);
			end,
			cols = {
				tostring(j.devid), tostring(j.subid), j.label
			}
		}

		table.insert(devs, newent);
	end

	local wnd = awbwman_listwnd(menulbl("Analog Options"), 
		deffont_sz, linespace, {0.2, 0.2, 0.6}, devs, desktoplbl);

	if (wnd == nil) then
		return;
	end
end

function awb_inputed()
	local res = glob_resource("keyconfig/*.cfg", RESOURCE_THEME);	
	local ctable = {};
	set_tblfun(ctable);

	inputed_glut = {};
	local symres = glob_resource("keyconfig/*.sym", RESOURCE_THEME);

	if (symres and #symres > 0) then
		for i, v in ipairs(symres) do
			local resv = system_load("keyconfig/" .. v);
			if (resv) then
				local group, tbl = resv();

				if (type(group) == "string" and type(tbl) == "table") then
					inputed_glut[group] = tbl;
				else
					warning(string.format("loading helper (%s) failed" ..
						", expected key, tbl\n", v));
				end
			end
		end
	end

	local list = {
		{
			cols    = {"New Layout..."},
			trigger = function(self, wnd)
				wnd:destroy(awbwman_cfg().animspeed);
				local activetbl = {};
				pop_deftbl(activetbl, 4, 8, 6, {"START", "SELECT", "COIN1"});
				ctable.table = activetbl;
				inputed_editlay(ctable);	
			end
		}
	};

	local devtbl = inputanalog_query();
	if (#devtbl == 0) then
		inputanalog_query(0, 0, 1);
		devtbl = inputanalog_query();
	end

	if (#devtbl > 0) then
		table.insert(list, {
			cols = {"Analog Options..."},
			trigger = function(self, wnd)
				wnd:destroy(awbwman_cfg().animspeed);
				inputed_anallay(devtbl);
			end
		});
	end

	table.insert(list, {
		cols = {"Re- scan Analog..."},
			trigger = function(self, wnd)
				inputanalog_query(0, 0, 1);
				local x = wnd.x;
				local y = wnd.y;

				wnd:destroy();
				local newwnd = awb_inputed();
				if (newwnd ~= nil) then
					newwnd:move(x, y);
				end
			end
	});

	for i,v in ipairs(res) do
		local base, ext = string.extension(v);
		local res = {
			cols = {base}
		};
		res.trigger = function(self, wnd)
			local vid, lines = desktoplbl([[Edit\n\rDelete]]);
			awbwman_popup(vid, lines, function(ind)
				if (ind == 1) then
					wnd:destroy(awbwman_cfg().animspeed);
					ctable.table = system_load("keyconfig/" .. v)();
					if (ctable.table) then
						inputed_editlay(ctable, v); 
					end
				else
					zap_resource("keyconfig/" .. v);
					res = glob_resource("keyconfig/*.cfg", RESOURCE_THEME);
					table.remove(list, ind);
					wnd:force_update();
				end
			end, {});
		end
		table.insert(list, res);
	end

	local wnd = awbwman_listwnd(menulbl("Input Editor"), 
		deffont_sz, linespace, {1.0}, list, desktoplbl);

	if (wnd ~= nil) then
		wnd.name = "Input Editor";
		wnd.helpmsg = MESSAGE["HELP_INPUT"];
	end

	return wnd;
end

function inputed_configlist()
	res = glob_resource("keyconfig/*.cfg", RESOURCE_THEME);
	return res;
end

local descrtbl = {
	name = "inputed",
	caption = "Input",
	icon = "ipnuted",
	trigger = awb_inputed 
};

return descrtbl;
