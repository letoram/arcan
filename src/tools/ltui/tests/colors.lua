local function draw(ctx)
	local fg_r, fg_g, fg_b = ctx:get_color(tui_color.primary);
	local bg_r, bg_g, bg_b = ctx:get_color(tui_color.background);
	local iattr = tui_attr(
		{fr = bg_r, fg = bg_g, fb = bg_b, br = fg_r, bg = fg_g, bb = fg_b}
	);

	ctx:erase_screen();
	local w, h = ctx:dimensions()
	for x=0,w-1 do
		ctx:write_to(x, 0, "S", iattr)
		ctx:write_to(x, h-1, "S", iattr)
	end
	for y=0,h-1 do
		ctx:write_to(0, y, "S", iattr)
		ctx:write_to(w-1, y, "S", iattr)
	end

	local set = {};
	for k,v in pairs(tui_color) do
		table.insert(set, k)
	end

	local rowst = ""
	for i=1,w-2 do
		rowst = rowst .. " "
	end

	local ind = 1
	for y = 1,h-1,2 do
		iattr.br, iattr.bg, iattr.bb = ctx:get_color(tui_color[set[ind]])
		ctx:write_to(1, y, rowst, iattr)
		ctx:write_to(1, y, set[ind], iattr)
		ind = ind + 1
		if ind > #set then
			ind = 1
		end
	end

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

while (conn:refresh()) do
	conn:process();
end
