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

-- this restricts the search path further from the CAREFUL_USERMASK
-- default down to only ones defined in the current applications and
-- system, not in the shared space
local SYMTABLE_DOMAIN =
	bit.bor(
		bit.bor(SYS_APPL_RESOURCE, APPL_TEMP_RESOURCE),
		SYS_SCRIPT_RESOURCE
	);

local GLOBPATH = "devmaps/keyboard/";

-- for legacy reasons, we provide an sdl compatible symtable
local KEYSYM_LABEL_LUT = {
	[8] = "BACKSPACE",
	[9] = "TAB",
	[12] = "CLEAR",
	[13] = "RETURN",
	[19] = "PAUSE",
	[27] = "ESCAPE",
	[32] = "SPACE",
	[33] = "EXCLAIM",
	[34] = "QUOTEDBL",
	[35] = "HASH",
	[36] = "DOLLAR",
	[38] = "AMPERSAND",
	[39] = "QUOTE",
	[40] = "LEFTPAREN",
	[41] = "RIGHTPAREN",
	[42] = "ASTERISK",
	[43] = "PLUS",
	[44] = "COMMA",
	[45] = "MINUS",
	[46] = "PERIOD",
	[47] = "SLASH",
	[48] = "0",
	[49] = "1",
	[50] = "2",
	[51] = "3",
	[52] = "4",
	[53] = "5",
	[54] = "6",
	[55] = "7",
	[56] = "8",
	[57] = "9",
	[58] = "COLON",
	[59] = "SEMICOLON",
	[60] = "LESS",
	[61] = "EQUALS",
	[62] = "GREATER",
	[63] = "QUESTION",
	[64] = "AT",
	[91] = "LEFTBRACKET",
	[92] = "BACKSLASH",
	[93] = "RIGHTBRACKET",
	[94] = "CARET",
	[95] = "UNDERSCORE",
	[96] = "BACKQUOTE",
	[97] = "a",
	[98] = "b",
	[99] = "c",
	[100] = "d",
	[101] = "e",
	[102] = "f",
	[103] = "g",
	[104] = "h",
	[105] = "i",
	[106] = "j",
	[107] = "k",
	[108] = "l",
	[109] = "m",
	[110] = "n",
	[111] = "o",
	[112] = "p",
	[113] = "q",
	[114] = "r",
	[115] = "s",
	[116] = "t",
	[117] = "u",
	[118] = "v",
	[119] = "w",
	[120] = "x",
	[121] = "y",
	[122] = "z",
	[127] = "DELETE",
	[160] = "WORLD_0",
	[161] = "WORLD_1",
	[162] = "WORLD_2",
	[163] = "WORLD_3",
	[164] = "WORLD_4",
	[165] = "WORLD_5",
	[166] = "WORLD_6",
	[167] = "WORLD_7",
	[168] = "WORLD_8",
	[169] = "WORLD_9",
	[170] = "WORLD_10",
	[171] = "WORLD_11",
	[172] = "WORLD_12",
	[173] = "WORLD_13",
	[174] = "WORLD_14",
	[175] = "WORLD_15",
	[176] = "WORLD_16",
	[177] = "WORLD_17",
	[178] = "WORLD_18",
	[179] = "WORLD_19",
	[180] = "WORLD_20",
	[181] = "WORLD_21",
	[182] = "WORLD_22",
	[183] = "WORLD_23",
	[184] = "WORLD_24",
	[185] = "WORLD_25",
	[186] = "WORLD_26",
	[187] = "WORLD_27",
	[188] = "WORLD_28",
	[189] = "WORLD_29",
	[190] = "WORLD_30",
	[191] = "WORLD_31",
	[192] = "WORLD_32",
	[193] = "WORLD_33",
	[194] = "WORLD_34",
	[195] = "WORLD_35",
	[196] = "WORLD_36",
	[197] = "WORLD_37",
	[198] = "WORLD_38",
	[199] = "WORLD_39",
	[200] = "WORLD_40",
	[201] = "WORLD_41",
	[202] = "WORLD_42",
	[203] = "WORLD_43",
	[204] = "WORLD_44",
	[205] = "WORLD_45",
	[206] = "WORLD_46",
	[207] = "WORLD_47",
	[208] = "WORLD_48",
	[209] = "WORLD_49",
	[210] = "WORLD_50",
	[211] = "WORLD_51",
	[212] = "WORLD_52",
	[213] = "WORLD_53",
	[214] = "WORLD_54",
	[215] = "WORLD_55",
	[216] = "WORLD_56",
	[217] = "WORLD_57",
	[218] = "WORLD_58",
	[219] = "WORLD_59",
	[220] = "WORLD_60",
	[221] = "WORLD_61",
	[222] = "WORLD_62",
	[223] = "WORLD_63",
	[224] = "WORLD_64",
	[225] = "WORLD_65",
	[226] = "WORLD_66",
	[227] = "WORLD_67",
	[228] = "WORLD_68",
	[229] = "WORLD_69",
	[230] = "WORLD_70",
	[231] = "WORLD_71",
	[232] = "WORLD_72",
	[233] = "WORLD_73",
	[234] = "WORLD_74",
	[235] = "WORLD_75",
	[236] = "WORLD_76",
	[237] = "WORLD_77",
	[238] = "WORLD_78",
	[239] = "WORLD_79",
	[240] = "WORLD_80",
	[241] = "WORLD_81",
	[242] = "WORLD_82",
	[243] = "WORLD_83",
	[244] = "WORLD_84",
	[245] = "WORLD_85",
	[246] = "WORLD_86",
	[247] = "WORLD_87",
	[248] = "WORLD_88",
	[249] = "WORLD_89",
	[250] = "WORLD_90",
	[251] = "WORLD_91",
	[252] = "WORLD_92",
	[253] = "WORLD_93",
	[254] = "WORLD_94",
	[255] = "WORLD_95",
	[256] = "KP0",
	[257] = "KP1",
	[258] = "KP2",
	[259] = "KP3",
	[260] = "KP4",
	[261] = "KP5",
	[262] = "KP6",
	[263] = "KP7",
	[264] = "KP8",
	[265] = "KP9",
	[266] = "KP_PERIOD",
	[267] = "KP_DIVIDE",
	[268] = "KP_MULTIPLY",
	[269] = "KP_MINUS",
	[270] = "KP_PLUS",
	[271] = "KP_ENTER",
	[272] = "KP_EQUALS",
	[273] = "UP",
	[274] = "DOWN",
	[275] = "RIGHT",
	[276] = "LEFT",
	[277] = "INSERT",
	[278] = "HOME",
	[279] = "END",
	[280] = "PAGEUP",
	[281] = "PAGEDOWN",
	[282] = "F1",
	[283] = "F2",
	[284] = "F3",
	[285] = "F4",
	[286] = "F5",
	[287] = "F6",
	[288] = "F7",
	[289] = "F8",
	[290] = "F9",
	[291] = "F10",
	[292] = "F11",
	[293] = "F12",
	[294] = "F13",
	[295] = "F14",
	[296] = "F15",
	[300] = "NUMLOCK",
	[301] = "CAPSLOCK",
	[302] = "SCROLLOCK",
	[303] = "RSHIFT",
	[304] = "LSHIFT",
	[305] = "RCTRL",
	[306] = "LCTRL",
	[307] = "RALT",
	[308] = "LALT",
	[309] = "RMETA",
	[310] = "LMETA",
	[311] = "LSUPER",
	[312] = "RSUPER",
	[313] = "MODE",
	[314] = "COMPOSE",
	[315] = "HELP",
	[316] = "PRINT",
	[317] = "SYSREQ",
	[318] = "BREAK",
	[319] = "MENU",
	[320] = "POWER",
	[321] = "EURO",
	[322] = "UNDO"
};

