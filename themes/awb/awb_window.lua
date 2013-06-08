--
-- Simple window helper class
--
-- Based around a central canvas (other vid or as it starts out,
-- a default colour) and a border, with optional bars that one can
-- add buttons to. 
-- 
--
-- table <= awbwnd_create(options)
-- possible options
--
local function awbwnd_show(self)
	show_image(self.anchor);
	resize_image(self.anchor, 0, 0);
	
	if (self.fullscreen) then
		move_image(self.anchor, 0, 0);
	else
		move_image(self.anchor, self.x, self.y); 
	end

	show_image(self.canvas);
end

local function awbwnd_reorder(self, orderv)
	order_image(self.bordert, orderv);
	order_image(self.borderd, orderv);
	order_image(self.borderl, orderv);
	order_image(self.borderr, orderv);
	order_image(self.canvas, orderv);

	for key, val in pairs(self.directions) do
			val:reorder(orderv);
	end
end

local function awbwnd_hide()
end

local function awbwnd_alloc(self)
	local bcol = settings.colourtable.dialog_border;
	local wcol = settings.colourtable.dialog_window;

	self.anchor = fill_surface(1, 1, 0, 0, 0);

--
-- we split the border into 4 objs to limit wasted fillrate,
-- only show if border is set to true (but alloc anyhow)
--
	self.bordert = fill_surface(1, 1, bcol.r, bcol.g, bcol.b);
	self.borderr = instance_image(self.bordert);
	show_image(self.borderr);
	self.borderl = instance_image(self.bordert);
	show_image(self.borderl);
	self.borderd = instance_image(self.bordert);
	show_image(self.borderd);
	link_image(self.bordert, self.anchor);

	if (self.border) then
		show_image(self.bordert);
	end

	self.resize_border = function(s)
		local bw = s.borderw;
		resize_image(s.bordert, s.width,           bw);
		resize_image(s.borderr, bw, s.height - bw * 2);
		resize_image(s.borderl, bw, s.height - bw * 2);
		resize_image(s.borderd, s.width,           bw);
		move_image(s.borderl, 0,            bw);
		move_image(s.borderr, s.width - bw, bw);
		move_image(s.borderd, 0, s.height - bw);
	end

	self:resize_border();
	
	local cwidth  = self.width  - self.borderw * 2;
	local cheight = self.height - self.borderw * 2;
	local cx      = self.borderw;
	local cy      = self.borderw;

-- then check the different "bars" and resize / offset based on that

--
-- these need update triggers when we move etc. as they can't be directly
-- attached to the anchor due to instancing requirements, canvas is just
-- a placeholder, the :container(vid) method will do the rest 
--
	if (self.mode == "container") then
		self.canvas = fill_surface(cwidth, cheight, 0, 0, 0); 
		move_image(self.canvas, cx, cy);
		link_image(self.canvas, self.anchor);
		show_image(self.canvas);	

	elseif (self.mode == "container_managed") then
		self.canvas = fill_surface(1, 1, 0, 0, 0);

-- these require scrollbars
	elseif (self.mode == "iconview") then
		self.canvas = fill_surface(cwidth, cheight, wcol.r, wcol.g, wcol.b);
		move_image(self.canvas, cx, cy);
		link_image(self.canvas, self.anchor);
		show_image(self.canvas);

	elseif (self.mode == "listview") then
		self.canvas = fill_surface(cwidth, cheight, wcol.r, wcol.g, wcol.b);
		move_image(self.canvas, cx, cy); 
		link_image(self.canvas, self.anchor);
	end

	return self;
end

local function awbwbar_refresh(self)
-- align against border while maintaining set "thickness"
	local bstep = self.parent.border and self.parent.borderw or 0;

	local bx = self.direction == "right" and 
		(self.parent.width - self.thickness - bstep) or bstep;
	local by = self.direction == "bottom" and 
		(self.parent.height - self.thickness - bstep) or bstep;

	move_image(self.activeid, bx, by);

