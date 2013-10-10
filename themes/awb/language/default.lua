--
-- Simple table of messages for internationalization
-- These follow the regular format- string format and won't be "unescaped".
--
return {
	GROUP_MUSIC = "Music",
	GROUP_RECORDINGS = "Recordings",
	GROUP_VIDEOS = "Videos",
	GROUP_SYSTEMS = "Systems",
	GROUP_SAVES = "Saves",
	GROUP_TOOLS = "Tools",
	HOVER_CLONE = "Clone: Attach a copy of the canvas\\n\\r to the mouse cursor",
	HOVER_FILTER = "Display Filters: click to activate / set group" ..
	"\\n\\rright-click specific filter to configure",
	HOVER_PLAYPAUSE = "Pause / Play at normal speed",
	HOVER_FASTFWD = "Increase playback speed",
	HOVER_STATESAVE = "Save current target state",
	HOVER_STATELOAD = "Load target state",
	HOVER_TARGETCFG = "Target/Timing specific configuration\\n\\r",
	HOVER_CPUFILTER = "CPU- Based Display Filters",
	HOVER_GLOBALINPUT = "Toggle Global Input ON/OFF",
	HOVER_INPUTCFG = "Switch active input layout",
	HELPER_MSG = [[
		(global)\n\r
			LCTRL\tgrab/release input\n\r
			SHIFT+TAB\t cycle visible windows\n\r
			ALT+F4\t close normal (non-media) window\n\r
			RCLICK\t context menu (where applicable)\n\r
			F12\t\tforce-focus window\n\r
			F11\t\tgather/scatter visible windows\n\r\n\r
		(titlebar)\n\r
			SHIFT+CLICK+DRAG\t fling window\n\r\n\r
		(target window)\n\r
			RCLICK\t scale options (resize-button)\n\r
	]];
};

