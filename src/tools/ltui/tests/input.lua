-- input test
--
-- this test show all the possible input options, from querying own inputs
-- all the way up to text and mouse motion
--

conn = tui_open("input_test", "") or error("couldn't connect");

local function write(c, msg)
	local attr = tui_attr(i);
	print("write:", msg);
	c:write(msg, attr);
end

local function mods_to_string(mods)
	return "";
end

-- C är fel metatabell!

conn:set_handlers({
	query_label = function(c, ind, country, lang)
		if ind == 0 then
			return "TEST",
				"label used for testing", TUI_ITYPE_BTN, symbols["L"]
		end
	end,
	label = function(c, lbl)
		write(c, (act and "label-press(" or "label-release(") .. lbl .. ")")
		return true -- consume
	end,
	utf8 = function(c, str)
		if (str == "\r") then
			c:cursor_to(0, 0);
		else
			write(c, "utf8(" .. str .. ")")
		end
		return true
	end,
	mouse_motion = function(c, rel, x, y, mods)
		write(c, string.format("mouse@%d,%d (%s)", x, y, mods_to_string(mods)))
	end,
	mouse_button = function(c, id, active, x, y, mods)
		write(c, string.format("mouse-button(%d=%d)@%d,%d (%s)",
			id, tonumber(active), x, y, mods_to_string(mods)))
	end,
	key = function(c, id, sym, code, mods)
		write(c, string.format(
			"generic-key: (%d:%d:%d) (%s)", id, sym, code, mods_to_string(mods)))
	end
});

-- safe to pretty much just run this.
while(conn:process()) do
	conn:refresh();
end