local LABEL_KEYSYM_LUT = {};
for keysym, label in pairs(KEYSYM_LABEL_LUT) do
	LABEL_KEYSYM_LUT[label] = keysym;
end

local KEYSYM_ASCII_LUT = {
	[266] = ".",
	[267] = "/",
	[268] = "*",
	[269] = "-",
	[270] = "+",
	[272] = "="
};
for i=32,122 do
	KEYSYM_ASCII_LUT[i] = KEYSYM_LABEL_LUT[i];
end
for i=256,265 do
	KEYSYM_ASCII_LUT[i] = KEYSYM_LABEL_LUT[ (i - 256) + 48 ];
end

local symtable =
{
	counter = 0,
	delay = 0,
	period = 0
};

symtable.tolabel = function(keysym)
	return KEYSYM_LABEL_LUT[keysym]
end

symtable.tokeysym = function(label)
	return LABEL_KEYSYM_LUT[label]
end

symtable.tochar = function(ind)
	return KEYSYM_ASCII_LUT[ind];
end

symtable.u8lut = {};
symtable.u8basic = {};
symtable.symlut = {};

function symtable.tick(tbl)
	if not tbl.last or tbl.period == 0 then
		return
	end

	tbl.counter = tbl.counter - 1
	if tbl.counter < 0 and (-tbl.counter) % tbl.period == 0 then
		_G[APPLID .. "_input"](tbl.last)
	end
