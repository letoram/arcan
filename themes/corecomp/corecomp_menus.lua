-- just hand plucked from gridle_menus, should really be generalized to a shared script some day ..

function menu_resetgcount(node)
	local node = current_menu;
	while (node.parent) do node = node.parent; end
	node.gamecount = -1;
end

function build_globmenu(globstr, cbfun, globmask)
	local lists = glob_resource(globstr, globmask);
	local resptr = {};
	
	for i = 1, #lists do
		resptr[ lists[i] ] = cbfun;
	end
	
	return lists, resptr;
end

-- for some menu items we just want to have a list of useful values
-- this little function builds a list of those numbers, with corresponding functions,
-- dispatch handling etc.
function gen_tbl_menu(name, tbl, triggerfun, isstring)
	local reslbl = {};
	local resptr = {};
	
	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = isstring and label or tonumber(label);
		if (save) then
			store_key(name, tonumber(label));
		else
		end
		
		if (triggerfun) then triggerfun(label); end
	end

	for key,val in ipairs(tbl) do
		table.insert(reslbl, val);
		resptr[val] = basename;
	end
	
	return reslbl, resptr;
end

function gen_num_menu(name, base, step, count, triggerfun)
	local reslbl = {};
	local resptr = {};
	local clbl = base;
	
	local basename = function(label, save)
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		settings[name] = tonumber(label);
		if (save) then
			store_key(name, tonumber(label));
		else
		end
		
		if (triggerfun) then triggerfun(); end
	end

	clbl = base;
	for i=1,count do
		if (type(step) == "function") then clbl = step(i); end

		table.insert(reslbl, tostring(clbl));
		resptr[tostring(clbl)] = basename;
		
		if (type(step) == "number") then clbl = clbl + step; end
	end

	return reslbl, resptr;
end

function add_submenu(dstlbls, dstptrs, label, key, lbls, ptrs)
	if (dstlbls == nil or dstptrs == nil or #lbls == 0) then return; end
	
	table.insert(dstlbls, label);
	
	dstptrs[label] = function()
		local fmts = {};
		local ind = tostring(settings[key]);
	
		if (ind) then
			fmts[ ind ] = settings.colourtable.notice_fontstr;
			if(get_key(key)) then
				fmts[ get_key(key) ] = settings.colourtable.alert_fontstr;
			end
		end
		
		menu_spawnmenu(lbls, ptrs, fmts);
	end
end

function menu_spawnmenu(list, listptr, fmtlist)
	if (#list < 1) then
		return nil;
	end

	local parent = current_menu;
	local props = image_surface_resolve_properties(current_menu.cursorvid);
	local windsize = VRESH;

	local yofs = 0;
	if (props.y + windsize > VRESH) then
		yofs = VRESH - windsize;
	end

	current_menu = listview_create(list, windsize, VRESW / 3, fmtlist);
	current_menu.parent = parent;
	current_menu.ptrs = listptr;
	current_menu.updatecb = parent.updatecb;
	current_menu:show();
	move_image( current_menu.anchor, props.x + props.width + 6, props.y);
	
	local xofs = 0;
	local yofs = 0;
	
-- figure out where the window is going to be.
	local aprops_l = image_surface_properties(current_menu.anchor, settings.fadedelay);
	local wprops_l = image_surface_properties(current_menu.window, settings.fadedelay);
	local dx = aprops_l.x;
	local dy = aprops_l.y;
	
	local winw = wprops_l.width;
	local winh = wprops_l.height;
	
	if (dx + winw > VRESW) then
		dx = dx + (VRESW - (dx + winw));
	end
	
	if (dy + winh > VRESH) then
		dy = dy + (VRESH - (dy + winh));
	end
	
	move_image( current_menu.anchor, dx, dy, settings.fadedelay );
	
	return current_menu;
end

function corecomp_defaultdispatch(exithook)
	if (not settings.iodispatch["MENU_UP"]) then
		settings.iodispatch["MENU_UP"] = function(iotbl) 
			current_menu:move_cursor(-1, true); 
		end
	end

	if (not settings.iodispatch["MENU_DOWN"]) then
			settings.iodispatch["MENU_DOWN"] = function(iotbl)
			current_menu:move_cursor(1, true); 
		end
	end
	
	if (not settings.iodispatch["MENU_SELECT"]) then
		settings.iodispatch["MENU_SELECT"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, false);
				if (current_menu and current_menu.updatecb) then
					current_menu.updatecb();
				end
			end
		end
	end
	
-- figure out if we should modify the settings table
	if (not settings.iodispatch["FLAG_FAVORITE"]) then
		settings.iodispatch["FLAG_FAVORITE"] = function(iotbl)
				selectlbl = current_menu:select();
				if (current_menu.ptrs[selectlbl]) then
					current_menu.ptrs[selectlbl](selectlbl, true);
					if (current_menu and current_menu.updatecb) then
						current_menu.updatecb();
					end
				end
			end
	end
	
	if (not (settings.iodispatch["MENU_ESCAPE"])) then
		settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();

		if (current_menu.parent ~= nil) then
			current_menu = current_menu.parent;
		else -- top level
			exithook();
		end
		end
	end
	
	if (not settings.iodispatch["MENU_RIGHT"]) then
		settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	end
	
	if (not settings.iodispatch["MENU_LEFT"]) then
		settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];
	end
end