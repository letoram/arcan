-- multiple interface on-screen keyboard
-- labels used for input: MENU_SELECT, MENU_UP, MENU_DOWN, MENU_LEFT, MENU_RIGHT, MENU_ESCAPE 
-- usage:
--  create_keymap() => table.
--  table:show(),
--   table:input(label) => nil or button + inputstr
--   table:inputkey(char) => nil
--

-- last "line" is control that won't be added
local keymap = {
	"a", "b", "c", "d", "e", "f", [[\n]],
	"g", "h", "i", "j", "k", "l", [[\n]],
	"m", "n", "o", "p", "q", "r", [[\n]],
	"s", "t", "u", "v", "w", "x", [[\n]],
	"y", "z", "0", "1", "2", "3", [[\n]],
	"4", "5", "6", "7", "8", "9",
	"*", " ", [[\n]], "enter" };

local function osdkdb_input(self, label)
	if (label == "MENU_UP") then self:move(self.npr * -1);
elseif (label == "MENU_DOWN") then self:move(self.npr);
elseif (label == "MENU_LEFT") then self:move(-1);
elseif (label == "MENU_RIGHT") then self:move(1);
elseif (label == "MENU_SELECT") then
	if (self.cursor > self.lastline) then
		return self.keymap[self.cursor], self.str;
	else
		self:inputkey( self.keymap[self.cursor] )
	end
end
end

local function osdkbd_inputkey(self, char)
	self.str = self.str .. char;
	self:update();
end

local function osdkbd_step(self, dir)
	if (#self.rows[ self.currow ] > self.curcol + dir) then
	
	self.cursor = (self.cursor + step) % #self.keymap;
	if (self.keymap[self.cursor] == [[\n]]) then
		self.cursor = step > 0 and self.cursor + 1 or self.cursor - 1
	end
end

local function osdkbd_steprow(self, dir)

end

local function osdkbd_buildgrid(w, h)
-- calculate how many buttons per column and how many rows
-- reposition output window
end
	
local function osdkbd_show(self)
	-- reorder to highest vid (border) +1 (canvas) +2 (text), +3 (cursor)
end

local function osdkbd_hide(self)
end

function create_osdkbd(map)
	local restbl = {
		cursor = 0,
	};
	
	if (map) then restbl.keymap = map else restbl.keymap = keymap; end

	rows  = {};
	crow  = 0;
	maxrow = 0; 

-- figure out how many rows we have, and which one is the widest
	for i=1,#restbl.keymap do
		if (restbl[i] == [[\n]]) then
			if (crow > maxrow) then maxrow = crow; end
			table.insert(rows, {});
			crow = 0;
		else
			rows[i].insert(restbl[i])
		end
	end

	restbl.rows = rows;
	restbl.rowmax = maxrow;
	
	
	restbl.button_background = keymap_buttonbg;
	restbl.border = function(self) return self.border_vid; end
	restbl.anchor = function(self) return self.anchor_vid; end
	restbl.canvas = function(self) return self.canvas_vid; end
	restbl.input  = osdkbd_input;
	restbl.show   = osdkbd_show;
	restbl.hide   = osdkbd_hide;

	return restbl;
end