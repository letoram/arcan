function welcome()
	local symfun = system_load("builtin/keyboard.lua");
	if (symfun ~= nil) then
		symtable = symfun();
	end

	titlestr = render_text( [[\ffonts/default.ttf,18\bWelcome to ARCAN!]] );
	move_image(titlestr,
		VRESW * 0.5 - (0.5 * image_surface_properties(titlestr).width));
	show_image(titlestr);

	local vid = load_image("images/icons/arcanicon.png");
	if (valid_vid(vid)) then
		resize_image(vid, 64, 64);
		move_image(vid, VRESW - 64, 0);
		show_image(vid);
		nudge_image(vid, 0, VRESH - 64, 100, INTERP_EXPIN);
		move_image(vid, VRESW - 64, 0, 100, INTERP_EXPOUT);
		image_transform_cycle(vid, 1);
	end

	intrstr = render_text(
[[\ffonts/default.ttf,12\bUsage:
\!b arcan <cmdline arguments> applname <appl arguments>]] )

	move_image(intrstr, VRESW * 0.5 -
		(0.5 * image_surface_properties(intrstr).width), 24 );

	show_image(intrstr);

	welcomestr = [[\n\r
	\ffonts/default.ttf,14\bPoints of reference:\!b\n\r\ffonts/default.ttf,12
	http://www.arcan-fe.com - Main Site\n\r
	https://github.com/letoram/arcan - Github Page\n\r
	contact@arcan-fe.com - E-mail contact\n\r
	\ffonts/default.ttf,14\b\n\nDetected settings:\!b\n\r]];

	left_inf = render_text(welcomestr);

	local st = {};
	table.insert(st, string.format("Resolution:\\t\\t%d x %d", VRESW, VRESH));
	table.insert(st, string.format("Clock:\\t\\t%d Hz", CLOCKRATE));
	table.insert(st, string.format("GL Version:\\t\\t%s", GL_VERSION));
	table.insert(st, string.format("Build:\\t\\t%s", API_ENGINE_BUILD));
	right_inf = render_text(table.concat(st, "\\n\\r"));
	move_image(right_inf, image_surface_properties(left_inf).width + 10, 38);

	argwindow = render_text(
[[\n\r\ffonts/default.ttf,14\t\bCommand-Line Arguments:\!b
\n\r\ffonts/default.ttf,12
-w\t--width       \tdesired canvas width (default: 640)\n\r
-h\t--height      \tdesired canvas height (default: 480)\n\r
-f\t--fullscreen  \ttoggle fullscreen mode ON (default: off)\n\r
-m\t--conservative\ttoggle conservative memory management (default: off)\n\r
-q\t--timedump    \twait n ticks, dump snapshot to resources/logs/timedump\n\r
-s\t--windowed    \ttoggle borderless window mode\n\r
-p\t--rpath          \tchange default searchpath for shared resources\n\r
-B\t--binpath     \tchange default searchpath and base for arcan_framesever\n\r
-t\t--applpath    \tchange default searchpath for applications\n\r
-b\t--fallback    \tset a recovery/fallback application if appname crashes\n\r
-d\t--database    \tsqlite database (default: arcandb.sqlite)\n\r
-g\t--debug       \tincrement debug level (events, coredumps, etc.)\n\r
-S\t--nosound     \tdisable audio output (set gain to 0dB) \n\n
]]);

	appl_list = glob_resource("*", SYS_APPL_RESOURCE);
	if (#appl_list > 0) then
		local lst = {"\\bPossible <applname>:\\!b\\n\\r"};
		for k, v in ipairs(appl_list) do
			local item = string.gsub(v, "\\", "\\\\");
			if k % 5 == 0 then
				item = item .. [[\n\r]];
			end
			table.insert(lst, item);
		end
		lst = table.concat(lst, " ");
		img = render_text(lst);
		move_image(img, 0, image_surface_properties(argwindow).height + 48);
		show_image(img);
	end

	move_image(argwindow, 10, 38);
	show_image(argwindow);
end

local tick_counter = 500;
function welcome_clock_pulse()
	tick_counter = tick_counter - 1;
	if (tick_counter == 0) then
		return shutdown("timeout");
	end
end

function welcome_input( inputtbl )
	if (inputtbl.kind == "digital" and
		inputtbl.translated and inputtbl.active) then
		if (symtable[ inputtbl.keysym ] == "ESCAPE") then
			shutdown();
		end
	end
end

