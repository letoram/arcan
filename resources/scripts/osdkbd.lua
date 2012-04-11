-- multiple interface on-screen keyboard
-- labels used for input: MENU_SELECT, MENU_UP, MENU_DOWN, MENU_LEFT, MENU_RIGHT, MENU_ESCAPE 
-- usage:
--  create_keymap() => table.
--  table:show(),
--   table:input(label) => nil or button + inputstr
--   table:inputkey(char) => nil
--


local keymap = {  
	"A", "B", "C", "D", "E", "F", "G", "1", "2", "3", "\n",
	"H", "I", "J", "K", "L", "M", "N", "4", "5", "6", "\n",
	"O", "P", "Q", "R", "S", "T", "U", "7", "8", "9", "\n",
	"V", "W", "X", "Y", "Z", " ", "%", "0" };

local function gridxy(chrh, col, row)
	return ( col * chrh ), ( row * chrh );
end
	
local function osdkbd_input(self, label)
	if (label == "MENU_UP") then self:steprow(-1);
elseif (label == "MENU_DOWN") then self:steprow(1);
elseif (label == "MENU_LEFT") then self:step(-1);
elseif (label == "MENU_RIGHT") then self:step(1);
elseif (label == "MENU_SELECT") then
	local ch = self.rows[ self.currow ][ self.curcol ];
	if (type(ch) == "string") then
		self.str = self.str .. ch;
		self:update();
	else
		-- specials, for customized icons we'd need another table for this
		-- for now, we hardhack it (that won't pass in the future though)
		if (self.currow == #self.rows) then
			if (self.curcol == #self.rows[ #self.rows ]) then -- select
				return self.str;
		else
				self.str = string.sub( self.str, 1, -2 );
				self:update();
			end
		end
	end
end
	return nil;
end

local function osdkbd_inputkey(self, iotbl)
	local key = self.symtable.tochar( iotbl.keysym );
	local msg = self.symtable[ iotbl.keysym ];
	
	if (key) then
		if (string.len(key) == 1) then
			self.str = self.str .. string.upper(key);
			self:update();
			return;
		end
	end

	if (msg == "BACKSPACE") then
		self.str = string.sub( self.str, 1, -2 );
		self:update();
	elseif (msg == "RETURN" or msg == "KP_ENTER") then
		return self.str;
	end

	return nil;
end

local function osdkbd_update(self)
	if (self.textvid ~= BADID) then delete_image(self.textvid); end
	self.textvid = render_text( [[\ffonts/default.ttf,]] .. self.chrh .. [[\#ffffff]] .. self.str);
	link_image(self.textvid, self.window);
	order_image(self.textvid, self.order + 2);
	image_clip_on(self.textvid);
	show_image(self.textvid);
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

	instant_image_transform(self.cursorvid);
	local x,y = gridxy( self.chrh, self.curcol - 1, self.currow );
	move_image(self.cursorvid, x, y, 5); 
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
	
	instant_image_transform(self.cursorvid);
	local x,y = gridxy( self.chrh, self.curcol - 1, self.currow );
	move_image(self.cursorvid, x, y, 5); 
end

local function osdkbd_buildgrid(self, windw, windh)
-- calculate how many buttons per column and how many rows,
-- output text in first row, control button in last

	self.anchor = fill_surface(1, 1, 0, 0, 0);
	self.window = fill_surface(windw - 8, windh - 8, 0, 0, 128);
	self.border = fill_surface(windw, windh, 0, 0, 164);

	link_image(self.border, self.anchor);
	link_image(self.window, self.anchor);
	
	image_mask_clear(self.border, MASK_SCALE);
	image_mask_clear(self.border, MASK_OPACITY);
	image_mask_clear(self.window, MASK_SCALE);
	image_mask_clear(self.window, MASK_OPACITY);

	local rowh = windh / (#self.rows + 2);
	local roww = windw / (self.colmax + 2);
	local chrh = math.floor( rowh > roww and roww or rowh );
	local vido = max_current_image_order() + 1;
	self.order = vido;
	
	order_image(self.border, vido);
	order_image(self.window, vido+1);

	local prop = image_surface_properties(self.border);
	
	move_image(self.window, 4, 4);

	self.chrh = chrh - (chrh % 2);

	self.vidrows = {};
	for i=1, #self.rows do
		vidcol = {};
		
		for j=1, #self.rows[i] do
			if type(self.rows[i][j]) == "string" then
				vidcol[j] = render_text( [[\ffonts/default.ttf,]] .. chrh .. [[\#ffffff]] .. self.rows[i][j]);
			else
				vidcol[j] = self.rows[i][j];
				local props = image_surface_properties( vidcol[j] );
				resize_image(vidcol[j], self.chrh * 0.9, self.chrh * 0.9);
			end

			link_image(vidcol[j], self.window);
			local x, y = gridxy( self.chrh, j - 1, i);
			move_image(vidcol[j], x, y);
			show_image(vidcol[j]);
			order_image(vidcol[j], vido+3);
		end

		table.insert(self.vidrows, vidcol);
	end

	resize_image(self.border, chrh * self.colmax + 12, chrh + chrh * (#self.rows) + 12);
	resize_image(self.window, chrh * self.colmax + 4, chrh + chrh * (#self.rows) + 4);
	local props = image_surface_properties(self.border);
	
	self.inputwin  = fill_surface(chrh * self.colmax + 4, chrh - 4, 0, 0, 64);
	self.cursorvid = fill_surface(chrh, chrh - 4, 255, 0, 0);
	
	link_image(self.inputwin, self.window);
	link_image(self.cursorvid, self.window);

	image_clip_on(self.cursorvid);

	order_image(self.inputwin, vido + 1);
	order_image(self.cursorvid, vido + 2);
	show_image(self.inputwin);
	show_image(self.cursorvid);
	move_image(self.anchor, VRESW * 0.5 - props.width * 0.5, VRESH * 0.5 - props.height * 0.5);
end

local function osdkbd_show(self)
	blend_image(self.window, 1.0, 5);
	blend_image(self.border, 1.0, 5);
end

local function osdkbd_hide(self)
	hide_image(self.window);
	hide_image(self.border);
end

function create_osdkbd(map)
	local restbl = {
		cursor = 0,
		str = "",
		textvid = BADID,
		curcol = 1,
		currow = 1 
	};
	
	if (map) then restbl.keymap = map else restbl.keymap = keymap; end

	rows  = {};
	crow  = {};
	maxcol = 0;
	restbl.symtable   = system_load("scripts/symtable.lua")();
	restbl.enterimage = load_image("ok.png");
	restbl.leftimage  = load_image("remove.png");
	force_image_blend(restbl.enterimage);
	force_image_blend(restbl.leftimage);
	table.insert(restbl.keymap, restbl.leftimage);
	table.insert(restbl.keymap, restbl.enterimage);

-- figure out how many rows we have, and which one is the widest
	for i=1,#restbl.keymap do
		if (restbl.keymap[i] == "\n") then
			if (#crow > maxcol) then maxcol = #crow; end
			table.insert(rows, crow); 
			crow = {};
		else
			table.insert(crow, restbl.keymap[i]);
		end
	end

	if (#crow > 0) then table.insert(rows, crow); end
	
	if (maxcol == 0) then return nil; end
	
	restbl.rows = rows;
	restbl.colmax = maxcol;
	
	restbl.button_background = keymap_buttonbg;
	restbl.border = function(self) return self.border_vid; end
	restbl.anchor = function(self) return self.anchor_vid; end
	restbl.canvas = function(self) return self.canvas_vid; end
	restbl.input  = osdkbd_input;
	restbl.input_key = osdkbd_inputkey;
	restbl.show   = osdkbd_show;
	restbl.hide   = osdkbd_hide;
	restbl.update = osdkbd_update;
	restbl.step   = osdkbd_step;
	restbl.steprow= osdkbd_steprow;

	osdkbd_buildgrid(restbl, VRESW, VRESH);
	local x,y = gridxy( restbl.chrh, restbl.curcol - 1, restbl.currow );
	move_image(restbl.cursorvid, x, y);
	osdkbd_update(restbl);
	return restbl;
end