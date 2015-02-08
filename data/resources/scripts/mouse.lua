--
-- Copyright 2014, Björn Ståhl
-- License: 3-Clause BSD.
-- Reference: http://arcan-fe.com
--

--
-- Mouse- gesture / collision triggers
--
local mouse_handlers = {
	click = {},
	over  = {},
	out   = {},
  drag  = {},
	press = {},
	release = {},
	drop  = {},
	hover = {},
	motion = {},
	dblclick = {},
	rclick = {}
};

local mstate = {
-- tables of event_handlers to check for match when
	handlers = mouse_handlers,
	eventtrace = false,
	btns = {false, false, false, false, false},
	cur_over = {},
	hover_track = {},
	autohide = false,
	hide_base = 40,
	hide_count = 40,
	hidden = true,

-- mouse event is triggered
	accel_x      = 1,
	accel_y      = 1,
	dblclickstep = 12,  -- maximum number of ticks between clicks for dblclick
	drag_delta   = 8,  -- wiggle-room for drag
	hover_ticks  = 30, -- time of inactive cursor before hover is triggered
	hover_thresh = 12, -- pixels movement before hover is released
	click_timeout= 8;  -- maximum number of ticks before a press-release pair isn't a tick
	click_cnt    = 0,
	counter      = 0,
	hover_count  = 0,
	x_ofs        = 0,
	y_ofs        = 0,
	last_hover   = 0,
	x = 0,
	y  = 0
};

local function mouse_cursorupd(x, y)
	if (mstate.hidden and (x ~= 0 or y ~= 0)) then

		if (mstate.native == nil) then
			instant_image_transform(mstate.cursor);
			blend_image(mstate.cursor, 1.0, 10);
			mstate.hidden = false;
		end

	elseif (mstate.hidden) then
		return 0, 0;
	end

	x = x * mstate.accel_x;
	y = y * mstate.accel_y;

	lmx = mstate.x;
	lmy = mstate.y;

	mstate.x = mstate.x + x;
	mstate.y = mstate.y + y;

	mstate.x = mstate.x < 0 and 0 or mstate.x;
	mstate.y = mstate.y < 0 and 0 or mstate.y;
	mstate.x = mstate.x > VRESW and VRESW-1 or mstate.x;
	mstate.y = mstate.y > VRESH and VRESH-1 or mstate.y;
	mstate.hide_count = mstate.hide_base;

	if (mstate.native) then
		move_cursor(mstate.x, mstate.y);
	else
		move_image(mstate.cursor, mstate.x + mstate.x_ofs,
			mstate.y + mstate.y_ofs);
	end
	return (mstate.x - lmx), (mstate.y - lmy);
end

-- global event handlers for things like switching cursor on press
mstate.lmb_global_press = function()
		mstate.y_ofs = 2;
		mstate.x_ofs = 2;
		mouse_cursorupd(0, 0);
	end

mstate.lmb_global_release = function()
		mstate.x_ofs = 0;
		mstate.y_ofs = 0;
		mouse_cursorupd(0, 0);
	end

-- this can be overridden to cache previous queries
mouse_pickfun = pick_items;

local function linear_find(table, label)
	for a,b in pairs(table) do
		if (b == label) then return a end
	end

	return nil;
end

local function insert_unique(tbl, key)
	for key, val in ipairs(tbl) do
		if val == key then
			tbl[key] = val;
			return;
		end
	end

	table.insert(tbl, key);
end

local function linear_ifind(table, val)
	for i=1,#table do
		if (table[i] == val) then
			return true;
		end
	end

	return false;
end

local function linear_find_vid(table, vid, state)
-- we filter here as some scans (over, out, ...) may query state
-- for objects that no longer exists
	if (not valid_vid(vid)) then
		return;
	end

	for a,b in pairs(table) do
		if (b:own(vid, state)) then
			return b;
		end
	end
end

local function cached_pick(xpos, ypos, depth, nitems)
	if (mouse_lastpick == nil or CLOCK > mouse_lastpick.tick or
		xpos ~= mouse_lastpick.x or ypos ~= mouse_lastpick.y) then
		local res = pick_items(xpos, ypos, depth, nitems);

		mouse_lastpick = {
			tick = CLOCK,
			x = xpos,
			y = ypos,
			count = nitems,
			val = res
		};

		return res;
	else
		return mouse_lastpick.val;
	end
end

function mouse_cursor()
	return mstate.cursor;
end

function mouse_state()
	return mstate;
end

