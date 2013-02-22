--
-- Setup for Gridle- Remote, just a derivate of Gridle- Customview
-- Without the need for a navigator
-- 
local grid_stepx = 2;
local grid_stepy = 2;

local stepleft, stepup, stepdown, stepright, show_config, setup_layouted;

layouted = {
	layoutfile = "layouts/default.lua"
};

-- map resource-finder properties with their respective name in the editor dialog
local remaptbl = {};
remaptbl["bezel"]       = "bezels";
remaptbl["screenshot"]  = "screenshots";
remaptbl["marquee"]     = "marquees";
remaptbl["overlay"]     = "overlay";
remaptbl["bezel"]       = "bezels";
remaptbl["backdrop"]    = "backdrops";
remaptbl["movie"]       = "movies";
remaptbl["controlpanel"]= "controlpanels";
remaptbl["boxart"]      = "boxart";

-- list of the currently allowed modes (size, position, opacity, orientation)
layouted.position_modes_default  = {"position", "size", "opacity", "orientation"};
layouted.position_modes_3d       = {"position3d", "rotate3d"};
layouted.axis = 0;
layouted.orderind = 1;
layouted.temporary = {};
layouted.temporary_models = {};

helplbls = {};
helplbls["position"] = {
	"Position",
	"(LEFT/RIGHT/UP/DOWN) to move",
	"(SWITCH_VIEW) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["position3d"] = {
	"Position (3D), Axis: 0",
	"(LEFT/RIGHT) to increase/decrease angle",
	"(UP/DOWN) to switch active axis",
	"(SWITCH_VIEW) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["rotate3d"] = {
	"Rotate (3D), Axis: 0",
	"(SWITCH_VIEW) to switch mode",
	"(MENU_UP/DOWN) to switch active axis",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["size"] = {
	"Scale",
	"(RIGHT/DOWN) to increase size",
	"(LEFT/UP) to decrease size",
	"(SWITCH_VIEW) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["opacity"] = {
	"Blend",
	"(LEFT/RIGHT) increase / decrease opacity",
	"(UP/DOWN) increase / decrease Z-order",
	"(SWITCH_VIEW) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

helplbls["orientation"] = {
	"Rotate",
	"(UP/DOWN) aligned step (45 deg.)",
	"(LEFT/RIGHT) increase / decrease angle",
	"(SWITCH_VIEW) to switch mode",
	"(SELECT) to save",
	"(ESCAPE) to cancel"
};

-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end

-- inject a submenu into a main one
-- dstlbls : array of strings to insert into
-- dstptrs : hashtable keyed by label for which to insert the spawn function
-- label   : to use for dstlbls/dstptrs
-- lbls    : array of strings used in the submenu (typically from gen_num, gen_tbl)
-- ptrs    : hashtable keyed by label that acts as triggers (typically from gen_num, gen_tbl)
function add_submenu(dstlbls, dstptrs, label, key, lbls, ptrs)
	if (dstlbls == nil or dstptrs == nil or #lbls == 0) then return; end
	
	table.insert(dstlbls, label);
	
	dstptrs[label] = function()
		local fmts = {};
		local ind = tostring(settings[key]);
	
		if (ind) then
			fmts[ ind ] = settings.colourtable.notice_fontstr;
			if(get_key(key)) then
				fmts[ get_key(key) ] = settings.colourtable.alert_fontstr;
			end
		end
		
		menu_spawnmenu(lbls, ptrs, fmts);
	end
end

-- create and display a listview setup with the menu defined by the arguments.
-- list    : array of strings that make up the menu
-- listptr : hashtable keyed by list labels
-- fmtlist : hashtable keyed by list labels, on match, will be prepended when rendering (used for icons, highlights etc.)
function menu_spawnmenu(list, listptr, fmtlist)
	if (#list < 1) then
		return nil;
	end

	local parent = current_menu;
	local props = image_surface_resolve_properties(current_menu.cursorvid);
	local windsize = VRESH;

	local yofs = 0;
	if (props.y + windsize > VRESH) then
		yofs = VRESH - windsize;
	end

	current_menu = listview_create(list, windsize, VRESW / 3, fmtlist);
	current_menu.parent = parent;
	current_menu.ptrs = listptr;
	current_menu.updatecb = parent.updatecb;
	current_menu:show();
	move_image( current_menu.anchor, props.x + props.width + 6, props.y);
	
	local xofs = 0;
	local yofs = 0;
	
-- figure out where the window is going to be.
	local aprops_l = image_surface_properties(current_menu.anchor, settings.fadedelay);
	local wprops_l = image_surface_properties(current_menu.window, settings.fadedelay);
	local dx = aprops_l.x;
	local dy = aprops_l.y;
	
	local winw = wprops_l.width;
	local winh = wprops_l.height;
	
	if (dx + winw > VRESW) then
		dx = dx + (VRESW - (dx + winw));
	end
	
	if (dy + winh > VRESH) then
		dy = dy + (VRESH - (dy + winh));
	end

	move_image( current_menu.anchor, math.floor(dx), math.floor(dy), settings.fadedelay );
	return current_menu;
end

function build_globmenu(globstr, cbfun, globmask)
	local lists = glob_resource(globstr, globmask);
	local resptr = {};
	
	for i = 1, #lists do
		resptr[ lists[i] ] = cbfun;
	end
	
	return lists, resptr;
end

-- name     : settings[name] to store under
-- tbl      : array of string with labels of possible values
-- isstring : treat value as string or convert to number before sending to store_key
function gen_tbl_menu(name, tbl, triggerfun, isstring)
	local reslbl = {};
	local resptr = {};

	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = isstring and label or tonumber(label);

		if (save) then
			store_key(name, isstring and label or tonumber(label));
		else
		end

		if (triggerfun) then triggerfun(label); end
	end

	for key,val in ipairs(tbl) do
		table.insert(reslbl, val);
		resptr[val] = basename;
	end

	return reslbl, resptr;
end

-- traversed to root node, updating visibility for each menu on the way
function cascade_visibility(menu, val)
	if (menu.parent) then
		cascade_visibility(menu.parent, val);
	end

	if (val > 0.9) then
		if (infowin) then
			infowin:destroy();
			infowin = nil;
		end
	end
	
	blend_image(menu.anchor, val);
	menu:push_to_front();
end

-- change the label shown 
local function update_infowin()
	if (infowin) then
		infowin:destroy();
	end

-- used in the setup/edit/mode. Position a quadrant away from the current item, and show the appropriate help text 
	infowin = listview_create( helplbls[layouted.position_modes[layouted.position_marker]], VRESW / 2, VRESH / 2 );
	local xpos = (layouted.ci.x < VRESW / 2) and (VRESW / 2) or 0;
	local ypos = (layouted.ci.y < VRESH / 2) and (VRESH / 2) or 0;
	infowin:show();
	move_image(infowin.anchor, math.floor(xpos), math.floor(ypos));
end

-- used in the setup/edit/mode.
local function position_toggle()
-- don't allow any other mode to be used except position until we have an upper left boundary
	layouted.position_marker = (layouted.position_marker + 1 > #layouted.position_modes) and 1 or (layouted.position_marker + 1);
	update_infowin();
end

-- used in the setup/edit mode, whenever user-input changes the state of the current item
local function update_object(imgvid)
	resize_image(imgvid, layouted.ci.width, layouted.ci.height);
	move_image(imgvid, layouted.ci.x, layouted.ci.y);
	blend_image(imgvid, layouted.ci.opa);
	rotate_image(imgvid, layouted.ci.ang);
	order_image(imgvid, layouted.ci.zv);

	if (layouted.ci.tiled) then
		local props = image_surface_initial_properties(imgvid);
		image_scale_txcos(imgvid, layouted.ci.width / props.width, layouted.ci.height / props.height);
	end
	
end

local function update_object3d(model)
	move3d_model(model, layouted.ci.pos[1], layouted.ci.pos[2], layouted.ci.pos[3]);
	rotate3d_model(model, layouted.ci.ang[1], layouted.ci.ang[2], layouted.ci.ang[3], 0, ROTATE_ABSOLUTE);
end

-- used whenever a shader is toggled for the 'background' label, applied in both edit and view mode.
local function update_bgshdr()
	local dst = nil;
	
	if (layouted.in_config) then
		for ind, val in ipairs(layouted.itemlist) do
			if (val.kind == "background") then
				dst = val.vid;
				val.shader = layouted.bgshader_label;
				break
			end
		end
	else
		dst = layouted.background;
	end

	if (dst) then
		local props = image_surface_properties(dst);
		shader_uniform(layouted.bgshader, "display", "ff", PERSIST, props.width, props.height);
		image_shader(dst, layouted.bgshader);
	end
end

-- used in edit / scale 
local function cursor_step(vid, x, y)
	layouted.ci.width  = layouted.ci.width + x;
	layouted.ci.height = layouted.ci.height + y;

	if (layouted.ci.width <= 0)  then layouted.ci.width  = 1; end
	if (layouted.ci.height <= 0) then layouted.ci.height = 1; end
	
	update_object(vid);
end

-- used in edit / positioning 
local function cursor_slide(vid, x, y)
	layouted.ci.x = layouted.ci.x + x;
	layouted.ci.y = layouted.ci.y + y;
	
	update_object(vid);
end

-- used in edit / rotate
local function orientation_rotate(vid, ang, align)
	layouted.ci.ang = layouted.ci.ang + ang;

	if (align) then
		local rest = layouted.ci.ang % 45;
		layouted.ci.ang = (rest > 22.5) and (layouted.ci.ang - rest) or (layouted.ci.ang + rest);
	end
	
	update_object(vid);
end

-- used in edit / blend
local function order_increment(vid, val)
	layouted.ci.zv = layouted.ci.zv + val;
	if (layouted.ci.zv < 1) then layouted.ci.zv = 1; end
	if (layouted.ci.zv >= layouted.orderind) then layouted.ci.zv = layouted.orderind - 1; end
	
	update_object(vid);
end

-- used in edit / blend
local function opacity_increment(vid, byval)
	layouted.ci.opa = layouted.ci.opa + byval;
	
	if (layouted.ci.opa < 0.0) then layouted.ci.opa = 0.0; end
	if (layouted.ci.opa > 1.0) then layouted.ci.opa = 1.0; end
	
	update_object(vid);
end

local function cursor_rotate3d(model, step)
	layouted.ci.ang[ layouted.axis+1 ] = layouted.ci.ang[ layouted.axis+1 ] + step;
	update_object3d(model);
end

local function cursor_position3d(model, step)
	layouted.ci.pos[ layouted.axis+1 ] = layouted.ci.pos[ layouted.axis+1 ] + step;
	update_object3d(model);
end

local function cursor_axis3d(model)
	layouted.axis = (layouted.axis + 1) % 3;
	helplbls["position3d"][1] = "Position (3D), Axis: " .. tostring(layouted.axis);
	helplbls["rotate3d"][1] = "Rotate (3D), Axis: " .. tostring(layouted.axis);
	update_infowin();
	update_object3d(model);
end

-- used in edit mode, depending on source object type etc. a list of acceptable labels
-- is set to position modes, this function connects these to the regular menu input labels
layouted.position_item = function(vid, trigger, lbls)
-- as the step size is rather small, enable keyrepeat (won't help for game controllers though,
-- would need state tracking and hook to the clock 
	cascade_visibility(current_menu, 0.0);
	toggle_mouse_grab(MOUSE_GRABON);
	
	layouted.position_modes  = lbls and lbls or layouted.position_modes_default;
	layouted.position_marker = 1;
	
	local imenu = {};
	imenu["MOUSE_X"] = function(label, tbl)
		local lbl = layouted.position_modes[layouted.position_marker];
		if (tbl.samples[2] == nil or tbl.samples[2] == 0) then return; end
		if     (lbl == "size")        then cursor_step(vid, tbl.samples[2], 0);
		elseif (lbl == "orientation") then orientation_rotate(vid, 0.1 * tbl.samples[2], false);
		elseif (lbl == "position")    then cursor_slide(vid, tbl.samples[2], 0);
		elseif (lbl == "opacity")     then opacity_increment(vid, 0.01 * tbl.samples[2]);
		elseif (lbl == "rotate3d")    then cursor_rotate3d(vid, tbl.samples[2]);
		elseif (lbl == "position3d")  then cursor_position3d(vid, 0.01 * tbl.samples[2]); end
	end

	imenu["MOUSE_Y"] = function(label, tbl)
		local lbl = layouted.position_modes[layouted.position_marker];
		if (tbl.samples[2] == nil or tbl.samples[2] == 0) then return; end
		if     (lbl == "size")        then cursor_step(vid, 0, tbl.samples[2]);
		elseif (lbl == "position")    then cursor_slide(vid, 0, tbl.samples[2]); end
	end
	
	imenu["MENU_LEFT"]   = function()
		local lbl = layouted.position_modes[layouted.position_marker];
		if     (lbl == "size")        then cursor_step(vid, grid_stepx * -1, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid,-2, false);
		elseif (lbl == "opacity")     then opacity_increment(vid, 0.1);
		elseif (lbl == "position")    then cursor_slide(vid, grid_stepx * -1, 0); 
		elseif (lbl == "rotate3d")    then cursor_rotate3d(vid, -20);
		elseif (lbl == "position3d")  then cursor_position3d(vid, -0.2);
		end
	end

	imenu["MENU_RIGHT"]  = function() 
		local lbl = layouted.position_modes[layouted.position_marker];
		if     (lbl == "size")        then cursor_step(vid,grid_stepx, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid, 2, false);
		elseif (lbl == "opacity")     then opacity_increment(vid, -0.1);
		elseif (lbl == "position")    then cursor_slide(vid, grid_stepx, 0);
		elseif (lbl == "rotate3d")    then cursor_rotate3d(vid, 20);
		elseif (lbl == "position3d")  then cursor_position3d(vid, 0.2);
		end
	end

	imenu["MENU_UP"]     = function()
		local lbl = layouted.position_modes[layouted.position_marker];
		if     (lbl == "size")        then cursor_step(vid,0, grid_stepy * -1);
		elseif (lbl == "orientation") then orientation_rotate(vid, -45, true);
		elseif (lbl == "opacity")     then order_increment(vid,1); 
		elseif (lbl == "position")    then cursor_slide(vid, 0, grid_stepy * -1);
		elseif (lbl == "rotate3d")    then cursor_axis3d(vid);
		elseif (lbl == "position3d")  then cursor_axis3d(vid);
		end
	end

	imenu["MENU_DOWN"]   = function() 
		local lbl = layouted.position_modes[layouted.position_marker];
		if     (lbl == "size")        then cursor_step(vid,0, grid_stepy);
		elseif (lbl == "orientation") then orientation_rotate(vid, 45, true);
		elseif (lbl == "opacity")     then order_increment(vid,-1); 
		elseif (lbl == "position")    then cursor_slide(vid, 0, grid_stepy); 
		elseif (lbl == "rotate3d")    then cursor_axis3d(vid);
		elseif (lbl == "position3d")  then cursor_axis3d(vid);
		end 
	end
	
	imenu["MENU_ESCAPE"] = function() toggle_mouse_grab(MOUSE_GRABOFF); trigger(false, vid); end
	imenu["SWITCH_VIEW"] = function() position_toggle();   end
	imenu["MENU_SELECT"] = function() toggle_mouse_grab(MOUSE_GRABOFF); trigger(true, vid); end

	dispatch_push(imenu, "layout editor");
	update_infowin();
end

layouted.new_item = function(vid, dstgroup, dstkey)
	local props = image_surface_properties(vid);

	layouted.ci = {};
	layouted.ci.width = (props.width  > VRESW * 0.5) and VRESW * 0.5 or props.width;
	layouted.ci.height= (props.height > VRESH * 0.5) and VRESH * 0.5 or props.height;
	layouted.ci.x     = 0.5 * (VRESW - layouted.ci.width);
	layouted.ci.y     = 0.5 * (VRESH - layouted.ci.height);
	layouted.ci.opa   = 1.0;
	layouted.ci.ang   = 0;
	layouted.ci.kind  = dstgroup;
	layouted.ci.res   = dstkey;
	
	layouted.ci.zv    = layouted.orderind;
	layouted.orderind = layouted.orderind + 1;
end

layouted.new_item3d = function(model, dstgroup, dstkey)
	layouted.ci = {};

	layouted.ci.ang = {0.0, 0.0, 0.0};
	layouted.ci.pos = {-1.0, 0.0, -4.0};
-- not really used, just so infowin have something to work with 
	layouted.ci.x   = 0;
	layouted.ci.y   = 0;
	layouted.ci.opa = 1.0;
	
	layouted.ci.zv  = layouted.orderind;
	layouted.orderind = layouted.orderind + 1;
	
	layouted.ci.kind = dstgroup;
	layouted.ci.res  = dstkey;
end

local function to_menu()
	layouted.ci = nil;
	dispatch_pop();

	settings.iodispatch["MENU_ESCAPE"]("", false, false);
	cascade_visibility(current_menu, 1.0);
	kbd_repeat(settings.repeatrate);
end

local function save_item(state, vid)
	if (state) then
		layouted.ci.vid = vid;
		table.insert(layouted.itemlist, layouted.ci);
	else
		delete_image(vid);
	end

	to_menu();
end

local function save_item_bg(state, vid)
	if (state == false) then
		delete_image(vid);
		to_menu();
		return;
	end
	
	local found = false;
	layouted.ci.vid = vid;
	
	for ind, val in ipairs(layouted.itemlist) do
		if val.kind == "background" then
			delete_image(layouted.itemlist[ind].vid);
			layouted.itemlist[ind] = layouted.ci; 
			found = true;
			break
		end
	end

	if (found == false) then
		table.insert(layouted.itemlist, layouted.ci);
	end

	video_3dorder(ORDER_LAST);
	to_menu();
end

local function positionfun(label)
	vid = load_image("images/" .. label);
	
	if (vid ~= BADID) then
		layouted.new_item(vid, "static_media", label);
		layouted.ci.res = "images/" .. label;

		update_object(vid);
		layouted.position_item(vid, save_item);
	end
end

local function effecttrig(label)
	local shdr = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. label, "bgeffect", {});
	layouted.bgshader = shdr;
	layouted.bgshader_label = label;

	update_bgshdr();
	settings.iodispatch["MENU_ESCAPE"]();
end

local function get_identimg(label)
	local vid = BADID;
	
	if (resource("images/placeholders/" .. string.lower(label) .. ".png")) then
		vid = load_image("images/placeholders/" .. string.lower(label) .. ".png");
	end
	
	if (vid == BADID) then
-- as a fallback, generate a label
		vid = render_text(settings.colourtable.label_fontstr .. label);
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, vid);
		return vid, true;
	else
		return vid, false;
	end
end

local function positiondynamic(label)
	if (label == "Model") then
		local model = load_model("placeholder");

		if (model) then
			local vid = model.vid;
			layouted.new_item3d(vid, "model", string.lower(label));
			orient3d_model(model.vid, 0, -90, 0);
			layouted.position_item(vid, save_item, layouted.position_modes_3d);
			show_image(vid);
			update_object3d(vid);
			return;
		end
	end
		
	local vid, tiled = get_identimg(label);

	if (label == "Vidcap") then
		layouted.new_item(vid, "vidcap", string.lower(label));
		layouted.ci.index = 0;
	else
		layouted.new_item(vid, "dynamic_media", string.lower(label));
	end

	layouted.ci.tiled = tiled;
	layouted.ci.width  = VRESW * 0.3;
	layouted.ci.height = VRESH * 0.3;
	update_object(vid);
	layouted.position_item(vid, save_item);
end

local function positionlabel(label)
	vid = render_text(settings.colourtable.label_fontstr .. label);
	layouted.new_item(vid, "label", string.lower(label));
	update_object(vid);
	layouted.position_item(vid, save_item);
end

-- stretch to fit screen, only opa change allowed
local function positionbg(label)
	local tiled = false;
	local vid = load_image("backgrounds/" .. label);
	if (vid == BADID) then return; end

	layouted.ci = {};
	layouted.ci.tiled  = tiled;
	local props = image_surface_properties(vid);

	switch_default_texmode( TEX_REPEAT, TEX_REPEAT, vid );

	-- threshold for tiling rather than stretching
	if (props.width < VRESW / 2 or props.height < VRESH / 2) then
		layouted.ci.tiled  = true;
	end

	layouted.ci.width  = VRESW;
	layouted.ci.height = VRESH;
	layouted.ci.zv     = 0;
	layouted.ci.x      = 0;
	layouted.ci.y      = 0;
	layouted.ci.opa    = 1.0;
	layouted.ci.ang    = 0;
	layouted.ci.kind   = "background";
	layouted.ci.shader = layouted.bgshader_label;
	layouted.ci.res    = "backgrounds/" .. label;

	if (layouted.ci.tiled) then
		local props = image_surface_initial_properties(vid);
		image_scale_txcos(vid, layouted.ci.width / props.width, layouted.ci.height / props.height);
	end

	update_object(vid);
	layouted.position_item(vid, save_item_bg);
end

-- take the custom view and dump to a .lua config
local function save_layout()
	open_rawresource(layouted.layoutfile);
	write_rawresource("local cview = {};\n");
	write_rawresource("cview.static = {};\n");
	write_rawresource("cview.dynamic = {};\n");
	write_rawresource("cview.models  = {};\n");
	write_rawresource("cview.dynamic_labels = {};\n");
	write_rawresource("cview.vidcap = {};\n");
	write_rawresource("cview.aspect = " .. tostring( VRESW / VRESH ) .. ";\n");
	
	for ind, val in ipairs(layouted.itemlist) do
		if (val.kind == "model") then
			write_rawresource("local item = {};\n");
			write_rawresource("item.pos = {" .. tostring(val.pos[1]) .. ", " .. tostring(val.pos[2]) .. ", " .. tostring(val.pos[3]) .. "};\n");
			write_rawresource("item.ang = {" .. tostring(val.ang[1]) .. ", " .. tostring(val.ang[2]) .. ", " .. tostring(val.ang[3]) .. "};\n");

-- "options" for each item aren't definable yet, so hard- code in the necessary ones here 
			write_rawresource("item.dir_light = {1.0, 0.0, 0.0};\n");
			write_rawresource("item.ambient   = {0.3, 0.3, 0.3};\n");
			write_rawresource("item.diffuse   = {0.6, 0.6, 0.6};\n");

			write_rawresource("table.insert(cview.models, item);\n");
		else
			write_rawresource("local item = {};\n");
			write_rawresource("item.x      = " .. tostring( val.x / VRESW ) .. ";\n");
			write_rawresource("item.y      = " .. tostring( val.y / VRESH ) .. ";\n");
			write_rawresource("item.order  = " .. val.zv .. ";\n");
			write_rawresource("item.opa    = " .. val.opa .. ";\n");
			write_rawresource("item.ang    = " .. val.ang .. ";\n");
			write_rawresource("item.width  = " .. tostring(val.width / VRESW ) .. ";\n");
			write_rawresource("item.height = " .. tostring(val.height / VRESH ) .. ";\n");
			write_rawresource("item.tiled  = " .. tostring(val.tiled == true) .. ";\n");
		
			if val.kind == "static_media" then
				write_rawresource("item.res    = \"" .. val.res .. "\";\n");
				write_rawresource("table.insert(cview.static, item);\n");

			elseif val.kind == "dynamic_media" then
				write_rawresource("item.res    = \"" .. val.res .. "\";\n");
				write_rawresource("table.insert(cview.dynamic, item);\n");

			elseif val.kind == "vidcap" then
				write_rawresource("item.index  = " .. val.index .. ";\n");
				write_rawresource("table.insert(cview.vidcap, item);\n");
	
			elseif val.kind == "label" then
				write_rawresource("item.res    = \"" .. val.res .. "\";\n");
				write_rawresource("item.font   = [[\\ffonts/multilang.ttf,]];\n");
				write_rawresource("table.insert(cview.dynamic_labels, item);\n");
			
			elseif val.kind == "background" then
				write_rawresource("item.res    = \"" .. val.res .."\";\n");
				if (val.shader) then
					write_rawresource("item.shader = \"" .. val.shader .. "\";\n");
				end
				write_rawresource("cview.background = item;\n");
			else
				print("[layouted:save_layout] warning, unknown kind: " .. val.kind);
			end
		end

	end
	
	write_rawresource("return cview;\n");
	close_rawresource();
	
	while current_menu ~= nil do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end

-- save and load
	dispatch_pop();
	pop_video_context();
	gridleremote_layouted(lasttrigger);
end

-- reuse by other menu functions
function menu_defaultdispatch(tbl)
	if (not tbl["MENU_UP"]) then
		tbl["MENU_UP"] = function(iotbl) 
			current_menu:move_cursor(-1, true); 
		end
	end

	if (not tbl["MENU_DOWN"]) then
			tbl["MENU_DOWN"] = function(iotbl)
			current_menu:move_cursor(1, true); 
		end
	end
	
	if (not tbl["MENU_SELECT"]) then
		tbl["MENU_SELECT"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, false);
				if (current_menu and current_menu.updatecb) then
					current_menu.updatecb();
				end
			end
		end
	end
	
-- figure out if we should modify the settings table
	if (not tbl["FLAG_FAVORITE"]) then
		tbl["FLAG_FAVORITE"] = function(iotbl)
				selectlbl = current_menu:select();
				if (current_menu.ptrs[selectlbl]) then
					current_menu.ptrs[selectlbl](selectlbl, true);
					if (current_menu and current_menu.updatecb) then
						current_menu.updatecb();
					end
				end
			end
	end
	
	if (not tbl["MENU_ESCAPE"]) then
		tbl["MENU_ESCAPE"] = function(iotbl, restbl, silent)
			current_menu:destroy();

			if (current_menu.parent ~= nil) then
				current_menu = current_menu.parent;
			else -- top level
				dispatch_pop();
			end
		end

	end
	
	if (not tbl["MENU_RIGHT"]) then
		tbl["MENU_RIGHT"] = tbl["MENU_SELECT"];
	end
	
	if (not tbl["MENU_LEFT"]) then
		tbl["MENU_LEFT"]  = tbl["MENU_ESCAPE"];
	end
end

local function show_config()
	layouted_display = settings.iodispatch;
	layouted.itemlist = {};
	
	local imenu = {};
	menu_defaultdispatch(imenu);
	
	imenu["MENU_LEFT"] = function(label, save, sound)
		if (current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
	end
	imenu["MENU_ESCAPE"] = imenu["MENU_LEFT"];
	
	local mainlbls = {};
	local mainptrs = {};

	add_submenu(mainlbls, mainptrs, "Backgrounds...", "ignore", build_globmenu("backgrounds/*.png", positionbg, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Background Effects...", "ignore", build_globmenu("shaders/bgeffects/*.fShader", effecttrig, THEME_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Images...", "ignore", build_globmenu("images/*.png", positionfun, THEME_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Dynamic Media...", "ignore", gen_tbl_menu("ignore",	{"Screenshot", "Movie", "Bezel", "Marquee", "Flyer", "Boxart", "Vidcap", "Model"}, positiondynamic));
	add_submenu(mainlbls, mainptrs, "Dynamic Labels...", "ignore", gen_tbl_menu("ignore", {"Title", "Year", "Players", "Target", "Genre", "Subgenre", "Setname", "Buttons", "Manufacturer", "System"}, positionlabel));
	
	table.insert(mainlbls, "---");
	table.insert(mainlbls, "Save");
	table.insert(mainlbls, "Exit");

	mainptrs["Exit"] = function() shutdown(); end
	mainptrs["Save"] = save_layout;
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;
	layouted.root_menu = current_menu;

	current_menu:show();
	move_image(current_menu.anchor, 10, VRESH * 0.1, settings.fadedelay);
	dispatch_push(imenu, "layout menu");
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

local function place_model(modelid, pos, ang)
	move3d_model(modelid, pos[1], pos[2], pos[3]);
	rotate3d_model(modelid, ang[1], ang[2], ang[3]);
	show_image(modelid);
end

function gridleremote_updatedynamic(newtbl)
	if (newtbl == nil or newtbl == layouted.lasttbl) then
		return;
	end

	layouted.lasttbl = newtbl;
--	toggle_led(newtbl.players, newtbl.buttons, "")	;

-- this table is maintained for every newly selected item, and just tracks everything to delete.
	for ind, val in ipairs(layouted.temporary) do
		if (valid_vid(val)) then delete_image(val); end 
	end

	for ind, val in ipairs(layouted.temporary_models) do
		if (valid_vid(val.vid)) then delete_image(val.vid); end
	end
	
	layouted.temporary = {};
	layouted.temporary_models = {};

	local restbl = resourcefinder_search( newtbl, true );

	if (restbl) then
		if (layouted.current.models and #layouted.current.models > 0) then
			local modelstr = find_cabinet_model(newtbl);
			local model  = modelstr and setup_cabinet_model(modelstr, restbl, {}) or nil;

			if (model) then
				local shdr = layouted.light_shader;
	
				table.insert(layouted.temporary_models, model);
				table.insert(layouted.temporary, model.vid);

				local cm = layouted.current.models[1];
				
				image_shader(model.vid, layouted.light_shader);
				place_model(model.vid, cm.pos, cm.ang);

				local ld = cm.dir_light and cm.dir_light or {1.0, 0.0, 0.0};
				shader_uniform(shdr, "wlightdir", "fff", PERSIST, ld[1], ld[2], ld[3]);

				local la = cm.ambient and cm.ambient or {0.3, 0.3, 0.3};
				shader_uniform(shdr, "wambient",  "fff", PERSIST, la[1], la[2], la[3]);
				
				ld = cm.diffuse and cm.diffuse or {0.6, 0.6, 0.6};
				shader_uniform(shdr, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6);
	
-- reuse the model for multiple instances
				for i=2,#layouted.current.models do
					local nid = instance_image(model.vid);
					image_mask_clear(nid, MASK_POSITION);
					image_mask_clear(nid, MASK_ORIENTATION);
					place_model(nid, layouted.current.models[i].pos, layouted.current.models[i].ang);
				end
			end
		end

		for ind, val in ipairs(layouted.current.dynamic) do
			reskey = remaptbl[val.res];
			
			if (reskey and restbl[reskey] and #restbl[reskey] > 0) then
				if (reskey == "movies") then
					vid, aid = load_movie(restbl[reskey][1], FRAMESERVER_LOOP, function(source, status)
						place_item(source, val);
						play_movie(source);
					end)
					table.insert(layouted.temporary, vid);	
				else
					vid = load_image_asynch(restbl[reskey][1], function(source, status)
						place_item(source, val);
					end);
					table.insert(layouted.temporary, vid);
				end
	
			end
		end

		for ind, val in ipairs(layouted.current.dynamic_labels) do
			local dststr = newtbl[val.res];
			
			if (type(dststr) == "number") then dststr = tostring(dststr); end
			
			if (dststr and string.len( dststr ) > 0) then
				local capvid = fill_surface(math.floor( VRESW * val.width), math.floor( VRESH * val.height ), 0, 0, 0);
				vid = render_text(val.font .. math.floor( VRESH * val.height ) .. " " .. dststr);
				link_image(vid, capvid);
				image_mask_clear(vid, MASK_OPACITY);
				place_item(capvid, val);

				hide_image(capvid);
				show_image(vid);
				resize_image(vid, 0, VRESH * val.height);
				order_image(vid, val.order);
				table.insert(layouted.temporary, capvid);
				table.insert(layouted.temporary, vid);
			end
			
		end
		
	end
end

local function setup_layouted(triggerfun)
	local background = nil;
	for ind, val in ipairs( layouted.current.static ) do
		local vid = load_image( val.res );
		place_item( vid, val );
	end

-- video capture devices, can either be instances of the same vidcap OR multiple devices based on index 
	layouted.current.vidcap_instances = {};
	for ind, val in ipairs( layouted.current.vidcap ) do
		inst = layouted.current.vidcap_instances[val.index];
		
		if (valid_vid(inst)) then
			inst = instance_image(inst);
			image_mask_clearall(inst);
			place_item( inst, val );
		else
			local vid = load_movie("vidcap:" .. tostring(val.index), FRAMESERVER_LOOP, function(source, status)
				place_item(source, val);
				play_movie(source);
			end);
		
			layouted.current.vidcap_instances[val.index] = vid;
		end
	end

-- load background effect 
	if (layouted.current.background) then
		vid = load_image( layouted.current.background.res );
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, vid);

		layouted.background = vid;

		place_item(vid, layouted.current.background);
		layouted.bgshader_label = layouted.current.background.shader;

		local props  = image_surface_properties(vid);
		local iprops = image_surface_initial_properties(vid);

		if (layouted.current.background.tiled) then
			image_scale_txcos(vid, props.width / iprops.width, props.height / iprops.height);
		end
		
		if (layouted.bgshader_label) then
			layouted.bgshader = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. layouted.bgshader_label, "bgeffect", {});
			update_bgshdr();
		end
	end

end

local function layouted_3dbase()
	local lshdr = load_shader("shaders/dir_light.vShader", "shaders/dir_light.fShader", "cvdef3d");
	shader_uniform(lshdr, "map_diffuse", "i"  , PERSIST, 0);
	layouted.light_shader = lshdr;
end

function gridleremote_layouted(triggerfun, layoutname)
	local disptbl;
	lasttrigger = triggerfun;
	if (layoutname) then
		layouted.layoutfile = "layouts/" .. layoutname;
	end
	
-- try to load a preexisting configuration file, if no one is found
-- launch in configuration mode -- to reset this procedure, delete any 
-- layouted_cfg.lua and reset layouted.in_config
	setup_3dsupport();
	layouted_3dbase();

	if (resource(layouted.layoutfile)) then
		layouted.background    = nil;
		layouted.bgshader      = nil;
		layouted.current       = system_load(layouted.layoutfile)();
	
		if (layouted.current) then
			layouted.in_layouted = true;
			layouted.in_config = false;
			setup_layouted();
			triggerfun();
		end

	else
		layouted.in_config = true;
		video_3dorder(ORDER_LAST);
		disptbl = show_config();
	end
end