/*
 * For legacy reasons we use SDLs scancode as internal
 * representation, so convert between whatever the linux
 * have for the moment and that.
 *
 * But as will all things text, it's a table of a table of a table
 * where at least one bit will mismatch every time.
 */

static uint16_t klut[512] = {0};

enum {
	K_UNKNOWN = 0,
	K_FIRST = 0,
	K_BACKSPACE = 8,
	K_TAB = 9,
	K_CLEAR = 12,
	K_RETURN = 13,
	K_PAUSE = 19,
	K_ESCAPE = 27,
	K_SPACE = 32,
	K_EXCLAIM = 33,
	K_QUOTEDBL = 34,
	K_HASH = 35,
	K_DOLLAR = 36,
	K_0 = 48,
	K_1 = 49,
	K_2 = 50,
	K_3 = 51,
	K_4 = 52,
	K_5 = 53,
	K_6 = 54,
	K_7 = 55,
	K_8 = 56,
	K_9 = 57,
	K_MINUS = 20,
	K_EQUALS = 21,
	K_A = 97,
  K_B = 98,
	K_C = 99,
	K_D = 100,
	K_E = 101,
	K_F = 102,
	K_G = 103,
	K_H = 104,
	K_I = 105,
	K_J = 106,
	K_K = 107,
	K_L = 108,
	K_M = 109,
	K_N = 110,
	K_O = 111,
	K_P = 112,
	K_Q = 113,
	K_R = 114,
	K_S = 115,
	K_T = 116,
	K_U = 117,
	K_V = 118,
	K_W = 119,
	K_X = 120,
	K_Y = 121,
	K_Z = 122,
	K_LESS = 60, /* 102nd key, right of lshift */
	K_KP_LEFTBRACE = 91,
	K_KP_RIGHTBRACE = 93,
	K_KP_ENTER = 271,
	K_LCTRL = 306,
	K_SEMICOLON = 59,
	K_APOSTROPHE = 48,
	K_GRAVE = 49,
	K_LSHIFT = 304,
	K_BACKSLASH = 92,
	K_COMMA = 44,
	K_PERIOD = 46,
	K_SLASH = 61,
	K_RSHIFT = 303,
	K_KP_MULTIPLY = 268,
	K_LALT = 308,
	K_CAPSLOCK = 301,
	K_F1 = 282,
	K_F2 = 283,
	K_F3 = 284,
	K_F4 = 285,
	K_F5 = 286,
	K_F6 = 287,
	K_F7 = 288,
	K_F8 = 289,
	K_F9 = 290,
	K_F10 = 291,
	K_NUMLOCKCLEAR = 300,
	K_SCROLLLOCK = 302,
	K_KP_0 = 256,
	K_KP_1 = 257,
	K_KP_2 = 258,
	K_KP_3 = 259,
	K_KP_4 = 260,
	K_KP_5 = 261,
	K_KP_6 = 262,
	K_KP_7 = 263,
	K_KP_8 = 264,
	K_KP_9 = 265,
	K_KP_MINUS = 269,
	K_KP_PLUS = 270,
	K_KP_PERIOD = 266,
	K_INTERNATIONAL1,
	K_INTERNATIONAL2,
	K_F11 = 292,
	K_F12 = 293,
	K_INTERNATIONAL3,
	K_INTERNATIONAL4,
	K_INTERNATIONAL5,
	K_INTERNATIONAL6,
	K_INTERNATIONAL7,
	K_INTERNATIONAL8,
	K_INTERNATIONAL9,
	K_RCTRL = 305,
	K_KP_DIVIDE = 267,
	K_SYSREQ = 317,
	K_RALT = 307,
	K_HOME = 278,
	K_UP = 273,
	K_PAGEUP = 280,
	K_LEFT = 276,
	K_RIGHT = 275,
	K_END = 279,
	K_DOWN = 274,
	K_PAGEDOWN = 281,
	K_INSERT = 277,
	K_DELETE = 127,
	K_LMETA = 310,
	K_RMETA = 309,
	K_COMPOSE = 314,
	K_MUTE,
	K_VOLUMEDOWN,
	K_VOLUMEUP,
	K_POWER,
	K_KP_EQUALS,
	K_KP_PLUSMINUS,
	K_LANG1,
	K_LANG2,
	K_LANG3,
	K_LGUI,
	K_RGUI,
	K_STOP,
	K_AGAIN,
};

