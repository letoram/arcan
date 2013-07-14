--
-- AWB Window Manager,
-- More advanced windows from the (awbwnd.lua) base
-- tracking ordering, creation / destruction /etc.
--

--
-- Spawn a normal class window with optional caption
--

-- #attic for now
local awbwnd_invsh = [[
uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
	vec4 col = texture2D(map_diffuse, texco);
	gl_FragColor = vec4(1.0 - col.r,
		1.0 - col.g, 
		1.0 - col.b,
		col.a * obj_opacity);
}
]];
-- /#attic

local awb_wtable = {};
local awb_cfg = {
	wlimit      = 10,
	activeres   = "awbicons/border.png",
	inactiveres = "awbicons/border_inactive.png",
	alphares    = "awbicons/alpha.png",
	topbar_sz   = 16
};

local function awbwman_focus(wnd)
	if (awb_cfg.focus) then
		if (awb_cfg.focus == wnd) then
			return;
		end

		order_image(awb_cfg.focus.anchor, #awb_wtable * 10 - 10);
		awb_cfg.focus:inactive();
	end

	order_image(wnd.anchor, #awb_wtable * 10);
	wnd:active();

	awb_cfg.focus = wnd;
end

local function awbwman_close(wcont)
	for i=1,#awb_wtable do
		if (awb_wtable[i] == wcont) then
			table.remove(awb_wtable, i);
			break;
		end
	end

	if (awb_cfg.focus == wcont) then
		awb_cfg.focus = nil;
		warning("fixme; find a new window to focus\n");
	end
	
	wcont:destroy(15);
end

local function awbwman_regwnd(wcont)
	table.insert(awb_wtable, wcont);
	awbwman_focus(wcont);
end

local function awbman_mhandlers(wnd, bar)
	bar.drag = function(self, vid, x, y)
		awbwman_focus(self.parent);
		local props = image_surface_resolve_properties(self.parent.anchor);
		wnd:move(props.x + x, props.y + y);
	end
 
	bar.dblclick = function(self, vid, x, y)
		if (self.maximized) then
			wnd:move(self.oldx, self.oldy);
			wnd:resize(self.oldw, self.oldh);
			self.maximized = false;
		else
			self.maximized = true;
			self.oldx = wnd.x;
			self.oldy = wnd.y;
			self.oldw = wnd.width;
			self.oldh = wnd.height;
			wnd:move(0, 20);
			wnd:resize(VRESW, VRESH - 20);
		end
	end

	bar.drop = function(self, vid, x, y)
		awbwman_focus(self.parent);
		local props = image_surface_resolve_properties(self.parent.anchor);
		wnd:move(math.floor(props.x), math.floor(props.y));
	end

	bar.click = function(self, vid, x, y)
		awbwman_focus(self.parent);
	end

  mouse_addlistener(bar, {"drag", "drop", "click", "dblclick"});
end

function awbwman_spawn(caption)
	local wcont  = awbwnd_create({});
	local tmpfun = wcont.destroy;

-- default drag, click, double click etc.
	wcont.destroy = function(self, time)
		mouse_droplistener(self);
		mouse_droplistener(self.top);
		tmpfun(self, time);
	end

-- single color canvas (but treated as textured)
-- for shader or replacement 
	local r = colortable.bgcolor[1];
	local g = colortable.bgcolor[2];
	local b = colortable.bgcolor[3];

-- separate click handler for the canvas area
-- as more advanced windows types (selection etc.) may need 
-- to override
	local canvas = fill_surface(wcont.width, wcont.height, r, g, b);
	wcont:update_canvas(canvas, true);
	local chandle = {};
	chandle.click = function(vid, x, y)
		awbwman_focus(wcont);
	end
	chandle.own = function(self,vid)
		return vid == canvas; 
	end
	chandle.vid = canvas;
	mouse_addlistener(chandle, {"click"});

-- top windowbar
	local tbar = wcont:add_bar("t", awb_cfg.activeres,
		awb_cfg.inactiveres, awb_cfg.topbar_sz);
	tbar:add_icon("l", awb_cfg.bordericns["close"], function()
		awbwman_close(wcont);
	end);

	local rbar = wcont:add_bar("r", awb_cfg.alphares,
		awb_cfg.alphares, awb_cfg.topbar_sz, 0);
	image_mask_set(rbar.vid, MASK_UNPICKABLE);

-- register, push to front etc.
  awbman_mhandlers(wcont, tbar);
	awbwman_regwnd(wcont);

	hide_image(wcont.anchor);
	blend_image(wcont.anchor, 1.0, 15);

	return wcont;
end

--
-- Load / Store default settings for window behavior etc.
--
function awbwman_init()
	awb_cfg.bordericns = {};
	awb_cfg.bordericns["close"]    = load_image("awbicons/close.png");
	awb_cfg.bordericns["resize"]   = load_image("awbicons/resize.png");
end
