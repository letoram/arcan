// Keyboard lookup table for evdev → SDL-compatible keysyms.
// Durian's KEYSYM_LABEL_LUT uses SDL keysym values: ASCII for printable
// characters, 256+ range for special keys (arrows, F-keys, modifiers).

// SDL-compatible keysym values matching durian's builtin/keyboard.lua KEYSYM_LABEL_LUT
const K_BACKSPACE: c_uint = 8;
const K_TAB: c_uint = 9;
const K_RETURN: c_uint = 13;
const K_ESCAPE: c_uint = 27;
const K_SPACE: c_uint = 32;
const K_DELETE: c_uint = 127;

// Keypad
const K_KP0: c_uint = 256;
const K_KP1: c_uint = 257;
const K_KP2: c_uint = 258;
const K_KP3: c_uint = 259;
const K_KP4: c_uint = 260;
const K_KP5: c_uint = 261;
const K_KP6: c_uint = 262;
const K_KP7: c_uint = 263;
const K_KP8: c_uint = 264;
const K_KP9: c_uint = 265;
const K_KP_PERIOD: c_uint = 266;
const K_KP_DIVIDE: c_uint = 267;
const K_KP_MULTIPLY: c_uint = 268;
const K_KP_MINUS: c_uint = 269;
const K_KP_PLUS: c_uint = 270;
const K_KP_ENTER: c_uint = 271;

// Navigation
const K_UP: c_uint = 273;
const K_DOWN: c_uint = 274;
const K_RIGHT: c_uint = 275;
const K_LEFT: c_uint = 276;
const K_INSERT: c_uint = 277;
const K_HOME: c_uint = 278;
const K_END: c_uint = 279;
const K_PAGEUP: c_uint = 280;
const K_PAGEDOWN: c_uint = 281;

// Function keys
const K_F1: c_uint = 282;
const K_F2: c_uint = 283;
const K_F3: c_uint = 284;
const K_F4: c_uint = 285;
const K_F5: c_uint = 286;
const K_F6: c_uint = 287;
const K_F7: c_uint = 288;
const K_F8: c_uint = 289;
const K_F9: c_uint = 290;
const K_F10: c_uint = 291;
const K_F11: c_uint = 292;
const K_F12: c_uint = 293;

// Lock keys
const K_NUMLOCK: c_uint = 300;
const K_CAPSLOCK: c_uint = 301;
const K_SCROLLOCK: c_uint = 302;

// Modifiers
const K_RSHIFT: c_uint = 303;
const K_LSHIFT: c_uint = 304;
const K_RCTRL: c_uint = 305;
const K_LCTRL: c_uint = 306;
const K_RALT: c_uint = 307;
const K_LALT: c_uint = 308;
const K_RMETA: c_uint = 309;
const K_LMETA: c_uint = 310;

// Misc
const K_MODE: c_uint = 313;
const K_COMPOSE: c_uint = 314;
const K_MENU: c_uint = 319;

// Lookup table: Linux scancode → SDL-compatible keysym
export var klut: [512]c_uint = [_]c_uint{0} ** 512;