function mouse_destroy()
	mouse_handlers = {};
	mouse_handlers.click = {};
  mouse_handlers.drag  = {};
	mouse_handlers.drop  = {};
	mouse_handlers.over = {};
	mouse_handlers.out = {};
	mouse_handlers.motion = {};
	mouse_handlers.dblclick = {};
	mouse_handlers.rclick = {};
	mstate.handlers = mouse_handlers;
	mstate.eventtrace = false;
	mstate.btns = {false, false, false, false, false};
	mstate.cur_over = {};
	mstate.hover_track = {};
	mstate.autohide = false;
	mstate.hide_base = 40;
	mstate.hide_count = 40;
	mstate.hidden = true;
	mstate.accel_x = 1;
	mstate.accel_y = 1;
	mstate.dblclickstep = 6;
	mstate.drag_delta = 8;
	mstate.hover_ticks = 30;
	mstate.hover_thresh = 12;
	mstate.counter = 0;
	mstate.hover_count = 0;
	mstate.x_ofs = 0;
	mstate.y_ofs = 0;
	mstate.last_hover = 0;
	toggle_mouse_grab(MOUSE_GRABOFF);
	if (valid_vid(mstate.cursor)) then
		delete_image(mstate.cursor);
		mstate.cursor = BADID;
	end
end

--
-- Load / Prepare cursor, read default acceleration and
-- filtering settings.
-- cvid : video id of image to use as cursor (will take control of id)
-- clayer : which ordervalue for cursor to have
-- pickdepth : how many vids beneath cvid should be concidered?
-- cachepick : avoid unecessary
-- hidden : start in hidden state or not
--
function mouse_setup(cvid, clayer, pickdepth, cachepick, hidden)
	mstate.cursor = cvid;
	mstate.hidden = false;
	mstate.x = math.floor(VRESW * 0.5);
	mstate.y = math.floor(VRESH * 0.5);

	if (hidden ~= nil and hidden ~= true) then
	else
		show_image(cvid);
	end

	move_image(cvid, mstate.x, mstate.y);
	mstate.pickdepth = pickdepth;
	order_image(cvid, clayer);
	image_mask_set(cvid, MASK_UNPICKABLE);
	if (cachepick) then
		mouse_pickfun = cached_pick;
	else
		mouse_pickfun = pick_items;
	end

	mouse_cursorupd(0, 0);
end

function mouse_setup_native(resimg)
	local tmp = null_surface(1, 1);
	local props = image_surface_properties(resimg);

	image_sharestorage(resimg, tmp);
	cursor_setstorage(resimg);
	delete_image(resimg);
	mstate.cursor_vid = tmp;
	mstate.native = true;

	mstate.x = math.floor(VRESW * 0.5);
	mstate.y = math.floor(VRESH * 0.5);
	mstate.pickdepth = 1;
	mouse_pickfun = cached_pick;

	resize_cursor(props.width, props.height);

	mouse_cursorupd(0, 0);
end

--
-- Some devices just give absolute movements, convert
-- these to relative before moving on
--
function mouse_absinput(x, y)

	mstate.rel_x = x - mstate.x;
	mstate.rel_y = y - mstate.y;

	mstate.x = x;
	mstate.y = y;

	if (mstate.native) then
		move_cursor(mstate.x, mstate.y);
	else
		move_image(mstate.cursor, mstate.x + mstate.x_ofs,
			mstate.y + mstate.y_ofs);
	end

	mouse_input(x, y, nil, true);
end

function mouse_xy()
	if (mstate.native) then
		local x, y = cursor_position();
		return x, y;
	else
		local props = image_surface_resolve_properties(mstate.cursor);
		return props.x, props.y;
	end
end

local function mouse_drag(x, y)
	if (mstate.eventtrace) then
		warning(string.format("mouse_drag(%d, %d)", x, y));
	end

	for key, val in pairs(mstate.drag.list) do
		local res = linear_find_vid(mstate.handlers.drag, val, "drag");
		if (res) then
			res:drag(val, x, y);
		end
	end
end

local function rmbhandler(hists, press)
	if (press) then
		mstate.rpress_x = mstate.x;
		mstate.rpress_y = mstate.y;
	else
		if (mstate.eventtrace) then
			warning("right click");
		end

		for key, val in pairs(hists) do
			local res = linear_find_vid(mstate.handlers.rclick, val, "rclick");
			if (res) then
				res:rclick(val, mstate.x, mstate.y);
			end
		end
	end
end

