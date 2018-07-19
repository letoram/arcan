-- various symbol table conversions for handling underlying input
-- layer deficiencies, customized remapping etc.
--
-- also basic support for keymaps and translations.
--
-- Translations are managed globally and built using a symbol- level
-- mash of modifiers and symbol squashed into a string index with utf8 out.
-- They are stored in the k/v database in the appl_ specific domain.
--
-- Translations can also be shadowed by a switchable overlay of
-- translations (for context- specific remapping)
--
-- Keymaps work on a local level and are tied to input platform and uses
-- other, low-level fields (devid, subid, scancode, modifiers). They can
-- be used to provide keysym and the default utf8 result, and are stored
-- in SYMTABLE_DOMAIN as .lua files.
--
-- [iotbl] -> patch(iotbl, keymap) -> translation -> out.
--
-- the higher-level [label] remapping is not performed here.

-- modify to use other namespace
local SYMTABLE_DOMAIN = APPL_RESOURCE;
local GLOBPATH = "devmaps/keyboard/";

-- for legacy reasons, we provide an sdl compatible symtable
local symtable = {};
 symtable[8] = "BACKSPACE";
 symtable["BACKSPACE"] = 8;
 symtable[9] = "TAB";
 symtable["TAB"] = 9;
 symtable[12] = "CLEAR";
 symtable["CLEAR"] = 12;
 symtable[13] = "RETURN";
 symtable["RETURN"] = 13;
 symtable[19] = "PAUSE";
 symtable["PAUSE"] = 19;
 symtable[27] = "ESCAPE";
 symtable["ESCAPE"] = 27;
 symtable[32] = " ";
 symtable["SPACE"] = 32;
 symtable[33] = "!";
 symtable["EXCLAIM"] = 33;
 symtable[34] = "\"";
 symtable["QUOTEDBL"] = 34;
 symtable[35] = "#";
 symtable["HASH"] = 35;
 symtable[36] = "$";
 symtable["DOLLAR"] = 36;
 symtable[38] = "&";
 symtable["AMPERSAND"] = 38;
 symtable[39] = "'";
 symtable["QUOTE"] = 39;
 symtable[40] = "(";
 symtable["LEFTPAREN"] = 40;
 symtable[41] = ")";
 symtable["RIGHTPAREN"] = 41;
 symtable[42] = "*";
 symtable["ASTERISK"] = 42;
 symtable[43] = "+";
 symtable["PLUS"] = 43;
 symtable[44] = ",";
 symtable["COMMA"] = 44;
 symtable[45] = "-";
 symtable["MINUS"] = 45;
 symtable[46] = ".";
 symtable["PERIOD"] = 46;
 symtable[47] = "/";
 symtable["SLASH"] = 47;
 symtable[48] = "0";
 symtable["0"] = 48;
 symtable[49] = "1";
 symtable["1"] = 49;
 symtable[50] = "2";
 symtable["2"] = 50;
 symtable[51] = "3";
 symtable["3"] = 51;
 symtable[52] = "4";
 symtable["4"] = 52;
 symtable[53] = "5";
 symtable["5"] = 53;
 symtable[54] = "6";
 symtable["6"] = 54;
 symtable[55] = "7";
 symtable["7"] = 55;
 symtable[56] = "8";
 symtable["8"] = 56;
 symtable[57] = "9";
 symtable["9"] = 57;
 symtable[58] = ":";
 symtable["COLON"] = 58;
 symtable[59] = ";";
 symtable["SEMICOLON"] = 59;
 symtable[60] = "<";
 symtable["LESS"] = 60;
 symtable[61] = "=";
 symtable["EQUALS"] = 61;
 symtable[62] = ">";
 symtable["GREATER"] = 62;
 symtable[63] = "?";
 symtable["QUESTION"] = 63;
 symtable[64] = "@";
 symtable["AT"] = 64;
 symtable[91] = "(";
 symtable["LEFTBRACKET"] = 91;
 symtable[92] = "\\";
 symtable["BACKSLASH"] = 92;
 symtable[93] = "]";
 symtable["RIGHTBRACKET"] = 93;
 symtable[94] = "^";
 symtable["CARET"] = 94;
 symtable[95] = "_";
 symtable["UNDERSCORE"] = 95;
 symtable[96] = "´";
 symtable["BACKQUOTE"] = 96;
 symtable[97] = "a";
 symtable["a"] = 97;
 symtable[98] = "b";
 symtable["b"] = 98;
 symtable[99] = "c";
 symtable["c"] = 99;
 symtable[100] = "d";
 symtable["d"] = 100;
 symtable[101] = "e";
 symtable["e"] = 101;
 symtable[102] = "f";
 symtable["f"] = 102;
 symtable[103] = "g";
 symtable["g"] = 103;
 symtable[104] = "h";
 symtable["h"] = 104;
 symtable[105] = "i";
 symtable["i"] = 105;
 symtable[106] = "j";
 symtable["j"] = 106;
 symtable[107] = "k";
 symtable["k"] = 107;
 symtable[108] = "l";
 symtable["l"] = 108;
 symtable[109] = "m";
 symtable["m"] = 109;
 symtable[110] = "n";
 symtable["n"] = 110;
 symtable[111] = "o";
 symtable["o"] = 111;
 symtable[112] = "p";
 symtable["p"] = 112;
 symtable[113] = "q";
 symtable["q"] = 113;
 symtable[114] = "r";
 symtable["r"] = 114;
 symtable[115] = "s";
 symtable["s"] = 115;
 symtable[116] = "t";
 symtable["t"] = 116;
 symtable[117] = "u";
 symtable["u"] = 117;
 symtable[118] = "v";
 symtable["v"] = 118;
 symtable[119] = "w";
 symtable["w"] = 119;
 symtable[120] = "x";
 symtable["x"] = 120;
 symtable[121] = "y";
 symtable["y"] = 121;
 symtable[122] = "z";
 symtable["z"] = 122;
 symtable[127] = "DELETE";
 symtable["DELETE"] = 127;
 symtable[160] = "WORLD_0";
 symtable["WORLD_0"] = 160;
 symtable[161] = "WORLD_1";
 symtable["WORLD_1"] = 161;
 symtable[162] = "WORLD_2";
 symtable["WORLD_2"] = 162;
 symtable[163] = "WORLD_3";
 symtable["WORLD_3"] = 163;
 symtable[164] = "WORLD_4";
 symtable["WORLD_4"] = 164;
 symtable[165] = "WORLD_5";
 symtable["WORLD_5"] = 165;
 symtable[166] = "WORLD_6";
 symtable["WORLD_6"] = 166;
 symtable[167] = "WORLD_7";
 symtable["WORLD_7"] = 167;
 symtable[168] = "WORLD_8";
 symtable["WORLD_8"] = 168;
 symtable[169] = "WORLD_9";
 symtable["WORLD_9"] = 169;
 symtable[170] = "WORLD_10";
 symtable["WORLD_10"] = 170;
 symtable[171] = "WORLD_11";
 symtable["WORLD_11"] = 171;
 symtable[172] = "WORLD_12";
 symtable["WORLD_12"] = 172;
 symtable[173] = "WORLD_13";
 symtable["WORLD_13"] = 173;
 symtable[174] = "WORLD_14";
 symtable["WORLD_14"] = 174;
 symtable[175] = "WORLD_15";
 symtable["WORLD_15"] = 175;
 symtable[176] = "WORLD_16";
 symtable["WORLD_16"] = 176;
 symtable[177] = "WORLD_17";
 symtable["WORLD_17"] = 177;
 symtable[178] = "WORLD_18";
 symtable["WORLD_18"] = 178;
 symtable[179] = "WORLD_19";
 symtable["WORLD_19"] = 179;
 symtable[180] = "WORLD_20";
 symtable["WORLD_20"] = 180;
 symtable[181] = "WORLD_21";
 symtable["WORLD_21"] = 181;
 symtable[182] = "WORLD_22";
 symtable["WORLD_22"] = 182;
 symtable[183] = "WORLD_23";
 symtable["WORLD_23"] = 183;
 symtable[184] = "WORLD_24";
 symtable["WORLD_24"] = 184;
 symtable[185] = "WORLD_25";
 symtable["WORLD_25"] = 185;
 symtable[186] = "WORLD_26";
 symtable["WORLD_26"] = 186;
 symtable[187] = "WORLD_27";
 symtable["WORLD_27"] = 187;
 symtable[188] = "WORLD_28";
 symtable["WORLD_28"] = 188;
 symtable[189] = "WORLD_29";
 symtable["WORLD_29"] = 189;
 symtable[190] = "WORLD_30";
 symtable["WORLD_30"] = 190;
 symtable[191] = "WORLD_31";
 symtable["WORLD_31"] = 191;
 symtable[192] = "WORLD_32";
 symtable["WORLD_32"] = 192;
 symtable[193] = "WORLD_33";
 symtable["WORLD_33"] = 193;
 symtable[194] = "WORLD_34";
 symtable["WORLD_34"] = 194;
 symtable[195] = "WORLD_35";
 symtable["WORLD_35"] = 195;
 symtable[196] = "WORLD_36";
 symtable["WORLD_36"] = 196;
 symtable[197] = "WORLD_37";
 symtable["WORLD_37"] = 197;
 symtable[198] = "WORLD_38";
 symtable["WORLD_38"] = 198;
 symtable[199] = "WORLD_39";
 symtable["WORLD_39"] = 199;
 symtable[200] = "WORLD_40";
 symtable["WORLD_40"] = 200;
 symtable[201] = "WORLD_41";
 symtable["WORLD_41"] = 201;
 symtable[202] = "WORLD_42";
 symtable["WORLD_42"] = 202;
 symtable[203] = "WORLD_43";
 symtable["WORLD_43"] = 203;
 symtable[204] = "WORLD_44";
 symtable["WORLD_44"] = 204;
 symtable[205] = "WORLD_45";
 symtable["WORLD_45"] = 205;
 symtable[206] = "WORLD_46";
 symtable["WORLD_46"] = 206;
 symtable[207] = "WORLD_47";
 symtable["WORLD_47"] = 207;
 symtable[208] = "WORLD_48";
 symtable["WORLD_48"] = 208;
 symtable[209] = "WORLD_49";
 symtable["WORLD_49"] = 209;
 symtable[210] = "WORLD_50";
 symtable["WORLD_50"] = 210;
 symtable[211] = "WORLD_51";
 symtable["WORLD_51"] = 211;
 symtable[212] = "WORLD_52";
 symtable["WORLD_52"] = 212;
 symtable[213] = "WORLD_53";
 symtable["WORLD_53"] = 213;
 symtable[214] = "WORLD_54";
 symtable["WORLD_54"] = 214;
 symtable[215] = "WORLD_55";
 symtable["WORLD_55"] = 215;
 symtable[216] = "WORLD_56";
 symtable["WORLD_56"] = 216;
 symtable[217] = "WORLD_57";
 symtable["WORLD_57"] = 217;
 symtable[218] = "WORLD_58";
 symtable["WORLD_58"] = 218;
 symtable[219] = "WORLD_59";
 symtable["WORLD_59"] = 219;
 symtable[220] = "WORLD_60";
 symtable["WORLD_60"] = 220;
 symtable[221] = "WORLD_61";
 symtable["WORLD_61"] = 221;
 symtable[222] = "WORLD_62";
 symtable["WORLD_62"] = 222;
 symtable[223] = "WORLD_63";
 symtable["WORLD_63"] = 223;
 symtable[224] = "WORLD_64";
 symtable["WORLD_64"] = 224;
 symtable[225] = "WORLD_65";
 symtable["WORLD_65"] = 225;
 symtable[226] = "WORLD_66";
 symtable["WORLD_66"] = 226;
 symtable[227] = "WORLD_67";
 symtable["WORLD_67"] = 227;
 symtable[228] = "WORLD_68";
 symtable["WORLD_68"] = 228;
 symtable[229] = "WORLD_69";
 symtable["WORLD_69"] = 229;
 symtable[230] = "WORLD_70";
 symtable["WORLD_70"] = 230;
 symtable[231] = "WORLD_71";
 symtable["WORLD_71"] = 231;
 symtable[232] = "WORLD_72";
 symtable["WORLD_72"] = 232;
 symtable[233] = "WORLD_73";
 symtable["WORLD_73"] = 233;
 symtable[234] = "WORLD_74";
 symtable["WORLD_74"] = 234;
 symtable[235] = "WORLD_75";
 symtable["WORLD_75"] = 235;
 symtable[236] = "WORLD_76";
 symtable["WORLD_76"] = 236;
 symtable[237] = "WORLD_77";
 symtable["WORLD_77"] = 237;
 symtable[238] = "WORLD_78";
 symtable["WORLD_78"] = 238;
 symtable[239] = "WORLD_79";
 symtable["WORLD_79"] = 239;
 symtable[240] = "WORLD_80";
 symtable["WORLD_80"] = 240;
 symtable[241] = "WORLD_81";
 symtable["WORLD_81"] = 241;
 symtable[242] = "WORLD_82";
 symtable["WORLD_82"] = 242;
 symtable[243] = "WORLD_83";
 symtable["WORLD_83"] = 243;
 symtable[244] = "WORLD_84";
 symtable["WORLD_84"] = 244;
 symtable[245] = "WORLD_85";
 symtable["WORLD_85"] = 245;
 symtable[246] = "WORLD_86";
 symtable["WORLD_86"] = 246;
 symtable[247] = "WORLD_87";
 symtable["WORLD_87"] = 247;
 symtable[248] = "WORLD_88";
 symtable["WORLD_88"] = 248;
 symtable[249] = "WORLD_89";
 symtable["WORLD_89"] = 249;
 symtable[250] = "WORLD_90";
 symtable["WORLD_90"] = 250;
 symtable[251] = "WORLD_91";
 symtable["WORLD_91"] = 251;
 symtable[252] = "WORLD_92";
 symtable["WORLD_92"] = 252;
 symtable[253] = "WORLD_93";
 symtable["WORLD_93"] = 253;
 symtable[254] = "WORLD_94";
 symtable["WORLD_94"] = 254;
 symtable[255] = "WORLD_95";
 symtable["WORLD_95"] = 255;
 symtable[256] = "KP0";
 symtable["KP0"] = 256;
 symtable[257] = "KP1";
 symtable["KP1"] = 257;
 symtable[258] = "KP2";
 symtable["KP2"] = 258;
 symtable[259] = "KP3";
 symtable["KP3"] = 259;
 symtable[260] = "KP4";
 symtable["KP4"] = 260;
 symtable[261] = "KP5";
 symtable["KP5"] = 261;
 symtable[262] = "KP6";
 symtable["KP6"] = 262;
 symtable[263] = "KP7";
 symtable["KP7"] = 263;
 symtable[264] = "KP8";
 symtable["KP8"] = 264;
 symtable[265] = "KP9";
 symtable["KP9"] = 265;
 symtable[266] = "KP_PERIOD";
 symtable["KP_PERIOD"] = 266;
 symtable[267] = "KP_DIVIDE";
 symtable["KP_DIVIDE"] = 267;
 symtable[268] = "KP_MULTIPLY";
 symtable["KP_MULTIPLY"] = 268;
 symtable[269] = "KP_MINUS";
 symtable["KP_MINUS"] = 269;
 symtable[270] = "KP_PLUS";
 symtable["KP_PLUS"] = 270;
 symtable[271] = "KP_ENTER";
 symtable["KP_ENTER"] = 271;
 symtable[272] = "KP_EQUALS";
 symtable["KP_EQUALS"] = 272;
 symtable[273] = "UP";
 symtable["UP"] = 273;
 symtable[274] = "DOWN";
 symtable["DOWN"] = 274;
 symtable[275] = "RIGHT";
 symtable["RIGHT"] = 275;
 symtable[276] = "LEFT";
 symtable["LEFT"] = 276;
 symtable[277] = "INSERT";
 symtable["INSERT"] = 277;
 symtable[278] = "HOME";
 symtable["HOME"] = 278;
 symtable[279] = "END";
 symtable["END"] = 279;
 symtable[280] = "PAGEUP";
 symtable["PAGEUP"] = 280;
 symtable[281] = "PAGEDOWN";
 symtable["PAGEDOWN"] = 281;
 symtable[282] = "F1";
 symtable["F1"] = 282;
 symtable[283] = "F2";
 symtable["F2"] = 283;
 symtable[284] = "F3";
 symtable["F3"] = 284;
 symtable[285] = "F4";
 symtable["F4"] = 285;
 symtable[286] = "F5";
 symtable["F5"] = 286;
 symtable[287] = "F6";
 symtable["F6"] = 287;
 symtable[288] = "F7";
 symtable["F7"] = 288;
 symtable[289] = "F8";
 symtable["F8"] = 289;
 symtable[290] = "F9";
 symtable["F9"] = 290;
 symtable[291] = "F10";
 symtable["F10"] = 291;
 symtable[292] = "F11";
 symtable["F11"] = 292;
 symtable[293] = "F12";
 symtable["F12"] = 293;
 symtable[294] = "F13";
 symtable["F13"] = 294;
 symtable[295] = "F14";
 symtable["F14"] = 295;
 symtable[296] = "F15";
 symtable["F15"] = 296;
 symtable[300] = "NUMLOCK";
 symtable["NUMLOCK"] = 300;
 symtable[301] = "CAPSLOCK";
 symtable["CAPSLOCK"] = 301;
 symtable[302] = "SCROLLOCK";
 symtable["SCROLLOCK"] = 302;
 symtable[303] = "RSHIFT";
 symtable["RSHIFT"] = 303;
 symtable[304] = "LSHIFT";
 symtable["LSHIFT"] = 304;
 symtable[305] = "RCTRL";
 symtable["RCTRL"] = 305;
 symtable[306] = "LCTRL";
 symtable["LCTRL"] = 306;
 symtable[307] = "RALT";
 symtable["RALT"] = 307;
 symtable[308] = "LALT";
 symtable["LALT"] = 308;
 symtable[309] = "RMETA";
 symtable["RMETA"] = 309;
 symtable[310] = "LMETA";
 symtable["LMETA"] = 310;
 symtable[311] = "LSUPER";
 symtable["LSUPER"] = 311;
 symtable[312] = "RSUPER";
 symtable["RSUPER"] = 312;
 symtable[313] = "MODE";
 symtable["MODE"] = 313;
 symtable[314] = "COMPOSE";
 symtable["COMPOSE"] = 314;
 symtable[315] = "HELP";
 symtable["HELP"] = 315;
 symtable[316] = "PRINT";
 symtable["PRINT"] = 316;
 symtable[317] = "SYSREQ";
 symtable["SYSREQ"] = 317;
 symtable[318] = "BREAK";
 symtable["BREAK"] = 318;
 symtable[319] = "MENU";
 symtable["MENU"] = 319;
 symtable[320] = "POWER";
 symtable["POWER"] = 320;
 symtable[321] = "EURO";
 symtable["EURO"] = 321;
 symtable[322] = "UNDO";
 symtable["UNDO"] = 322;

 local tmptbl = {};
 tmptbl[266] = ".";
 tmptbl[267] = "/";
 tmptbl[268] = "*";
 tmptbl[269] = "-";
 tmptbl[270] = "+";
 tmptbl[271] = nil;
 tmptbl[272] = "=";

