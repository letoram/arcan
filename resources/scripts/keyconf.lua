-- Keyconf.lua
----------------------------------------------------------
-- includable by any theme
-- will go through a table of desired mappings,
-- and associate these with input events. 
-- These can then be serialized to a file that the various tools
-- can convert to different targets (generating 
-- configurations) for external launch,
-- or used for conversion in internal launch.
-- modify the possible entries as you see fit, these are only helpers. 
----------------------------------------------------------

local keyconf_current = {};
keyconf_current.table = {};
-- first char is directive, 
-- whitespace : optional
-- r : required
-- a : analog

keyconf_current.menu_group = {
	"rMENU_ESCAPE",
	"rMENU_UP",
	"rMENU_DOWN",
	"rMENU_LEFT",
	"rMENU_RIGHT",
	"rMENU_SELECT",
	"aCURSOR_X",
	"aCURSOR_Y"
};

-- is iterated until the player signals escape,
-- also, the pattern PLAYERN is also inserted, where N is the
-- current number of the player 
keyconf_current.player_group = {
	"rUP",
	"rDOWN",
	"rLEFT",
	"rRIGHT",
	"rSTART",
    "rCOIN1",
    " COIN2",
    " BUTTON1",
    " BUTTON2",
    " BUTTON3",
    " BUTTON4",
    " BUTTON5",
    " BUTTON6"
};

function keyconf_renderline(string, size)
	if (keyconf_current.textvid) then 
		delete_image(keyconf_current.textvid);
		keyconf_current.textvid = nil;
	end

	if (size == nil) then
	    size = 18
	end

-- push to front, render text, resize window, align to current resolution 
	keyconf_current.textvid = render_text([[\ffonts/default.ttf,]] .. size .. " " .. string);
	keyconf_current.line = string;
	prop = image_surface_properties(keyconf_current.textvid);
	resize_image(keyconf_current.bgwindow, prop.width + 20, prop.height + 20, 0);
	move_image(keyconf_current.bgwindow, (VRESW - (prop.width + 20)) / 2, (VRESH - (prop.height + 20)) / 2, 0);
	prop = image_surface_properties(keyconf_current.bgwindow);
	move_image(keyconf_current.textvid, prop.x + 10, prop.y + 10, 0);
	order_image(keyconf_current.textvid, 254);
	order_image(keyconf_current.bgwindow, 253);
	show_image(keyconf_current.textvid);
	show_image(keyconf_current.bgwindow);
end


