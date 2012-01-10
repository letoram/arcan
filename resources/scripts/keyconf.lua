-- Keyconf.lua
----------------------------------------------------------
-- includable by any theme
-- will go through a table of desired mappings,
-- and associate these with input events. 
-- These can then be serialized to a file that the various tools
-- can convert to different targets (generating 
-- configurations) for external launch,
-- or used for conversion in internal launch.
-- modify the possible entries as you see fit, these are only helpers. 
----------------------------------------------------------

-- first char is directive, 
-- whitespace : optional
-- r : required
-- a : analog

local default_menu_group = {
	"rMENU_ESCAPE",
	"rMENU_UP",
	"rMENU_DOWN",
	"rMENU_LEFT",
	"rMENU_RIGHT",
	"rMENU_SELECT",
	"aCURSOR_X",
	"aCURSOR_Y"
};

-- is iterated until the player signals escape,
-- also, the pattern PLAYERN is also inserted, where N is the
-- current number of the player 
local default_player_group = {
	"rUP",
	"rDOWN",
	"rLEFT",
	"rRIGHT",
	"rSTART",
    "rCOIN1",
    " COIN2"
};

local function keyconf_renderline(self, string, size)
	if (self.textvid) then
		delete_image(self.textvid);
		self.textvid = nil;
	end

	if (size == nil) then
	    size = 18
	end

-- push to front, render text, resize window, align to current resolution 
	self.textvid = render_text([[\ffonts/default.ttf,]] .. size .. " " .. string);
	self.line = string;
	prop = image_surface_properties(self.textvid);
	resize_image(self.bgwindow, prop.width + 20, prop.height + 20, 0);
	move_image(self.bgwindow, (VRESW - (prop.width + 20)) / 2, (VRESH - (prop.height + 20)) / 2, 0);
	prop = image_surface_properties(self.bgwindow);
	move_image(self.textvid, prop.x + 10, prop.y + 10, 0);
	order_image(self.textvid, 254);
	order_image(self.bgwindow, 253);
	show_image(self.textvid);
	show_image(self.bgwindow);
end