symtable.tochar = function(ind)
	if (ind >= 32 and ind <= 122) then
		return symtable[ind];
	elseif (ind >= 256 and ind <= 265) then
		return symtable[ (ind - 256) + 48 ];
	elseif (ind >= 266 and ind <= 272) then
		return tmptbl[ind];
	else
		return nil;
	end
end

symtable.u8lut = {};
symtable.u8basic = {};
symtable.symlut = {};

symtable.patch = function(tbl, iotbl)
	local mods = table.concat(decode_modifiers(iotbl.modifiers), "_");
	iotbl.old_utf8 = iotbl.utf8;

-- apply utf8 translation and modify supplied utf8 with keymap
	if (tbl.keymap) then
		local m = tbl.keymap.map;
		local ind = iotbl.modifiers == 0 and "plain" or mods;
			if (m[ind] and m[ind][iotbl.subid]) then
				iotbl.utf8 = m[ind][iotbl.subid];
			end
		end

-- other symbols are described relative to the internal sdl symbols
	local sym = tbl.symlut[iotbl.number] and
		tbl.symlut[iotbl.number] or tbl[iotbl.keysym];
	if (not sym) then
		sym = "UNKN" .. tostring(iotbl.number);
	else
		iotbl.keysym = tbl[sym];
	end
	local lutsym = string.len(mods) > 0 and (mods .."_" .. sym) or sym;

