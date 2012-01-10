-- Ledconf.lua
----------------------------------------------------------
-- includable by any theme
-- closely tied to keyconf.lua in the sense that it uses
-- the same sort of "label->..." mapping although it also
-- assumes certain patterns to the LEDs in question to be
-- able to go from a control-mask and toggle the right
-- LEDs.
--
-- There is some potential for expansion here,
-- particularly animation / attract-mode /
-- highlight-when-pushed (or perhaps even something more
-- esoteric like hooking LED- up to internal- launch
-- target memory value ;-)
--
-- [LABEL] => ctrlid:ledid
----------------------------------------------------------

local function ledconf_config(self, labels)
	self.table = {};
	self.labels = labels;
	self.config = true;

	self.ctrlval = 0;
	self.groupid = 0;
	self.ledval = 0;

	self.windowvid = fill_surface( 32, 32, 0, 0, 254);

	local w = VRESW * 0.3;
	local h = VRESH * 0.3;
	resize_image(self.windowvid, w, h, NOW);
	move_image(self.windowvid, VRESW * 0.5 - (w * 0.5), VRESH * 0.5 - (h * 0.5), NOW);
	order_image(self.windowvid, 253);
	show_image(self.windowvid);
	
	self:nextlabel(false);
	self:drawvals();
end

local function ledconf_flush(self)
	print("time to flush to " .. self.ledfile);
	
	zap_resource(self.ledfile);
	open_rawresource(self.ledfile);
	if (write_rawresource("local ledconf = {};\n") == false) then
		print("Couldn't save ledsym.lua, check diskspace and permissions in theme folder.\n");
		close_rawresource();
		return;
	end
	
	for key, value in pairs(self.table) do
		write_rawresource( "ledconf[\"" .. key .. "\"] = {" .. value[1] .. ", " .. value[2] .. "};" );
	end
			                 
	write_rawresource("return ledconf;");
	close_rawresource();
end

local function ledconf_cleanup(self)
	if (self) then
		if (self.windowvid ~= nil and self.windowvid ~= BADID) then delete_image(self.windowvid); end
		if (self.valvid ~= nil and self.valvid ~= BADID) then delete_image(self.valvid); end
		self:flush();
		self.active = true;
	end
end

