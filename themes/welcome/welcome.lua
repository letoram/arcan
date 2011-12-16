-- Meet and greet screen
-- Sweep the LEDs (if present) as a simple test as well.
--
last_leds = {};
ltime = 50;

function welcome()
	local symfun = system_load("scripts/symtable.lua");
	symtable = symfun();

	welcomestr = [[\ffonts/default.ttf,18\t\tWelcome to ARCAN!\n\rPoints of reference: \n\r\i\ffonts/default.ttf,14
https://sourceforge.net/projects/arcanfe/\!i\t - Project Page\n\r\i
\ffonts/default.ttf,18\!iDetected settings:\n\r\ffonts/default.ttf,14]];

	gamelst = list_games( {} );

	if (gamelst == nil) then
		gamelst = {};
	end

	games = [[\b#games in database:\!b\t]] .. tostring( # gamelst ); 

	display = [[\bvideo resolution:\!b\t]] .. tostring(VRESH) .. "x" .. tostring(VRESW);

	internal_clock = [[\binternal clock:\!b\t]] .. tostring(CLOCK) .. " hz";

	hardware = [[\b# joysticks:\b\t]] .. tostring(JOYSTICKS) .. 
		[[\n\r\b# led controllers:\b\t]] .. tostring(LEDCONTROLLERS);
		
	pathstr = [[ \btheme:\!b\t ]] .. tostring(THEMEPATH) ..
		[[\n\r\bresource path: \!b\t ]] .. tostring(RESOURCEPATH) ..
		[[\n\r\bbinpath: \!b\t ]] .. tostring(BINPATH) ..
		[[\n\r\blibpath: \!b\t ]] .. tostring(LIBPATH);
		
	internalmode = [[\binternal mode support:\!b\t]] .. tostring(INTERNALMODE);
	vid = render_text( welcomestr .. [[\n\r\ffonts/default.ttf,14]] .. display .. [[\n\r]] .. games .. [[\n\r]] .. internal_clock .. 
	[[\n\r]] .. hardware .. [[\n\r]] .. pathstr .. [[\n\r]] .. internalmode );
	
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

-- check for available helper scripts etc.
function sanity_test()
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