-- two support layers at the moment, normal press or with modifiers.
	if (iotbl.active) then
		if (tbl.u8lut[lutsym]) then
			iotbl.utf8 = tbl.u8lut[lutsym];
		elseif (tbl.u8lut[sym]) then
			iotbl.utf8 = tbl.u8lut[sym];
		end
	else
		iotbl.utf8 = "";
	end

	return sym, lutsym;
end

-- used for tracking repeat etc. where we don't want meta keys to
-- trigger repeated input
local metak = {
	LALT = true,
	RALT = true,
	LCTRL = true,
	RCTRL = true,
	LSHIFT = true,
	RSHIFT = true
};

symtable.is_modifier = function(symtable, iotbl)
	return metak[symtable[iotbl.keysym]] ~= nil;
end

-- for filling the utf8- field with customized bindings
symtable.add_translation = function(tbl, combo, u8)
	if (not combo) then
		print("tried to add broken combo:", debug.traceback());
		return;
	end

	tbl.u8lut[combo] = u8;
	tbl.u8basic[combo] = u8;
end

-- uses the utf8k_ind:key=value for escaping
symtable.load_translation = function(tbl)
	for i,v in ipairs(match_keys("utf8k_%")) do
		local pos, stop = string.find(v, "=", 1);
		local npos, nstop = string.find(v, string.char(255), stop+1);
		if (not npos) then
			warning("removing broken binding for " .. v);
			store_key(v, "");
		else
			local key = string.sub(v, stop+1, npos-1);
			local val = string.sub(v, nstop+1);
			tbl:add_translation(key, val);
		end
	end
