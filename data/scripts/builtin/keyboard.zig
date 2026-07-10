
var SYMTABLE_DOMAIN = bit.bor(bit.bor(SYS_APPL_RESOURCE, APPL_TEMP_RESOURCE), SYS_SCRIPT_RESOURCE);

var GLOBPATH = "devmaps/keyboard/";

var KEYSYM_LABEL_LUT = .{
    __may_kv(8, "BACKSPACE"),
    __may_kv(9, "TAB"),
    __may_kv(12, "CLEAR"),
    __may_kv(13, "RETURN"),
    __may_kv(19, "PAUSE"),
    __may_kv(27, "ESCAPE"),
    __may_kv(32, "SPACE"),
    __may_kv(33, "EXCLAIM"),
    __may_kv(34, "QUOTEDBL"),
    __may_kv(35, "HASH"),
    __may_kv(36, "DOLLAR"),
    __may_kv(38, "AMPERSAND"),
    __may_kv(39, "QUOTE"),
    __may_kv(40, "LEFTPAREN"),
    __may_kv(41, "RIGHTPAREN"),
    __may_kv(42, "ASTERISK"),
    __may_kv(43, "PLUS"),
    __may_kv(44, "COMMA"),
    __may_kv(45, "MINUS"),
    __may_kv(46, "PERIOD"),
    __may_kv(47, "SLASH"),
    __may_kv(48, "0"),
    __may_kv(49, "1"),
    __may_kv(50, "2"),
    __may_kv(51, "3"),
    __may_kv(52, "4"),
    __may_kv(53, "5"),
    __may_kv(54, "6"),
    __may_kv(55, "7"),
    __may_kv(56, "8"),
    __may_kv(57, "9"),
    __may_kv(58, "COLON"),
    __may_kv(59, "SEMICOLON"),
    __may_kv(60, "LESS"),
    __may_kv(61, "EQUALS"),
    __may_kv(62, "GREATER"),
    __may_kv(63, "QUESTION"),
    __may_kv(64, "AT"),
    __may_kv(91, "LEFTBRACKET"),
    __may_kv(92, "BACKSLASH"),
    __may_kv(93, "RIGHTBRACKET"),
    __may_kv(94, "CARET"),
    __may_kv(95, "UNDERSCORE"),
    __may_kv(96, "BACKQUOTE"),
    __may_kv(97, "a"),
    __may_kv(98, "b"),
    __may_kv(99, "c"),
    __may_kv(100, "d"),
    __may_kv(101, "e"),
    __may_kv(102, "f"),
    __may_kv(103, "g"),
    __may_kv(104, "h"),
    __may_kv(105, "i"),
    __may_kv(106, "j"),
    __may_kv(107, "k"),
    __may_kv(108, "l"),
    __may_kv(109, "m"),
    __may_kv(110, "n"),
    __may_kv(111, "o"),
    __may_kv(112, "p"),
    __may_kv(113, "q"),
    __may_kv(114, "r"),
    __may_kv(115, "s"),
    __may_kv(116, "t"),
    __may_kv(117, "u"),
    __may_kv(118, "v"),
    __may_kv(119, "w"),
    __may_kv(120, "x"),
    __may_kv(121, "y"),
    __may_kv(122, "z"),
    __may_kv(127, "DELETE"),
    __may_kv(160, "WORLD_0"),
    __may_kv(161, "WORLD_1"),
    __may_kv(162, "WORLD_2"),
    __may_kv(163, "WORLD_3"),
    __may_kv(164, "WORLD_4"),
    __may_kv(165, "WORLD_5"),
    __may_kv(166, "WORLD_6"),
    __may_kv(167, "WORLD_7"),
    __may_kv(168, "WORLD_8"),
    __may_kv(169, "WORLD_9"),
    __may_kv(170, "WORLD_10"),
    __may_kv(171, "WORLD_11"),
    __may_kv(172, "WORLD_12"),
    __may_kv(173, "WORLD_13"),
    __may_kv(174, "WORLD_14"),
    __may_kv(175, "WORLD_15"),
    __may_kv(176, "WORLD_16"),
    __may_kv(177, "WORLD_17"),
    __may_kv(178, "WORLD_18"),
    __may_kv(179, "WORLD_19"),
    __may_kv(180, "WORLD_20"),
    __may_kv(181, "WORLD_21"),
    __may_kv(182, "WORLD_22"),
    __may_kv(183, "WORLD_23"),
    __may_kv(184, "WORLD_24"),
    __may_kv(185, "WORLD_25"),
    __may_kv(186, "WORLD_26"),
    __may_kv(187, "WORLD_27"),
    __may_kv(188, "WORLD_28"),
    __may_kv(189, "WORLD_29"),
    __may_kv(190, "WORLD_30"),
    __may_kv(191, "WORLD_31"),
    __may_kv(192, "WORLD_32"),
    __may_kv(193, "WORLD_33"),
    __may_kv(194, "WORLD_34"),
    __may_kv(195, "WORLD_35"),
    __may_kv(196, "WORLD_36"),
    __may_kv(197, "WORLD_37"),
    __may_kv(198, "WORLD_38"),
    __may_kv(199, "WORLD_39"),
    __may_kv(200, "WORLD_40"),
    __may_kv(201, "WORLD_41"),
    __may_kv(202, "WORLD_42"),
    __may_kv(203, "WORLD_43"),
    __may_kv(204, "WORLD_44"),
    __may_kv(205, "WORLD_45"),
    __may_kv(206, "WORLD_46"),
    __may_kv(207, "WORLD_47"),
    __may_kv(208, "WORLD_48"),
    __may_kv(209, "WORLD_49"),
    __may_kv(210, "WORLD_50"),
    __may_kv(211, "WORLD_51"),
    __may_kv(212, "WORLD_52"),
    __may_kv(213, "WORLD_53"),
    __may_kv(214, "WORLD_54"),
    __may_kv(215, "WORLD_55"),
    __may_kv(216, "WORLD_56"),
    __may_kv(217, "WORLD_57"),
    __may_kv(218, "WORLD_58"),
    __may_kv(219, "WORLD_59"),
    __may_kv(220, "WORLD_60"),
    __may_kv(221, "WORLD_61"),
    __may_kv(222, "WORLD_62"),
    __may_kv(223, "WORLD_63"),
    __may_kv(224, "WORLD_64"),
    __may_kv(225, "WORLD_65"),
    __may_kv(226, "WORLD_66"),
    __may_kv(227, "WORLD_67"),
    __may_kv(228, "WORLD_68"),
    __may_kv(229, "WORLD_69"),
    __may_kv(230, "WORLD_70"),
    __may_kv(231, "WORLD_71"),
    __may_kv(232, "WORLD_72"),
    __may_kv(233, "WORLD_73"),
    __may_kv(234, "WORLD_74"),
    __may_kv(235, "WORLD_75"),
    __may_kv(236, "WORLD_76"),
    __may_kv(237, "WORLD_77"),
    __may_kv(238, "WORLD_78"),
    __may_kv(239, "WORLD_79"),
    __may_kv(240, "WORLD_80"),
    __may_kv(241, "WORLD_81"),
    __may_kv(242, "WORLD_82"),
    __may_kv(243, "WORLD_83"),
    __may_kv(244, "WORLD_84"),
    __may_kv(245, "WORLD_85"),
    __may_kv(246, "WORLD_86"),
    __may_kv(247, "WORLD_87"),
    __may_kv(248, "WORLD_88"),
    __may_kv(249, "WORLD_89"),
    __may_kv(250, "WORLD_90"),
    __may_kv(251, "WORLD_91"),
    __may_kv(252, "WORLD_92"),
    __may_kv(253, "WORLD_93"),
    __may_kv(254, "WORLD_94"),
    __may_kv(255, "WORLD_95"),
    __may_kv(256, "KP0"),
    __may_kv(257, "KP1"),
    __may_kv(258, "KP2"),
    __may_kv(259, "KP3"),
    __may_kv(260, "KP4"),
    __may_kv(261, "KP5"),
    __may_kv(262, "KP6"),
    __may_kv(263, "KP7"),
    __may_kv(264, "KP8"),
    __may_kv(265, "KP9"),
    __may_kv(266, "KP_PERIOD"),
    __may_kv(267, "KP_DIVIDE"),
    __may_kv(268, "KP_MULTIPLY"),
    __may_kv(269, "KP_MINUS"),
    __may_kv(270, "KP_PLUS"),
    __may_kv(271, "KP_ENTER"),
    __may_kv(272, "KP_EQUALS"),
    __may_kv(273, "UP"),
    __may_kv(274, "DOWN"),
    __may_kv(275, "RIGHT"),
    __may_kv(276, "LEFT"),
    __may_kv(277, "INSERT"),
    __may_kv(278, "HOME"),
    __may_kv(279, "END"),
    __may_kv(280, "PAGEUP"),
    __may_kv(281, "PAGEDOWN"),
    __may_kv(282, "F1"),
    __may_kv(283, "F2"),
    __may_kv(284, "F3"),
    __may_kv(285, "F4"),
    __may_kv(286, "F5"),
    __may_kv(287, "F6"),
    __may_kv(288, "F7"),
    __may_kv(289, "F8"),
    __may_kv(290, "F9"),
    __may_kv(291, "F10"),
    __may_kv(292, "F11"),
    __may_kv(293, "F12"),
    __may_kv(294, "F13"),
    __may_kv(295, "F14"),
    __may_kv(296, "F15"),
    __may_kv(300, "NUMLOCK"),
    __may_kv(301, "CAPSLOCK"),
    __may_kv(302, "SCROLLOCK"),
    __may_kv(303, "RSHIFT"),
    __may_kv(304, "LSHIFT"),
    __may_kv(305, "RCTRL"),
    __may_kv(306, "LCTRL"),
    __may_kv(307, "RALT"),
    __may_kv(308, "LALT"),
    __may_kv(309, "RMETA"),
    __may_kv(310, "LMETA"),
    __may_kv(311, "LSUPER"),
    __may_kv(312, "RSUPER"),
    __may_kv(313, "MODE"),
    __may_kv(314, "COMPOSE"),
    __may_kv(315, "HELP"),
    __may_kv(316, "PRINT"),
    __may_kv(317, "SYSREQ"),
    __may_kv(318, "BREAK"),
    __may_kv(319, "MENU"),
    __may_kv(320, "POWER"),
    __may_kv(321, "EURO"),
    __may_kv(322, "UNDO"),
};

