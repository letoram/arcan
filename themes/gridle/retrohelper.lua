--
-- Assisting tables (and possibly illustrative graphics) showing the
-- mapping between PLAYERn_BUTTONm vs. target/game specific
--
-- these currently don't take what's "plugged" into each port currently
--

-- identstr comes from the first "message" event sent to the event handler
local function retrohelper_psx(porttype)
	restbl.max_buttons = 4 + 4;
	restbl.max_axes = 2;

	restbl.ident = {};

	local x = load_image("icons/ps_x.png");
	if (not valid_vid(x)) then
		x = fill_surface(32, 32, 141, 187, 243);
	end

	local square = load_image("icons/ps_square.png");
	if (not valid_vid(square)) then
		square = fill_surface(32, 32, 246, 136, 212);
	end

	local circle = load_image("icons/ps_circle.png");
	if (not valid_vid(circle)) then
		circle = fill_surface(32, 32, 255, 89, 77);
	end

	local triangle = load_image("icons/ps_tri.png");
	if (not valid_vid(triangle)) then
		triangle = fill_surface(32, 32, 0, 202, 185);
	end

	table.insert(restbl.ident, circle);
	table.insert(restbl.ident, x);
	table.insert(restbl.ident, triangle);
	table.insert(restbl.ident, square);
	
	restbl.destroy = function()
		for ind, val in ipairs(restbl.identimg) do
			delete_image(val);
		end
	end

	return restbl;
end

function retrohelper_lookup(identstr, porttype)
	if (string.match(identstr, "Mednafen.*PSX")) then
		return retrohelper_psx(porttype);
	else
		return nil;
	end
end
