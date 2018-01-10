local function draw(ctx)
	local fg_r, fg_g, fg_b = ctx:get_color(tui_color.primary);
	local bg_r, bg_g, bg_b = ctx:get_color(tui_color.background);
	local iattr = tui_attr(
		{fr = bg_r, fg = bg_g, fb = bg_b, br = fg_r, bg = fg_g, bb = fg_b}
	);
	iattr = tui_attr(
		{br = 255, bg = 255, bb = 255}
	);

-- if we don't do this, we get interesting visual glitches
-- if we DO do this, we get interesting black frames
--	ctx:erase_screen();
	local w, h = ctx:dimensions()
	for x=0,w-1 do
		ctx:write_to(x, 0, "S", iattr)
		ctx:write_to(x, h-1, "S", iattr)
	end
	for y=0,h-1 do
		ctx:write_to(0, y, "S", iattr)
		ctx:write_to(w-1, y, "S", iattr)
	end
	ctx:refresh()
end

local ht = {
	resized = function(tui, w, h)
		draw(tui);
	end,
	recolor = function(tui)
		draw(tui);
	end
};

conn = tui_open("draw_test", "") or error("couldn't connect");
conn:set_handlers(ht);
conn:set_flags(tui_flags.hide_cursor);
draw(conn);

while(conn:process()) do
	conn:refresh();
end