export fn init_keyblut() callconv(.c) void {
    // Printable ASCII chars from unshifted US QWERTY
    // ESC=27, 1-9=49-57, 0=48, -=45, ==61
    klut[1] = K_ESCAPE;
    klut[2] = '1'; klut[3] = '2'; klut[4] = '3'; klut[5] = '4'; klut[6] = '5';
    klut[7] = '6'; klut[8] = '7'; klut[9] = '8'; klut[10] = '9'; klut[11] = '0';
    klut[12] = '-'; klut[13] = '=';
    klut[14] = K_BACKSPACE;
    klut[15] = K_TAB;
    // QWERTY row
    klut[16] = 'q'; klut[17] = 'w'; klut[18] = 'e'; klut[19] = 'r'; klut[20] = 't';
    klut[21] = 'y'; klut[22] = 'u'; klut[23] = 'i'; klut[24] = 'o'; klut[25] = 'p';
    klut[26] = '['; klut[27] = ']';
    klut[28] = K_RETURN;
    klut[29] = K_LCTRL;
    // ASDF row
    klut[30] = 'a'; klut[31] = 's'; klut[32] = 'd'; klut[33] = 'f'; klut[34] = 'g';
    klut[35] = 'h'; klut[36] = 'j'; klut[37] = 'k'; klut[38] = 'l';
    klut[39] = ';'; klut[40] = '\''; klut[41] = '`';
    klut[42] = K_LSHIFT;
    klut[43] = '\\';
    // ZXCV row
    klut[44] = 'z'; klut[45] = 'x'; klut[46] = 'c'; klut[47] = 'v'; klut[48] = 'b';
    klut[49] = 'n'; klut[50] = 'm'; klut[51] = ','; klut[52] = '.'; klut[53] = '/';
    klut[54] = K_RSHIFT;
    klut[55] = K_KP_MULTIPLY;
    klut[56] = K_LALT;
    klut[57] = K_SPACE;
    klut[58] = K_CAPSLOCK;
    // F1-F10
    klut[59] = K_F1; klut[60] = K_F2; klut[61] = K_F3; klut[62] = K_F4; klut[63] = K_F5;
    klut[64] = K_F6; klut[65] = K_F7; klut[66] = K_F8; klut[67] = K_F9; klut[68] = K_F10;
    klut[69] = K_NUMLOCK;
    klut[70] = K_SCROLLOCK;
    // Keypad 7-9, 4-6, 1-3, 0
    klut[71] = K_KP7; klut[72] = K_KP8; klut[73] = K_KP9; klut[74] = K_KP_MINUS;
    klut[75] = K_KP4; klut[76] = K_KP5; klut[77] = K_KP6; klut[78] = K_KP_PLUS;
    klut[79] = K_KP1; klut[80] = K_KP2; klut[81] = K_KP3;
    klut[82] = K_KP0; klut[83] = K_KP_PERIOD;
    // F11-F12
    klut[87] = K_F11; klut[88] = K_F12;
    klut[96] = K_KP_ENTER;
    klut[97] = K_RCTRL;
    klut[98] = K_KP_DIVIDE;
    klut[100] = K_RALT;
    // Navigation
    klut[102] = K_HOME;
    klut[103] = K_UP;
    klut[104] = K_PAGEUP;
    klut[105] = K_LEFT;
    klut[106] = K_RIGHT;
    klut[107] = K_END;
    klut[108] = K_DOWN;
    klut[109] = K_PAGEDOWN;
    klut[110] = K_INSERT;
    klut[111] = K_DELETE;
    // Meta keys
    klut[125] = K_LMETA;
    klut[126] = K_RMETA;
    klut[127] = K_COMPOSE;
    klut[139] = K_MENU;
}

export fn lookup_keycode(code: c_uint, _: u16) callconv(.c) u16 {
    if (code < 512 and klut[code] != 0) return @intCast(klut[code]);
    return @intCast(code);
}

// Basic ASCII mapping: unshifted characters for US QWERTY layout
const unshifted = [128]u8{
    0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, '\t', // 0-15
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\r', 0, 'a', 's', // 16-31
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, '\\', 'z', 'x', 'c', 'v', // 32-47
    'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0, 0, 0, 0, 0, 0, // 48-63
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 64-79
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 80-95
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 96-111
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 112-127
};

const shifted = [128]u8{
    0, 27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8, '\t',
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\r', 0, 'A', 'S',
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|', 'Z', 'X', 'C', 'V',
    'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

const ARKMOD_LSHIFT: u16 = 1;
const ARKMOD_RSHIFT: u16 = 2;

export fn lookup_character(code: c_uint, mods: u16, _: bool) callconv(.c) u16 {
    if (code >= 128) return 0;
    const is_shift = (mods & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)) != 0;
    const ch: u8 = if (is_shift) shifted[code] else unshifted[code];
    return @intCast(ch);
}