function keyconf_new(n_players, menugroup, playergroup)
	keyconf_current.bgwindow = fill_surface(32, 32, 0, 0, 254);
	if (menugroup ~= nil) then
	    keyconf_current.menu_group = menugroup;
	end
	
	if (playergroup ~= nil) then
	    keyconf_current.player_group = playergroup;
	end
	
	keyconf_current.used = {};
	keyconf_current.table = {};

	keyconf_renderline( [[\#ffffffWelcome to Arcan keyconfig!\r\nPlease press a button for MENU_ESCAPE (required)]], 18);
	keyconf_current.label = [[Please press a button for MENU_ESCAPE (required)]];

	keyconf_current.key = "MENU_ESCAPE";
	keyconf_current.key_kind = "r";

	keyconf_current.configlist = {}
	keyconf_current.ofs = 1;
	ofs = 1;

	for i=1,#keyconf_current.menu_group do
		keyconf_current.configlist[ofs] = keyconf_current.menu_group[i];
		ofs = ofs + 1;
	end
	
	if (n_players > 0) then
		for i=1,n_players do
            for j=1,#keyconf_current.player_group do
                kind = string.sub(keyconf_current.player_group[j], 1, 1);
				keyconf_current.configlist[ofs] = kind .. "PLAYER" .. i .. "_" .. string.sub(keyconf_current.player_group[j], 2);
				ofs = ofs + 1;
			end
		end
	end
	
end

-- query the user for the next input table
function keyconf_next_key()
    keyconf_current.ofs = keyconf_current.ofs + 1;

    if (keyconf_current.ofs <= # keyconf_current.configlist) then
 
        keyconf_current.key = keyconf_current.configlist[keyconf_current.ofs];
        keyconf_current.key_kind = string.sub(keyconf_current.key, 1, 1);
        keyconf_current.key = string.sub(keyconf_current.key, 2);

	local lbl;
	
        lbl = "(".. tostring(keyconf_current.ofs) .. " / " ..tostring(# keyconf_current.configlist) ..")";

	if (keyconf_current.key_kind == "A" or keyconf_current.key_kind == "r") then
	    lbl = "(required) ";
	else
	    lbl = "(optional) ";
	end

        if (keyconf_current.key_kind == "a" or keyconf_current.key_kind == "A") then
	    lbl = lbl .. [[ Please provide input along \ione \!iaxis on an analog device for:\n\r ]] .. keyconf_current.key .. [[\t 0 samples grabbed]];
            keyconf_current.analog_samples = {};
	else
	    lbl = lbl .. "Please press a button for " .. keyconf_current.key;
	end

	keyconf_current.label = lbl;
        keyconf_renderline( keyconf_current.label );

        return true;
    else
        return false;
    end
end

-- return the symstr that match inputtable, or nil.

function keyconf_match(input, label)
    if (input == nil or keyconf_current.table == nil) then 
        return nil;
    end

    if (type(input) == "table") then
        kv = keyconf_current.table[ keyconf_tbltoid(input) ];
    else
        kv = keyconf_current.table[ input ];
    end

    if label ~= nil then
	if type(kv) == "table" then
	    for i=1, #kv do
		if kv[i] == label then 
		    return true;
		end
	    end
	    
	    return false;
	else
	    return kv == label;
	end
    end

-- need some patching for axis events (carry over the analog values) 
    return kv;
end

function keyconf_tbltoid(inputtable)
    if (inputtable.kind == "analog") then
	return "analog:" ..inputtable.devid .. ":" .. inputtable.subid;
    end
    
    if (inputtable.translated) then
	if keyconf_current.ignore_modifiers then
	    return "translated:" .. inputtable.devid .. ":" .. inputtable.keysym;
	else
	    return "translated:" .. inputtable.devid .. ":" .. inputtable.keysym .. ":" .. inputtable.modifiers;
	end
	
    else
	return "digital:" .. inputtable.devid .. ":" .. inputtable.subid;
    end
end

-- associate 
function keyconf_set(inputtable)

-- forward lookup: 1..n
    local id = keyconf_tbltoid(inputtable);
    if (keyconf_current.table[id] == nil) then
	keyconf_current.table[id] = {};
    end
    
    table.insert(keyconf_current.table[id], keyconf_current.key);

    keyconf_current.table[keyconf_current.key] = id;
end

function keyconf_analog(inputtable)
    -- find which axis that is active, sample 'n' numbers
    table.insert(keyconf_current.analog_samples, keyconf_tbltoid(inputtable));

    keyconf_current.label = "(".. tostring(keyconf_current.ofs) .. " / " ..tostring(# keyconf_current.configlist) ..")";
    keyconf_current.label = keyconf_current.label .. [[ Please provide input along \ione \!iaxis on an analog device for:\n\r ]] .. keyconf_current.key .. [[\t ]] .. tostring(# keyconf_current.analog_samples) .. " samples grabbed (100+ needed)";

    counttable = {}

    for i=1,#keyconf_current.analog_samples do
        val = counttable[ keyconf_current.analog_samples[i] ] or 0;
        counttable[ keyconf_current.analog_samples[i] ] = val + 1;
    end

    max = 1;
    maxkey = "not found";

    for key, value in pairs( counttable ) do
        if (value > max) then
           max = value;
           maxkey = key;
        end
    end

    keyconf_current.label = keyconf_current.label .. [[\n\r dominant device(:axis) is (]] .. maxkey .. ")";
    if ( #keyconf_current.analog_samples >= 100 and maxkey == keyconf_tbltoid(inputtable) ) then
        keyconf_set(inputtable);
        return keyconf_next_key();
    else
        keyconf_renderline( keyconf_current.label );
    end

    return true;
end

function keyconf_input(inputtable)
-- any key to configure?
    if (keyconf_current.key == nil) then
	return false;
    end
	
    key = nil;
	
    if ( (keyconf_current.key_kind == 'a' or keyconf_current.key_kind == 'A')
     and inputtable.kind == "analog") then
	key = keyconf_analog(inputtable);
        if (key == nil) then
            return true;
	else 
	    return key;
	end
    elseif (inputtable.kind == "digital" and inputtable.active == true) then
	key = inputtable;
    else
	return true;
    end

-- special treatement for the escape key, double- escape == abort
   if ( keyconf_match(key, "MENU_ESCAPE") ) then
        if (keyconf_current.key_kind == 'r' or keyconf_current.key_kind == "A") then
            keyconf_renderline( [[\#ff0000Cannot skip required keys/axes.\n\r\#ffffff]] .. keyconf_current.label );
        else
            return keyconf_next_key();
        end
    elseif ( keyconf_current.key_kind ~= 'a' and keyconf_current.key_kind ~= 'A' ) then 
	if ( keyconf_match(key) ~= nil ) then
	    print("Notice: Button (" .. keyconf_tbltoid(inputtable) .. ") already in use.\n");
	end

	keyconf_set( inputtable );
        return keyconf_next_key(); -- any more to insert?
    end
	
    return true;
end

function keyconf_flush()
    zap_resource("keysym.lua");
    open_rawresource("keysym.lua");
    if (write_rawresource("local keyconf = {};\n") == false) then
	print("Couldn't save keysym.lua, check diskspace and permissions in theme folder.\n");
	close_rawresource();
	return;
    end

    for key, value in pairs(keyconf_current.table) do
	if (type(value) == "table") then
	    write_rawresource( "keyconf[\"" .. key .. "\"] = {\"");
	    write_rawresource( table.concat(value, "\",\"") .. "\"};\n" );
	else
	    write_rawresource( "keyconf[\"" .. key .. "\"] = \"" .. value .. "\";\n" );
	end
    end

    write_rawresource("return keyconf;");
    close_rawresource();

    keyconf_cleanup();
end

function keyconf_running()
	-- returns true if there is a configure session running
	if (keyconf_current == nil) then
		return false;
	else
		return true;
	end
end

function keyconf_cleanup()
	if (keyconf_current) then
		delete_image(keyconf_current.textvid);
		delete_image(keyconf_current.bgwindow);
	end
end

-- set the current working table.
-- for each stored entry, set prefix if defined 
    
if ( resource("keysym.lua") ) then
    symfun = system_load("keysym.lua");
    keyconf_current.table = symfun();
end

keyconf_current.new = keyconf_new;
keyconf_current.match = keyconf_match;
keyconf_current.input = keyconf_input;
keyconf_current.cleanup = keyconf_cleanup;
keyconf_current.save = keyconf_flush;
keyconf_current.id = keyconf_tbltoid;
keyconf_current.ignore_modifiers = true;

return keyconf_current;
