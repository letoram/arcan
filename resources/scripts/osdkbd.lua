--
-- Text input & OSD Keyboard
--
-- Labels:
--  MENU_SELECT (input current cursor item),
--  MENU_UP, MENU_DOWN, MENU_LEFT, MENU_RIGHT (navigate),
--  MENU_ESCAPE (quick- cancel)
--  CONTEXT (hide / show keymap)
--
-- Constructor:
--  create_keymap(altmap, optionstbl) => table.
--   options in optionstbl:
--    case_insensitive (true | false)
--     keyboard_hidden (true | false)
--
-- Instance functions:
--  :show(),
--  :hide()
--  :input(label)     => nil | button,inputstr
--  :inputkey(keysym) => nil | button, inputstr
--

-- PD stack snippet
local function stack(t)
	local Stack = {
		push = function(self, ...)
			for _, v in ipairs{...} do
				self[#self+1] = v
			end
		end,

		pop = function(self, num)
			local num = num or 1
			if num > #self then
				return nil;
			end

			local ret = {}
			for i = num, 1, -1 do
				ret[#ret+1] = table.remove(self)
			end

			return unpack(ret)
		end
	}
	return setmetatable(t or {}, {__index = Stack})
end

local function gridxy(chrh, col, row)
	return ( col * chrh ), ( row * chrh );
end

local function osdkbd_input(self, label, active)
	if (active == false) then return; end

-- semantics change for input depending on if the keyboard is hidden or not
	if (self.keyboard_hidden == true and label ~= "CONTEXT") then return; end

	if     (label == "MENU_UP")     then self:steprow(-1);
	elseif (label == "MENU_DOWN")   then self:steprow(1);
	elseif (label == "MENU_LEFT")   then self:step(-1);
	elseif (label == "MENU_RIGHT")  then self:step(1);
	elseif (label == "CONTEXT")     then
		if (self.keyboard_hidden) then
			self:showkbd();
		else
			self:hidekbd();
		end
	elseif (label == "MENU_SELECT") then
		local ch = self.rows[ self.currow ][ self.curcol ];
		if (type(ch) == "string") then
			self.str = self.str .. ch;
			self:update();

		elseif (type(ch) == "table") then
			msg = ch:trigger(self, active, false);
			if (msg ~= nil) then
				ch:trigger(self, active, true);
				return msg;
			else
				self:update();
			end
		end
	end -- of select

	return nil;
end

local function osdkbd_inputkey(self, iotbl, active)
	local symname = self.symtable[ iotbl.subid ];
-- special treatment for shiftstates

	if (symname == "FIRST" or symname == nil) then symname = self.symtable[ iotbl.keysym ]; end

	if (symname == "LSHIFT" or symname == "RSHIFT") then
		self.shiftstate = active;
	end

-- special navigation characters
	if (active == false) then return; end

	if (symname == "KP_ENTER" or symname == "RETURN") then
		return self.str;

	elseif (symname == "BACKSPACE") then
		self.str = string.sub( self.str, 1, -2 );
		self:update();
		return nil;
	end
-- missing (tab for suggestions, up/down without OSD for history)
-- scan through the map to see that the character is allowed (insensitive search)
	key = symname;

	if (key) then
		if (self.shiftstate) then
			key = string.upper(key);
		end

		local mk = string.upper(key);
		found = nil

		for i=1,#self.keymap do
			if self.keymap[i] and string.upper(self.keymap[i]) == mk then
				found = i
				break
			end
		end

		if (found ~= nil) then
			self.str = self.str .. (self.case_insensitive and mk or key);
			self:update();
			return;
		end
	end

end

local function utf8forward(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
			ofs = ofs + 1;
		until (ofs > string.len(src) or utf8kind( string.byte(src, ofs) ) < 2);
	end

	return ofs;
end

local function osdkbd_update(self)
	if (self.textvid ~= BADID) then
		delete_image(self.textvid);
	end

	if (#self.str < #self.prefix) then
		self.str = self.prefix;
	end

	order = image_surface_properties(self.inputwin).order;

-- Make sure possible "overflow" fits, or scroll the window without yielding a larger input texture
	local workstr = self.str;
	local width, height = text_dimensions( [[\ffonts/default.ttf,]] .. self.inph .. [[\#ffffff]] .. string.gsub(workstr, "\\", "\\\\"));

-- need to clip..
	if (width > self.windoww) then
		workstr = ".." .. self.str;
		local baseofs = utf8forward(self.str, 1);

		while (width > self.windoww) do
			workstr = ".." .. string.sub(self.str, baseofs);
			width, height = text_dimensions( [[\ffonts/default.ttf,]] .. self.inph .. [[\#ffffff]] .. string.gsub(workstr, "\\", "\\\\") );
			baseofs = utf8forward(self.str, baseofs);
		end
	end

	local textstr = string.gsub( workstr, "\\", "\\\\" );
	self.textvid = render_text( [[\ffonts/default.ttf,]] .. self.inph .. [[\#ffffff]] .. " " .. textstr );
	link_image(self.textvid, self.window);
	order_image(self.textvid, order);
	image_clip_on(self.textvid);

	local width = image_surface_properties(self.textvid).width;

	show_image(self.textvid);
end

local function osdkbd_updatecursor(tbl, col, row)
	local lx, ly = gridxy(tbl.chrh, col, row);

-- prevent movements to stack
	instant_image_transform(tbl.cursorvid);
	move_image(tbl.cursorvid, lx, ly - 2, 5);
end

local function osdkbd_step(self, dir)
	self.curcol = self.curcol + dir;

	if (self.curcol > #self.rows[ self.currow ]) then
		self.curcol = 1;
		self:steprow(1);
		return;
	end

	if (self.curcol <= 0) then
		self:steprow(-1, true);
		self.curcol = #self.rows[ self.currow ];
	end

	self:update_cursor(self.curcol - 1, self.currow);
end

local function osdkbd_steprow(self, dir, noredraw)
	self.currow = self.currow + dir;

	if (self.currow <= 0) then
		self.currow = #self.rows;
	elseif (self.currow > #self.rows) then
		self.currow = 1;
	end

	if (self.curcol > #self.rows[ self.currow ]) then
		self.curcol = #self.rows[self.currow];
	end

	if (noredraw) then return; end

	osdkbd_updatecursor(self, self.curcol - 1, self.currow);
end

local function osdkbd_hidekbd(self)
	instant_image_transform(self.window);
	instant_image_transform(self.border);
	resize_image(self.window, self.windoww, self.chrh, 5);
	resize_image(self.border, self.borderw, self.chrh + 4, 5);
	self.keyboard_hidden = true;
end

local function osdkbd_showkbd(self)
	self.keyboard_hidden = false;
	instant_image_transform(self.window);
	instant_image_transform(self.border);
	resize_image(self.window, self.windoww, self.windowh, 5);
	resize_image(self.border, self.borderw, self.borderh, 5);
end

local function osdkbd_buildgrid(self, windw, windh)
-- render, or use existing imagery (shift-state currently ignored)
	if (self.vidrows) then
		for i=1, #self.vidrows do
			for j=1, #self.vidrows[i] do
				if (valid_vid(self.vidrows[i][j])) then delete_image(self.vidrows[i][j]); end
			end
		end
	end

	self.vidrows = {};

	for i=1, #self.rows do
		vidcol = {};

		for j=1, #self.rows[i] do
			if type(self.rows[i][j]) == "string" then
				vidcol[j] = render_text( [[\ffonts/default.ttf,]] .. self.chrh .. [[\#ffffff]] .. string.gsub(self.rows[i][j], "\\", "\\\\"));
				image_tracetag(vidcol[j], "osdkbd grid letter");
			else
				vidcol[j] = self.rows[i][j]:load(self);
				resize_image(vidcol[j], math.floor(self.chrh * 0.9), math.floor(self.chrh * 0.9));
			end

			link_image(vidcol[j], self.window);
			local x, y = gridxy( self.chrh, j - 1, i);
			local cellp = image_surface_properties(vidcol[j]);

-- center in grid square
			move_image(vidcol[j], math.floor(x + 0.5 * (self.chrh - cellp.width)), math.floor(y + 2));
			show_image(vidcol[j]);
			image_clip_on(vidcol[j]);
			order_image(vidcol[j], max_current_image_order());
		end

		table.insert(self.vidrows, vidcol);
	end
end

local function osdkbd_buildform(self, windw, windh)
-- calculate how many buttons per column and how many rows, output text in first row
	local ctb = settings.colourtable; -- where's the "using" clause when needed ..

	self.anchor = fill_surface(1, 1, 0, 0, 0);
	image_tracetag(self.anchor, "osdkbd anchor");

-- will resize these later based on the button grid
	self.window = fill_surface(1, 1, ctb.dialog_window.r, ctb.dialog_window.g, ctb.dialog_window.b);
	image_tracetag(self.window, "osdkbd window");

	self.border = fill_surface(1, 1, ctb.dialog_border.r, ctb.dialog_border.g, ctb.dialog_border.b);
	image_tracetag(self.border, "osdkbd border");

-- we link everything to anchor for cleanup
	link_image(self.border, self.anchor);
	link_image(self.window, self.anchor);
	show_image(self.window);
	show_image(self.border);

	local rowh = windh / (#self.rows + 2);
	local roww = windw / (self.colmax + 2);
	self.windw = windw;
	self.windh = windh;
	self.chrh = math.floor( rowh > roww and roww or rowh );
	self.inph  = math.floor(self.chrh * 0.7);

	move_image(self.window, 3, 3);

	self.chrh = self.chrh - (self.chrh % 2);

	osdkbd_buildgrid(self, windw, windh);

	self.borderw = math.floor(self.chrh * self.colmax + 12);
	self.borderh = math.floor(self.chrh + self.chrh * (#self.rows) + 12);
	self.windoww = self.borderw - 8;
	self.windowh = self.borderh - 8;

	resize_image(self.border, self.borderw, self.borderh);
	resize_image(self.window, self.windoww, self.windowh);

	self.inputwin  = fill_surface(self.windoww, self.chrh, 0.5 * ctb.dialog_window.r, 0.5 * ctb.dialog_window.g, 0.5 * ctb.dialog_window.b);
	self.cursorvid = fill_surface(self.chrh, self.chrh, ctb.dialog_cursor.r, ctb.dialog_cursor.g, ctb.dialog_cursor.b);

	link_image(self.inputwin, self.window);
	link_image(self.cursorvid, self.window);

	image_clip_on(self.cursorvid);

-- won't show until :show is invoked anyhow as window inherits from anchor
	show_image(self.inputwin);
	blend_image(self.cursorvid, settings.colourtable.dialog_cursor.a);

-- center (the user is free to move this anchor however .. )
	move_image(self.anchor, math.floor(0.5 * (VRESW - self.windoww)), math.floor(0.5 * (VRESH - self.windowh)));
end

local function osdkbd_show(self)
	self:update_cursor(self.curcol - 1, self.currow);
	self:update();

	blend_image(self.anchor, 1.0, 5);
	order_image(self.anchor, 0);
	order_image(self.border, max_current_image_order() + 1);

	local base = max_current_image_order();
	order_image(self.window, base);
	order_image(self.cursorvid, base);
	order_image(self.inputwin, base);
	if (self.textvid and self.textvid ~= BADID) then
		order_image(self.textvid, base);
	end

	local itemorder = base + 1;
	for i=1, #self.vidrows do
		for j=1, #self.vidrows[i] do
			local vid = self.vidrows[i][j];
			if (vid ~= nil and vid ~= BADID) then
				order_image(vid, itemorder);
			end
		end
	end

end

local function osdkbd_destroy(self)
-- everything else should be linked living already
	delete_image(self.anchor);
end

local function osdkbd_hide(self)
	blend_image(self.anchor, 0.0, 5);
end

function osdkbd_extended_table()
	return {
	"A", "B", "C", "D", "E", "F", "G", "1", "2", "3", ":", "\n", -- SHIFT
	"H", "I", "J", "K", "L", "M", "N", "4", "5", "6", ";", "\n", -- ERASE
	"O", "P", "Q", "R", "S", "T", "U", "7", "8", "9", "_", "\n", -- OK
	"V", "W", "X", "Y", "Z", " ", "%", ",", "0", ".", "-", "\n",
	"/", "\"", "?", "!", "$", "&", ")", "="};
end

function osdkbd_restricted_table()
	return {
	"A", "B", "C", "D", "E", "F", "G", "1", "2", "3", "\n", -- SHIFT
	"H", "I", "J", "K", "L", "M", "N", "4", "5", "6", "\n", -- ERASE
	"O", "P", "Q", "R", "S", "T", "U", "7", "8", "9", "\n", -- OK
	"V", "W", "X", "Y", "Z", " ", "%", "-", "0", "_", "\n" };
end

function osdkbd_alphanum_table()
	return {
	"A", "B", "C", "D", "E", "F", "G", "1", "2", "3", "\n", -- SHIFT
	"H", "I", "J", "K", "L", "M", "N", "4", "5", "6", "\n", -- ERASE
	"O", "P", "Q", "R", "S", "T", "U", "7", "8", "9", "\n", -- OK
	"V", "W", "X", "Y", "Z", " ", nil, "-", "0", "_", "\n" };
end

function osdkbd_create(map, opts)
	local restbl = {
		cursor = 0,
		str = "",
		textvid = BADID,
		curcol = 1,
		currow = 1
	};

	if (not opts) then
		opts = {}
	end

	if (map) then
		restbl.keymap = map;
	else
		restbl.keymap = osdkbd_restricted_table();
	end

-- make sure global settings are in place
	if (settings == nil) then
		settings = {};
	end

	if (settings.colourtable == nil) then
		settings.colourtable = system_load("scripts/colourtable.lua")();
	end

	local rows  = {};
	local crow  = {};

	local maxcol = 0;
	if (opts.case_insensitive == nil or opts.case_insensitive == true) then
		restbl.case_insensitive = true;
	else
		restbl.case_insensitive = false;
	end

-- need a local copy of the keysym <=> character mapping table
	restbl.symtable    = system_load("scripts/symtable.lua")();

-- as well as some indicator images, will not always be used.
	local imgs = stack();

	oktbl = {};
	oktbl.load = function(self, parent)
		local res = load_image("images/icons/ok.png");
		force_image_blend(res);
		return res;
	end

	oktbl.trigger = function(self, parent, active, cleanup)
		return parent.str;
	end
	imgs:push(oktbl);

	local erasetbl = {};

	erasetbl.load = function(self, parent)
		local res = load_image("images/icons/remove.png");
		force_image_blend(res);
		return res;
	end

	erasetbl.trigger = function(self, parent, active, cleanup)
		if (cleanup) then delete_image(self.image); end

		parent.str = string.sub(parent.str, 1, -2);
		return nil;
	end
	imgs:push(erasetbl);

	if (restbl.case_insensitive == false) then
		local shifttbl = {};
		restbl.uppercase = true;

		shifttbl.load = function(self, parent)
			local res = parent.uppercase and load_image("images/icons/osd_shift_down.png") or load_image("images/icons/osd_shift_up.png");
			force_image_blend(res);
			return res;
		end

		shifttbl.trigger = function(self, parent, active, cleanup)
			if (cleanup) then delete_image(self.image); end

-- switch the case for all entries in osdkbd
			for i=1, #parent.rows do
				vidcol = {};

				for j=1, #parent.rows[i] do
					if type(parent.rows[i][j]) == "string" then
						parent.rows[i][j] = parent.uppercase and string.lower(parent.rows[i][j]) or string.upper(parent.rows[i][j]);
					end
				end
			end

-- free and replace with a new grid
			parent.uppercase = not parent.uppercase;
			osdkbd_buildgrid(parent, parent.windw, parent.windh);
		end

		imgs:push(shifttbl);
	end

-- split the keymap into rows, note how wide the widest one is,
-- and split the "special" keys along the right side
	for i=1,#restbl.keymap do
		if (restbl.keymap[i] == "\n") then
			local num = imgs:pop();
			if (num) then
				table.insert(crow, num);
			end

			if (#crow > maxcol) then maxcol = #crow; end

			table.insert(rows, crow);
			crow = {};
		else
			table.insert(crow, restbl.keymap[i]);
		end
	end

	if (#crow > 0) then
		table.insert(rows, crow);
	end

-- empty keymap? do nothing
	if (maxcol == 0) then
		return nil;
	end

-- prepare the rest of the table
	restbl.shift_state       = false;
	restbl.keyboard_hidden   = false;
	restbl.button_background = keymap_buttonbg;

	if (opts.prefix) then
		restbl.prefix = opts.prefix;
		restbl.str = opts.prefix;
	else
		restbl.prefix = "";
	end

	if (opts.startstr) then
		restbl.str = opts.startstr;
	end

	restbl.input_key     = osdkbd_inputkey;
	restbl.update_cursor = osdkbd_updatecursor;

	restbl.input   = osdkbd_input;
	restbl.rows    = rows;
	restbl.colmax  = maxcol;
	restbl.show    = osdkbd_show;
	restbl.hide    = osdkbd_hide;
	restbl.hidekbd = osdkbd_hidekbd;
	restbl.showkbd = osdkbd_showkbd;
	restbl.update  = osdkbd_update;
	restbl.step    = osdkbd_step;
	restbl.steprow = osdkbd_steprow;
	restbl.destroy = osdkbd_destroy;

	restbl.col = 1;

-- lastly, populate the grid with synthesized images
	osdkbd_buildform(restbl, VRESW, VRESH);
	if (restbl.keyboard_hidden) then
		restbl:hidekbd();
	end

	return restbl;
end