var LABEL_KEYSYM_LUT = .{};

pub fn __init() void {
    for (pairs(KEYSYM_LABEL_LUT)) |__may_pair| {
        const keysym = __may_pair[0];
        const label = __may_pair[1];
        LABEL_KEYSYM_LUT[label] = keysym;
    }
    var KEYSYM_ASCII_LUT = .{
        __may_kv(266, "."),
        __may_kv(267, "/"),
        __may_kv(268, "*"),
        __may_kv(269, "-"),
        __may_kv(270, "+"),
        __may_kv(272, "="),
    };
    for (32..122 + 1) |i| {
        KEYSYM_ASCII_LUT[i] = KEYSYM_LABEL_LUT[i];
    }
    for (256..265 + 1) |i| {
        KEYSYM_ASCII_LUT[i] = KEYSYM_LABEL_LUT[(i - 256) + 48];
    }
    var symtable = .{
        .counter = 0,
        .delay = 0,
        .period = 0,
    };

    symtable.tolabel = struct { fn anon(keysym: anytype) V {
        return KEYSYM_LABEL_LUT[keysym];
    } }.anon;
    symtable.tokeysym = struct { fn anon(label: anytype) V {
        return LABEL_KEYSYM_LUT[label];
    } }.anon;
    symtable.tochar = struct { fn anon(ind: anytype) V {
        return KEYSYM_ASCII_LUT[ind];
    } }.anon;
    symtable.u8lut = .{};
    symtable.u8basic = .{};
    symtable.symlut = .{};
    symtable.tick = struct { fn anon(tbl: anytype) void {
        if (!tbl.last or (tbl.period == 0)) {
            return;
        }
        tbl.counter = tbl.counter - 1;
        if ((tbl.counter < 0) and (((-tbl.counter) % tbl.period) == 0)) {
            _G[APPLID ++ "_input"](tbl.last);
        }
    } }.anon;

    symtable.kbd_repeat = struct { fn anon(tbl: anytype, ctr: anytype, period: anytype) void {
        kbd_repeat(0, 0);
        if (!ctr) {
            var key = get_key("keydelay");
            if (key and tonumber(key)) {
                ctr = tonumber(key);
            } else {
                ctr = 10;
            }
        }
        if (!period) {
            var per = get_key("keyrate");
            if (per and tonumber(per)) {
                period = tonumber(per);
            } else {
                period = 4;
            }
        }
        tbl.counter = ctr;
        tbl.period = period;
        tbl.delay = ctr;
    } }.anon;

    symtable.patch = struct { fn anon(tbl: Obj, iotbl: anytype) V {
        var mods = table.concat(decode_modifiers(iotbl.modifiers), "_");
        iotbl.old_utf8 = iotbl.utf8;
        if (tbl.is_modifier(iotbl)) {
            tbl.last = null;
            tbl.counter = tbl.delay;
        } else {
            if (iotbl.active) {
                if (tbl.last != iotbl) {
                    tbl.counter = tbl.delay;
                }
                tbl.last = iotbl;
            } else if (tbl.last and (tbl.last.subid == iotbl.subid)) {
                tbl.last = null;
                tbl.counter = tbl.delay;
            }
        }
        if (tbl.keymap) {
            var m = tbl.keymap.map;
            var ind = ((iotbl.modifiers == 0) and "plain") or mods;
            if (m[ind] and m[ind][iotbl.subid]) {
                iotbl.utf8 = m[ind][iotbl.subid];
            }
        }
        var sym = (tbl.symlut[iotbl.number] and tbl.symlut[iotbl.number]) or KEYSYM_LABEL_LUT[iotbl.keysym];
        if (!sym) {
            sym = "UNKN" ++ tostring(iotbl.number);
        } else {
            iotbl.keysym = LABEL_KEYSYM_LUT[sym];
        }
        var lutsym = ((string.len(mods) > 0) and (mods ++ ("_" ++ sym))) or sym;

        if (iotbl.active) {
            if (tbl.u8lut[lutsym]) {
                iotbl.utf8 = tbl.u8lut[lutsym];
            } else if (tbl.u8lut[sym]) {
                iotbl.utf8 = tbl.u8lut[sym];
            }
        } else {
            iotbl.utf8 = "";
        }
        return __may_mv(sym, lutsym);
    } }.anon;
    var metak = .{
        .LALT = true,
        .RALT = true,
        .LCTRL = true,
        .RCTRL = true,
        .LSHIFT = true,
        .RSHIFT = true,
    };

    symtable.is_modifier = struct { fn anon(symtable: anytype, iotbl: anytype) bool {
        return metak[KEYSYM_LABEL_LUT[iotbl.keysym]] != null;
    } }.anon;
    symtable.add_translation = struct { fn anon(tbl: anytype, combo: bool, u8: anytype) void {
        if (!combo) {
            print("tried to add broken combo:", debug.traceback());
            return;
        }
        tbl.u8lut[combo] = u8;
        tbl.u8basic[combo] = u8;
    } }.anon;
    symtable.load_translation = struct { fn anon(tbl: Obj) void {
        for (match_keys("utf8k_%"), 0..) |v, i| {
            const pos, const stop = string.find(v, "=", 1);
            const npos, const nstop = string.find(v, string.char(255), stop + 1);
            if (!npos) {
                warning("removing broken binding for " ++ v);
                store_key(v, "");
            } else {
                var key = string.sub(v, stop + 1, npos - 1);
                var val = string.sub(v, nstop + 1);
                tbl.add_translation(key, val);
            }
        }
    } }.anon;
    symtable.update_map = struct { fn anon(tbl: anytype, iotbl: anytype, u8: anytype) void {
        if (!tbl.keymap) {
            tbl.keymap = .{
                .name = "unknown",
                .map = .{
                    .plain = .{},
                },
                .diac = .{},
                .diac_ind = 0,
            };
        }
        var m = tbl.keymap.map;
        if (iotbl.modifiers == 0) {
            m.plain[iotbl.subid] = u8;
        } else {
            var mods = table.concat(decode_modifiers(iotbl.modifiers), "_");
            if (!m[mods]) {
                m[mods] = .{};
            }
            m[mods][iotbl.subid] = u8;
        }
    } }.anon;
    symtable.store_translation = struct { fn anon(tbl: anytype) void {
        var rst = .{};
        for (match_keys("utf8k_%"), 0..) |v, i| {
            const pos, const stop = string.find(v, "=", 1);
            var key = string.sub(v, 1, pos - 1);
            rst[key] = "";
        }
        store_key(rst);
        var ind = 1;
        var out = .{};
        for (pairs(tbl.u8basic)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            out["utf8k_" ++ tostring(ind)] = k ++ (string.char(255) ++ v);
        }
        store_key(out);
    } }.anon;
    const tryload = struct { fn tryload(km: []const u8) V {
        var kmp = GLOBPATH ++ km;

        if (!resource(kmp)) {
            warning("couldn't locate keymap (" ++ (GLOBPATH ++ ("): " ++ km)));
            return;
        }
        var res = system_load(kmp, 0);
        if (!res) {
            warning("parsing error loading keymap (" ++ (GLOBPATH ++ ("): " ++ km)));
            return;
        }
        const okstate, const map = pcall(res);
        if (!okstate) {
            warning("execution error loading keymap: " ++ km);
            return;
        }
        if (map and (type(map) == "table") and map.name and (string.len(map.name) > 0)) {
            if (map.platform_flt and !map.platform_flt()) {
                warning("platform filter rejected keymap: " ++ km);
                return;
            }
            if (!map.symmap) {
                map.symmap = .{};
            }
            map.dctind = 0;
            return map;
        } else {
            warning("invalid / corrupt map");
        }
    } }.tryload;

    symtable.list_keymaps = struct { fn anon(tbl: anytype, cached: anytype) V {
        var res = .{};
        var list = glob_resource(GLOBPATH ++ "*.lua", SYMTABLE_DOMAIN);

        if (list and (@intCast(list.len) > 0)) {
            for (list, 0..) |v, k| {
                var map = tryload(v);
                if (map) {
                    table.insert(res, map.name);
                }
            }
        }
        table.sort(res);
        return res;
    } }.anon;
    symtable.load_keymap = struct { fn anon(tbl: anytype, name: anytype) bool {
        if (!name) {
            name = get_key("keymap") or "default.lua";
        }
        if (resource(GLOBPATH ++ name, SYMTABLE_DOMAIN)) {
            var res = tryload(name);

            if (res) {
                symtable.keymap = res;
                symtable.symlut = res.symmap;
                return true;
            }
        }
        return false;
    } }.anon;

    symtable.reset = struct { fn anon(tbl: anytype) void {
        tbl.keymap = null;
        tbl.counter = tbl.delay;
        tbl.u8basic = .{};
    } }.anon;
    symtable.translation_overlay = struct { fn anon(tbl: anytype, combotbl: anytype) void {
        tbl.u8lut = .{};
        for (pairs(tbl.u8basic)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            tbl.u8lut[k] = v;
        }
        for (pairs(combotbl)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            tbl.u8lut[k] = v;
        }
    } }.anon;
    symtable.save_keymap = struct { fn anon(tbl: anytype, name: []const u8) bool {
        assert(name and (type(name) == "string") and (string.len(name) > 0));
        var dst = GLOBPATH ++ (name ++ ".lua");
        if (resource(dst, SYMTABLE_DOMAIN)) {
            zap_resource(dst);
        }
        var wout: Obj = open_nonblock(dst, 1);
        if (!wout) {
            warning("symtable/save: couldn't open " ++ (name ++ " for writing."));
            return false;
        }
        wout.write(string.format("local res = { name = [[%s]], ", name));
        wout.write("dctbl = {}, symmap = {}, map = { plain = {} } };\n");
        if (tbl.keymap) {
            for (pairs(tbl.keymap.map)) |__may_pair| {
                const k = __may_pair[0];
                const v = __may_pair[1];
                wout.write(string.format("res.map[\"%s\"] = {};\n", k));
                for (pairs(v)) |__may_pair| {
                    const i = __may_pair[0];
                    const j = __may_pair[1];
                    wout.write(string.format("res.map[\"%s\"][%d] = %q;\n", k, tonumber(i), j));
                }
            }
        }
        for (pairs(tbl.symlut)) |__may_pair| {
            const k = __may_pair[0];
            const v = __may_pair[1];
            wout.write(string.format("res.symmap[%d] = %q;\n", k, v));
        }
        wout.write("return res;\n");
        wout.close();
    } }.anon;
    return symtable;
}
