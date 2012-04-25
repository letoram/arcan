-- Quite exhaustive tester for the I/O parts of the event management. 
-- (use with -w 640 -h 480)

analogtbl = {};
digitaltbl = {};
translatetbl = {};
lookuptbl = {};
analogdata = {};

function drawline(text, size)
    if (size == nil) then
	size = 18
    end
    
    return render_text( [[\ffonts/default.ttf,]] .. size .. " " .. text );
end

function eventtest()
--	zap keyconf table
    system_load("scripts/keyconf.lua")();
    symtable  = system_load("scripts/symtable.lua")();
	keyconfig = keyconf_create();
	
    local analabel   = drawline( [[\bAnalog]], 18 );
    local digilabel  = drawline( [[\bDigital]], 18 );
    local lookuplabel = drawline( [[\bLookup]], 18 );
    local translabel = drawline( [[\bTranslated]], 18 ); 

    move_image(analabel, 0, 0, 0);
    move_image(digilabel, (VRESW / 3), 0, 0);
    move_image(translabel, (VRESW / 3) * 2, 0, 0);
    move_image(lookuplabel, 0, VRESH / 2, 0);
    
    show_image(analabel);
    show_image(digilabel);
    show_image(translabel);

-- redirect if we need to config hack
	if (keyconfig.active == false) then
		keyconfig.iofun = eventtest_input;
		eventtest_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				eventtest_input = keyconfig.iofun;
			end
		end
	end
end

function digital_str(iotbl)
    table.insert(digitaltbl, "dev(" .. iotbl.devid .. "),sub(" ..iotbl.subid .. "):" .. tostring(iotbl.active));

    line = "";
    for i=1, #digitaltbl do 
	line = line .. digitaltbl[i] .. [[\r\n]];
    end
    
    if (#digitaltbl > 10) then
	table.remove(digitaltbl, 1);
    end
    
    if (digitalimg) then
	delete_image(digitalimg);
    end
    
    digitalimg = drawline(line, 12);
    move_image(digitalimg, (VRESW / 3), 20, 0);
    show_image(digitalimg);
end

function translate_str(iotbl)
    table.insert(translatetbl, "dev(" .. iotbl.devid .. "), sub(" ..iotbl.subid .. ") [" ..
	iotbl.modifiers .. "] => " .. iotbl.keysym .. ", " .. tostring(iotbl.active));

    line = "";
    for i=1, #translatetbl do 
	line = line .. translatetbl[i] .. [[\r\n]];
    end
    
    if (#translatetbl > 10) then
	table.remove(translatetbl, 1);
    end
    
    if (translateimg) then
	delete_image(translateimg);
    end
    
    translateimg = drawline(line, 12);
    move_image(translateimg, (VRESW / 3) * 2, 20, 0);
    show_image(translateimg);
end

function lookup(iotbl)
    line = "";

    if symtable[iotbl.keysym] then
	line = line .. iotbl.keysym .. " =(symtable)> " .. symtable[iotbl.keysym] .. [[\t]];
    end
    
    if keyconfig:match(iotbl) then
		line = line .. iotbl.keysym ..  " =(keyconf)> " .. table.concat(keyconfig:match(iotbl), ",");
    end
    
    if line ~= "" then
	table.insert(lookuptbl, line);
    end
    
    if (#lookuptbl > 10) then
	table.remove(lookuptbl, 1);
    end

    line = "";
    for i=1, #lookuptbl do 
	line = line .. lookuptbl[i] .. [[\r\n]];
    end

    if (lookupimg) then
	delete_image(lookupimg);
    end
    
    lookupimg = drawline(line, 12);
    move_image(lookupimg, 0, VRESH / 2 + 20, 0);
    show_image(lookupimg);
end

function eventtest_clock_pulse(stamp, delta)
    if (analogimg) then
	delete_image(analogimg);
    end
    
    line = "";
    for ak, ad in pairs( analogdata ) do 
	workline = [[\n\rDevice(]] .. ak .. [[):\n\r\t]];
		
	for id, iv in pairs( ad ) do
	    workline = workline .. " axis: " .. id .. " # " .. iv .. [[\n\r\t]];
	end 

	line = line .. workline .. [[\r\n]];
    end
    
    analogimg = drawline(line, 12);
    move_image(analogimg, 0, 20, 0);
    show_image(analogimg);
end

function eventtest_input( iotbl )
	if (iotbl.kind == "digital") then
		if (iotbl.translated) then
			translate_str(iotbl);
			lookup(iotbl);
		else
			digital_str(iotbl);
		end
    
    elseif (iotbl.kind == "analog") then -- analog
		if (analogdata[iotbl.devid] == nil) then
			analogdata[iotbl.devid] = {};
		end

		if (analogdata[iotbl.devid][iotbl.subid] == nil) then
			analogdata[iotbl.devid][iotbl.subid] = 0;
		end

		local tbl = keyconfig:match(iotbl);
		analogdata[iotbl.devid][iotbl.subid] = analogdata[iotbl.devid][iotbl.subid] + 1;
    end
end
