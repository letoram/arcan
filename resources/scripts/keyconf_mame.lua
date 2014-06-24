-- basic exporter plugin from a keyconf- based symbol table into a default.cfg style MAME config.
--
-- This works basically by taking the symbols ("labels") from the keyconf table
-- and every mapped symbol with a corresponding translation in xlatetbl will have its
-- 'id' format (i.e. analogdigitaltranslated:devid:subdevid) translated to the corresponding MAME version.
--
--
-- this table was derived from src/emu/inpttype.h
-- left column keyconf labelid right column mame labelid
local sdlsymtbl = system_load("scripts/symtable_mame.lua")();
local xlatetbl = {
PLAYER1_UP      = "P1_JOYSTICK_UP",
PLAYER1_DOWN    = "P1_JOYSTICK_DOWN",
PLAYER1_LEFT    = "P1_JOYSTICK_LEFT",
PLAYER1_RIGHT   = "P1_JOYSTICK_RIGHT",
PLAYER1_DOWN    = "P1_JOYSTICK_DOWN",
PLAYER1_BUTTON1 = "P1_BUTTON1",
PLAYER1_BUTTON2 = "P1_BUTTON2",
PLAYER1_BUTTON3 = "P1_BUTTON3",
PLAYER1_BUTTON4 = "P1_BUTTON4",
PLAYER1_BUTTON5 = "P1_BUTTON5",
PLAYER1_BUTTON6 = "P1_BUTTON6",
PLAYER1_BUTTON7 = "P1_BUTTON7",
PLAYER1_BUTTON8 = "P1_BUTTON8",
PLAYER1_BUTTON9 = "P1_BUTTON9",
PLAYER1_BUTTON10= "P1_BUTTON10",
PLAYER1_BUTTON11= "P1_BUTTON11",
PLAYER1_BUTTON12= "P1_BUTTON12",
PLAYER1_BUTTON13= "P1_BUTTON13",
PLAYER1_BUTTON14= "P1_BUTTON14",
PLAYER1_BUTTON15= "P1_BUTTON15",
PLAYER1_BUTTON16= "P1_BUTTON16",
PLAYER1_START   = "START1",
PLAYER1_COIN1   = "COIN1",
PLAYER2_SELECT  = "P2_SELECT",
PLAYER2_UP      = "P2_JOYSTICK_UP",
PLAYER2_DOWN    = "P2_JOYSTICK_DOWN",
PLAYER2_LEFT    = "P2_JOYSTICK_LEFT",
PLAYER2_RIGHT   = "P2_JOYSTICK_RIGHT",
PLAYER2_DOWN    = "P2_JOYSTICK_DOWN",
PLAYER2_BUTTON1 = "P2_BUTTON1",
PLAYER2_BUTTON2 = "P2_BUTTON2",
PLAYER2_BUTTON3 = "P2_BUTTON3",
PLAYER2_BUTTON4 = "P2_BUTTON4",
PLAYER2_BUTTON5 = "P2_BUTTON5",
PLAYER2_BUTTON6 = "P2_BUTTON6",
PLAYER2_BUTTON7 = "P2_BUTTON7",
PLAYER2_BUTTON8 = "P2_BUTTON8",
PLAYER2_BUTTON9 = "P2_BUTTON9",
PLAYER2_BUTTON10= "P2_BUTTON10",
PLAYER2_BUTTON11= "P2_BUTTON11",
PLAYER2_BUTTON12= "P2_BUTTON12",
PLAYER2_BUTTON13= "P2_BUTTON13",
PLAYER2_BUTTON14= "P2_BUTTON14",
PLAYER2_BUTTON15= "P2_BUTTON15",
PLAYER2_BUTTON16= "P2_BUTTON16",
PLAYER2_START   = "START2",
PLAYER2_COIN1   = "COIN2",
PLAYER2_SELECT  = "P2_SELECT",
PLAYER3_UP      = "P3_JOYSTICK_UP",
PLAYER3_DOWN    = "P3_JOYSTICK_DOWN",
PLAYER3_LEFT    = "P3_JOYSTICK_LEFT",
PLAYER3_RIGHT   = "P3_JOYSTICK_RIGHT",
PLAYER3_DOWN    = "P3_JOYSTICK_DOWN",
PLAYER3_BUTTON1 = "P3_BUTTON1",
PLAYER3_BUTTON2 = "P3_BUTTON2",
PLAYER3_BUTTON3 = "P3_BUTTON3",
PLAYER3_BUTTON4 = "P3_BUTTON4",
PLAYER3_BUTTON5 = "P3_BUTTON5",
PLAYER3_BUTTON6 = "P3_BUTTON6",
PLAYER3_BUTTON7 = "P3_BUTTON7",
PLAYER3_BUTTON8 = "P3_BUTTON8",
PLAYER3_BUTTON9 = "P3_BUTTON9",
PLAYER3_BUTTON10= "P3_BUTTON10",
PLAYER3_BUTTON11= "P3_BUTTON11",
PLAYER3_BUTTON12= "P3_BUTTON12",
PLAYER3_BUTTON13= "P3_BUTTON13",
PLAYER3_BUTTON14= "P3_BUTTON14",
PLAYER3_BUTTON15= "P3_BUTTON15",
PLAYER3_BUTTON16= "P3_BUTTON16",
PLAYER3_START   = "START3",
PLAYER3_COIN1   = "COIN3",
PLAYER3_SELECT  = "P3_SELECT",
PLAYER4_UP      = "P4_JOYSTICK_UP",
PLAYER4_DOWN    = "P4_JOYSTICK_DOWN",
PLAYER4_LEFT    = "P4_JOYSTICK_LEFT",
PLAYER4_RIGHT   = "P4_JOYSTICK_RIGHT",
PLAYER4_DOWN    = "P4_JOYSTICK_DOWN",
PLAYER4_BUTTON1 = "P4_BUTTON1",
PLAYER4_BUTTON2 = "P4_BUTTON2",
PLAYER4_BUTTON3 = "P4_BUTTON3",
PLAYER4_BUTTON4 = "P4_BUTTON4",
PLAYER4_BUTTON5 = "P4_BUTTON5",
PLAYER4_BUTTON6 = "P4_BUTTON6",
PLAYER4_BUTTON7 = "P4_BUTTON7",
PLAYER4_BUTTON8 = "P4_BUTTON8",
PLAYER4_BUTTON9 = "P4_BUTTON9",
PLAYER4_BUTTON10= "P4_BUTTON10",
PLAYER4_BUTTON11= "P4_BUTTON11",
PLAYER4_BUTTON12= "P4_BUTTON12",
PLAYER4_BUTTON13= "P4_BUTTON13",
PLAYER4_BUTTON14= "P4_BUTTON14",
PLAYER4_BUTTON15= "P4_BUTTON15",
PLAYER4_BUTTON16= "P4_BUTTON16",
PLAYER4_START   = "START2",
PLAYER4_COIN1   = "COIN2",
PLAYER4_SELECT  = "P4_SELECT",
MOUSE_X         = {"P1_PEDAL", "P1_TRACKBALL_X"},
MOUSE_Y         = {"P1_PEDAL2", "P1_TRACKBALL_Y"}
};

