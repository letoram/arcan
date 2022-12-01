/* See LICENSE file for copyright and license details. */

/*
 * What program is execed by st depends of these precedence rules:
 * 1: program passed with -e
 * 2: scroll and/or utmp
 * 3: SHELL environment variable
 * 4: value of shell in /etc/passwd
 * 5: value of shell in config.h
 */
static char *shell = "/bin/sh";
char *utmp = NULL;
/* scroll program: to enable use a string like "scroll" */
char *scroll = NULL;
char *stty_args = "stty raw pass8 nl -echo -iexten -cstopb 38400";

/* identification sequence returned in DA and DECID */
char *vtiden = "\033[?6c";

/*
 * word delimiter string
 *
 * More advanced example: L" `'\"()[]{}"
 */
wchar_t *worddelimiters = L" ";

/* alt screens */
int allowaltscreen = 1;

/* allow certain non-interactive (insecure) window operations such as:
   setting the clipboard text */
int allowwindowops = 1;

/*
 * draw latency range in ms - from new content/keypress/etc until drawing.
 * within this range, st draws when content stops arriving (idle). mostly it's
 * near minlatency, but it waits longer for slow updates to avoid partial draw.
 * low minlatency will tear/flicker more, as it can "detect" idle too early.
 */
static double minlatency = 8;
static double maxlatency = 33;

/*
 * blinking timeout (set to 0 to disable blinking) for the terminal blinking
 * attribute.
 */
static unsigned int blinktimeout = 800;

/*
 * thickness of underline and bar cursors
 */
static unsigned int cursorthickness = 2;

/*
 * bell volume. It must be a value between -100 and 100. Use 0 for disabling
 * it
 */
static int bellvolume = 0;

/* default TERM value */
char *termname = "st-256color";

/*
 * spaces per tab
 *
 * When you are changing this value, don't forget to adapt the »it« value in
 * the st.info and appropriately install the st.info in the environment where
 * you use this st version.
 *
 *	it#$tabspaces,
 *
 * Secondly make sure your kernel is not expanding tabs. When running `stty
 * -a` »tab0« should appear. You can tell the terminal to not expand tabs by
 *  running following command:
 *
 *	stty tabs
 */
unsigned int tabspaces = 8;

/* Terminal colors (16 first used in escape sequence) */
static const char *colorname[] = {
	/* 8 normal colors */
	"black",
	"red3",
	"green3",
	"yellow3",
	"blue2",
	"magenta3",
	"cyan3",
	"gray90",

	/* 8 bright colors */
	"gray50",
	"red",
	"green",
	"yellow",
	"#5c5cff",
	"magenta",
	"cyan",
	"white",

	[255] = 0,

	/* more colors can be added after 255 to use with DefaultXX */
	"#cccccc",
	"#555555",
	"gray90", /* default foreground colour */
	"black", /* default background colour */
};


/*
 * Default colors (colorname index)
 * foreground, background, cursor, reverse cursor
 */
unsigned int defaultfg = 258;
unsigned int defaultbg = 259;
unsigned int defaultcs = 256;
static unsigned int defaultrcs = 257;

/*
 * Default shape of cursor
 * 2: Block ("█")
 * 4: Underline ("_")
 * 6: Bar ("|")
 * 7: Snowman ("☃")
 */
static unsigned int cursorshape = 2;

/*
 * Default columns and rows numbers
 */

static unsigned int cols = 80;
static unsigned int rows = 24;

/*
 * Color used to display font attributes when fontconfig selected a font which
 * doesn't match the ones requested.
 */
static unsigned int defaultattr = 11;

