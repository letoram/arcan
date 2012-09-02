-- simple [message list] (LEFT, RIGHT, SELECT, ESCAPE) selection dialog

local function dialog_nextlabel(self, step)
	if (self.labelstr) then delete_image(self.labelstr); self.labelstr = nil; end

-- move and cap
	self.current = self.current + step;
	if (self.current < 1) then self.current = #self.options; end
	if (self.current > #self.options) then self.current = 1; end
	
	local vid = render_text(self.optionfont .. self.options[ self.current ]);
	local props = image_surface_properties(self.window);

-- position below message string, center and clip to window
	link_image(vid, self.window);
	image_clip_on(vid);
	move_image(vid, 0.5 * (props.width - image_surface_properties(vid).width), self.maxheight / 4 * 3);
	order_image(vid, max_current_image_order() + 1);
	image_mask_clear(vid, MASK_OPACITY);
	show_image(vid);
	
	self.labelstr = vid;
end

local function dialog_input(self, label )
	local resstr = nil;
	if (not self.visible) then return nil; end
	if (label == "MENU_LEFT") then
		self:nextlabel(-1);
	elseif (label == "MENU_RIGHT") then
		self:nextlabel(1);
	elseif (label == "MENU_SELECT") then
		resstr = self.options[ self.current ];
		self:destroy();
	elseif (label == "MENU_ESCAPE" and self.canescape) then
		resstr = "MENU_ESCAPE";
		self:destroy();
	end
	
	return resstr;
end

local function dialog_sizewindow(self)
-- figure out reasonable dimensions for the window
	local strw, strh = text_dimensions(self.message);
	
	if (self.options) then
		local maxh = strh;
		
		for ind, val in ipairs(self.options) do
			local optw, opth = text_dimensions(val);
			if (optw > strw) then strw = optw; end
			if (opth > strh) then strh = opth; end
		end

		strh = strh + maxh;
	end

	restable.maxwidth = strw; 
	restable.maxheight = strh;
end

local function dialog_free(self, timer)
	local time = 0;
	if (timer and type(timer) == "number" and time > 0) then time = timer; end
	
	if (self.anchor) then
		expire_image(self.anchor, time);
	end
end

local function dialog_show(self)
-- take anchor and place it one element outside of view, then all inherited properties (position, opacity etc.) can be retained
	if (restable.anchor == nil) then
		restable.anchor = fill_surface(1, 1, 0, 0, 0);
		move_image(restable.anchor, -1, -1);
		
		local windw = self.maxwidth; 
		local padding = windw * 0.3;
		restable.border = fill_surface(windw + padding + 6, self.maxheight + 26, settings.colourtable.dialog_border.r, settings.colourtable.dialog_border.g, settings.colourtable.dialog_border.b );
		restable.window = fill_surface(windw + padding, self.maxheight + 20, settings.colourtable.dialog_window.r, settings.colourtable.dialog_window.g, settings.colourtable.dialog_window.b );

		link_image(restable.border, restable.anchor);
		link_image(restable.window, restable.anchor);
		blend_image(restable.anchor, 1.0, 15);
		blend_image(restable.border, settings.colourtable.dialog_border.a);
		blend_image(restable.window, settings.colourtable.dialog_window.a);
		
		order_image(restable.anchor, 0);
		order_image(restable.border, max_current_image_order() + 1);
		order_image(restable.window, max_current_image_order() + 1);
		move_image(restable.window, 3, 3);
	end

	local header = render_text(restable.messagefont .. self.message);
	local windw = image_surface_properties(restable.window).width;
	local props = image_surface_properties(header);
	
	link_image(header, self.window);
	move_image(header, 0.5 * ( windw - props.width), 12);
	order_image(header, max_current_image_order() + 1);
	image_mask_clear(header, MASK_OPACITY);
	image_clip_on(header);
	show_image(header);
	
	local borderp = image_surface_properties( restable.border );
	if (self.options) then
		self:nextlabel(0);
	end
	
	local x = 0.5 * (VRESW - borderp.width);
	local y = 0.5 * (VRESH - borderp.height);
	
	if (self.valign == "top") then    y = 0; end
	if (self.halign == "left") then   x = 0; end
	if (self.valign == "bottom") then y = VRESH - borderp.height; end
	if (self.halign == "right") then  x = VRESW - borderp.width; end

	move_image(restable.anchor, x, y);
	blend_image(restable.border, 1.0, 5);
	self.visible = true;
end

function dialog_create(message, options, canescape)
	if (settings == nil) then settings = {}; end
	if (settings.colourtable == nil) then settings.colourtable = system_load("scripts/colourtable.lua")(); end

	restable = {};
	
	restable.messagefont = settings.colourtable.label_fontstr; 
	restable.optionfont = settings.colourtable.data_fontstr; 
	restable.show = dialog_show;
	restable.destroy = dialog_free;
	restable.options = options;
	restable.current = 1;
	restable.message = message;

-- no options? just use as an info window
	if (options ~= nil and #options > 0) then
		restable.input = dialog_input;
		restable.nextlabel = dialog_nextlabel;
		restable.canescape = canescape;
	end

	dialog_sizewindow(restable);

	return restable;
end