local function ledconf_nextlabel(self, store)
	if (self.active) then return false; end
	
	if (store) then
		self.table[ self.labels[ self.labelofs ] ] = { self.ctrlval, self.ledval };
	end
	
	self.labelofs = self.labelofs + 1;
	
	if (self.labelofs > # self.labels) then
		self:cleanup();
	else
		if (self.msgheader) then
			delete_image(self.msgheader);
		end
		
		self.msgheader = render_text( self.fontline .. [[Welcome to Arcan ledconf!\r\nPlease set values for label:\n\r\#00ffae]] .. self.labels[self.labelofs] ..
				[[\n\r\#ffffffCtrl:\tLed#]]);
		local props = image_surface_properties(self.msgheader);
		resize_image(self.windowvid, props.width + 10, props.height + 40);
		link_image(self.msgheader, self.windowvid);
		image_mask_clear(self.msgheader, MASK_SCALE);
		order_image(self.msgheader, 254);
		move_image(self.msgheader, 5, 5);
		show_image(self.msgheader);
		return true;
	end

	return false;
end

local function ledconf_drawvals(self)
	local msg = "";
	
	if (self.groupid == 0) then
		msg = [[\#ff0000]] .. self.fontline .. tostring(self.ctrlval) .. [[\t\#ffffff]] .. tostring(self.ledval);
	else
		msg = [[\#ffffff]] .. self.fontline .. tostring(self.ctrlval) .. [[\t\#ff0000]] .. tostring(self.ledval);
	end

	if (self.valvid ~= BADID) then
		delete_image(self.valvid);
	end

	local props = image_surface_properties(self.msgheader);
	
	self.valvid = render_text( msg );
	link_image(self.valvid, self.windowvid);
	image_clip_on(self.valvid);
	image_mask_clear(self.valvid, MASK_SCALE);
	move_image(self.valvid, 5, props.y + props.height + 5, NOW);
	order_image(self.valvid, 254);
	show_image(self.valvid);
end

local function ledconf_flush(self)
	zap_resource("ledsym.lua");
	open_rawresource("ledsym.lua");

	if (write_rawresource("local ledconf = {};\n") == false) then
	    print("Couldn't save ledsym.lua, check diskspace and permissions in theme folder.\n");
		close_rawresource();
		return;
	end

-- for key, value in pairs(keyconf_current.table) do
	for key, value in pairs(self.table) do
		write_rawresource( "ledconf[\"" .. key .. "\"] = {" .. tostring(value[1]) .. "," .. tostring(value[2]) .. "};\n" );
	end

	write_rawresource("return ledconf;");
	close_rawresource();
end

local function ledconf_value_change(self, val)
	self:set_led( self.ctrlval, self.ledval, 0);
	local lv = controller_leds( self.ctrlval );

	if (self.groupid == 0) then
		self.ctrlval = (self.ctrlval + val) % LEDCONTROLLERS;
	else
		self.ledval = (self.ledval + val) % lv;
	end
	
	self:set_led( self.ctrlval, self.ledval, 1);
	self:drawvals(self);
end

local function ledconf_set_led(self, ctrl, id, val)
	local key = tostring(ctrl) .. ":" .. tostring(id);
	if (self.ledcache[ key ] ~= nil and self.ledcache[ key ][3] ~= val) then
		self.ledcache[ key ] = {ctrl, id, val};
		set_led(ctrl, id, val);
	end
end
-- 
local function ledconf_clearall(self)
	for i=0,LEDCONTROLLERS-1 do
		j = 0;
		while j < controller_leds(i) do
			set_led(i, j, 0);
			self.ledcache[ tostring(i) .. ":" .. tostring(j) ] = {i, j, 0};
			j = j + 1;
		end
	end
end

local function ledconf_setall(self)
	for i=0,LEDCONTROLLERS-1 do
		j = 0;
		while j < controller_leds(i) do
			self.ledcache[ tostring(i) .. ":" .. tostring(j) ] = {i, j, 1};
			j = j + 1;
		end
	end
end

local function ledconf_group_change(self, val)
	self.groupid = (self.groupid + val) % 2;
	self:drawvals(self);
end

-- menu left/right, change group
-- menu up/right, change value in group
-- menu select, save current values to current label
-- menu escape, skip setting a LED for this label
local function ledconf_input(self, symlbl)
	if (self.active == true) then
		return true;
	end

	if (symlbl == "MENU_UP") then
		self:value_change(1);
	elseif (symlbl == "MENU_DOWN") then
		self:value_change(-1);
	elseif (symlbl == "MENU_LEFT") then
		self:group_change(-1);
	elseif (symlbl == "MENU_RIGHT") then
		self:group_change(1);
	elseif (symlbl == "MENU_SELECT") then
		self:nextlabel(true);
	elseif (symlbl == "MENU_ESCAPE") then
		self:nextlabel(false);
	end

	return false;
end

-- some extra work here due to possibly high latency / cost
-- for each set_led operation
function ledconf_toggle(self, players, buttons)
	if (type(players) ~= "number" or type(buttons) ~= "number") then return false; end

	local list = {};
	
	for np=1,players do
		for nb=1,buttons do
			local labelstr = "PLAYER" .. tostring(np) .. "_BUTTON" .. tostring(nb);
			local refr = self.table[ labelstr ];
			if (refr) then
				list[ tostring(refr[1]) .. ":" .. tostring(refr[2])  ] = 1;
			end
		end
	end

	for key, val in pairs( self.ledcache ) do
		if (list[key] == nil) then
			self:set_led( val[1], val[2], 0);
		else
			self:set_led( val[1], val[2], 1);
		end
	end

	return true;
end

function ledconf_create(labels)
local ledcfgtbl = {
		labelofs = 0,
		valvid = BADID,
		ledfile = "ledsym.lua",
		new = ledconf_config,
		input = ledconf_input,
		toggle = ledconf_toggle,
		nextlabel = ledconf_nextlabel,
		flush = ledconf_flush,
		cleanup = ledconf_cleanup,
		drawvals = ledconf_drawvals,
		value_change = ledconf_value_change,
		group_change = ledconf_group_change,
		setall = ledconf_setall,
		set_led = ledconf_set_led,
		clearall = ledconf_clearall,
		fontline = [[\ffonts/default.ttf,18 ]],
		ledcache = {};
	}

	for k, v in ipairs(arguments) do
		if (string.sub(v, 1, 8) == "ledname=") then
			local fn = string.sub(v, 9);
			if (string.len(fn) > 0) then
				restbl.ledfile = fn;
			end
		elseif (string.sub(v, 1, 10) == "ledlabels=") then
			local vals = string.sub(v, 11);
			if (string.len(vals) > 0) then
				for token in string.gmatch(vals, "[^,]+") do
					table.insert(labels, token);
				end
			end
		elseif (v == "forceledconf") then
		        zap_resource(ledcfgtbl.ledfile);
		end
	end

	if (resource(ledcfgtbl.ledfile)) then
		local ledsym = system_load(ledcfgtbl.ledfile);
		ledcfgtbl.table = ledsym();
		ledcfgtbl.active = true;
	elseif LEDCONTROLLERS > 0 then 
		ledcfgtbl.active = false;
		ledcfgtbl:new(labels);
	else
		ledcfgtbl.active = true;
	end

-- reset AND populate cache 
	ledcfgtbl.clearall(ledcfgtbl);
	
	return ledcfgtbl;
end