local function islabel( instr )
	rv = true;

	if (string.sub(instr, 1, 7) == "analog:" or
			string.sub(instr, 1, 8) == "digital:" or
			string.sub(instr, 1, 11) == "translated:") then
		rv = false;
	end

	return rv;
end

local function keyidtomame( keyid )
	resstr = nil;

	local tlelem = {};
	for a in string.gmatch(keyid, "[^:]+") do
		table.insert(tlelem, a);
	end

	if (tlelem[1] == "analog") then
		print("Keyconf::Mame conversion, analog (axis) movement currently unsupported, edit the .cfg manually.");

	elseif (string.sub(keyid, 1, 8) == "digital:") then
-- JOYCODE, index, BUTTON1..n
-- MOUSECODE, index, BUTTON1..n
		if (tlelem[4] == "mouse") then
			resstr = "MOUSECODE_" .. tonumber(tlelem[2]) + 1 .. "_BUTTON" .. tonumber(tlelem[3]) .. "\n";
		else
			resstr = "JOYCODE_" .. tonumber(tlelem[2]) .. "_BUTTON" .. tonumber(tlelem[3]) .. "\n";
		end

	elseif (tlelem[1] == "translated") then
-- the other fields are just sdl keysym code, and, if applicable (it can be turned of) :modifier
		resstr = sdlsymtbl[ tonumber( tlelem[3] ) ];
		if (tlelem[4] ~= nil and tonumber(tlelem[4]) > 0 and resstr) then -- add modifiers to resstr.
			local modnumtbl = decode_modifiers( tonumber(tlelem[4]) );
			for ind, mod in pairs(modnumtbl) do
				if (mod == "lalt") then resstr = "KEYCODE_LALT " .. resstr .. "\n"; end
				if (mod == "ralt") then resstr = "KEYCODE_RALT " .. resstr .. "\n"; end
				if (mod == "lctrl") then resstr = "KEYCODE_LCTRL " .. resstr .. "\n"; end
				if (mod == "rctrl") then resstr = "KEYCODE_RCTRL " .. resstr .. "\n"; end
				if (mod == "lshift") then resstr = "KEYCODE_LSHIFT " .. resstr .. "\n"; end
				if (mod == "rshift") then resstr = "KEYCODE_RSHIFT " .. resstr .. "\n"; end
			end
		end
	end

	return resstr;
end

local function mameentry( id, labels )
	mameid = keyidtomame( id );

	if (mameid == nil) then
		print("Keyconf::Mame conversion, couldn't find a mame- accepted corresponding input for: " .. id .. ", ignored.");
		return false;
	end

	for ind, lbl in pairs(labels) do
		local match = xlatetbl[ lbl ];
		if (match) then
			write_rawresource("<port type=\"" .. match .. "\">\n\t\t\t<newseq type=\"standard\">" .. mameid .. "</newseq>\n\t\t</port>\n\t\t");
		else
			print("Keyconf::Mame conversion, couldn't find a corresponding label for: " .. lbl .. ", ignored.");
		end
	end
end

function keyconf_tomame(keyconf, dstname )
	if (keyconf and keyconf.table ~= nil) then
		zap_resource(dstname);
		open_rawresource(dstname);

		if (write_rawresource("<?xml version=\"1.0\"?>\n<mameconfig version=\"10\">\n\t") == false) then
			print(" Couldn't write to: " .. dstname .. " check filename permissons and try again.\n");
		else
			write_rawresource("<system name=\"default\">\n\t<input>\n\t\t");

			for key, val in pairs(keyconf.table) do
				if (islabel( key ) == false) then
					mameentry( key, val );
				end
			end

			write_rawresource("</input>\n\t</system>\n</mameconfig>\n");
		end
	end
end
