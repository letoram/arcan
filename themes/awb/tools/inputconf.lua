--
-- Keyboard input here is similar to the more simple keyconf.lua
-- It uses the same translation mechanism from table to identity string
-- but uses the awbwman* class of functions to build the UI etc. functions 
--

--
-- fill tbl with PLAYERpc_AXISac   = analog:0:0:none
--          with PLAYERpc_BUTTONbc = translated:0:0:none
--          with PLAYERpc_other
local activetbl = {};

local function pop_deftbl(tbl, pc, bc, ac, other)
	for i=1,pc do
		for j=1,bc do 
			tbl["PLAYER" .. tostring(i) .. "_BUTTON" ..tostring(j)] = 
				"translated:0:0:none";
		end

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
		return string.format("analog:%d:%d:%s", 
			itbl.devid, itbl.subid, itbl.source);
	end

	if itbl.translated then
		if self.ignore_modifiers then
			return string.format("translated:%d:%s", 
				itbl.devid, itbl.keysym);
		else
			return string.format("translated:%d:%d:%s", 
				itbl.devid, itbl.keysym, itbl.modifiers);
		end
	else
		return string.format("digital:%d:%d:%s",
			itbl.devid, itbl.subid, itbl.source);
	end
end

local function insert_unique(tbl, key)
	for key, val in ipairs(tbl) do
		if val == key then
			return;
		end
	end
	
	table.insert(tbl, key);
end

local function input_anal(edittbl)
	print("configure analog");
end

local function input_dig(edittbl)
	print("configure digital");
end

local function inputed_editlay(intbl, outputres)
	local list = {};

	for k,v in pairs(intbl) do
		local res = {};
		res.name = k;
		res.bind = v;
		res.trigger = (string.sub(v, 1, 6) == "analog") and input_anal or input_dig;
		if (v == "analog:0:0:none" or 
			v == "digital:0:0:none" or v == "translated:0:0:none") then
			res.cols = {k, "not bound"};
		else
			res.cols = {k, v};
		end
		table.insert(list, res);
	end

	table.sort(list, function(a,b) 
		return string.lower(a.name) < string.lower(b.name); 
	end);

-- and because *** intbl don't keep track of order, sort list..

	local wnd = awbwman_listwnd(menulbl("Input Editor"), 
		deffont_sz, linespace, {0.5, 0.5}, function(filter, ofs, lim)
			local res = {};
			local ul = ofs + lim;
			for i=ofs, ul do
				table.insert(res, list[i]);
			end
			return res, #list;
		end, desktoplbl);
	wnd.name = "Input Editor";
end

--
-- Try and reuse as much of scripts/keyconf.lua
-- as possible
--
local deftbl = {
	id = keyconf_tbltoid,
	idtotbl = keyconf_idtotbl,
	ignore_modifiers = false 
};

function inputed_translate(iotbl, cfg)
	if (cfg == nil) then
		return;
	end

	deftbl.table = cfg;
	
	if (iotbl.source == nil) then
		iotbl.source = tostring(iotbl.devid);
	end

	local lbls = keyconf_match(deftbl, iotbl);
	if (lbls == nil) then 
		return;
	end

	local res = {};

	for k,v in ipairs(lbls) do
		table.insert(res, keyconf_buildtable(deftbl, v, iotbl));
	end

	return res;
end

function inputed_getcfg(lbl)
	print(debug.traceback());
	lbl = "keyconfig/" .. lbl;

	if (resource(lbl)) then
		return system_load(lbl)();
	end

	return nil;
end

--
-- Spawn a window listing layouts, including a "new" will bring up
-- the layout editor, which is a list view of possible labels.
-- doubleclick there brings up the input dialog that samples input
-- (digital or analog) and 
--
function awb_inputed()
	res = glob_resource("keyconfig/*.cfg", RESOURCE_THEME);	

	local list = {
		{
			cols    = {"New Layout..."},
			trigger = function(self, wnd)
				activetbl = {};
				wnd:destroy(awbwman_cfg().animspeed);
				pop_deftbl(activetbl, 4, 8, 6, {"START", "SELECT", "COIN1"});
				inputed_editlay(activetbl);	
			end
		}
	};

	for i,v in ipairs(res) do
		local res = { cols = {v},
			trigger = function(self, wnd)
				wnd:destroy(awbwman_cfg().animspeed);
				inputed_editlay(system_load("keyconfig/" .. v)());
			end
		};

		table.insert(list, res);
	end

	local wnd = awbwman_listwnd(menulbl("Input Editor"), deffont_sz, linespace, {1.0},
		function(filter, ofs, lim)
			local res = {};
			local ul = ofs + lim;
			for i=ofs, ul do
				table.insert(res, list[i]);
			end
			return res, #list;
		end, desktoplbl);
	wnd.name = "Input Editor";
end

function inputed_configlist()
	res = glob_resource("keyconfig/*.cfg", RESOURCE_THEME);
	return res;
end