local function lmbhandler(hists, press)
	if (press) then
		mstate.press_x = mstate.x;
		mstate.press_y = mstate.y;
		mstate.predrag = {};
		mstate.predrag.list = hists;
		mstate.predrag.count = mstate.drag_delta;
		mstate.click_cnt = mstate.click_timeout;
		mstate.lmb_global_press();

		for key, val in pairs(hists) do
			local res = linear_find_vid(mstate.handlers.press, val, "press");
			if (res) then
				if (res:press(val, mstate.x, mstate.y)) then
					break;
				end
			end
		end

	else -- release
		mstate.lmb_global_release();

		for key, val in pairs(hists) do
			local res = linear_find_vid(mstate.handlers.press, val, "release");
			if (res) then
				if (res:release(val, mstate.x, mstate.y)) then
					break;
				end
			end
		end

		if (mstate.eventtrace) then
			warning(string.format("left click: %s", table.concat(hists, ",")));
		end

		if (mstate.drag) then -- already dragging, check if dropped
			if (mstate.eventtrace) then
				warning("drag");
			end

			for key, val in pairs(mstate.drag.list) do
				local res = linear_find_vid(mstate.handlers.drop, val, "drop");
				if (res) then
					if (res:drop(val, mstate.x, mstate.y)) then
						return;
					end
				end
			end
-- only click if we havn't started dragging or the button was released quickly
		else
			if (mstate.click_cnt > 0) then
				for key, val in pairs(hists) do
					local res = linear_find_vid(mstate.handlers.click, val, "click");
					if (res) then
						if (res:click(val, mstate.x, mstate.y)) then
							break;
						end
					end
				end
			end

-- double click is based on the number of ticks since the last click
			if (mstate.counter > 0 and mstate.counter <= mstate.dblclickstep) then
				if (mstate.eventtrace) then
					warning("double click");
				end

				for key, val in pairs(hists) do
					local res = linear_find_vid(mstate.handlers.dblclick, val,"dblclick");
					if (res) then
						if (res:dblclick(val, mstate.x, mstate.y)) then
							break;
						end
					end
				end
			end
		end

		mstate.counter   = 0;
		mstate.predrag   = nil;
		mstate.drag      = nil;
	end
end

--
-- we kept mouse_input that supported both motion and
-- button update at once for backwards compatibility.
--
function mouse_button_input(ind, active)
	if (ind < 1 or ind > 3) then
		return;
	end

	local hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1);

	if (ind == 1 and active ~= mstate.btns[1]) then
		lmbhandler(hists, active);
	end

	if (ind == 3 and active ~= mstate.btns[3]) then
		rmbhandler(hists, active);
	end

	mstate.btns[ind] = active;
end

local function mbh(hists, state)
-- change in left mouse-button state?
	if (state[1] ~= mstate.btns[1]) then
		lmbhandler(hists, state[1]);

	elseif (state[3] ~= mstate.btns[3]) then
		rmbhandler(hists, state[3]);
	end

-- remember the button states for next time
	mstate.btns[1] = state[1];
	mstate.btns[2] = state[2];
	mstate.btns[3] = state[3];
end

function mouse_input(x, y, state, noinp)
	if (noinp == nil or noinp == false) then
		x, y = mouse_cursorupd(x, y);
	else
		x = mstate.rel_x;
		y = mstate.rel_y;
	end

	mstate.hover_count = 0;

	if (#mstate.hover_track > 0) then
		local dx = math.abs(mstate.hover_x - mstate.x);
		local dy = math.abs(mstate.hover_y - mstate.y);

		if (dx + dy > mstate.hover_thresh) then
			for i,v in ipairs(mstate.hover_track) do
				if (v.state.hover and
					v.state:hover(v.vid, mstate.x, mstate.y, false)) then
					break;
				end
			end

			mstate.hover_track = {};
			mstate.hover_x = nil;
			mstate.last_hover = CLOCK;
		end
	end

-- look for new mouse over objects
-- note that over/out do not filter drag/drop targets, that's up to the owner
	local hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1);

	if (mstate.drag) then
		mouse_drag(x, y);
		if (state ~= nil) then
			mbh(hists, state);
		end
		return;
	end

	for i=1,#hists do
		if (linear_find(mstate.cur_over, hists[i]) == nil) then
			table.insert(mstate.cur_over, hists[i]);
			local res = linear_find_vid(mstate.handlers.over, hists[i], "over");
			if (res) then
				res:over(hists[i], mstate.x, mstate.y);
			end
		end
	end

