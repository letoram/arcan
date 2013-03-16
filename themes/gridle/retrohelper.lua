--
-- Assisting tables (and possibly illustrative graphics) showing the
-- mapping between PLAYERn_BUTTONm vs. target/game specific
--
-- these currently don't take what's "plugged" into each port currently
--

-- identstr comes from the first "message" event sent to the event handler
local function retrohelper_psx(porttype)
	restbl.buttons = 4 + 4;
	restbl.axes = 2;

	restbl.ident = {};

	local add = function(key, icon, label)
		restbl.ident[key] = {};
		restbl.ident[key].icon = icon;
		restbl.ident[key].label = label;
	end

	add("PLAYER1_BUTTON1","icons/ps_circle.png", "Player 1, Circle");
	add("PLAYER1_BUTTON2","icons/ps_x.png", "Player 1, Cross");
	add("PLAYER1_BUTTON3","icons/ps_tri.png", "Player 1, Triangle");
	add("PLAYER1_BUTTON4","icons/ps_square.png", "Player 1, Square");
	add("PLAYER1_BUTTON5","icons/ps_l1.png", "Player 1, L1");
	add("PLAYER1_BUTTON6","icons/ps_r1.png", "Player 1, R1");
	add("PLAYER1_BUTTON7","icons/ps_l2.png", "Player 1, L2");
	add("PLAYER1_BUTTON8","icons/ps_r2.png", "Player 1, R2");

	add("PLAYER1_AXIS1", nil, "Player 1, Left Stick (X)");
	add("PLAYER1_AXIS2", nil, "Player 1, Left Stick (Y)");
	add("PLAYER1_AXIS3", nil, "Player 1, Right Stick (X)");
	add("PLAYER1_AXIS4", nil, "Player 1, Right Stick (Y)");

	add("PLAYER2_BUTTON1","icons/ps_circle.png", "Player 2, Circle");
	add("PLAYER2_BUTTON2","icons/ps_x.png", "Player 2, Cross");
	add("PLAYER2_BUTTON3","icons/ps_tri.png", "Player 2, Triangle");
	add("PLAYER2_BUTTON4","icons/ps_square.png", "Player 2, Square");
	add("PLAYER2_BUTTON5","icons/ps_l1.png", "Player 2, L1");
	add("PLAYER2_BUTTON6","icons/ps_r1.png", "Player 2, R1");
	add("PLAYER2_BUTTON7","icons/ps_l2.png", "Player 2, L2");
	add("PLAYER2_BUTTON8","icons/ps_r2.png", "Player 2, R2");

	add("PLAYER2_AXIS1", nil, "Player 2, Left Stick (X)");
	add("PLAYER2_AXIS2", nil, "Player 2, Left Stick (Y)");
	add("PLAYER2_AXIS3", nil, "Player 2, Right Stick (X)");
	add("PLAYER2_AXIS3", nil, "Player 2, Right Stick (Y)");

	return restbl;
end

function retrohelper_lookup(identstr, porttype)
	if (string.match(identstr, "Mednafen.*PSX")) then
		return retrohelper_psx(porttype);
	else
		return nil;
	end
end