-- then adjust based on other available bars, priority to top/bottom
	if (self.vertical) then
		local props  = image_surface_properties(self.parent.borderr, -1);
		
		if (self.parent.directions["top"]) then
			local thick = self.parent.directions["top"].thickness;
			nudge_image(self.root, 0, thick);
			props.height = props.height - thick; 
		end
		
		if (self.parent.directions["bottom"]) then
			props.height = props.height - self.parent.directions["bottom"].thickness;
		end

		resize_image(self.activeid, self.thickness, props.height);
	else
		local wbarw = image_surface_properties(self.parent.borderd, -1).width;
		wbarw = wbarw - self.parent.borderw * 2;	
		resize_image(self.activeid, wbarw, self.thickness);
	end

	link_image(self.activeid, self.root);
	image_mask_clear(self.activeid, MASK_OPACITY);
end

local function awbwnd_setwbar(dsttbl, active)
	if (dsttbl.activeid) then
		delete_image(dsttbl.activeid);
		dsttbl.activeid = nil;
	end

-- stretch and tile
	dsttbl.activeid = (type(active) == "function") and active() or 
		load_image(tostring(active), asynch_show);

	show_image(dsttbl.activeid);
	dsttbl:refresh();
end

local function awbbar_own(self, vid)
	if (vid == self.activeid) then
		return self.direction;
	end

-- FIXME: sweep for buttons here
end

local function awbbar_reorder(self, order)
	if (valid_vid(self.activeid)) then
		order_image(self.activeid, order);
	end

-- FIXME: sweep for buttons, set order+1
end

local function awbwnd_resize(self, neww, newh)
	local minh_pad = 0;
	local minw_pad = 0;

-- maintain contraints;
-- based on which bar-slots are available, make
-- sure that we accompany minimum thickness and height
	if (self.directions["left"] ~= nil) then 
		minw_pad = minw_pad + self.directions["left"].thickness;
		minh_pad = minh_pad + self.directions["left"].minheight;
	end

	if (self.directions["right"] ~= nil) then
		minw_pad = minw_pad + self.directions["right"].thickness;
		minh_pad = minh_pad + self.directions["right"].minheight;
	end

	if (self.directions["top"] ~= nil) then
		minh_pad = minh_pad + self.directions["top"].thickness;
		minw_pad = minw_pad + self.directions["top"].minheight;
	end

	if (self.directions["bottom"] ~= nil) then
		minh_pad = minh_pad + self.directions["bottom"].thickness;
		minw_pad = minw_pad + self.directions["bottom"].minwidth;
	end

	if (self.minw < minw_pad * 2) then
		self.minw = minw_pad * 2;
	end

	if (self.minh < minh_pad * 2) then
		self.minh = minh_pad * 2;
	end
 
	if (neww < self.minw) then
		neww = self.minw;
	end

	if (newh < self.minh) then
		newh = self.minh;
	end

-- FIXME: reposisition / resize buttons
end

local function awbwnd_addbar(self, direction, active_resdescr, inactive_resdescr, thickness)
	if (direction ~= "top" and direction ~= "bottom"
		and direction ~= "left" and direction ~= "right") or thickness < 1 then
		return false;
	end

	if (self.directions[direction]) then
		delete_image(self.directions[direction].root);
		delete_image(self.directions[direction].state);
	end

	local newdir = {};
	newdir.root      = fill_surface(1, 1, 0, 0, 0);
	newdir.parent    = self;
	newdir.activeres = active_resdescr;
	newdir.inactvres = inactive_resdescr;
	newdir.thickness = thickness;
	newdir.minwidth  = 0;
	newdir.minheight = 0;
	newdir.refresh   = awbwbar_refresh;
	newdir.vertical  = direction == "left" or direction == "right";
	newdir.direction = direction;
	newdir.own       = awbbar_own;
	newdir.reorder   = awbbar_reorder;

	link_image(newdir.root, self.bordert);
	awbwnd_setwbar(newdir, newdir.activeres);

	self.directions[direction] = newdir;

	return true;
end

local function awbwnd_newpos(self, newx, newy)
	if (self.fullscreen) then
		return;
	end

	move_image(self.anchor, newx, newy);
end