end

symtable.update_map = function(tbl, iotbl, u8)
	if (not tbl.keymap) then
		tbl.keymap = {
			name = "unknown",
			map = {
				plain = {}
			},
			diac = {},
			diac_ind = 0
		};
	end

	local m = tbl.keymap.map;
	if (iotbl.modifiers == 0) then
		m.plain[iotbl.subid] = u8;
	else
		local mods = table.concat(decode_modifiers(iotbl.modifiers), "_");
		if (not m[mods]) then
			m[mods] = {};
		end
		m[mods][iotbl.subid] = u8;
	end
end

symtable.store_translation = function(tbl)
-- drop current list
	local rst = {};
	for i,v in ipairs(match_keys("utf8k_%")) do
		local pos, stop = string.find(v, "=", 1);
		local key = string.sub(v, 1, pos-1);
		rst[key] = "";
	end
	store_key(rst);

-- use numeric indices due to restrictions on key values and use the
-- invalid 255 char as split
	local ind = 1;
	local out = {};
	for k,v in pairs(tbl.u8basic) do
		out["utf8k_" .. tostring(ind)] = k .. string.char(255) .. v;
	end
	store_key(out);
end

local function tryload(km)
	local kmp = GLOBPATH .. km;
	if (not resource(kmp)) then
		warning("couldn't locate keymap (" .. GLOBPATH .. "): " .. km);
		return;
	end

	local res = system_load(kmp, 0);
	if (not res) then
		warning("parsing error loading keymap (" .. GLOBPATH .. "): " .. km);
		return;
	end

	local okstate, map = pcall(res);
	if (not okstate) then
		warning("execution error loading keymap: " .. km);
		return;
	end
	if (map and type(map) == "table"
		and map.name and string.len(map.name) > 0) then

		if (map.platform_flt and not map.platform_flt()) then
			warning("platform filter rejected keymap: " .. km);
			return nil;
		end

		map.dctind = 0;
		return map;
	end
