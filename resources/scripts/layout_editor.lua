--
-- (mostly) generalized version of the layout editor
-- reused in streaming and in remote control scripts
--
-- uses; colourtable, listview support scripts
-- also requires the global symbols settings, soundmap, dispatch_push and dispatch_pop
--
-- suggestions for future changes;
--
--  (*) better mouse support (cursor to allow picking etc.)
--  (*) define shaders per object type
--  (*) explicitly specify instancing
--  (*) define transformation paths and timing
--  (*) define transition rules (switching layout based on input event)
--  (*) attach particle system to object
--  (*) more properties to change
--  (*) alternate, non-menu based interface
--  (*) linking / clipping hierarchies
--  (*) surface synthesis
--  (*) add more information to each object
--  (*) alignment grid, snap to other objects (so link objects)
--  (*) 3D positioning with collision
--  (*) Reference geometry for other 3D items (occluders, lights, ...)
--  (*) simple 3D wall/room construction and CSG
--  (*) navigation triggers (link layouts)
--  All these combined and it would become a decent sortof presentation tool as well :)
--

LAYRES_IMAGE       = 1;
LAYRES_STATIC      = 2;
LAYRES_SPECIAL     = 3; -- on-load callback will be handled externally
LAYRES_FRAMESERVER = 4; -- actual set of possible arguments are defined by the add_resource resource (function expected)
LAYRES_MODEL       = 5;
LAYRES_TEXT        = 6;
LAYRES_NAVIGATOR   = 7;

LAYRES_CONVTBL = {"image", "static", "special", "fsrv", "model", "text", "nav"};

-- list of the currently allowed modes (size, position, opacity, orientation)
local position_modes_2d       = {"position", "size", "opacity", "orientation"};
local position_modes_3d       = {"position3d", "rotate3d"};
local position_modes_text     = {"position", "size", "text_prop", "text_attrib", "orientation"};

