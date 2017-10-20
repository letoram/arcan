lines = {
COLOR_PRIMARY, "primary",
COLOR_SECONDARY, "secondary",
COLOR_BG, "background",
COLOR_TEXT, "text",
COLOR_CURSOR, "cursor",
COLOR_ALTCURSOR, "altcursor",
COLOR_HIGHLIGHT, "highlight",
COLOR_LABEL, "label",
COLOR_WARNING, "warning",
COLOR_ERROR, "error",
COLOR_INACTIVE, "inactive"
};

local ht = {
	resize = function(tui, w, h)
		conn:cursor_to(0, 0);

		for i=0,#lines-1,2 do
			local attr = tui_attr();
			local r,g,b = conn:get_color(lines[i+1]);
			attr.fr = r; attr.fg = g; attr.fb = b;
			conn:write(lines[i+2], attr);
		end
	end
};

conn = tui_open("color_test", "") or error("couldn't connect");
conn:set_handlers(ht);
ht.resize(conn);

while(conn:process()) do
	conn:refresh();
end

