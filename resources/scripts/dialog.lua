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
	move_image(vid, 0.5 * (self.maxwidth - image_surface_properties(vid).width), self.maxheight / 4 * 3);
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
	local maxstrlen = string.len(self.message);

	for ind, val in ipairs(self.options) do
		local len = string.len(val);
		if (len > maxstrlen) then maxstrlen = len; end
	end
	
	local tmpstr = string.rep("M", maxstrlen);
	local tmpvid = render_text( restable.messagefont .. tmpstr );
	local props = image_surface_properties( tmpvid );
	restable.maxwidth = props.width; 
	restable.maxheight = props.height * 4;

	delete_image(tmpvid);
end

local function dialog_free(self)
	if (restable.anchor) then
		delete_image(restable.anchor);
	end
end

local function dialog_show(self)
-- take anchor and place it one element outside of view, then all inherited properties (position, opacity etc.) can be retained
	if (restable.anchor == nil) then
		restable.anchor = fill_surface(1, 1, 0, 0, 0);
		move_image(restable.anchor, -1, -1);
		
		restable.border = fill_surface(self.maxwidth + 26, self.maxheight + 26, settings.colourtable.dialog_border.r, settings.colourtable.dialog_border.g, settings.colourtable.dialog_border.b );
		restable.window = fill_surface(self.maxwidth + 20, self.maxheight + 20, settings.colourtable.dialog_window.r, settings.colourtable.dialog_window.g, settings.colourtable.dialog_window.b );

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
	link_image(header, self.window);
	move_image(header, 0.5 * (self.maxwidth - image_surface_properties(header).width), self.maxheight / 4);
	order_image(header, max_current_image_order() + 1);
	image_mask_clear(header, MASK_OPACITY);
	show_image(header);
	
	local borderp = image_surface_properties( restable.border );
	self:nextlabel(0);
	move_image(restable.anchor, 0.5 * (VRESW - borderp.width), 0.5 * (VRESH - borderp.height) );
	blend_image(restable.border, 1.0, 5);
	self.visible = true;
end

function dialog_create(message, options, canescape)
	restable = {};
	
-- forceload colourtable if its missing
	if (#options == 0) then return; end
	if (settings == nil) then settings = {}; end
	if (settings.colourtable == nil) then settings.colourtable = system_load("scripts/colourtable.lua")(); end
	
	restable.messagefont = settings.colourtable.label_fontstr; 
	restable.optionfont = settings.colourtable.data_fontstr; 
	restable.show = dialog_show;
	restable.destroy = dialog_free;
	restable.options = options;
	restable.current = 1;
	restable.message = message;
	restable.input = dialog_input;
	restable.nextlabel = dialog_nextlabel;
	restable.canescape = canescape;

	dialog_sizewindow(restable);

	return restable;
end
