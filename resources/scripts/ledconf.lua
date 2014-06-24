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
-- suggested changes currently not covered include
-- moving the labels from a sequence to a user controlled field,
-- so that if the LABEL group is selected (menu_left/right) you
-- can go back and change an old label or more quickly skip.
--
-- [LABEL] => ctrlid:ledid
----------------------------------------------------------

local function ledconf_destroy(self)
	expire_image(self.window, 20);
	blend_image(self.window, 0.0, 20);
	expire_image(self.border, 20);
	blend_image(self.border, 0.0, 20);
	expire_image(self.anchor, 20);

if (self.msgheader and self.msgheader ~= BADID) then
	delete_image(self.msgheader);
	delete_image(self.valvid);
end

	self.active = true;
	self:flush();
end

local function ledconf_new(self, labels)
	self.table = {};
	self.labels = labels;
	table.sort(self.labels);

	self.config = true;
	self.anchor = fill_surface(1, 1, 0, 0, 0);
	move_image(self.anchor, -1, -1);

	self.border = fill_surface(VRESW * 0.33 + 6, VRESH * 0.33 + 6, settings.colourtable.dialog_border.r, settings.colourtable.dialog_border.g, settings.colourtable.dialog_border.b );
	self.window = fill_surface(VRESW * 0.33, VRESH * 0.33, settings.colourtable.dialog_window.r, settings.colourtable.dialog_window.g, settings.colourtable.dialog_window.b );

	link_image(self.border, self.anchor);
	link_image(self.window, self.anchor);
	blend_image(self.anchor, 1.0, 15);
	blend_image(self.border, settings.colourtable.dialog_border.a);
	blend_image(self.window, settings.colourtable.dialog_window.a);
	order_image(self.anchor, 0);
	move_image(self.window, 3, 3);

	self.ctrlval = 0;
	self.groupid = 0;
	self.ledval = 0;

	self:nextlabel(false);
	self:drawvals();

	order_image(self.border, max_current_image_order());
	order_image(self.window, max_current_image_order() + 1);
	order_image(self.msgheader, max_current_image_order());
	order_image(self.valvid, max_current_image_order());
end

local function ledconf_flush(self)
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

local function ledconf_nextlabel(self, store)
	if (self.active) then return false; end

	if (store) then
		self.table[ self.labels[ self.labelofs ] ] = { self.ctrlval, self.ledval };
	end

	self.labelofs = self.labelofs + 1;

	if (self.labelofs > # self.labels) then
		self:destroy();
	else
		if (self.msgheader) then
			delete_image(self.msgheader);
		end

		self.msgheader = render_text( settings.colourtable.fontstr .. [[Welcome to LEDconf!\r\nPlease set values for label:\n\r\#00ffae]] .. self.labels[self.labelofs] ..
				[[\n\r\#ffffffCtrl:\tLed#]]);
		local props = image_surface_properties(self.msgheader);

		resize_image(self.window, props.width + 10, props.height + 40);
		resize_image(self.border, props.width + 16, props.height + 46);

		link_image(self.msgheader, self.window);
		image_mask_clear(self.msgheader, MASK_SCALE);
		image_mask_clear(self.msgheader, MASK_OPACITY);
		order_image(self.msgheader,image_surface_properties(self.window).order + 1);
		move_image(self.msgheader, 5, 5);
		show_image(self.msgheader);

		move_image(self.anchor, VRESW * 0.5 - props.width * 0.5, VRESH * 0.5 - (props.height + 10) * 0.5, 0);
		return true;
	end

	return false;
end

local function ledconf_drawvals(self)
	local msg = "";

	if (self.groupid == 0) then
		msg = settings.colourtable.fontstr .. [[\#ff0000]] .. tostring(self.ctrlval) .. [[\t\#ffffff]] .. tostring(self.ledval);
	else
		msg = settings.colourtable.fontstr .. [[\#ffffff]] .. tostring(self.ctrlval) .. [[\t\#ff0000]] .. tostring(self.ledval);
	end

	if (self.valvid ~= BADID) then
		delete_image(self.valvid);
	end

	local props = image_surface_properties(self.msgheader);

	self.valvid = render_text( msg );
	link_image(self.valvid, self.window);
	image_clip_on(self.valvid);
	image_mask_clear(self.valvid, MASK_SCALE);
	move_image(self.valvid, 5, props.y + props.height + 5, NOW);
	order_image(self.valvid, props.order);
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

local function ledconf_set_led_label(self, label, active)
		local val = self.table and self.table[label] or nil
		if (val) then
			self:set_led(val[1], val[2], active and 1 or 0);
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
			set_led(i, j, 1);
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
		return not self:nextlabel(true);
	elseif (symlbl == "MENU_ESCAPE") then
		return not self:nextlabel(false);
	end

	return false;
end

function ledconf_listtoggle(self, labellist)
	if (self.table == nil) then
		return false;
	end

	list = {};

	for key, val in pairs(labellist) do
		local refr = self.table[ val ];
		if (refr) then
			list[ tostring(refr[1]) .. ":" .. tostring(refr[2]) ] = 1;
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

-- some extra work here due to possibly high latency / cost
-- for each set_led operation
function ledconf_toggle(self, players, buttons)
	if (type(players) ~= "number" or type(buttons) ~= "number") then return false; end

	local list = {};

	for np=1,players do
		for nb=1,buttons do
			local labelstr = "PLAYER" .. tostring(np) .. "_BUTTON" .. tostring(nb);
			table.insert(list, labelstr);
		end
	end

	return self:listtoggle(list);
end

function ledconf_create(labels)
local ledcfgtbl = {
		labelofs = 0,
		valvid = BADID,
		ledfile = "ledsym.lua",
		new = ledconf_new,
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
		set_led_label = ledconf_set_led_label,
		clearall = ledconf_clearall,
		listtoggle = ledconf_listtoggle,
		destroy = ledconf_destroy,
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
		ledcfgtbl:clearall();
	else
		ledcfgtbl.active = true;
	end

	return ledcfgtbl;
end
