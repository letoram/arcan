-- grid- view specific context menus
-- 
-- same as with gridle_intmenus and gridle_menus
-- just patching dispatchinput, a lot of string/functiontbls and calls to
-- spawn_menu. 
--
--
-- Filter 
-- Launch Mode
-- Admin
--

local mainlbls = {
	"Filter",
	"Admin"
}

local filterlbls = {
	"Family",
	"Manufacturer",
	"System",
	"Year"
};

-- change launch mode for this particular game
function gridlemenu_context( gametbl )
	griddispatch = settings.iodispatch;
	settings.iodispatch = {};
	gridle_oldinput = gridle_input;
	gridle_input = gridle_dispatchinput;
	
	gridlemenu_defaultdispatch();

	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;
end