local helplbls = {};
helplbls["position"] = {
	"Position",
	"(LEFT/RIGHT/UP/DOWN) to move",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["tile"] = {
	"Tile",
	"(LEFT/RIGHT) to increase/decrease horizontal tile factor",
	"(UP/DOWN) to increase/decrease vertical tile factor",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["position3d"] = {
	"Position (3D), Axis: 0",
	"(LEFT/RIGHT) to increase/decrease angle",
	"(UP/DOWN) to switch active axis",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["rotate3d"] = {
	"Rotate (3D), Axis: 0",
	"(LEFT/RIGHT) to increment/decrement position",
	"(UP/DOWN) to switch active axis",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["size"] = {
	"Scale",
	"(RIGHT/DOWN) to increase size",
	"(LEFT/UP) to decrease size",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["text_prop"] = {
	"Font Dimensions",
	"(UP/DOWN) to cycle font",
	"(LEFT/RIGHT) to increase/decrease character limit",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
}

helplbls["text_attrib"] = {
	"Font Properties",
	"(LEFT) toggle bold on/off",
	"(RIGHT) toggle italic on/off",
	"(DOWN) toggle color picker",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["opacity"] = {
	"Blend",
	"(LEFT/RIGHT) increase / decrease opacity",
	"(UP/DOWN) increase / decrease Z-order",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["orientation"] = {
	"Rotate",
	"(UP/DOWN) aligned step (45 deg.)",
	"(LEFT/RIGHT) increase / decrease angle",
	"(CONTEXT) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

local grid_stepx = 1;
local grid_stepy = 1;
-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end

-- traversed to root node, updating visibility for each menu on the way
function cascade_visibility(menu, val, parent)
	if (menu.parent) then
		cascade_visibility(menu.parent, val, parent);
	end

	if (val > 0.9) then
		if (parent.infowin) then
			parent.infowin:destroy();
			parent.infowin = nil;
		end
	end

	blend_image(menu.anchor, val);
	menu:push_to_front();
end

-- used in the setup/edit mode, whenever user-input changes the state of the current item
local function update_object(props)
	resize_image(props.vid, props.width, props.height);
	move_image(props.vid, props.x, props.y);
	blend_image(props.vid, props.opa);
	rotate_image(props.vid, props.ang);
	order_image(props.vid, props.zv);
	if (props.tile_h ~= 1 or props.tile_v ~= 1) then
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, props.vid);
		image_scale_txcos(props.vid, props.tile_h, props.tile_v);
	end
end

-- change the label shown
local function update_infowin(self, item)
	if (self.infowin) then
		self.infowin:destroy();
		self.infowin = nil;
	end

	local fmts = {};
	fmts[ helplbls[item.modes[self.marker]][1] ] = [[\#ffff00]];

-- used in the setup/edit/mode. Position a quadrant away from the current item, and show the appropriate help text
	self.infowin = listview_create( helplbls[item.modes[self.marker]], VRESW / 2, VRESH / 2, fmts );

	local xpos = (item.x < VRESW / 2) and (VRESW / 2) or 0;
	local ypos = (item.y < VRESH / 2) and (VRESH / 2) or 0;

	self.infowin:show();
	video_3dorder(ORDER_LAST);
	move_image(self.infowin.anchor, math.floor(xpos), math.floor(ypos));

	item:update();
end

local function update_object3d(model)
-- we keep this mostly translucent as not to occlude UI elements
	blend_image(model.vid, 0.3);
	move3d_model(model.vid, model.pos[1], model.pos[2], model.pos[3]);
	rotate3d_model(model.vid, model.ang[1], model.ang[2], model.ang[3], 0, ROTATE_ABSOLUTE);
end

local function toggle_colorpicker(vid)
	local imenu = {};
	local cellw, cellh;

	cellw = VRESW > 800 and 32 or 12;
	cellh = VRESH > 600 and 32 or 12;

	local props = image_surface_properties(vid.vid);
	local x = math.floor( VRESW * 0.5 - (8 * (cellw + 4)) );
	local y = math.floor( VRESH * 0.5 - (8 * (cellh + 4)) );

	local colpick = colpicker_new(cellw, cellh, x, y, 16, 16);
	vid.tmpcol = vid.col;
	vid.oldx = vid.x;
	vid.oldy = vid.y;
	vid.x = 0;
	vid.y = 0;
	vid:update();

	vid.owner.infowin:destroy();
	vid.owner.infowin = nil;

	imenu["MENU_LEFT"] = function()
		vid.col = colpick:step_cursor_col(-1);
		vid.invalidate = true;
		vid:update();
	end

	imenu["MENU_RIGHT"] = function()
		vid.col = colpick:step_cursor_col( 1);
		vid.invalidate = true;
		vid:update();
	end

	imenu["MENU_UP"] = function()
		vid.col = colpick:step_cursor_row(-1);
		vid.invalidate = true;
		vid:update();
	end

	imenu["MENU_DOWN"] = function()
		vid.col = colpick:step_cursor_row( 1);
		vid.invalidate = true;
		vid:update();
	end

	imenu["MENU_SELECT"] = function()
		vid.tmpcol = nil;
		vid.x = vid.oldx;
		vid.y = vid.oldy;
		vid:update();
		colpick:destroy();
		vid.invalidate = true;
		update_infowin(vid.owner, vid);
		dispatch_pop();
	end

	imenu["MENU_ESCAPE"] = function()
		vid.col = vid.tmpcol;
		imenu["MENU_SELECT"]();
	end

	dispatch_push(imenu, "layout editor (colorpicker)", nil, -1);
end

--
-- hide menus, setup input for positioning etc
-- vid is expected to respond to scale,rotate,slide,blend,rotate3d,position3d and axisstep
-- .
local function position_item(self, vid, trigger)
	cascade_visibility(current_menu, 0.0, self);
	video_3dorder(ORDER_LAST);

	local marker = 1;
	local imenu = {};

	imenu["MOUSE_X"] = function(label, tbl)
		local lbl = vid.modes[ self.marker ];
		if (tbl.samples[2] == nil or tbl.samples[2] == 0) then return; end
		if     (lbl == "size")        then vid:scale(tbl.samples[2], 0);
		elseif (lbl == "orientation") then vid:rotate(0.1 * tbl.samples[2], false);
		elseif (lbl == "position")    then vid:slide(tbl.samples[2], 0);
		elseif (lbl == "opacity")     then vid:blend(0.01 * tbl.samples[2]);
		elseif (lbl == "rotate3d")    then vid:rotate(tbl.samples[2]);
		elseif (lbl == "position3d")  then vid:slide(0.01 * tbl.samples[2]); end
	end

	imenu["MOUSE_Y"] = function(label, tbl)
		local lbl = vid.modes[ self.marker ];
		if (tbl.samples[2] == nil or tbl.samples[2] == 0) then return; end
		if     (lbl == "size")        then vid:scale(0, tbl.samples[2]);
		elseif (lbl == "position")    then vid:slide(0, tbl.samples[2]); end
	end

	imenu["MENU_LEFT"]   = function()
		local lbl = vid.modes[ self.marker ];
		if     (lbl == "size")        then vid:scale(grid_stepx * -1, 0);
		elseif (lbl == "orientation") then vid:rotate(-2, false);
		elseif (lbl == "opacity")     then vid:blend(0.1);
		elseif (lbl == "position")    then vid:slide(grid_stepx * -1, 0);
		elseif (lbl == "rotate3d")    then vid:rotate(-20);
		elseif (lbl == "position3d")  then vid:slide(-0.2);
		elseif (lbl == "text_attrib") then vid.bold = not vid.bold; vid.invalidate = true; vid:update();
		elseif (lbl == "text_prop")   then vid.maxlen = (vid.maxlen > 1) and (vid.maxlen - 1) or 1; vid.invalidate = true; vid:update();
		end
	end

	imenu["MENU_RIGHT"]  = function()
		local lbl = vid.modes[ self.marker ];
		if     (lbl == "size")        then vid:scale(grid_stepx, 0);
		elseif (lbl == "orientation") then vid:rotate(2, false);
		elseif (lbl == "opacity")     then vid:blend(-0.1);
		elseif (lbl == "position")    then vid:slide(grid_stepx, 0);
		elseif (lbl == "rotate3d")    then vid:rotate(20);
		elseif (lbl == "position3d")  then vid:slide(0.2);
		elseif (lbl == "text_attrib") then vid.italic = not vid.italic; vid.invalidate = true; vid:update();
		elseif (lbl == "text_prop")   then vid.maxlen = vid.maxlen + 1; vid.invalidate = true; vid:update();
		end
	end

	imenu["MENU_UP"]     = function()
		local lbl = vid.modes[ self.marker ];
		if     (lbl == "size")        then vid:scale(0, grid_stepy * -1);
		elseif (lbl == "orientation") then vid:rotate(-45, true);
		elseif (lbl == "opacity")     then vid:order(1);
		elseif (lbl == "position")    then vid:slide(0, grid_stepy * -1);
		elseif (lbl == "rotate3d")    then vid:axisstep(1);
		elseif (lbl == "position3d")  then vid:axisstep(1);
		elseif (lbl == "text_prop")   then vid:cyclefont(1);
		end
	end

	imenu["MENU_DOWN"]   = function()
		local lbl = vid.modes[ self.marker ];
		if     (lbl == "size")        then vid:scale(0, grid_stepy);
		elseif (lbl == "orientation") then vid:rotate(45, true);
		elseif (lbl == "opacity")     then vid:order(-1);
		elseif (lbl == "position")    then vid:slide(0, grid_stepy);
		elseif (lbl == "rotate3d")    then vid:axisstep(-1); update_infowin(self, vid);
		elseif (lbl == "position3d")  then vid:axisstep(-1); update_infowin(self, vid);
		elseif (lbl == "text_prop")   then vid:cyclefont(-1);
		elseif (lbl == "text_attrib") then toggle_colorpicker(vid);
		end
	end

	imenu["MENU_ESCAPE"] = function() toggle_mouse_grab(MOUSE_GRABOFF); trigger(false, vid); end
	imenu["CONTEXT"]     = function()
		self.invalidate = true;
		self.marker = self.marker + 1 > #vid.modes and 1 or (self.marker + 1);
		update_infowin(self, vid);
	end
	imenu["MENU_SELECT"] = function() toggle_mouse_grab(MOUSE_GRABOFF); trigger(true, vid);  end

	self.marker = 1;

	toggle_mouse_grab(MOUSE_GRABON);
	dispatch_push(imenu, "customview (position)", nil, -1);
	update_infowin(self, vid);
end

local function gen_modify_menu(self, mod)
	local dstfun;
	local lbls = {};
	local ptrs = {};

	for ind, tbl in ipairs(self.items) do
		if (tbl ~= nil) then
			local lbl = string.format("(%d)%s:%4s", ind, LAYRES_CONVTBL[tbl.kind], tbl.res);
			table.insert(lbls, lbl);
			if (mod) then
				ptrs[lbl] = function()
					if (valid_vid(tbl.vid)) then
						self:position(tbl, function()
							video_3dorder(ORDER_NONE);
							dispatch_pop();
							cascade_visibility(current_menu, 1.0, self); settings.iodispatch["MENU_ESCAPE"]();
						end);
					end
				end
			else
-- can rely on remove as the escape forces the menu to be rebuilt with new functions
				ptrs[lbl] = function()
					if (valid_vid(self.items[ind].vid)) then
						delete_image(self.items[ind].vid);
					end

					table.remove(self.items, ind);
					settings.iodispatch["MENU_ESCAPE"]();
				end
			end

		end
	end

	fmts = {};
	menu_spawnmenu(lbls, ptrs, fmts);
end

local function cancel_quit(self, status)
	while current_menu ~= nil do
		local last = current_menu;
		current_menu:destroy();
		current_menu = current_menu.parent;
	end

	for ind, val in ipairs(self.items) do
		if (valid_vid(val.vid)) then
			delete_image(val.vid);
			val.vid = nil;
		end
	end

	self.items = nil;
	dispatch_pop();

	if (self.finalizer ~= nil) then
		self.finalizer(status);
	end

end

local function place_item( vid, tbl )
	local x = math.floor(tbl.x     * VRESW);
	local y = math.floor(tbl.y     * VRESH);
	local w = math.floor(tbl.width * VRESW);
	local h = math.floor(tbl.height* VRESH);

  move_image(vid, x, y);
	rotate_image(vid, tbl.ang);
	resize_image(vid, w, h);
	order_image(vid, tbl.order);
	blend_image(vid, tbl.opa);
end

local function show(self)
	if (current_menu) then
		current_menu:destroy();
		if (dispatch_current().name == "layout editor") then
			dispatch_pop();
		end
	end

-- sweep groups and build a menu based on that, this is a two-tier hierarchical menu
	local mainlbls = {};
	local mainptrs = {};

	for key, val in pairs(self.groups) do
		if key ~= "_default" then
			local newlbls = {};
			local newptrs = {};

			for ind, lbl in ipairs(val.labels) do
				table.insert(newlbls, lbl);
				newptrs[lbl] = val.ptrs[lbl];
			end

			add_submenu(mainlbls, mainptrs, key, " ", newlbls, newptrs, {});
		else
			for ind, lbl in ipairs(self.groups["_default"].labels) do
				table.insert(mainlbls, lbl);
				mainptrs[lbl] = self.groups["_default"].ptrs[lbl];
			end
		end
	end

	table.insert(mainlbls, "----------");
	table.insert(mainlbls, "Modify...");
	table.insert(mainlbls, "Delete...");
	table.insert(mainlbls, "Action...");

	mainptrs["Modify..."] = function() gen_modify_menu(self, true); end
	mainptrs["Delete..."] = function() gen_modify_menu(self, false); end
	mainptrs["Action..."] = function()
		local have_sq = true;

		if (self.validation_hook ~= nil) then
			have_sq = self:validation_hook();
		end

		local lbls = nil;
		if (have_sq) then
			lbls = {"Save/Quit", "Cancel"};
		else
			lbls = {"Cancel"};
		end

		local ptrs = {};
		ptrs["Save/Quit"] = function() self:store(); cancel_quit(self, true ); end
		ptrs["Cancel"]    = function()               cancel_quit(self, false); end
		menu_spawnmenu(lbls, ptrs, {});
	end

	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu:show();
	move_image(current_menu.anchor, 10, math.floor(VRESH * 0.1));
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;
	self.root_menu = self.current_menu;

	local imenu = {};
	menu_defaultdispatch(imenu);
	local escape_menu = function(label, save, sound)
		if (current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
			if (sound == nil or sound == false) then
				play_audio(soundmap["MENU_FADE"]);
			end
		end
	end

	imenu["MENU_LEFT"]   = escape_menu;
	imenu["MENU_ESCAPE"] = escape_menu;

	dispatch_push(imenu, "layout editor", nil, -1);
end

local function save(self)
	local fname = self.layname;

	if (resource(fname)) then
		zap_resource(fname);
	end

	open_rawresource(fname);
	write_rawresource("local layout = {};\n");
	write_rawresource(string.format("layout.orig_w = %d;\n", VRESW));
	write_rawresource(string.format("layout.orig_h = %d;\n", VRESH));

	write_rawresource("layout.types = {};\n");
	for ind, val in ipairs(LAYRES_CONVTBL) do
		write_rawresource("layout.types[\"" .. val .. "\"] = {};\n");
	end

	for ind, val in ipairs(self.items) do
		val:store();
	end

	write_rawresource("return layout;\n");
	close_rawresource();
end

local function rotate(self, ang, align)
	self.ang = self.ang + ang;

	if (align) then
		local rest = self.ang % 45;
		self.ang = (rest > 22.5) and (self.ang - rest) or (self.ang + rest);
	end

	self:update();
end

local function scale(self, dx, dy)
	self.width  = self.width  + dx;
	self.height = self.height + dy;

	if (self.width <= 0) then
		self.width = 1;
	end

	if (self.height <= 0) then
		self.height = 1;
	end

	self:update();
end

local function order(self, step)
	self.zv = self.zv + step;
	if (self.zv < 1) then
		self.zv = 1;
	end

	self:update();
end

local function slide(self, dx, dy)
	self.x = self.x + dx;
	self.y = self.y + dy;

-- constrain against window borders
	local props = image_surface_properties(self.vid);
	if (self.x >= VRESW) then
		self.x = VRESW - 1;
	end

	if (self.y >= VRESH) then
		self.y = VRESH - 1;
	end

	if (self.x + props.width < 0) then
		self.x = -props.width + 1;
	end

	if (self.y + props.height < 0) then
		self.y = -props.height + 1;
	end

	self:update();
end

local function blend(self, d_opa)
	self.opa = self.opa + d_opa;
	if (self.opa < 0.01) then self.opa = 0.01; end
	if (self.opa > 1.0 ) then self.opa = 1.0; end

	self:update();
end

local function rotate3d(self, step)
	self.ang[ self.axis ] = self.ang[ self.axis ] + step;
	self:update();
end

local function slide3d(self, step)
	self.pos[ self.axis ] = self.pos[ self.axis ] + step;
	self:update();
end

local function axisstep(self, step)
	self.axis = self.axis + step;

	if (self.axis < 1) then
		self.axis = 3;
	elseif (self.axis > 3) then
		self.axis = 1;
	end

	helplbls["position3d"][1] = "Position (3D), Axis: " .. tostring(self.axis);
	helplbls["rotate3d"][1]   = "Rotate (3D), Rotate: " .. tostring(self.axis);
	self:update();
end

local function new_3ditem(restbl)
	restbl.blend  = blend;
	restbl.scale  = scale;
	restbl.rotate = rotate3d;
	restbl.slide  = slide3d;
	restbl.update = update_object3d;
	restbl.modes  = position_modes_3d;
	restbl.axisstep = axisstep;

	show_image(restbl.vid);

	restbl.store = function(self)
		write_rawresource("local itbl = {};\n");
		write_rawresource(string.format("itbl.res  = \"%s\";\n", self.res));
		write_rawresource(string.format("itbl.type = \"%s\";\n", LAYRES_CONVTBL[self.kind]));
		write_rawresource(string.format("itbl.pos  = {%f, %f, %f};\n", self.pos[1], self.pos[2], self.pos[3]));
		write_rawresource(string.format("itbl.opa  = %d;\n", self.opa));
		write_rawresource(string.format("itbl.zv   = %d;\n", self.zv));
		write_rawresource(string.format("itbl.ang  = {%f, %f, %f};\n", self.ang[1], self.ang[2], self.ang[3]));
		write_rawresource(string.format("itbl.dirlight = {%f, %f, %f};\n", self.dirlight[1], self.dirlight[2], self.dirlight[3]));
		write_rawresource(string.format("itbl.ambient  = {%f, %f, %f};\n", self.ambient[1], self.ambient[2], self.ambient[3]));
		write_rawresource(string.format("itbl.diffuse  = {%f, %f, %f};\n", self.diffuse[1], self.diffuse[2], self.diffuse[3]));
		write_rawresource(string.format("itbl.idtag = \"%s\";", self.idtag));
		write_rawresource(string.format("if (layout[\"%s\"] == nil) then layout[\"%s\"] = {}; end\n", self.idtag, self.idtag));
		write_rawresource(string.format("table.insert(layout[\"%s\"], itbl);\n", self.idtag));
		write_rawresource("table.insert(layout.types[itbl.type], itbl);\n");
	end

	restbl.dirlight = {1.0, 0.0, 0.0};
	restbl.ambient  = {0.3, 0.3, 0.3};
	restbl.diffuse  = {0.3, 0.3, 0.3};
	restbl.ang  = {0.0,  0.0,  0.0};
	restbl.pos  = {-1.0, 0.0, -4.0};
	restbl.x    = 0;
	restbl.y    = 0;
	restbl.axis = 1;
	restbl.opa  = 1.0;

	return restbl;
end

local function textitem_update(vtbl)
	local msg = vtbl.caption;

-- render_text is extremely costly, avoid if not necessary
	if (vtbl.invalidate) then
		delete_image(vtbl.vid);

		local msg = string.sub(vtbl.caption, 1, vtbl.maxlen);

		if (string.len(msg) < vtbl.maxlen) then
			local blockch = "_";

			local ntc = vtbl.maxlen - string.len(msg);
			for i=1,ntc do
				msg = msg .. blockch;
			end
		end

		local fontstr = vtbl:fontstr(msg);

		vtbl.vid = render_text(fontstr);
		local props = image_surface_properties(vtbl.vid);
		vtbl.width = props.width;
		vtbl.height = props.height;
		vtbl.invalidate = false;
	end

	update_object(vtbl);
end

local function scaletext(self, stepx, stepy)
	if (stepx > 0) then
		self.fontsz = self.fontsz + 1;
	else
		self.fontsz = self.fontsz - 1;
		if (self.fontsz < 8) then
			self.fontsz = 8;
		end
	end

	self.invalidate = true;
	self:update();
end

local function textitem_cycle(self, step)
	self.owner.fontind = self.owner.fontind + step;

	if (self.owner.fontind < 1) then self.owner.fontind = #self.owner.fontlist; end
	if (self.owner.fontind > #self.owner.fontlist) then self.owner.fontind = 1; end

	self.invalidate = true;
	self.font = self.owner.fontlist[self.owner.fontind];
	self:update();
end

local function new_textitem(msg, parent)
	local restbl = {
		owner = parent,
		rotate = rotate,
		blend  = blend,
		order  = order,
		slide  = slide,
		scale  = scaletext,
		update = textitem_update,
		cyclefont = textitem_cycle,
		maxlen = 20,
		bold   = false,
		italic = false,
		caption = msg,
		modes = position_modes_text,
		opa = 1.0,
		ang = 0,
		tile_h = 1,
		tile_v = 1,
		fontind = 1,
		fontsz  = 24,
		zv = 1,
		x = 0,
		y = 0,
		invalidate = true,
		col = {255, 255, 255}
	};

	restbl.fontstr = function(self, msg)
		return string.format("\\ffonts/%s,%d%s%s\\#%02x%02x%02x %s", self.font,
			self.fontsz, self.bold and "\\b" or "\\!b", self.italic and "\\i" or "\\!i", self.col[1], self.col[2], self.col[3], msg);
	end

	restbl.store = function(self)
		write_rawresource("local itbl = {};\n");
		write_rawresource(string.format("itbl.res  = \"%s\";\n", self.res));
		write_rawresource(string.format("itbl.type = \"%s\";\n", LAYRES_CONVTBL[self.kind]));
		write_rawresource(string.format("itbl.size = %d;\n", self.fontsz));
		write_rawresource(string.format("itbl.opa  = %d;\n", self.opa));
		write_rawresource(string.format("itbl.ang  = %d;\n", self.ang));
		write_rawresource(string.format("itbl.zv   = %d;\n", self.zv));
		write_rawresource(string.format("itbl.pos  = {%d, %d};\n", self.x, self.y));
		write_rawresource(string.format("itbl.col  = {%d, %d, %d};\n", self.col[1], self.col[2], self.col[3]));
		write_rawresource(string.format("itbl.maxlen = %d;\n", self.maxlen));
		write_rawresource(string.format("itbl.idtag = \"%s\";", self.idtag));
		write_rawresource(string.format("itbl.fontstr = [[%s]];\n", self:fontstr("")));
		write_rawresource(string.format("if (layout[\"%s\"] == nil) then layout[\"%s\"] = {}; end\n", self.idtag, self.idtag));
		write_rawresource(string.format("table.insert(layout[\"%s\"], itbl);\n", self.idtag));
		write_rawresource("table.insert(layout.types[itbl.type], itbl);\n");
	end

	restbl.vid  = fill_surface(1, 1, 0, 0, 0);
	restbl.font = parent.fontlist[parent.fontind];

	restbl:update();

	return restbl;
end

local function new_2ditem(vid)
	local props = image_surface_properties(vid);
	local restbl = {
		scale  = scale,
		rotate = rotate,
		blend  = blend,
		slide  = slide,
		order  = order,
		modes  = position_modes_2d,
		opa = 1.0,
		ang = 0,
		vid = vid,
		tile_v = 1.0,
		tile_h = 1.0,
		update = update_object
	};

	restbl.width  =  (props.width > VRESW * 0.5) and math.floor(VRESW * 0.5) or props.width;
	restbl.height = (props.height > VRESW * 0.5) and math.floor(VRESW * 0.5) or props.height;

	restbl.x = math.floor( 0.5 * (VRESW - restbl.width) );
	restbl.y = math.floor( 0.5 * (VRESH - restbl.height) );

	return restbl;
end

local function default_store(self)
	write_rawresource("local itbl = {};\n");
	write_rawresource(string.format("itbl.res  = \"%s\";\n", self.res));
	write_rawresource(string.format("itbl.type = \"%s\";\n", LAYRES_CONVTBL[self.kind]));
	write_rawresource(string.format("itbl.idtag = \"%s\";\n", self.idtag));

	if (self.zv ~= nil) then
		write_rawresource(string.format("itbl.zv = %d;\n", self.zv));
	end

	if (self.width ~= nil and self.height ~= nil) then
		write_rawresource(string.format("itbl.size = {%d, %d};\n", self.width, self.height));
	end

	if (self.x ~= nil and self.y ~= nil) then
		write_rawresource(string.format("itbl.pos  = {%d, %d};\n", self.x, self.y));
	end

	if (self.tile_v ~= nil and self.tile_h ~= nil) then
		write_rawresource(string.format("itbl.tile = {%d, %d};\n", self.tile_v, self.tile_h));
	end

	if (self.opa ~= nil) then
		write_rawresource(string.format("itbl.opa  = %f;\n", self.opa));
	end

	if (self.ang ~= nil) then
		write_rawresource(string.format("itbl.ang  = %f;\n", self.ang));
	end

	write_rawresource(string.format("if (layout[\"%s\"] == nil) then layout[\"%s\"] = {}; end\n", self.idtag, self.idtag));
	write_rawresource(string.format("table.insert(layout[\"%s\"], itbl);\n", self.idtag));
	write_rawresource("table.insert(layout.types[itbl.type], itbl);\n");
end

local function add_new(self, idtag, label, kind, exclusive, identity)
	local positem = nil;
	local lbls = nil;

	if (type(identity) == "function") then
		identity = identity(label);
	elseif (valid_vid(identity)) then
		identity = instance_image(identity);
		image_mask_clearall(identity);
	end

-- for items that shouldn't / can't be positioned / placed
	if (kind == LAYRES_SPECIAL and identity == nil) then
		positem = {};
		positem.owner = self;
		positem.kind  = kind;
		positem.res   = label;
		positem.idtag = idtag;

		if (positem.owner.post_save_hook ~= nil) then
			positem.owner.post_save_hook(positem);
		end

		if (positem.store == nil) then
			positem.store = default_store;
		end

		table.insert(positem.owner.items, positem);
		return nil;

	elseif (kind == LAYRES_TEXT) then
		positem = new_textitem(label, self);

	elseif (kind == LAYRES_MODEL) then
		if (identity ~= nil) then
			positem = new_3ditem(identity);
		else
			return;
		end
	else
		positem = new_2ditem(identity, label, kind);
	end

	positem.owner = self;
	positem.idtag = idtag;
	positem.kind  = kind;
	positem.res   = label;
	positem.zv    = self.orderind;

	if (positem.store == nil) then
		positem.store = default_store;
	end

	self.orderind = self.orderind + 1;

	if (exclusive) then
		self:find_remove(idtag);
	end

	self:position(positem, function(save)
		if (save == false) then
			delete_image(positem.vid);
		else
			if (positem.owner.post_save_hook ~= nil) then
				positem.owner.post_save_hook(positem);
			end

			table.insert(positem.owner.items, positem);
		end

		dispatch_pop();
		video_3dorder(ORDER_NONE);
		cascade_visibility(current_menu, 1.0, self);
	end);
end

--
-- idtag is logical group the resource is connected to (relevant for exclusive or not, and for loading a premade layout)
-- identifier is the group- entry that will be shown to the user
-- label is whatever resource key that's needed to load the resource, can be a function and will then be used for generating a submenu
-- group is whatever supgroup to insert the entry as, the highest level "_default" is used in place of nil
-- kind determines which operations that should be configured
-- exclusive (true or false) determines if multiple entries are allowed to coexist (not so for background, navigator etc.)
-- identity is a function that will yield a vid to use as reference image
--
local function add_resource(self, idtag, identifier, label, group, kind, exclusive, identity)
	if (group == nil) then
		group = "_default";
	end

	if (self.groups[group] == nil) then
		self.groups[group] = {};
		self.groups[group].labels = {};
		self.groups[group].ptrs = {};
	end

	if (table.find(self.groups[group].labels, identifier) == nil) then

		table.insert(self.groups[group].labels, identifier);
		self.groups[group].ptrs[identifier] = function()

-- indirection variant on add_submenu, show() will run the label() function
			if (type(label) == "function") then
				local list = label();
				menu_spawnmenu( gen_tbl_menu( identifier, label(), function(lbl) self:add_new(idtag, lbl, kind, exclusive, identity); end, true) );

			else
				self:add_new(idtag, label, kind, exclusive, identity);
			end
		end
	end

end

local function find_remove(self, identifier)

	for ind, val in ipairs(self.items) do
		if (val.idtag == identifier) then
			delete_image(val.vid);
			table.remove(self.items, ind);
			break;
		end
	end

end

local function layout_cleanup(self)
	if (self.temporary) then
	for ind,val in ipairs(self.temporary) do
		if (valid_vid(val)) then
			self.expire_trigger(val);
		end
	end
	end

	if (self.temporary_static) then
		for ind,val in ipairs(self.temporary_static) do
			if (valid_vid(val)) then
				self.expire_trigger(val);
			end
		end
	end

end

local function layout_imagepos3d(self, src, val)
	order_image(src.vid, val.zv);
	move3d_model(src.vid, val.pos[1], val.pos[2], val.pos[3]);
	rotate3d_model(src.vid, val.ang[1], val.ang[2], val.ang[3], 0, ROTATE_ABSOLUTE);
--	show_image(src.vid);
	self.show_trigger(src.vid, val.opa);
end

local function layout_imagepos(self, src, val)
	order_image(src, val.zv);
	move_image(src, val.pos[1], val.pos[2]);
	rotate_image(src, val.ang);
	show_image(src);

	if (type(val.size) == "table") then
		resize_image(src, val.size[1], val.size[2]);
	end

	if (val.tile ~= nil) then
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, src);
		image_scale_txcos(src, val.tile[1], val.tile[2]);
	end

	self.show_trigger(src, val.opa);
end

--
-- Sweep through the layout, delete any previously loaded imagery (except the static flagged, no use reloading that)
-- Query the calling script in what resource it wants mapped based in type / etc.
-- trigger() can also return a function pointer if it needs a callback with the resulting vid
--

local function layout_show(self)
	if (self.temporary) then
		for ind, val in ipairs(self.temporary) do
			if (valid_vid(val)) then
				delete_image(val);
			end
		end
	end

	self.temporary = {}; -- contains resource VIDs that need to be cleared
	self.temporary_reuse = {}; -- contains a map of resource VIDs for instancing to re-use costly resources

	local imgproc = function(dsttbl, trigtype, val)
		local res, cback = self.trigger(trigtype, val);
		if (res) then
			local vid = load_image_asynch(res, function(src, stat)
				if (stat.kind == "loaded") then
					layout_imagepos(self, src, val);
				end
			end);

			if (valid_vid(vid) and cback) then
				cback(vid, val);
			end

			table.insert(dsttbl, vid);
		end

	end

	if (self.static_loaded == nil) then
		self.temporary_static = {};

		for ind, val in ipairs(self.types["static"]) do
			imgproc(self.temporary_static, LAYRES_STATIC, val);
		end

		self.static_loaded = true;
	end

	for ind, val in ipairs(self.types["image"]) do
		imgproc(self.temporary, LAYRES_IMAGE, val);
	end

	for ind, val in ipairs(self.types["fsrv"]) do
		local res = self.trigger(LAYRES_FRAMESERVER, val);
		if (res) then
			if valid_vid(self.temporary_reuse[res]) then
				local vid = instance_image(self.temporary_reuse[res]);
				image_mask_clearall(vid); -- clones can't live past their parent so nothing more to do
				layout_imagepos(self, vid, val);
			else
				local vid = load_movie(res,
					val.loop and FRAMESERVER_LOOP or FRAMESERVER_NOLOOP,
					function(src, stat)
					if (stat.source_audio ~= nil) then
						audio_gain(stat.source_audio, self.default_gain);
					end

					if (stat.kind == "resized") then
						layout_imagepos(self, src, val);
					end
				end);

				if valid_vid(vid) then
					layout_imagepos(self, vid, val);
					self.temporary_reuse[res] = vid;
					table.insert(self.temporary, vid);
				end
			end
		end -- loop
	end

	for ind, val in ipairs(self.types["model"]) do
		local msg, cback = self.trigger(LAYRES_MODEL, val);

		if (msg ~= nil and msg.vid) then
			table.insert(self.temporary, msg.vid);
			layout_imagepos3d(self, msg, val);
			if (cback) then
				cback(msg, val);
			end

		end
	end

	for ind, val in ipairs(self.types["text"]) do
		local msg = self.trigger(LAYRES_TEXT, val);
		if (msg ~= nil) then
			if (string.len(msg) > val.maxlen) then
				msg = string.sub(msg, 1, val.maxlen);
			end

			local vid = render_text( val.fontstr .. msg );
			layout_imagepos(self, vid, val);
			table.insert(self.temporary, vid);
		end
	end

end

--
-- Convenience helper around a finished layout
-- taking care of loading / cleanup
--
-- callback is expected a format with (self, type, itemtbl) that returns a vid or nil
-- lifetime management of the returned vid is left to the layout helper
--
function layout_load(name, callback, options)
	if (options == nil) then
		options = {};
	end

	if (not resource(name)) then
		return nil;
	end

	local restbl = system_load(name)();
	if (restbl.types == nil) then
		return nil;
	end

	restbl.default_gain = 1;
	restbl.destroy = layout_cleanup;
	restbl.show    = layout_show;
	restbl.trigger = callback;

	restbl.add_imagevid = function(self, vid, postbl)
			layout_imagepos(restbl, vid, postbl);
			table.insert(self.temporary, vid);
	end

	restbl.show_trigger = function(vid, opa)
		blend_image(vid, opa, 10);
	end

	restbl.expire_trigger = function(vid)
		blend_image(vid, 0.0, 10);
		expire_image(vid, 10);
	end

	return restbl;
end

function layout_new(name)
	local layout_cfg = {
		add_new = add_new,
		slide = slide,
		scale = scale,
		store = save,
		layname = name,
		current_axis = 0,
		orderind = 1,
		add_resource = add_resource,
		position = position_item,
		find_remove = find_remove,
		post_save_hook = nil,
		finalizer = nil,
		show = show,
		fontind = 1,
		default_gain = 1,
		items = {},
		groups = {}
	};

	layout_cfg.fontlist = glob_resource("fonts/*.ttf");

	system_load("scripts/colourpicker.lua")();

	return layout_cfg;
end