static void init_keyblut()
{
klut[KEY_ESC] = K_ESCAPE;
klut[KEY_1] = K_1;
klut[KEY_2] = K_2;
klut[KEY_3] = K_3;
klut[KEY_4] = K_4;
klut[KEY_5] = K_5;
klut[KEY_6] = K_6;
klut[KEY_7] = K_7;
klut[KEY_8] = K_8;
klut[KEY_9] = K_9;
klut[KEY_0] = K_0;
klut[KEY_MINUS] = K_MINUS;
klut[KEY_EQUAL] = K_EQUALS;
klut[KEY_BACKSPACE] = K_BACKSPACE;
klut[KEY_TAB] = K_TAB;
klut[KEY_Q] = K_Q;
klut[KEY_W] = K_W;
klut[KEY_E] = K_E;
klut[KEY_R] = K_R;
klut[KEY_T] = K_T;
klut[KEY_Y] = K_Y;
klut[KEY_U] = K_U;
klut[KEY_I] = K_I;
klut[KEY_O] = K_O;
klut[KEY_P] = K_P;
klut[KEY_LEFTBRACE] = K_KP_LEFTBRACE;
klut[KEY_RIGHTBRACE] = K_KP_RIGHTBRACE;
klut[KEY_ENTER] = K_RETURN;
klut[KEY_LEFTCTRL] = K_LCTRL;
klut[KEY_A] = K_A;
klut[KEY_S] = K_S;
klut[KEY_D] = K_D;
klut[KEY_F] = K_F;
klut[KEY_G] = K_G;
klut[KEY_H] = K_H;
klut[KEY_J] = K_J;
klut[KEY_K] = K_K;
klut[KEY_L] = K_L;
klut[KEY_SEMICOLON] = K_SEMICOLON;
klut[KEY_APOSTROPHE] = K_APOSTROPHE;
klut[KEY_GRAVE] = K_GRAVE;
klut[KEY_LEFTSHIFT] = K_LSHIFT;
klut[KEY_BACKSLASH] = K_BACKSLASH;
klut[KEY_Z] = K_Z;
klut[KEY_X] = K_X;
klut[KEY_C] = K_C;
klut[KEY_V] = K_V;
klut[KEY_B] = K_B;
klut[KEY_N] = K_N;
klut[KEY_M] = K_M;
klut[KEY_COMMA] = K_COMMA;
klut[KEY_DOT] = K_PERIOD;
klut[KEY_SLASH] = K_SLASH;
klut[KEY_RIGHTSHIFT] = K_RSHIFT;
klut[KEY_KPASTERISK] = K_KP_MULTIPLY;
klut[KEY_LEFTALT] = K_LALT;
klut[KEY_SPACE] = K_SPACE;
klut[KEY_CAPSLOCK] = K_CAPSLOCK;
klut[KEY_F1] = K_F1;
klut[KEY_F2] = K_F2;
klut[KEY_F3] = K_F3;
klut[KEY_F4] = K_F4;
klut[KEY_F5] = K_F5;
klut[KEY_F6] = K_F6;
klut[KEY_F7] = K_F7;
klut[KEY_F8] = K_F8;
klut[KEY_F9] = K_F9;
klut[KEY_F10] = K_F10;
klut[KEY_NUMLOCK] = K_NUMLOCKCLEAR;
klut[KEY_SCROLLLOCK] = K_SCROLLLOCK;
klut[KEY_KP7] = K_KP_7;
klut[KEY_KP8] = K_KP_8;
klut[KEY_KP9] = K_KP_9;
klut[KEY_KPMINUS] = K_KP_MINUS;
klut[KEY_KP4] = K_KP_4;
klut[KEY_KP5] = K_KP_5;
klut[KEY_KP6] = K_KP_6;
klut[KEY_KPPLUS] = K_KP_PLUS;
klut[KEY_KP1] = K_KP_1;
klut[KEY_KP2] = K_KP_2;
klut[KEY_KP3] = K_KP_3;
klut[KEY_KP0] = K_KP_0;
klut[KEY_KPDOT] = K_KP_PERIOD;
klut[KEY_ZENKAKUHANKAKU] = K_INTERNATIONAL1;
klut[KEY_102ND] = K_LESS;
klut[KEY_F11] = K_F11;
klut[KEY_F12] = K_F12;
klut[KEY_RO] = K_INTERNATIONAL3;
klut[KEY_KATAKANA] = K_INTERNATIONAL4;
klut[KEY_HIRAGANA] = K_INTERNATIONAL5;
klut[KEY_HENKAN] = K_INTERNATIONAL6;
klut[KEY_KATAKANAHIRAGANA] = K_INTERNATIONAL7;
klut[KEY_MUHENKAN] = K_INTERNATIONAL8;
klut[KEY_KPJPCOMMA] = K_INTERNATIONAL9;
klut[KEY_KPENTER] = K_KP_ENTER;
klut[KEY_RIGHTCTRL] = K_RCTRL;
klut[KEY_KPSLASH] = K_KP_DIVIDE;
klut[KEY_SYSRQ] = K_SYSREQ;
klut[KEY_RIGHTALT] = K_RALT;
klut[KEY_LINEFEED] = K_KP_ENTER;
klut[KEY_HOME] = K_HOME;
klut[KEY_UP] = K_UP;
klut[KEY_PAGEUP] = K_PAGEUP;
klut[KEY_LEFT] = K_LEFT;
klut[KEY_RIGHT] = K_RIGHT;
klut[KEY_END] = K_END;
klut[KEY_DOWN] = K_DOWN;
klut[KEY_PAGEDOWN] = K_PAGEDOWN;
klut[KEY_INSERT] = K_INSERT;
klut[KEY_DELETE] = K_DELETE;
/* ?? */
klut[KEY_MACRO] = K_UNKNOWN;
/* ?? */
klut[KEY_MUTE] = K_MUTE;
klut[KEY_VOLUMEDOWN] = K_VOLUMEDOWN;
klut[KEY_VOLUMEUP] = K_VOLUMEUP;
klut[KEY_POWER] = K_POWER;
klut[KEY_KPEQUAL] = K_KP_EQUALS;
klut[KEY_KPPLUSMINUS] = K_KP_PLUSMINUS;
klut[KEY_PAUSE] = K_PAUSE;
klut[KEY_KPCOMMA] = K_COMMA;
klut[KEY_HANGUEL] = K_LANG1;
klut[KEY_HANJA] = K_LANG2;
klut[KEY_YEN] = K_LANG3;
klut[KEY_LEFTMETA] = K_LMETA;
klut[KEY_RIGHTMETA] = K_RMETA;
/* ?? */
klut[KEY_COMPOSE] = K_COMPOSE;
/* ?? */
klut[KEY_STOP] = K_STOP;
klut[KEY_AGAIN] = K_AGAIN;
/* ?? */
klut[KEY_PROPS] = K_UNKNOWN;
/* ?? */
klut[KEY_UNDO] = K_UNKNOWN;
klut[KEY_FRONT] = K_UNKNOWN;
klut[KEY_COPY] = K_UNKNOWN;
klut[KEY_OPEN] = K_UNKNOWN;
klut[KEY_PASTE] = K_UNKNOWN;
klut[KEY_FIND] = K_UNKNOWN;
klut[KEY_CUT] = K_UNKNOWN;
klut[KEY_HELP] = K_UNKNOWN;
klut[KEY_MENU] = K_UNKNOWN;
klut[KEY_CALC] = K_UNKNOWN;
klut[KEY_SETUP] = K_UNKNOWN;
klut[KEY_SLEEP] = K_UNKNOWN;
klut[KEY_WAKEUP] = K_UNKNOWN;
klut[KEY_FILE] = K_UNKNOWN;
klut[KEY_SENDFILE] = K_UNKNOWN;
klut[KEY_DELETEFILE] = K_UNKNOWN;
klut[KEY_XFER] = K_UNKNOWN;
klut[KEY_PROG1] = K_UNKNOWN;
klut[KEY_PROG2] = K_UNKNOWN;
klut[KEY_WWW] = K_UNKNOWN;
klut[KEY_MSDOS] = K_UNKNOWN;
klut[KEY_COFFEE] = K_UNKNOWN;
klut[KEY_DIRECTION] = K_UNKNOWN;
klut[KEY_CYCLEWINDOWS] = K_UNKNOWN;
klut[KEY_MAIL] = K_UNKNOWN;
klut[KEY_BOOKMARKS] = K_UNKNOWN;
klut[KEY_COMPUTER] = K_UNKNOWN;
klut[KEY_BACK] = K_UNKNOWN;
klut[KEY_FORWARD] = K_UNKNOWN;
klut[KEY_CLOSECD] = K_UNKNOWN;
klut[KEY_EJECTCD] = K_UNKNOWN;
klut[KEY_EJECTCLOSECD] = K_UNKNOWN;
klut[KEY_NEXTSONG] = K_UNKNOWN;
klut[KEY_PLAYPAUSE] = K_UNKNOWN;
klut[KEY_PREVIOUSSONG] = K_UNKNOWN;
klut[KEY_STOPCD] = K_UNKNOWN;
klut[KEY_RECORD] = K_UNKNOWN;
klut[KEY_REWIND] = K_UNKNOWN;
klut[KEY_PHONE] = K_UNKNOWN;
klut[KEY_ISO] = K_UNKNOWN;
klut[KEY_CONFIG] = K_UNKNOWN;
klut[KEY_HOMEPAGE] = K_UNKNOWN;
klut[KEY_REFRESH] = K_UNKNOWN;
klut[KEY_EXIT] = K_UNKNOWN;
klut[KEY_MOVE] = K_UNKNOWN;
klut[KEY_EDIT] = K_UNKNOWN;
klut[KEY_SCROLLUP] = K_UNKNOWN;
klut[KEY_SCROLLDOWN] = K_UNKNOWN;
klut[KEY_KPLEFTPAREN] = K_UNKNOWN;
klut[KEY_KPRIGHTPAREN] = K_UNKNOWN;
klut[KEY_F13] = K_UNKNOWN;
klut[KEY_F14] = K_UNKNOWN;
klut[KEY_F15] = K_UNKNOWN;
klut[KEY_F16] = K_UNKNOWN;
klut[KEY_F17] = K_UNKNOWN;
klut[KEY_F18] = K_UNKNOWN;
klut[KEY_F19] = K_UNKNOWN;
klut[KEY_F20] = K_UNKNOWN;
klut[KEY_F21] = K_UNKNOWN;
klut[KEY_F22] = K_UNKNOWN;
klut[KEY_F23] = K_UNKNOWN;
klut[KEY_F24] = K_UNKNOWN;
klut[KEY_PLAYCD] = K_UNKNOWN;
klut[KEY_PAUSECD] = K_UNKNOWN;
klut[KEY_PROG3] = K_UNKNOWN;
klut[KEY_PROG4] = K_UNKNOWN;
klut[KEY_SUSPEND] = K_UNKNOWN;
klut[KEY_CLOSE] = K_UNKNOWN;
klut[KEY_PLAY] = K_UNKNOWN;
klut[KEY_FASTFORWARD] = K_UNKNOWN;
klut[KEY_BASSBOOST] = K_UNKNOWN;
klut[KEY_PRINT] = K_UNKNOWN;
klut[KEY_HP] = K_UNKNOWN;
klut[KEY_CAMERA] = K_UNKNOWN;
klut[KEY_SOUND] = K_UNKNOWN;
klut[KEY_QUESTION] = K_UNKNOWN;
klut[KEY_EMAIL] = K_UNKNOWN;
klut[KEY_CHAT] = K_UNKNOWN;
klut[KEY_SEARCH] = K_UNKNOWN;
klut[KEY_CONNECT] = K_UNKNOWN;
klut[KEY_FINANCE] = K_UNKNOWN;
klut[KEY_SPORT] = K_UNKNOWN;
klut[KEY_SHOP] = K_UNKNOWN;
klut[KEY_ALTERASE] = K_UNKNOWN;
klut[KEY_CANCEL] = K_UNKNOWN;
klut[KEY_BRIGHTNESSDOWN] = K_UNKNOWN;
klut[KEY_BRIGHTNESSUP] = K_UNKNOWN;
klut[KEY_MEDIA] = K_UNKNOWN;
klut[KEY_UNKNOWN] = K_UNKNOWN;
}

/*
 * from scancode to SDLs scancode to SDLs keycode ..
 */
static uint16_t lookup_keycode(uint16_t code)
{
	if (code > sizeof(klut) / sizeof(klut[0]))
		return 0;

	return klut[code];
}