/*
 * Special keys (change & recompile st.info accordingly)
 *
 * Mask value:
 * * Use TUIK_ANY_MOD to match the key no matter modifiers state
 * * Use TUIK_NO_MOD to match the key alone (no modifiers)
 * appkey value:
 * * 0: no value
 * * > 0: keypad application mode enabled
 * *   = 2: term.numlock = 1
 * * < 0: keypad application mode disabled
 * appcursor value:
 * * 0: no value
 * * > 0: cursor application mode enabled
 * * < 0: cursor application mode disabled
 *
 * Be careful with the order of the definitions because st searches in
 * this table sequentially, so any TUIK_ANY_MOD must be in the last
 * position for a key.
 */

/*
 * This is the huge key array which defines all compatibility to the Linux
 * world. Please decide about changes wisely.
 */

#define ShiftMask TUIM_SHIFT
#define TUIK_ANY_MOD (0xffff)
#define ControlMask TUIM_CTRL
#define Mod1Mask TUIM_ALT
#define TUIK_NO_MOD (0x0000)
#define Mod3Mask TUIM_LMETA
#define Mod4Mask TUIM_RMETA

static Key key[] = {
	/* keysym           mask            string      appkey appcursor */
/*	{ TUIK_KP_Home,       ShiftMask,      "\033[2J",       0,   -1},
	{ TUIK_KP_Home,       ShiftMask,      "\033[1;2H",     0,   +1},
	{ TUIK_KP_Home,       TUIK_ANY_MOD,     "\033[H",        0,   -1},
	{ TUIK_KP_Home,       TUIK_ANY_MOD,     "\033[1~",       0,   +1},
	{ TUIK_KP_Up,         TUIK_ANY_MOD,     "\033Ox",       +1,    0},
	{ TUIK_KP_Up,         TUIK_ANY_MOD,     "\033[A",        0,   -1},
	{ TUIK_KP_Up,         TUIK_ANY_MOD,     "\033OA",        0,   +1},
	{ TUIK_KP_Down,       TUIK_ANY_MOD,     "\033Or",       +1,    0},
	{ TUIK_KP_Down,       TUIK_ANY_MOD,     "\033[B",        0,   -1},
	{ TUIK_KP_Down,       TUIK_ANY_MOD,     "\033OB",        0,   +1},
	{ TUIK_KP_Left,       TUIK_ANY_MOD,     "\033Ot",       +1,    0},
	{ TUIK_KP_Left,       TUIK_ANY_MOD,     "\033[D",        0,   -1},
	{ TUIK_KP_Left,       TUIK_ANY_MOD,     "\033OD",        0,   +1},
	{ TUIK_KP_Right,      TUIK_ANY_MOD,     "\033Ov",       +1,    0},
	{ TUIK_KP_Right,      TUIK_ANY_MOD,     "\033[C",        0,   -1},
	{ TUIK_KP_Right,      TUIK_ANY_MOD,     "\033OC",        0,   +1},
	{ TUIK_KP_Prior,      ShiftMask,      "\033[5;2~",     0,    0},
	{ TUIK_KP_Prior,      TUIK_ANY_MOD,     "\033[5~",       0,    0},
	{ TUIK_KP_Begin,      TUIK_ANY_MOD,     "\033[E",        0,    0},
	{ TUIK_KP_End,        ControlMask,    "\033[J",       -1,    0},
	{ TUIK_KP_End,        ControlMask,    "\033[1;5F",    +1,    0},
	{ TUIK_KP_End,        ShiftMask,      "\033[K",       -1,    0},
	{ TUIK_KP_End,        ShiftMask,      "\033[1;2F",    +1,    0},
	{ TUIK_KP_End,        TUIK_ANY_MOD,     "\033[4~",       0,    0},
	{ TUIK_KP_Next,       ShiftMask,      "\033[6;2~",     0,    0},
	{ TUIK_KP_Next,       TUIK_ANY_MOD,     "\033[6~",       0,    0},
	{ TUIK_KP_Insert,     ShiftMask,      "\033[2;2~",    +1,    0},
	{ TUIK_KP_Insert,     ShiftMask,      "\033[4l",      -1,    0},
	{ TUIK_KP_Insert,     ControlMask,    "\033[L",       -1,    0},
	{ TUIK_KP_Insert,     ControlMask,    "\033[2;5~",    +1,    0},
	{ TUIK_KP_Insert,     TUIK_ANY_MOD,     "\033[4h",      -1,    0},
	{ TUIK_KP_Insert,     TUIK_ANY_MOD,     "\033[2~",      +1,    0},
	{ TUIK_KP_Delete,     ControlMask,    "\033[M",       -1,    0},
	{ TUIK_KP_Delete,     ControlMask,    "\033[3;5~",    +1,    0},
	{ TUIK_KP_Delete,     ShiftMask,      "\033[2K",      -1,    0},
	{ TUIK_KP_Delete,     ShiftMask,      "\033[3;2~",    +1,    0},
	{ TUIK_KP_Delete,     TUIK_ANY_MOD,     "\033[P",       -1,    0},
	{ TUIK_KP_Delete,     TUIK_ANY_MOD,     "\033[3~",      +1,    0},
	{ TUIK_KP_MULTIPLY,   TUIK_ANY_MOD,     "\033Oj",       +2,    0},
	{ TUIK_KP_ADD,        TUIK_ANY_MOD,     "\033Ok",       +2,    0},
	{ TUIK_KP_Enter,      TUIK_ANY_MOD,     "\033OM",       +2,    0},
	{ TUIK_KP_Enter,      TUIK_ANY_MOD,     "\r",           -1,    0},
	{ TUIK_KP_Subtract,   TUIK_ANY_MOD,     "\033Om",       +2,    0},
	{ TUIK_KP_Decimal,    TUIK_ANY_MOD,     "\033On",       +2,    0},
	{ TUIK_KP_Divide,     TUIK_ANY_MOD,     "\033Oo",       +2,    0},
	{ TUIK_KP_0,          TUIK_ANY_MOD,     "\033Op",       +2,    0},
	{ TUIK_KP_1,          TUIK_ANY_MOD,     "\033Oq",       +2,    0},
	{ TUIK_KP_2,          TUIK_ANY_MOD,     "\033Or",       +2,    0},
	{ TUIK_KP_3,          TUIK_ANY_MOD,     "\033Os",       +2,    0},
	{ TUIK_KP_4,          TUIK_ANY_MOD,     "\033Ot",       +2,    0},
	{ TUIK_KP_5,          TUIK_ANY_MOD,     "\033Ou",       +2,    0},
	{ TUIK_KP_6,          TUIK_ANY_MOD,     "\033Ov",       +2,    0},
	{ TUIK_KP_7,          TUIK_ANY_MOD,     "\033Ow",       +2,    0},
	{ TUIK_KP_8,          TUIK_ANY_MOD,     "\033Ox",       +2,    0},
	{ TUIK_KP_9,          TUIK_ANY_MOD,     "\033Oy",       +2,    0}, */
	{ TUIK_UP,            ShiftMask,      "\033[1;2A",     0,    0},
	{ TUIK_UP,            Mod1Mask,       "\033[1;3A",     0,    0},
	{ TUIK_UP,         ShiftMask|Mod1Mask,"\033[1;4A",     0,    0},
	{ TUIK_UP,            ControlMask,    "\033[1;5A",     0,    0},
	{ TUIK_UP,      ShiftMask|ControlMask,"\033[1;6A",     0,    0},
	{ TUIK_UP,       ControlMask|Mod1Mask,"\033[1;7A",     0,    0},
	{ TUIK_UP,ShiftMask|ControlMask|Mod1Mask,"\033[1;8A",  0,    0},
	{ TUIK_UP,            TUIK_ANY_MOD,     "\033[A",        0,   -1},
	{ TUIK_UP,            TUIK_ANY_MOD,     "\033OA",        0,   +1},
	{ TUIK_DOWN,          ShiftMask,      "\033[1;2B",     0,    0},
	{ TUIK_DOWN,          Mod1Mask,       "\033[1;3B",     0,    0},
	{ TUIK_DOWN,       ShiftMask|Mod1Mask,"\033[1;4B",     0,    0},
	{ TUIK_DOWN,          ControlMask,    "\033[1;5B",     0,    0},
	{ TUIK_DOWN,    ShiftMask|ControlMask,"\033[1;6B",     0,    0},
	{ TUIK_DOWN,     ControlMask|Mod1Mask,"\033[1;7B",     0,    0},
	{ TUIK_DOWN,ShiftMask|ControlMask|Mod1Mask,"\033[1;8B",0,    0},
	{ TUIK_DOWN,          TUIK_ANY_MOD,     "\033[B",        0,   -1},
	{ TUIK_DOWN,          TUIK_ANY_MOD,     "\033OB",        0,   +1},
	{ TUIK_LEFT,          ShiftMask,      "\033[1;2D",     0,    0},
	{ TUIK_LEFT,          Mod1Mask,       "\033[1;3D",     0,    0},
	{ TUIK_LEFT,       ShiftMask|Mod1Mask,"\033[1;4D",     0,    0},
	{ TUIK_LEFT,          ControlMask,    "\033[1;5D",     0,    0},
	{ TUIK_LEFT,    ShiftMask|ControlMask,"\033[1;6D",     0,    0},
	{ TUIK_LEFT,     ControlMask|Mod1Mask,"\033[1;7D",     0,    0},
	{ TUIK_LEFT,ShiftMask|ControlMask|Mod1Mask,"\033[1;8D",0,    0},
	{ TUIK_LEFT,          TUIK_ANY_MOD,     "\033[D",        0,   -1},
	{ TUIK_LEFT,          TUIK_ANY_MOD,     "\033OD",        0,   +1},
	{ TUIK_RIGHT,         ShiftMask,      "\033[1;2C",     0,    0},
	{ TUIK_RIGHT,         Mod1Mask,       "\033[1;3C",     0,    0},
	{ TUIK_RIGHT,      ShiftMask|Mod1Mask,"\033[1;4C",     0,    0},
	{ TUIK_RIGHT,         ControlMask,    "\033[1;5C",     0,    0},
	{ TUIK_RIGHT,   ShiftMask|ControlMask,"\033[1;6C",     0,    0},
	{ TUIK_RIGHT,    ControlMask|Mod1Mask,"\033[1;7C",     0,    0},
	{ TUIK_RIGHT,ShiftMask|ControlMask|Mod1Mask,"\033[1;8C",0,   0},
	{ TUIK_RIGHT,         TUIK_ANY_MOD,     "\033[C",        0,   -1},
	{ TUIK_RIGHT,         TUIK_ANY_MOD,     "\033OC",        0,   +1},
	{ TUIK_TAB,           ShiftMask,      "\033[Z",        0,    0},
	{ TUIK_A, ControlMask, "\x01", 0, 0},
	{ TUIK_B, ControlMask, "\x02", 0, 0},
	{ TUIK_C, ControlMask, "\x03", 0, 0},
	{ TUIK_D, ControlMask, "\x04", 0, 0},
	{ TUIK_E, ControlMask, "\x05", 0, 0},
	{ TUIK_F, ControlMask, "\x06", 0, 0},
	{ TUIK_G, ControlMask, "\x07", 0, 0},
	{ TUIK_H, ControlMask, "\x08", 0, 0},
	{ TUIK_I, ControlMask, "\x09", 0, 0},
	{ TUIK_J, ControlMask, "\x0a", 0, 0},
	{ TUIK_K, ControlMask, "\x0b", 0, 0},
	{ TUIK_L, ControlMask, "\x0c", 0, 0},
	{ TUIK_M, ControlMask, "\x0d", 0, 0},
	{ TUIK_N, ControlMask, "\x0e", 0, 0},
	{ TUIK_O, ControlMask, "\x0f", 0, 0},
	{ TUIK_P, ControlMask, "\x10", 0, 0},
	{ TUIK_Q, ControlMask, "\x11", 0, 0},
	{ TUIK_R, ControlMask, "\x12", 0, 0},
	{ TUIK_S, ControlMask, "\x13", 0, 0},
	{ TUIK_T, ControlMask, "\x14", 0, 0},
	{ TUIK_U, ControlMask, "\x15", 0, 0},
	{ TUIK_V, ControlMask, "\x16", 0, 0},
	{ TUIK_W, ControlMask, "\x17", 0, 0},
	{ TUIK_X, ControlMask, "\x18", 0, 0},
	{ TUIK_Y, ControlMask, "\x19", 0, 0},
	{ TUIK_Z, ControlMask, "\x1a", 0, 0},
	{ TUIK_3, ControlMask, "\x1b", 0, 0},
	{ TUIK_KP_LEFTBRACE, ControlMask, "\x1b", 0, 0},
	{ TUIK_4, ControlMask, "\x1c", 0, 0},
	{ TUIK_BACKSLASH, ControlMask, "\x1c", 0, 0},
	{ TUIK_5, ControlMask, "\x1d", 0, 0},
	{ TUIK_KP_RIGHTBRACE, ControlMask, "\x1d", 0, 0},
	{ TUIK_6, ControlMask, "\x1e", 0, 0},
	{ TUIK_GRAVE, ControlMask, "\x1e", 0, 0},
	{ TUIK_7, ControlMask, "\x1f", 0, 0},
	{ TUIK_SLASH, ControlMask, "\x1f", 0, 0},
	{ TUIK_8, ControlMask, "\x7f", 0, 0},
	{ TUIK_BACKSPACE, ControlMask, "\x7f", 0, 0},
	{ TUIK_PAGEUP, TUIK_ANY_MOD, "\e[5~", 0, 0},
	{ TUIK_PAGEDOWN, TUIK_ANY_MOD, "\e[6~", 0, 0},
	{ TUIK_RETURN,        Mod1Mask,       "\033\r",        0,    0},
	{ TUIK_RETURN,        TUIK_ANY_MOD,     "\r",            0,    0},
	{ TUIK_INSERT,        ShiftMask,      "\033[4l",      -1,    0},
	{ TUIK_INSERT,        ShiftMask,      "\033[2;2~",    +1,    0},
	{ TUIK_INSERT,        ControlMask,    "\033[L",       -1,    0},
	{ TUIK_INSERT,        ControlMask,    "\033[2;5~",    +1,    0},
	{ TUIK_INSERT,        TUIK_ANY_MOD,     "\033[4h",      -1,    0},
	{ TUIK_INSERT,        TUIK_ANY_MOD,     "\033[2~",      +1,    0},
	{ TUIK_DELETE,        ControlMask,    "\033[M",       -1,    0},
	{ TUIK_DELETE,        ControlMask,    "\033[3;5~",    +1,    0},
	{ TUIK_DELETE,        ShiftMask,      "\033[2K",      -1,    0},
	{ TUIK_DELETE,        ShiftMask,      "\033[3;2~",    +1,    0},
/*	{ TUIK_DELETE,        TUIK_ANY_MOD,     "\033[P",       +1,    0}, */
	{ TUIK_DELETE,        TUIK_ANY_MOD,     "\033[3~",      0,    0},
	{ TUIK_BACKSPACE,     0x0000,      "\177",          0,    0},
	{ TUIK_BACKSPACE,     Mod1Mask,       "\033\177",      0,    0},
	{ TUIK_HOME,          ShiftMask,      "\033[2J",       0,   -1},
	{ TUIK_HOME,          ShiftMask,      "\033[1;2H",     0,   +1},
	{ TUIK_HOME,          TUIK_ANY_MOD,     "\033[H",        0,   -1},
	{ TUIK_HOME,          TUIK_ANY_MOD,     "\033[1~",       0,   +1},
	{ TUIK_END,           ControlMask,    "\033[J",       -1,    0},
	{ TUIK_END,           ControlMask,    "\033[1;5F",    +1,    0},
	{ TUIK_END,           ShiftMask,      "\033[K",       -1,    0},
	{ TUIK_END,           ShiftMask,      "\033[1;2F",    +1,    0},
	{ TUIK_END,           TUIK_ANY_MOD,     "\033[4~",       0,    0},
/*	{ TUIK_Prior,         ControlMask,    "\033[5;5~",     0,    0},
	{ TUIK_Prior,         ShiftMask,      "\033[5;2~",     0,    0},
	{ TUIK_Prior,         TUIK_ANY_MOD,     "\033[5~",       0,    0},
	{ TUIK_Next,          ControlMask,    "\033[6;5~",     0,    0},
	{ TUIK_Next,          ShiftMask,      "\033[6;2~",     0,    0},
	{ TUIK_Next,          TUIK_ANY_MOD,     "\033[6~",       0,    0}, */
	{ TUIK_F1,            0x0000,      "\033OP" ,       0,    0},
	{ TUIK_F1, /* F13 */  ShiftMask,      "\033[1;2P",     0,    0},
	{ TUIK_F1, /* F25 */  ControlMask,    "\033[1;5P",     0,    0},
	{ TUIK_F1, /* F37 */  Mod4Mask,       "\033[1;6P",     0,    0},
	{ TUIK_F1, /* F49 */  Mod1Mask,       "\033[1;3P",     0,    0},
	{ TUIK_F1, /* F61 */  Mod3Mask,       "\033[1;4P",     0,    0},
	{ TUIK_F2,            TUIK_NO_MOD,      "\033OQ" ,       0,    0},
	{ TUIK_F2, /* F14 */  ShiftMask,      "\033[1;2Q",     0,    0},
	{ TUIK_F2, /* F26 */  ControlMask,    "\033[1;5Q",     0,    0},
	{ TUIK_F2, /* F38 */  Mod4Mask,       "\033[1;6Q",     0,    0},
	{ TUIK_F2, /* F50 */  Mod1Mask,       "\033[1;3Q",     0,    0},
	{ TUIK_F2, /* F62 */  Mod3Mask,       "\033[1;4Q",     0,    0},
	{ TUIK_F3,            TUIK_NO_MOD,      "\033OR" ,       0,    0},
	{ TUIK_F3, /* F15 */  ShiftMask,      "\033[1;2R",     0,    0},
	{ TUIK_F3, /* F27 */  ControlMask,    "\033[1;5R",     0,    0},
	{ TUIK_F3, /* F39 */  Mod4Mask,       "\033[1;6R",     0,    0},
	{ TUIK_F3, /* F51 */  Mod1Mask,       "\033[1;3R",     0,    0},
	{ TUIK_F3, /* F63 */  Mod3Mask,       "\033[1;4R",     0,    0},
	{ TUIK_F4,            TUIK_NO_MOD,      "\033OS" ,       0,    0},
	{ TUIK_F4, /* F16 */  ShiftMask,      "\033[1;2S",     0,    0},
	{ TUIK_F4, /* F28 */  ControlMask,    "\033[1;5S",     0,    0},
	{ TUIK_F4, /* F40 */  Mod4Mask,       "\033[1;6S",     0,    0},
	{ TUIK_F4, /* F52 */  Mod1Mask,       "\033[1;3S",     0,    0},
	{ TUIK_F5,            TUIK_NO_MOD,      "\033[15~",      0,    0},
	{ TUIK_F5, /* F17 */  ShiftMask,      "\033[15;2~",    0,    0},
	{ TUIK_F5, /* F29 */  ControlMask,    "\033[15;5~",    0,    0},
	{ TUIK_F5, /* F41 */  Mod4Mask,       "\033[15;6~",    0,    0},
	{ TUIK_F5, /* F53 */  Mod1Mask,       "\033[15;3~",    0,    0},
	{ TUIK_F6,            TUIK_NO_MOD,      "\033[17~",      0,    0},
	{ TUIK_F6, /* F18 */  ShiftMask,      "\033[17;2~",    0,    0},
	{ TUIK_F6, /* F30 */  ControlMask,    "\033[17;5~",    0,    0},
	{ TUIK_F6, /* F42 */  Mod4Mask,       "\033[17;6~",    0,    0},
	{ TUIK_F6, /* F54 */  Mod1Mask,       "\033[17;3~",    0,    0},
	{ TUIK_F7,            TUIK_NO_MOD,      "\033[18~",      0,    0},
	{ TUIK_F7, /* F19 */  ShiftMask,      "\033[18;2~",    0,    0},
	{ TUIK_F7, /* F31 */  ControlMask,    "\033[18;5~",    0,    0},
	{ TUIK_F7, /* F43 */  Mod4Mask,       "\033[18;6~",    0,    0},
	{ TUIK_F7, /* F55 */  Mod1Mask,       "\033[18;3~",    0,    0},
	{ TUIK_F8,            TUIK_NO_MOD,      "\033[19~",      0,    0},
	{ TUIK_F8, /* F20 */  ShiftMask,      "\033[19;2~",    0,    0},
	{ TUIK_F8, /* F32 */  ControlMask,    "\033[19;5~",    0,    0},
	{ TUIK_F8, /* F44 */  Mod4Mask,       "\033[19;6~",    0,    0},
	{ TUIK_F8, /* F56 */  Mod1Mask,       "\033[19;3~",    0,    0},
	{ TUIK_F9,            TUIK_NO_MOD,      "\033[20~",      0,    0},
	{ TUIK_F9, /* F21 */  ShiftMask,      "\033[20;2~",    0,    0},
	{ TUIK_F9, /* F33 */  ControlMask,    "\033[20;5~",    0,    0},
	{ TUIK_F9, /* F45 */  Mod4Mask,       "\033[20;6~",    0,    0},
	{ TUIK_F9, /* F57 */  Mod1Mask,       "\033[20;3~",    0,    0},
	{ TUIK_F10,           TUIK_NO_MOD,      "\033[21~",      0,    0},
	{ TUIK_F10, /* F22 */ ShiftMask,      "\033[21;2~",    0,    0},
	{ TUIK_F10, /* F34 */ ControlMask,    "\033[21;5~",    0,    0},
	{ TUIK_F10, /* F46 */ Mod4Mask,       "\033[21;6~",    0,    0},
	{ TUIK_F10, /* F58 */ Mod1Mask,       "\033[21;3~",    0,    0},
	{ TUIK_F11,           TUIK_NO_MOD,      "\033[23~",      0,    0},
	{ TUIK_F11, /* F23 */ ShiftMask,      "\033[23;2~",    0,    0},
	{ TUIK_F11, /* F35 */ ControlMask,    "\033[23;5~",    0,    0},
	{ TUIK_F11, /* F47 */ Mod4Mask,       "\033[23;6~",    0,    0},
	{ TUIK_F11, /* F59 */ Mod1Mask,       "\033[23;3~",    0,    0},
	{ TUIK_F12,           TUIK_NO_MOD,      "\033[24~",      0,    0},
	{ TUIK_F12, /* F24 */ ShiftMask,      "\033[24;2~",    0,    0},
	{ TUIK_F12, /* F36 */ ControlMask,    "\033[24;5~",    0,    0},
	{ TUIK_F12, /* F48 */ Mod4Mask,       "\033[24;6~",    0,    0},
	{ TUIK_F12, /* F60 */ Mod1Mask,       "\033[24;3~",    0,    0},
};