local function keyconf_new(self)
	self.bgwindow = fill_surface(32, 32, 0, 0, 254);
	self.used = {};
	self.table = {};

	keyconf_renderline(self, [[\#ffffffWelcome to Arcan keyconfig!\r\nPlease press a button for MENU_ESCAPE (required)]], 18);
	self.label = [[Please press a button for MENU_ESCAPE (required)]];

	self.key = "MENU_ESCAPE";
	self.key_kind = "r";

	self.configlist = {}
	self.ofs = 1;
	ofs = 1;

	for i=1,#self.menu_group do
		self.configlist[ofs] = self.menu_group[i];
		ofs = ofs + 1;
	end
	
	if (self.n_players > 0) then
		for i=1,self.n_players do
			for j=1,#self.player_group do
				kind = string.sub(self.player_group[j], 1, 1);
				self.configlist[ofs] = kind .. "PLAYER" .. i .. "_" .. string.sub(self.player_group[j], 2);
				ofs = ofs + 1;
			end
		end
	end

	show_image(self.bgwindow);
end

-- query the user for the next input table,
-- true on new key
-- false otherwise

local function keyconf_next_key(self)
	self.ofs = self.ofs + 1;

	if (self.ofs <= # self.configlist) then
 
		self.key = self.configlist[self.ofs];
		self.key_kind = string.sub(self.key, 1, 1);
		self.key = string.sub(self.key, 2);

		local lbl;
	
		lbl = "(".. tostring(self.ofs) .. " / " ..tostring(# self.configlist) ..")";

		if (self.key_kind == "A" or self.key_kind == "r") then
			lbl = "(required) ";
		else
			lbl = "(optional) ";
		end

		if (self.key_kind == "a" or self.key_kind == "A") then
			lbl = lbl .. [[ Please provide input along \ione \!iaxis on an analog device for:\n\r ]] .. self.key .. [[\t 0 samples grabbed]];
			self.analog_samples = {};
		else
			lbl = lbl .. "Please press a button for " .. self.key;
		end

		self.label = lbl;
		keyconf_renderline(self, self.label );

        return false;
    else
		self:cleanup();
		self.active = true;
        return true;
    end
end

-- return the symstr that match inputtable, or nil.
local function keyconf_match(self, input, label)
	if (input == nil) then
        return nil;
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
    end

    return kv;
end

local function keyconf_tbltoid(self, inputtable)
    if (inputtable.kind == "analog") then
	return "analog:" ..inputtable.devid .. ":" .. inputtable.subid;
    end
    
    if (inputtable.translated) then
		if self.ignore_modifiers then
	    return "translated:" .. inputtable.devid .. ":" .. inputtable.keysym;
	else
	    return "translated:" .. inputtable.devid .. ":" .. inputtable.keysym .. ":" .. inputtable.modifiers;
	end
	
    else
	return "digital:" .. inputtable.devid .. ":" .. inputtable.subid;
    end
end

-- associate 
local function keyconf_set(self, inputtable)

-- forward lookup: 1..n
    local id = keyconf_tbltoid(self, inputtable);
	if (self.table[id] == nil) then
		self.table[id] = {};
    end
    
	table.insert(self.table[id], self.key);

	self.table[self.key] = id;
end

-- return true on more samples needed,
-- false otherwise.
local function keyconf_analog(self, inputtable)
    -- find which axis that is active, sample 'n' numbers
	table.insert(self.analog_samples, keyconf_tbltoid(self, inputtable));

	self.label = "(".. tostring(self.ofs) .. " / " ..tostring(# self.configlist) ..")";
	self.label = self.label .. [[ Please provide input along \ione \!iaxis on an analog device for:\n\r ]] .. self.key .. [[\t ]] .. tostring(# self.analog_samples) .. " samples grabbed (100+ needed)";

    counttable = {}

	for i=1,#self.analog_samples do
		val = counttable[ self.analog_samples[i] ] or 0;
		counttable[ self.analog_samples[i] ] = val + 1;
    end

    max = 1;
    maxkey = "not found";

    for key, value in pairs( counttable ) do
        if (value > max) then
           max = value;
           maxkey = key;
        end
    end

	self.label = self.label .. [[\n\r dominant device(:axis) is (]] .. maxkey .. ")";
	if ( #self.analog_samples >= 100 and maxkey == self:id(inputtable) ) then
        self:set(inputtable);
        return false;
    else
		keyconf_renderline(self, self.label );
		return true;
	end
end

local function keyconf_input(self, inputtable)
	if (self.active or self.key == nil) then
		return true;
	end
	
-- early out, MENU_ESCAPE is defined to skip labels where this is allowed,
-- meaning a keykind of ' ' or 'a'.
	if (self:match(inputtable, "MENU_ESCAPE") and inputtable.active) then
		
		if (self.key_kind == 'A' or self.key_kind == 'r') then
			self:renderline([[\#ff0000Cannot skip required keys/axes.\n\r\#ffffff]] .. self.label );
			return false;
		else
			return self:next_key();
		end
	end

-- analog inputs or just look at the 'press' part.
	if (self.key_kind == 'a' or self.key_kind == 'A') then
		if (inputtable.kind == "analog") then self:analoginput(inputtable); end
		
	elseif (inputtable.kind == "digital" and inputtable.active) then
		if (self:match(key) ~= nil) then
			print("Keyconf.lua, Notice: Button (" ..self:id(inputtable) .. ") already in use.\n");
		end

		self:set(inputtable);
		return self:next_key();
	end

	return false;
end

local function keyconf_labels(self)
	local labels = {};
	
	for key, value in pairs(self.table) do
		if string.sub(key, 1, 7) == "analog:" or
				string.sub(key, 1, 8) == "digital:" or
				string.sub(key, 1, 11) == "translated:" then
		else
			table.insert(labels, key);
		end
	end

	return labels;
end

local function keyconf_flush(self)
	zap_resource(self.keyfile);
	open_rawresource(self.keyfile);
	if (write_rawresource("local keyconf = {};\n") == false) then
		print("Couldn't save keysym.lua, check diskspace and permissions in theme folder.\n");
		close_rawresource();
		return;
    end

	for key, value in pairs(self.table) do
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

local function keyconf_running(self)
	-- returns true if there is a configure session running
	if (self == nil) then
		return false;
	else
		return true;
	end
end

local function keyconf_cleanup(self)
	if (self) then
		delete_image(self.textvid);
		delete_image(self.bgwindow);
		self.active = true;
		self:flush();
	end
end

-- set the current working table.
-- for each stored entry, set prefix if defined 
function keyconf_create(nplayers, menugroup, playergroup, keyname)
	local restbl = {
		new = keyconf_new,
		match = keyconf_match,
		renderline = keyconf_renderline,
		next_key = keyconf_next_key,
		analoginput = keyconf_analog,
		flush = keyconf_flush,
		id = keyconf_tbltoid,
		input = keyconf_input,
		cleanup = keyconf_cleanup,
		set = keyconf_set,
--
		labels = keyconf_labels,
		ignore_modifiers = true,
		n_players = nplayers,
		keyfile = keyname
	};

	local players = 0;
	local buttons = {};

	if (keyname == nil) then restbl.keyfile = "keysym.lua"; end

-- command-line overrides
	for k,v in ipairs(arguments) do
		if (string.sub(v, 1, 8) == "players=") then
			local plc = tonumber( string.sub(v, 9) );
			if (plc and plc > 0) then restbl.n_players = plc; end
		elseif (string.sub(v, 1, 8) == "buttons=") then
			local bc = tonumber( string.sub(v, 9) );
			if (bc and bc > 0) then
				for i=1,bc do
					table.insert(default_player_group, "rBUTTON" .. tostring(i));
				end
			end
		elseif (string.sub(v, 1, 8) == "keyname=") then
			local fn = string.sub(v, 9);
			if (string.len(fn) > 0) then
				restbl.keyfile = fn;
			end
		elseif (v == "forcekeyconf") then
			zap_resource(restbl.keyfile);
		end
	end
	
	restbl.menu_group = menugroup and menugroup or default_menu_group;
	restbl.player_group = playergroup and playergroup or default_player_group;
	
	if ( resource(restbl.keyfile) ) then
		symfun = system_load(restbl.keyfile);
		restbl.table = symfun();
		restbl.active = true;
	else
		restbl:new();
		restbl.active = false;
	end

	return restbl;
end
