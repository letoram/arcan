--
-- Assisting tables (and possibly illustrative icons) showing the
-- mapping between PLAYERn_BUTTONm vs. target/game specific
--

local add = function(restbl, key, icon, label, skip)
    restbl.ident[key] = {};
    restbl.ident[key].icon = icon;
    restbl.ident[key].label = label;
		restbl.ident[key].skip  = skip;
end

-- identstr comes from the first "message" event sent to the event handler
local function retrohelper_psx(porttype)
	restbl.buttons = 4 + 4;
	restbl.axes = 4;
	restbl.players = 2;
	restbl.ident = {};

	add(restbl, "PLAYER1_COIN1", nil, "(Not Used)", true);
	add(restbl, "PLAYER1_BUTTON1","icons/ps_circle.png", "Player 1, Circle");
	add(restbl, "PLAYER1_BUTTON2","icons/ps_x.png", "Player 1, Cross");
	add(restbl, "PLAYER1_BUTTON3","icons/ps_tri.png", "Player 1, Triangle");
	add(restbl, "PLAYER1_BUTTON4","icons/ps_square.png", "Player 1, Square");
	add(restbl, "PLAYER1_BUTTON5","icons/ps_l1.png", "Player 1, L1");
	add(restbl, "PLAYER1_BUTTON6","icons/ps_r1.png", "Player 1, R1");
	add(restbl, "PLAYER1_BUTTON7","icons/ps_l2.png", "Player 1, L2");
	add(restbl, "PLAYER1_BUTTON8","icons/ps_r2.png", "Player 1, R2");
	add(restbl, "PLAYER1_AXIS1", nil, "Player 1, Left Stick (X)");
	add(restbl, "PLAYER1_AXIS2", nil, "Player 1, Left Stick (Y)");
	add(restbl, "PLAYER1_AXIS3", nil, "Player 1, Right Stick (X)");
	add(restbl, "PLAYER1_AXIS4", nil, "Player 1, Right Stick (Y)");

	add(restbl, "PLAYER2_COIN1", nil, "(Not Used)", true); 
	add(restbl, "PLAYER2_BUTTON1","icons/ps_circle.png", "Player 2, Circle");
	add(restbl, "PLAYER2_BUTTON2","icons/ps_x.png", "Player 2, Cross");
	add(restbl, "PLAYER2_BUTTON3","icons/ps_tri.png", "Player 2, Triangle");
	add(restbl, "PLAYER2_BUTTON4","icons/ps_square.png", "Player 2, Square");
	add(restbl, "PLAYER2_BUTTON5","icons/ps_l1.png", "Player 2, L1");
	add(restbl, "PLAYER2_BUTTON6","icons/ps_r1.png", "Player 2, R1");
	add(restbl, "PLAYER2_BUTTON7","icons/ps_l2.png", "Player 2, L2");
	add(restbl, "PLAYER2_BUTTON8","icons/ps_r2.png", "Player 2, R2");
	add(restbl, "PLAYER2_AXIS1", nil, "Player 2, Left Stick (X)");
	add(restbl, "PLAYER2_AXIS2", nil, "Player 2, Left Stick (Y)");
	add(restbl, "PLAYER2_AXIS3", nil, "Player 2, Right Stick (X)");
	add(restbl, "PLAYER2_AXIS4", nil, "Player 2, Right Stick (Y)");

	return restbl;
end

-- porttype for multitaps etc.?
function retrohelper_bsnes(porttype)
	restbl.buttons = 6;
	restbl.axes    = 0;
	restbl.players = 2;
	restbl.ident  = {};

	add(restbl, "PLAYER1_COIN1", nil, "(not used)", true); 
	add(restbl, "PLAYER1_BUTTON1", "icons/snes_a.png", "Player 1, A Button");
	add(restbl, "PLAYER1_BUTTON2", "icons/snes_b.png", "Player 1, B Button");
	add(restbl, "PLAYER1_BUTTON3", "icons/snes_x.png", "Player 1, X Button");
	add(restbl, "PLAYER1_BUTTON4", "icons/snes_y.png", "Player 1, Y Button");
	add(restbl, "PLAYER1_BUTTON5", "icons/ps_l1.png", "Player 1, L Button");
	add(restbl, "PLAYER1_BUTTON6", "icons/ps_r1.png", "Player 1, R Button");

	add(restbl, "PLAYER2_COIN1", nil, "(not used)", true); 
	add(restbl, "PLAYER2_BUTTON1", "icons/snes_a.png", "Player 2, A Button");
	add(restbl, "PLAYER2_BUTTON2", "icons/snes_b.png", "Player 2, B Button");
	add(restbl, "PLAYER2_BUTTON3", "icons/snes_x.png", "Player 2, X Button");
	add(restbl, "PLAYER2_BUTTON4", "icons/snes_y.png", "Player 2, Y Button");
	add(restbl, "PLAYER2_BUTTON5", "icons/ps_l1.png", "Player 2, L Button");
	add(restbl, "PLAYER2_BUTTON6", "icons/ps_r1.png", "Player 2, R Button");

	return restbl;
 end

function retrohelper_gambatte(porttype)
	restbl.buttons = 2;
	restbl.axes    = 0;
	restbl.players = 1;
	restbl.ident   = {};
	
	add(restbl, "PLAYER1_COIN1",   nil, "(not used)", true);
	add(restbl, "PLAYER1_BUTTON1", nil, "A Button");
	add(restbl, "PLAYER1_BUTTON2", nil, "B Button");
	add(restbl, "PLAYER1_START",   nil, "Start");
	add(restbl, "PLAYER1_SELECT",  nil, "Select");

	return restbl;
end

function retrohelper_nx(porttype)
	restbl.buttons = 6;
	restbl.axes    = 0;
	restbl.players = 1;
	restbl.ident   = {};

	add(restbl, "PLAYER1_COIN1",   nil, "(Reserved)", true); 
	add(restbl, "PLAYER1_START",   nil, "Inventory");
	add(restbl, "PLAYER1_SELECT",  nil, "System Settings");
	add(restbl, "PLAYER1_BUTTON1", nil, "(Reserved)", true); 
	add(restbl, "PLAYER1_BUTTON2", nil, "Jump");
	add(restbl, "PLAYER1_BUTTON3", nil, "Map");
	add(restbl, "PLAYER1_BUTTON4", nil, "Fire");
	add(restbl, "PLAYER1_BUTTON5", nil, "Previous Weapon");
	add(restbl, "PLAYER1_BUTTON6", nil, "Next Weapon");

	return restbl;
end

function retrohelper_lookup(identstr, porttype)

	if (string.match(identstr, "Mednafen.*PSX")) then
		return retrohelper_psx(porttype);
	elseif (string.match(identstr, "NXEngine")) then
		return retrohelper_nx(porttype);
	elseif (string.match(identstr, "bSNES") or string.match(identstr, "SNES9x")) then
		return retrohelper_bsnes(porttype);
	elseif (string.match(identstr, "gambatte")) then
		return retrohelper_gambatte(porttype);
	else
		return nil;
	end

end
