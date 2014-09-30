-- Meet and greet screen
-- Sweep the LEDs (if present) as a simple test as well.
--
last_leds = {};
ltime = 50;

function welcome()
	local symfun = system_load("scripts/symtable.lua");
	if (symfun ~= nil) then
		symtable = symfun();
	end

	titlestr = render_text( [[\ffonts/default.ttf,18\bWelcome to ARCAN!]] );
	move_image(titlestr,
		VRESW * 0.5 - (0.5 * image_surface_properties(titlestr).width));
	show_image(titlestr);

	intrstr = render_text(
[[\ffonts/default.ttf,12\bUsage:
\!b arcan <cmdline arguments> themename <theme arguments>]] )

	move_image(intrstr, VRESW * 0.5 -
		(0.5 * image_surface_properties(intrstr).width), 24 );

	show_image(intrstr);

	welcomestr = [[\n\r
	\ffonts/default.ttf,14\bPoints of reference:\!b\n\r\ffonts/default.ttf,12
	http://www.arcan-fe.com - Main Site\n\r
	https://github.com/letoram/arcan - Github Page\n\r
	contact@arcan-fe.com - E-mail contact\n\r
	\ffonts/default.ttf,14\b\n\nDetected settings:\!b\n\r]];

	gamelst = list_games( {} );

	if (gamelst == nil) then
		gamelst = {};
	end

	if (LIBPATH == nil) then
		LIBPATH = "not found";
	end

	local st = {welcomestr, [[\ffonts/default.ttf,12]]};
	table.insert(st, string.format("# Games:\\t\\t%d", #gamelst));
	table.insert(st, string.format("Resolution:\\t\\t%d x %d", VRESW, VRESH));
	table.insert(st, string.format("Clock:\\t\\t%d Hz", CLOCKRATE));
	table.insert(st, string.format("Themepath:\\t\\t%s", string.gsub(THEMEPATH, "\\", "\\\\")));
	table.insert(st, string.format("Respath:\\t\\t%s", string.gsub(RESOURCEPATH, "\\", "\\\\")));
	table.insert(st, string.format("Libpath:\\t\\t%s", string.gsub(LIBPATH, "\\", "\\\\")));
	table.insert(st, string.format("Binpath:\\t\\t%s", string.gsub(BINPATH, "\\", "\\\\")));
	table.insert(st, string.format("Internal:\\t\\t%s", tostring(INTERNALMODE)));

	datawindow = render_text(table.concat(st, "\\n\\r"));
	argwindow = render_text(
[[\n\r\ffonts/default.ttf,14\t\bCommand-Line Arguments:\!b
\n\r\ffonts/default.ttf,12
-w res  \t(default: 640)\n\r
-h res  \t(default: 480)\n\r
-x winx \tforce window x position\n\r
-y winy \tforce window y position\n\r
-f      \tswitch display to fullscreen\n\r
-m      \ttoggle conservative memory mode\n\r
-M rate \tsplit open a debug session\n\r
-O src  \tmonitor theme or LOG:fname\n\r
-s      \ttoggle borderless window mode\n\r
-p path \tset resourcepath\n\r
-t path \tset themepath\n\r
-o fsrv \tforce frameserver\n\r
-l lib  \tforce internal launch hijacklib\n\r
-d db   \tset database\n\r
-g      \tincrease debuglevel by one\n\r
-a nms  \tmultisampling\n\r
-v vs   \tdisable VSYNC\n\r
-V      \tdisable waiting between frames\n\r
-F      \tvsync prewake (range, 0..1)\n\r
-S      \tsilence audio output\n\r
]] );

	move_image(datawindow, VRESW - image_surface_properties(argwindow).width, 38);
	move_image(argwindow, 10, 38);

	for i=0,LEDCONTROLLERS-1 do
		j = 0;
		while j < controller_leds(i) do
			set_led(i, j, 1);
			j = j + 1;
		end

		last_leds[i] = controller_leds(i) - 1;
	end

	show_image(datawindow);
	show_image(argwindow);

	print( system_identstr() );
end

function welcome_input( inputtbl )
	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		if (symtable[ inputtbl.keysym ] == "ESCAPE") then
			shutdown();
		end
	end
end