end

function symtable.kbd_repeat(tbl, ctr, period)
-- disable platform key-repeat and leave it to builtin/keyboard
	kbd_repeat(0, 0)

-- fallback to defaults unless parameters are provided
	if not ctr then
		local key = get_key("keydelay")
		if key and tonumber(key) then
			ctr = tonumber(key)
		else
			ctr = 10
		end
	end

	if not period then
		local per = get_key("keyrate")
		if per and tonumber(per) then
			period = tonumber(per)
		else
			period = 4
		end
	end

	tbl.counter = ctr
	tbl.period = period
	tbl.delay = ctr
end

symtable.patch = function(tbl, iotbl)
	local mods = table.concat(decode_modifiers(iotbl.modifiers), "_");
	iotbl.old_utf8 = iotbl.utf8;

-- Remember for repeating in .tick(), only the same modifier table will
-- actually continue the repeats, so holding l until repeat then pressing shift
-- L will reset the repeat counter.
	if tbl:is_modifier(iotbl) then
		tbl.last = nil;
		tbl.counter = tbl.delay;
	else
		if iotbl.active then
			if tbl.last ~= iotbl then
				tbl.counter = tbl.delay;
			end

			tbl.last = iotbl;
		elseif tbl.last and tbl.last.subid == iotbl.subid then
			tbl.last = nil;
			tbl.counter = tbl.delay;
		end
	end

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
		tbl.symlut[iotbl.number] or KEYSYM_LABEL_LUT[iotbl.keysym];
	if (not sym) then
		sym = "UNKN" .. tostring(iotbl.number);
	else
		iotbl.keysym = LABEL_KEYSYM_LUT[sym];
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
	return metak[KEYSYM_LABEL_LUT[iotbl.keysym]] ~= nil;
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
			return;
		end

		if not map.symmap then
			map.symmap = {};
		end

		map.dctind = 0;
		return map;
	else
		warning("invalid / corrupt map");
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

function symtable.load_keymap(tbl, name)
	if not name then
		name = get_key("keymap") or "default.lua"
	end

	if (resource(GLOBPATH .. name, SYMTABLE_DOMAIN)) then
		local res = tryload(name);

		if (res) then
			symtable.keymap = res;
			symtable.symlut = res.symmap;
			return true;
		end
	end

	return false;
end

symtable.reset = function(tbl)
	tbl.keymap = nil;
	tbl.counter = tbl.delay;
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

-- store the current utf-8 keyboard utf8 map and symbol overrides
symtable.save_keymap = function(tbl, name)
	assert(name and type(name) == "string" and string.len(name) > 0);
	local dst = GLOBPATH .. name .. ".lua";
	if (resource(dst,SYMTABLE_DOMAIN)) then
		zap_resource(dst);
	end

-- the name suggests otherwise, but this is blocking
	local wout = open_nonblock(dst, 1);
	if (not wout) then
		warning("symtable/save: couldn't open " .. name .. " for writing.");
		return false;
	end

	wout:write(string.format("local res = { name = [[%s]], ", name));
	wout:write("dctbl = {}, symmap = {}, map = { plain = {} } };\n");

	if (tbl.keymap) then

-- write out by modifiers (plain, lshift, ...)
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