-- drop ones no longer selected
	for i=#mstate.cur_over,1,-1 do
		if (not linear_ifind(hists, mstate.cur_over[i])) then
			local res = linear_find_vid(mstate.handlers.out,mstate.cur_over[i],"out");
			if (res) then
				res:out(mstate.cur_over[i], mstate.x, mstate.y);
			end
			table.remove(mstate.cur_over, i);
		else
			local res = linear_find_vid(mstate.handlers.motion,
				mstate.cur_over[i], "motion");
			if (res) then
				res:motion(mstate.cur_over[i], mstate.x, mstate.y);
			end
		end
	end

	if (mstate.predrag) then
			mstate.predrag.count = mstate.predrag.count -
				(math.abs(x) + math.abs(y));

		if (mstate.predrag.count <= 0) then
			mstate.drag = mstate.predrag;
			mstate.predrag = nil;
		end
	end

	if (state == nil) then
		return;
	end

	mbh(hists, state);
end

mouse_motion = mouse_input;

--
-- triggers callbacks in tbl when desired events are triggered.
-- expected members of tbl;
-- own (function(vid)) true | tbl / false if tbl is considered
-- the owner of vid
--
function mouse_addlistener(tbl, events)
	if (tbl == nil) then
		warning("mouse_addlistener(), refusing to add empty table.\n");
		warning( debug.traceback() );
		return;
	end

	if (tbl.own == nil) then
		warning("mouse_addlistener(), missing own function in argument.\n");
	end

	if (tbl.name == nil) then
		warning(" -- mouse listener missing identifier -- ");
		warning( debug.traceback() );
	end

	for ind, val in ipairs(events) do
		if (mstate.handlers[val] ~= nil and
			linear_find(mstate.handlers[val], tbl) == nil and tbl[val] ~= nil) then
			insert_unique(mstate.handlers[val], tbl);
		elseif (tbl[val] ~= nil) then
			warning("mouse_addlistener(), unknown event function: "
				.. val ..".\n");
		end
	end
end

function mouse_dumphandlers()
	warning("mouse_dumphandlers()");

	for ind, val in pairs(mstate.handlers) do
		warning("\t" .. ind .. ":");
			for key, vtbl in ipairs(val) do
				warning("\t\t" ..
					(vtbl.name and vtbl.name or tostring(vtbl)));
			end
	end

	warning("/mouse_dumphandlers()");
end

--
-- Removes tbl from all callback tables
--
function mouse_droplistener(tbl)
	for key, val in pairs( mstate.handlers ) do
		for ind, vtbl in ipairs( val ) do
			if (tbl == vtbl) then
				table.remove(val, ind);
				break;
			end
		end
	end
end

function mouse_hide()
	if (mstate.native) then
		cursor_setstorage(WORLDID);
	else
		instant_image_transform(mstate.cursor);
		blend_image(mstate.cursor, 0.0, 20, INTERP_EXPOUT);
	end
end

function mouse_show()
	if (mstate.native) then
		cursor_setstorage(mstate.cursor_vid);
	else
		instant_image_transform(mstate.cursor);
		blend_image(mstate.cursor, 1.0, 20, INTERP_EXPOUT);
	end
end

function mouse_tick(val)
	mstate.counter = mstate.counter + val;
	mstate.hover_count = mstate.hover_count + 1;
	mstate.click_cnt = mstate.click_cnt > 0 and mstate.click_cnt - 1 or 0;

	if (mstate.autohide and mstate.hidden == false) then
		mstate.hide_count = mstate.hide_count - val;
		if (mstate.hide_count <= 0 and mstate.native == nil) then
			mstate.hidden = true;
			instant_image_transform(mstate.cursor);
			mstate.hide_count = mstate.hide_base;
			blend_image(mstate.cursor, 0.0, 20, INTERP_EXPOUT);
		end
	end

	local hval = mstate.hover_ticks;
	if (CLOCK - mstate.last_hover < 200) then
		hval = 2;
	end

	if (mstate.hover_count > hval) then
		if (hover_reset) then
			local hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1);
			for i=1,#hists do
				local res = linear_find_vid(mstate.handlers.hover, hists[i], "hover");
				if (res) then
					if (mstate.hover_x == nil) then
						mstate.hover_x = mstate.x;
						mstate.hover_y = mstate.y;
					end

					res:hover(hists[i], mstate.x, mstate.y, true);
					table.insert(mstate.hover_track, {state = res, vid = hists[i]});
				end
			end
		end

		hover_reset = false;
	else
		hover_reset = true;
	end
end

function mouse_dblclickrate(newr)
	if (newr == nil) then
		return mstate.dblclickstep;
	else
		mstate.dblclickstep = newr;
	end
end

function mouse_acceleration(newvx, newvy)
	if (newvx == nil) then
		return mstate.accel_x, mstate.accel_y;

	elseif (newvy == nil) then
		mstate.accel_x = math.abs(newvx);
		mstate.accel_y = math.abs(newvx);
	else
		mstate.accel_x = math.abs(newvx);
		mstate.accel_y = math.abs(newvy);
	end
end

