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
	internal_clock = [[clock:         \t]] .. tostring(CLOCK) .. " hz";
	hardware = [[#joysticks:\t\t]] .. tostring(JOYSTICKS) .. [[\n\r#ledctrls:\t\t]] .. tostring(LEDCONTROLLERS);
	pathstr = [[themepath:\t\t]] .. tostring(THEMEPATH) .. [[\n\rresourcepath:\t ]] .. tostring(RESOURCEPATH) ..
		[[\n\rbinpath:\t\t ]] .. tostring(BINPATH) ..
		[[\n\rlibpath:\t\t ]] .. tostring(LIBPATH);
	internalmode = [[internal mode:\t]] .. tostring(INTERNALMODE);

	vid = render_text( welcomestr .. [[\n\r\ffonts/default.ttf,12]] .. games .. [[\n\r]] .. hardware .. [[\n\r]] .. internal_clock .. 
	[[\n\r]] .. display .. [[\n\r]] .. pathstr .. [[\n\r]] .. internalmode );

	vid2 = render_text( [[\n\r\ffonts/default.ttf,14\t\bCommand-Line Arguments:\!b\n\r\ffonts/default.ttf,12
	-w res  \t(default: 640)\n\r
	-h res  \t(default: 480)\n\r
	-f      \tswitch resolution\n\r
	-m      \t conservative memory profile\n\r
	-s      \twindowed fullscreen\n\r
	-p pname\tforce resource path\n\r
	-t tname\tforce theme path\n\r
	-o fname\tforce frameserver\n\r
	-d fname\tdatabase filename\n\r
	-g      \tenable (partial) debug output\n\r
	-r num  \tset texture mode: (0, 1, 2)\n\t]] );

	move_image(vid2, VRESW - image_surface_properties(vid2).width, 105);
	move_image(vid, 10, 24);
		
	for i=0,LEDCONTROLLERS-1 do
		j = 0;
		while j < controller_leds(i) do
			set_led(i, j, 1);
			j = j + 1;
		end
		
		last_leds[i] = controller_leds(i) - 1;
	end	
	
	show_image(vid);
end

function welcome_input( inputtbl ) 
	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		if (symtable[ inputtbl.keysym ] == "ESCAPE") then
			shutdown();
		end
	end
end

-- tinker with the LEDs if they're present and working
function welcome_clock_pulse()
	
	ltime = ltime - 1;
	if ltime == 0 then
		for k, v in pairs(last_leds) do
			set_led(k, last_leds[k], 1);
			last_leds[k] = (last_leds[k] + 1) % controller_leds(k);
			set_led(k, last_leds[k], 0);
		end
		
		ltime = 50;
	end
end
