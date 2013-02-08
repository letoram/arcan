-- Meet and greet screen
-- Sweep the LEDs (if present) as a simple test as well.
--
last_leds = {};
ltime = 50;

function welcome()
	local symfun = system_load("scripts/symtable.lua");
	symtable = symfun();

	titlestr = render_text( [[\ffonts/default.ttf,18\bWelcome to ARCAN!]] );
	move_image(titlestr, VRESW * 0.5 - (0.5 * image_surface_properties(titlestr).width)); 
	show_image(titlestr);

	welcomestr = [[\n\r
	\ffonts/default.ttf,14\bPoints of reference:\!b\n\r\ffonts/default.ttf,12
	http://arcanfe.wordpress.com - Main Site\n\r
	https://sourceforge.net/projects/arcanfe\n\r
	fearcan@gmail.com - E-mail contact\n\r
	\ffonts/default.ttf,14\b\n\nDetected settings:\!b\n\r]];

	gamelst = list_games( {} );

	if (gamelst == nil) then
		gamelst = {};
	end

	games = [[#games:\t\t]] .. tostring( # gamelst ); 
	display = [[resolution:\t\t]] .. tostring(VRESH) .. "x" .. tostring(VRESW);
	internal_clock = [[clock:         \t]] .. tostring(CLOCKRATE) .. " hz";
	hardware = [[#joysticks:\t\t]] .. tostring(JOYSTICKS) .. [[\n\r#ledctrls:\t\t]] .. tostring(LEDCONTROLLERS);
	pathstr = [[themepath:\t\t]] .. tostring(THEMEPATH) .. [[\n\rresourcepath:\t ]] .. tostring(RESOURCEPATH) ..
		[[\n\rbinpath:\t\t ]] .. tostring(BINPATH) ..
		[[\n\rlibpath:\t\t ]] .. tostring(LIBPATH);
	internalmode = [[internal mode:\t]] .. tostring(INTERNALMODE);

	datawindow = render_text( welcomestr .. [[\n\r\ffonts/default.ttf,12]] .. games .. [[\n\r]] .. hardware .. [[\n\r]] .. internal_clock .. 
	[[\n\r]] .. display .. [[\n\r]] .. pathstr .. [[\n\r]] .. internalmode );

	argwindow = render_text( [[\n\r\ffonts/default.ttf,14\t\bCommand-Line Arguments:\!b\n\r\ffonts/default.ttf,12
	-w res  \t(default: 640)\n\r
	-h res  \t(default: 480)\n\r
	-v      \tdisable VSYNC\n\r
	-V      \tdisable WaitSleep (use with -v)\n\r
	-x winx \tset window start x coordinate\n\r
	-y winy \tset window start y coordinate\n\r
	-f      \tswitch resolution (fullscreen)\n\r
	-m      \tconservative memory profile\n\r
	-s      \tdisable window borders\n\r
	-p pname\tforce resource path\n\r
	-t tname\tforce theme path\n\r
	-o fname\tforce frameserver\n\r
  -l hijacklib\tforce hijack lib\n\r
	-d fname\tdatabase filename\n\r
	-g      \tenable (partial) debug output\n\r
	-a      \tmultisamples (default 4, disable 0)\n\r
	-S      \t0dB global audio output\n\r
	-r num  \tset texture scale mode: (0, 1, 2)\n\t]] );

	move_image(datawindow, VRESW - image_surface_properties(argwindow).width, 24);
	move_image(argwindow, 10, 24);
		
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
	
end

function welcome_input( inputtbl ) 
	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		if (symtable[ inputtbl.keysym ] == "ESCAPE") then
			shutdown();
		end
	end
end