local function awbwnd_active(self, active)

	for key, val in pairs(self.directions) do
		local active_inactive = val.active and val.activeres or
			(val.inactvres and val.inactvres or val.activeres);
		val.activestate = active;

		awbwnd_setwbar(val, active_inactive);
	end
end

-- 
-- only bars (and their buttons) are clickable
--
local function awbwnd_own(self, vid)
	for ind, val in pairs(self.directions) do
		local res = val:own(vid);
		if (res) then
			return res;
		end 
	end

	if (vid == self.canvas) then
		return "canvas";
	end
end

local function awbwnd_refreshicons(self)
--
-- based on orientation, "flood fill" with icons
-- until we run out of space
-- 
	local max_y  = self.height;
	local max_x  = self.width;
	local step_row;
	local step_col;
	local start_x = 0;
	local start_y = 0;
	
	if (self.iconalign == "top") then
		step_col = {self.spacing, 0};
		step_row = {0, self.spacing};

	elseif (self.iconalign == "bottom") then
		step_col = {0, self.spacing};
		step_row = {-self.spacing, 0};
		start_y  = max_y;

	elseif (self.iconalign == "left") then
		step_col = {0, self.spacing};
		step_row = {self.spacing, 0};

	elseif (self.iconalign == "right") then
		step_col = {0, self.spacing};
		step_row = {-self.spacing, 0};
		start_x  = max_x; 

	else
		warning("awbwnd_refreshicons() -- poor icon alignment specified.");
	end

	for ind, val in pairs(self.icons) do
		local aprops = image_surface_properties(val.active);
		local lprops = image_surface_properties(val.label);
		local mwidth = aprops.width > lprops.width 
			and aprops.width or lprops.width;
		local mheight= aprops.height > lprops.height
			and aprops.height or lprops.height;

-- left and right need to be shifted based on their height	
		show_image({val.active, val.label});
		move_image(val.active, curx, cury);
	end
end

local function awbwnd_addicon(self, name, img, imga, font, fontsz, trigger)
	if (self.icons[name] ~= nil) then
		delete_image(self.icons[name].main);
		delete_image(self.icons[name].mainsel);
	end

	local newent   = {};
	newent.main    = type(img) == "string" and load_image(img) or img;
	newent.mainsel = type(img) == "string" and load_image(imga) or img;
	newent.active  = newent.main;
	newent.label   = render_text(string.format("\\f%s,%d %s", font, 
		fontsz, name)); 
	newent.trigger = trigger;
	
	self.icons[name] = newent;
	local props = image_surface_properties(newent.main);	

	self:refresh_icons();
end

local function awbwnd_canvas(self, newvid)
	if (self.mode == "container") then
		a = true;
	elseif (self.mode == "container_managed") then
		a = true;
	elseif (self.mode == "iconview" or 
		self.mode == "listview") then
		a = true;
	end
end

function awbwnd_create(options)
	local restbl = {
		show    = awbwnd_show,
		hide    = awbwnd_hide,
		active  = awbwnd_active,
		add_bar = awbwnd_addbar, 
		resize  = awbwnd_newsize,
		move    = awbwnd_newpos,
		own     = awbwnd_own,
		reorder = awbwnd_reorder,
		update_canvas = awbwand_canvas,

-- static default properties
		mode = "container", -- {container, container_managed, iconview, listview} 
		fullscreen = false,
		border = true,
		borderw = 2,
		minw = 0,
		minh = 0,
		spacing = 16,
		activestate = true,

-- dynamic default properties
		x = 0, 
		y = 0,
		minimized = false,
		directions = {}
	};

	if options ~= nil then 
		for key, val in pairs(options) do
			restbl[key] = val;
		end
	end

	if (restbl.mode == "iconview") then
		restbl.add_icon = awbwnd_addicon;
		restbl.refresh_icons = awbwnd_refreshicons;
		restbl.icons = {};
	end

	if (restbl.fullscreen) then
		restbl.width  = VRESW;
		restbl.height = VRESH;
		restbl.x = 0;
		restbl.y = 0;
	end

	restbl = awbwnd_alloc(restbl);
	return restbl;	
end
 
