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
    symtable  = system_load("scripts/symtable.lua")();

    local analabel   = drawline( [[\bAnalog]], 18 );
    local digilabel  = drawline( [[\bDigital]], 18 );
    local lookuplabel = drawline( [[\bLookup]], 18 );
    local translabel = drawline( [[\bTranslated]], 18 );

		inputanalog_toggle(1);
		tc = null_surface(1, 1);

    move_image(analabel, 0, 0, 0);
    move_image(digilabel, (VRESW / 3), 0, 0);
    move_image(translabel, (VRESW / 3) * 2, 0, 0);
    move_image(lookuplabel, VRESW / 3 * 2, VRESH / 2, 0);

    show_image(analabel);
    show_image(digilabel);
    show_image(translabel);

-- enumerate the list of found devices
	restbl = inputanalog_query();
	print(#restbl, "entries found");

	for k, v in ipairs(restbl) do
		print("-new table-")
		print(k, v)
	end

-- enable analog events
	inputanalog_toggle(1);
end

function round(inn, dec)
	return math.floor( (inn * 10^dec) / 10^dec);
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
    move_image(lookupimg, VRESW / 3, VRESH / 2 + 20, 0);
    show_image(lookupimg);
end

function analog_str(intbl)
	local res = "";

	res = tostring(intbl.count) .. " : " .. tostring(round(intbl.min, 2)) ..
"/" .. tostring(round(intbl.max, 2)) .. "(" .. tostring(round(intbl.avg, 2)) .. ")";

	return res;
end

function eventtest_clock_pulse(stamp, delta)
    if (analogimg) then
	delete_image(analogimg);
    end

    line = "";
    for ak, ad in pairs( analogdata ) do
	workline = [[\n\rDevice(]] .. ak .. [[):\n\r\t]];

	for id, iv in pairs( ad ) do
	    workline = workline .. " axis: " .. id .. " # " .. analog_str(iv) .. [[\n\r\t]];
	end

	line = line .. workline .. [[\r\n]];
    end

    analogimg = drawline(line, 12);
    move_image(analogimg, 0, 20, 0);
    show_image(analogimg);
end

tick_counter = 500;
function eventtest_clock_pulse()
	tick_counter = tick_counter - 1;
	if (tick_counter == 0) then
		return shutdown("timeout");
	else
		delete_image(tc);
		tc = render_text("Shutdown in " .. tostring(tick_counter));
		show_image(tc);
		move_image(tc, 0, VRESH - 20);
	end
end

function eventtest_input( iotbl )
	tick_counter = 500;

	if (iotbl.kind == "digital") then
		if (iotbl.translated) then
			translate_str(iotbl);
			lookup(iotbl);
		else
			digital_str(iotbl);
		end

    elseif (iotbl.kind == "analog") then -- analog
		local anatbl = {};

		if (analogdata[iotbl.devid] == nil) then
			analogdata[iotbl.devid] = {};
		end

		if (analogdata[iotbl.devid][iotbl.subid] == nil) then
			analogdata[iotbl.devid][iotbl.subid] = anatbl;
			anatbl.count = 0;
			anatbl.min = 65535;
			anatbl.max = 0;
			anatbl.avg = 1;
			anatbl.samples = {};
		end

		anatbl = analogdata[iotbl.devid][iotbl.subid];
		anatbl.count = anatbl.count + 1;
		table.insert(anatbl.samples, iotbl.samples[1]);

		if (iotbl.samples[1] < anatbl.min) then
			anatbl.min = iotbl.samples[1];
		end

		if (iotbl.samples[1] > anatbl.max) then
			anatbl.max = iotbl.samples[1];
		end

		anatbl.avg = (anatbl.avg + iotbl.samples[1]) / 2;

		if (#anatbl.samples > 10) then
			table.remove(anatbl.samples, 1);
		end

		anatbl.match = tbl;
    end
end