end

symtable.list_keymaps = function(tbl, cached)
	local res = {};
	local list = glob_resource(GLOBPATH .. "*.lua", SYMTABLE_DOMAIN);

	if (list and #list > 0) then
		for k,v in ipairs(list) do
			local map = tryload(v);
			if (map) then
				table.insert(res, map.name);
			end
		end
	end

	table.sort(res);
	return res;
end

symtable.load_keymap = function(tbl, km)
	if (resource(GLOBPATH .. km, SYMTABLE_DOMAIN)) then
		local res = tryload(km);
		if (tryload(km)) then
			symtable.keymap = res;
			symtable.symlut = res.symmap and res.symmap or {};
			return true;
		end
	end

	return false;
end

symtable.reset = function(tbl)
	tbl.keymap = nil;
	tbl.u8basic = {};
end

-- switch overlay (for multiple windows with different remapping)
symtable.translation_overlay = function(tbl, combotbl)
	tbl.u8lut = {};
	for k,v in pairs(tbl.u8basic) do
		tbl.u8lut[k] = v;
	end

	for k,v in pairs(combotbl) do
		tbl.u8lut[k] = v;
	end
end

-- store the current utf-8 keymap + added translations into a
-- file (ignore the overlay)
symtable.save_keymap = function(tbl, name)
	assert(name and type(name) == "string" and string.len(name) > 0);
	local dst = GLOBPATH .. name .. ".lua";
	if (resource(dst,SYMTABLE_DOMAIN)) then
		zap_resource(dst);
	end

	local wout = open_nonblock(dst, 1);
	if (not wout) then
		warning("symtable/save: couldn't open " .. name .. " for writing.");
		return false;
	end

	wout:write(string.format("local res = { name = [[%s]], ", name));
	wout:write("dctbl = {}, symmap = {}, map = { plain = {} } };\n");

	if (tbl.keymap) then
		for k,v in pairs(tbl.keymap.map) do
			wout:write(string.format("res.map[\"%s\"] = {};\n", k));
			for i,j in pairs(v) do
				wout:write(string.format(
					"res.map[\"%s\"][%d] = %q;\n", k, tonumber(i), j));
			end
		end
	end

	for k,v in pairs(tbl.symlut) do
		wout:write(string.format("res.symmap[%d] = %q;\n", k, v));
	end

	wout:write("return res;\n");
	wout:close();
end

return symtable;
