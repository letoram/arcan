--
-- Copyright 2014-2015, Björn Ståhl
-- License: 3-Clause BSD.
-- Reference: http://arcan-fe.com
--
-- all functions are prefixed with mouse_
--
-- setup (takes control of vid):
--  setup_native(vid, hs_x, hs_y) or
--  setup(vid, layer, pickdepth, cachepick, hidden)
--   layer : order value
--   pickdepth : number of stacked vids to check (typically 1)
--   cachepick : cache results to reduce picking calls
--   hidden : start in hidden state
--
-- input:
--  button_input(ind, active)
--  input(x, y, state, mask_all_events)
--  absinput(x, y)
--
-- output:
--  mouse_xy()
--
-- tuning:
--  autohide() - true or false ; call to flip state, returns new state
--  acceleration(x_scale_factor, y_scale_factor) ;
--  dblclickrate(rate or nil) opt:rate ; get or set rate
--
-- state change:
--  hide, show
--  add_cursor(label, vid, hs_dx, hs_dy)
--  constrain(min_x, min_y, max_x, max_y)
--  switch_cursor(label) ; switch active cursor to label
--
-- overlay selection:
--  select_begin(vid, handler, constrain{x1,y1,x2,y2})
--	select_end
--
-- use:
--  addlistener(tbl, {event1, event2, ...})
--   possible events: drag, drop, click, over, out
--    dblclick, rclick, press, release, motion
--
--   tbl- fields:
--    own (function, req, callback(tbl, vid)
--     return true/false for ownership of vid
--
--    + matching functions for set of events
--
--  droplistener(tbl)
--  tick(steps)
--   + input (above)
--
-- debug:
--  increase debuglevel > 2 and outputs activity
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
	button = {},
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
	dblclickstep = 12, -- maximum number of ticks between clicks for dblclick
	drag_delta   = 4,  -- wiggle-room for drag
	hover_ticks  = 30, -- time of inactive cursor before hover is triggered
	hover_thresh = 12, -- pixels movement before hover is released
	click_timeout= 14; -- maximum number of ticks before we won't emit click
	click_cnt    = 0,
	counter      = 0,
	hover_count  = 0,
	x_ofs        = 0,
	y_ofs        = 0,
	last_hover   = 0,
	dev = 0,
	x = 0,
	y = 0,
	min_x = 0,
	min_y = 0,
	max_x = VRESW,
	max_y = VRESH,
	hotspot_x = 0,
	hotspot_y = 0,
	scale_w = 1, -- scale factors for cursor drawing
	scale_h = 1,
};

local cursors = {
};

local function lock_constrain()
-- locking to surface is slightly odd in that we still need to return
-- valid relative motion which may or may not come from a relative source
-- and still handle constraints e.g. warp/clamp
	if (mstate.lockvid) then
		local props = image_surface_resolve_properties(mstate.lockvid);
		local ul_x = props.x;
		local ul_y = props.y;
		local lr_x = props.x + props.width;
		local lr_y = props.y + props.height;

		if (mstate.warp) then
			local cpx = math.floor(props.x + 0.5 * props.width);
			local cpy = math.floor(props.y + 0.5 * props.height);
			input_samplebase(mstate.dev, cpx, cpy);
			mstate.x = cpx;
			mstate.y = cpy;
		else
			mstate.x = mstate.x < ul_x and ul_x or mstate.x;
			mstate.y = mstate.y < ul_y and ul_y or mstate.y;
			mstate.x = mstate.x > lr_x and lr_x or mstate.x;
			mstate.y = mstate.y > lr_y and lr_y or mstate.y;
		end

-- when we always get absolute coordinates even with relative motion,
-- we need to track the spill and offset..
	local nx = mstate.x;
	local ny = mstate.y;
		mstate.rel_x = (mstate.rel_x + mstate.x) < ul_x
			and (mstate.x - ul_x) or mstate.rel_x;
		mstate.rel_x = mstate.rel_x + mstate.x > lr_x
			and lr_x - mstate.x or mstate.rel_x;
		mstate.rel_y = mstate.rel_y + mstate.y < ul_y
			and mstate.y - ul_y or mstate.rel_y;
		mstate.rel_y = mstate.rel_y + mstate.y > lr_y
			and lr_y - mstate.y or mstate.rel_y;

-- resolve properties is expensive so return the values in the hope that they
-- might be re-usable by some other part
		return ul_x, ul_y, lr_x, lr_y;
	end
end

local function mouse_cursorupd(x, y)
	x = x * mstate.accel_x;
	y = y * mstate.accel_y;

	lmx = mstate.x;
	lmy = mstate.y;

	mstate.x = mstate.x + x;
	mstate.y = mstate.y + y;

	mstate.x = mstate.x < 0 and 0 or mstate.x;
	mstate.y = mstate.y < 0 and 0 or mstate.y;
	mstate.x = mstate.x > mstate.max_x and mstate.max_x - 1 or mstate.x;
	mstate.y = mstate.y > mstate.max_y and mstate.max_y - 1 or mstate.y;
	mstate.hide_count = mstate.hide_base;

	local relx = mstate.x - lmx;
	local rely = mstate.y - lmy;

	lock_constrain();
	if (mstate.native) then
		move_cursor(mstate.x, mstate.y);
	else
		move_image(mstate.cursor, mstate.x + mstate.x_ofs,
			mstate.y + mstate.y_ofs);
	end

	return relx, rely;
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

local function def_reveal()
	for i=1,20 do
		local surf = color_surface(16, 16, 0, 255, 0);
		show_image(surf);
		local seed = math.random(80) - 40;
		order_image(surf, 65534);
		local intime = math.random(50);
		local mx, my = mouse_xy();
		move_image(surf, mx, my);
		nudge_image(surf, math.random(150) - 75,
			math.random(150) - 75, intime);
		expire_image(surf, intime);
		blend_image(surf, 0.0, intime);
	end
end

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

local function select_regupd()
	local x, y = mouse_xy();
	local x2 = mstate.in_select.x;
	local y2 = mstate.in_select.y;

	if (x > x2) then
		local tx = x;
		x = x2;
		x2 = tx;
	end

	if (y > y2) then
		local ty = y;
		y = y2;
		y2 = ty;
	end

	return x, y, x2, y2;
end

-- re-use cached results if the cursor hasn't moved and the logical clock
-- hasn't changed since last query, this cuts down on I/O storms from high-
-- res devices
local function cached_pick(xpos, ypos, depth, reverse)
	if (mouse_lastpick == nil or CLOCK > mouse_lastpick.tick or
		xpos ~= mouse_lastpick.x or ypos ~= mouse_lastpick.y) then
		local res = pick_items(xpos, ypos, depth, reverse, mstate.rt);

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

function mouse_toxy(x, y, time)
-- disable all event handlers and visibly move cursor to position
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
	mstate.drag_delta = 4;
	mstate.hover_ticks = 30;
	mstate.hover_thresh = 12;
	mstate.counter = 0;
	mstate.hover_count = 0;
	mstate.x_ofs = 0;
	mstate.y_ofs = 0;
	mstate.last_hover = 0;
	toggle_mouse_grab(MOUSE_GRABOFF);

	for k,v in pairs(cursors) do
		delete_image(v.vid);
	end
	cursors = {};

	if (valid_vid(mstate.cursor)) then
		delete_image(mstate.cursor);
		mstate.cursor = BADID;
	end
end

function mouse_setup(cvid, clayer, pickdepth, cachepick, hidden)
	mstate.hidden = false;
	mstate.x = math.floor(mstate.max_x * 0.5);
	mstate.y = math.floor(mstate.max_y * 0.5);

	mstate.cursor = null_surface(1, 1);
	image_mask_set(mstate.cursor, MASK_UNPICKABLE);
	mouse_add_cursor("default", cvid, 0, 0);
	mstate.rt = rt;
	mouse_switch_cursor();

	if (not hidden) then
		show_image(mstate.cursor);
	end

	move_image(mstate.cursor, mstate.x, mstate.y);
	local props = image_surface_properties(cvid);
	mstate.size = {props.width, props.height};

	mstate.pickdepth = pickdepth;
	order_image(mstate.cursor, clayer);
	image_mask_set(cvid, MASK_UNPICKABLE);
	if (cachepick) then
		mouse_pickfun = cached_pick;
	else
		mouse_pickfun = pick_items;
	end

	mouse_cursorupd(0, 0);
end

function mouse_setup_native(resimg, hs_x, hs_y)
	mstate.native = true;
	if (hs_x == nil) then
		hs_x = 0;
		hs_y = 0;
	end

-- wash out any other dangling properties in resimg
	local tmp = null_surface(1, 1);
	local props = image_surface_properties(resimg);
	image_sharestorage(resimg, tmp);
	delete_image(resimg);

	mouse_add_cursor("default", tmp, hs_x, hs_y);
	mouse_switch_cursor();

	mstate.x = math.floor(mstate.max_x * 0.5);
	mstate.y = math.floor(mstate.max_y * 0.5);
	mstate.pickdepth = 1;
	mouse_pickfun = cached_pick;

	resize_cursor(props.width, props.height);
	mstate.size = {props.width, props.height};

	mouse_cursorupd(0, 0);
end

--
-- Some devices just give absolute movements, convert
-- these to relative before moving on
--
function mouse_absinput(x, y, nofwd)
	local rx = x - mstate.x;
	local ry = y - mstate.y;
	local arx = mstate.accel_x * rx;
	local ary = mstate.accel_y * ry;

	mstate.rel_x = arx;
	mstate.rel_y = ary;

	mstate.x = x + (arx - rx);
	mstate.y = y + (ary - ry);

-- also need to constrain the relative coordinates when we clamp
	local ulx, uly, lrx, lry = lock_constrain();

	if (mstate.native) then
		move_cursor(mstate.x, mstate.y);
	else
		move_image(mstate.cursor, mstate.x + mstate.x_ofs,
			mstate.y + mstate.y_ofs);
	end

	if (not nofwd) then
		mouse_input(mstate.x, mstate.y, nil, true);
	end
end

--
-- ignore all mouse motion and possibly forward to specificed
-- funtion. will reset when valid_vid(vid) fails.
--
function mouse_lockto(vid, fun, warp, state)
	local olv = mstate.lockvid;
	local olf = mstate.lockfun;

	if (valid_vid(vid)) then
		mstate.lockvid = vid;
		mstate.lockfun = fun;
		mstate.lockstate = state;
		mstate.warp = warp ~= nil and warp or false;
	else
		mstate.lockvid = nil;
		mstate.lockfun = nil;
		mstate.lockstate = nil;
		mstate.warp = false;
	end

	return olv, olf;
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

	local hitc = 0;
	for key, val in pairs(mstate.drag.list) do
		local res = linear_find_vid(mstate.handlers.drag, val, "drag");
		if (res) then
			res:drag(val, x, y);
			hitc = hitc + 1;
		end
	end

	return hitc;
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
			local res = linear_find_vid(mstate.handlers.release, val, "release");
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

		mstate.counter = 0;
		mstate.predrag = nil;
		mstate.drag = nil;
	end
end

local function mouse_lockh(relx, rely)
	local x, y = mouse_xy();
-- safeguard from deletions that don't clean up after themselves
	if (not valid_vid(mstate.lockvid)) then
		mouse_lockto();
	elseif (mstate.lockfun) then
		mstate.lockfun(relx, rely, x, y, mstate.lockstate);
	end
end

local function mouse_btnlock(ind, active)
	local x, y = mouse_xy();
	if (not valid_vid(mstate.lockvid)) then
		mouse_lockto(nil, nil);
		if (mstate.lockfun) then
			mstate.lockfun(x, y, 0, 0, ind, active);
		end
	end
end

--
-- we kept mouse_input that supported both motion and
-- button update at once for backwards compatibility.
--
function mouse_button_input(ind, active)
	if (ind < 1 or ind > #mstate.btns) then
		return;
	end

	if (mstate.lockvid) then
		return mouse_btnlock(ind, active);
	end

	local hists = mouse_pickfun(
		mstate.x + mstate.hotspot_x,
		mstate.y + mstate.hotspot_y, mstate.pickdepth, 1, mstate.rt);

	if (DEBUGLEVEL > 2) then
		local res = {}
		print("button matches:");
		for i, v in ipairs(hists) do
			print("\t" .. tostring(v) .. ":" .. (image_tracetag(v) ~= nil
				and image_tracetag(v) or "unknown"));
		end
		print("\n");
	end

	if (#mstate.handlers.button > 0) then
		for key, val in pairs(hists) do
			local res = linear_find_vid(mstate.handlers.button, val, "button");
			if (res) then
				res:button(val, ind, active, mstate.x, mstate.y);
			end
		end
	end

	mstate.in_handler = true;
	if (ind == 1 and active ~= mstate.btns[1]) then
		lmbhandler(hists, active);
	end

	if (ind == 3 and active ~= mstate.btns[3]) then
		rmbhandler(hists, active);
	end

	mstate.in_handler = false;
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

function mouse_reveal_hook(state)
	if (type(state) == "function") then
		mstate.reveal_hook = state;
	elseif (state) then
		mstate.reveal_hook = def_reveal;
	else
		mstate.reveal_hook = nil;
	end
end

function mouse_input(x, y, state, noinp)
	if (not mstate.revmask and mstate.hidden and (x ~= 0 or y ~= 0)) then

		if (mstate.native == nil) then
			instant_image_transform(mstate.cursor);
			blend_image(mstate.cursor, 1.0, 10);
			mstate.hidden = false;
		end

		if (mstate.reveal_hook) then
			mstate.reveal_hook();
		end

	elseif (mstate.hidden) then
		return 0, 0;
	end

	if (noinp == nil or noinp == false) then
		x, y = mouse_cursorupd(x, y);
	else
		x = mstate.rel_x;
		y = mstate.rel_y;
	end

	if (mstate.lockvid or mstate.lockfun) then
		return mouse_lockh(x, y);
	end

	mstate.in_handler = true;
	mstate.hover_count = 0;

	if (not mstate.hover_ign and #mstate.hover_track > 0) then
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
		local hitc = mouse_drag(x, y);
		if (state ~= nil) then
			mbh(hists, state);
		end
		mstate.in_handler = false;
		if (hitc > 0) then
			return;
		end
	end

-- drop ones no longer selected, do out before over as many handlers will
-- do something that is overwritten by the following over event
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

	for i=1,#hists do
		if (linear_find(mstate.cur_over, hists[i]) == nil) then
			table.insert(mstate.cur_over, hists[i]);
			local res = linear_find_vid(mstate.handlers.over, hists[i], "over");
			if (res) then
				res:over(hists[i], mstate.x, mstate.y);
			end
		end
	end

	if (mstate.predrag) then
		x, y = mouse_xy();
		local dx = math.abs(mstate.press_x - x);
		local dy = math.abs(mstate.press_y - y);
		local dist = math.sqrt(dx * dx + dy * dy);

		if (dist >= mstate.predrag.count) then
			mstate.drag = mstate.predrag;
			mstate.predrag = nil;
			mouse_drag(x - mstate.press_x, y - mstate.press_y);
		end
	end

	if (state == nil) then
		mstate.in_handler = false;
		return;
	end

	mbh(hists, state);
	mstate.in_handler = false;
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

function mouse_handlercount()
	local cnt = 0;
	for ind, val in pairs(mstate.handlers) do
		cnt = cnt + #val;
	end
	return cnt;
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

function mouse_add_cursor(label, img, hs_x, hs_y)
	if (label == nil or type(label) ~= "string") then
		if (valid_vid(img)) then
			delete_image(img);
		end
		return warning("mouse_add_cursor(), missing label or wrong type");
	end

	if (cursors[label] ~= nil) then
		delete_image(cursors[label].vid);
	end

	if (not valid_vid(img)) then
		return warning(string.format(
			"mouse_add_cursor(%s), missing image", label));
	end

	local props = image_storage_properties(img);
	cursors[label] = {
		vid = img,
		hotspot_x = hs_x,
		hotspot_y = hs_y,
		width = props.width,
		height = props.height
	};
end

function mouse_scale(factor)
	if (not mouse.prescale) then
		mouse.prescale = {
		};
	end
	cursor.accel_x = mouse.prescale.ax * factor;
	cursor.accel_y = mouse.prescale.ay * factor;
end

function mouse_cursor_sf(fx, fy)
	mstate.scale_w = fx and fx or 1.0;
	mstate.scale_h = fy and fy or 1.0;
	local new_w = mstate.size[1] * mstate.scale_w;
	local new_h = mstate.size[2] * mstate.scale_h;

	if (mstate.native) then
		resize_cursor(new_w, new_h);
	else
		resize_image(mstate.cursor, new_w, new_h);
	end
end

-- assumed: .vid(valid), .hotspot_x, .hotspot_y
function mouse_custom_cursor(ct)
	if (mstate.native) then
		cursor_setstorage(ct.vid);
	else
		image_sharestorage(ct.vid, mstate.cursor);
	end
	mstate.size = {ct.width, ct.height};
	mouse_cursor_sf(mstate.scale_w, mstate.scale_h);

-- hotspot isn't scaled yet
	local hsdx = mstate.hotspot_x - ct.hotspot_x;
	local hsdy = mstate.hotspot_y - ct.hotspot_y;

-- offset current position (as that might've triggered the event that
-- incited the caller to switch cursor by the change in label

	mstate.x = mstate.x + hsdx;
	mstate.y = mstate.y + hsdy;
	mstate.hotspot_x = ct.hotspot_x;
	mstate.hotspot_y = ct.hotspot_y;
end

function mouse_switch_cursor(label)
	if (label == nil) then
		label = "default";
	end

	if (label == mstate.active_label) then
		return;
	end

	mstate.active_label = label;

	if (cursors[label] == nil) then
		if (mstate.native) then
			cursor_setstorage(WORLDID);
		else
			hide_image(mstate.cursor);
		end
		return;
	end

	local ct = cursors[label];
	mouse_custom_cursor(ct);
end

function mouse_hide()
	if (mstate.native) then
		mouse_switch_cursor(nil);
	else
		instant_image_transform(mstate.cursor);
		blend_image(mstate.cursor, 0.0, 20, INTERP_EXPOUT);
	end
end

function mouse_autohide()
	mstate.autohide = not mstate.autohide;
	return mstate.autohide;
end

function mouse_hidemask(st)
	mstate.revmask = st;
end

function mouse_show()
	if (mstate.native) then
		mouse_switch_cursor(mstate.active_label);
	else
		instant_image_transform(mstate.cursor);
		blend_image(mstate.cursor, 1.0, 20, INTERP_EXPOUT);
	end
end

function mouse_tick(val)
	mstate.counter = mstate.counter + val;
	mstate.hover_count = mstate.hover_count + 1;
	mstate.click_cnt = mstate.click_cnt > 0 and mstate.click_cnt - 1 or 0;

	if (not mstate.drag and mstate.autohide and mstate.hidden == false) then
		mstate.hide_count = mstate.hide_count - val;
		if (mstate.hide_count <= 0 and mstate.native == nil) then
			mstate.hidden = true;
			instant_image_transform(mstate.cursor);
			mstate.hide_count = mstate.hide_base;
			blend_image(mstate.cursor, 0.0, 20, INTERP_EXPOUT);
			return;
		end
	end

	mstate.in_handler = true;
	local hval = mstate.hover_ticks;

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
	mstate.in_handler = false;
end

function mouse_dblclickrate(newr)
	if (newr == nil) then
		return mstate.dblclickstep;
	else
		mstate.dblclickstep = newr;
	end
end

function mouse_querytarget(rt)
	if (rt == nil) then
		rt = WORLDID;
	end

	local props = image_surface_properties(rt);
	if (mstate.native) then
	else
		rendertarget_attach(rt, mstate.cursor, RENDERTARGET_DETACH);
	end
	mstate.max_x = props.width;
	mstate.max_y = props.height;
	if (mstate.rt ~= rt) then
		mstate.rt = rt;
		mouse_select_end();
	end
end

-- vid will be the object that will be promoted to cursor order
-- and used to indicate the selected region. it's drawing setup
-- should match the desired behavior (so for pattern region rather
-- than blended, one needs repeating etc.)
function mouse_select_begin(vid, constrain)
	if (not valid_vid(vid)) then
		return false;
	end

	if (mstate.in_select) then
		mouse_select_end();
	end

	mstate.in_select = {
		x = mstate.x,
		y = mstate.y,
		vid = vid,
		hidden = mstate.hidden,
		autodelete = {},
		lockvid = mstate.lockvid,
		lockfun = mstate.lockfun
	};

	mouse_show();
-- just save any old constrain- vid and create a new one that match
	if (constrain) then
		assert(constrain[4] - constrain[2] > 0);
		assert(constrain[3] - constrain[1] > 0);
		assert(constrain[1] >= 0 and constrain[2] >= 0);
		assert(constrain[3] <= mstate.max_x and constrain[4] <= mstate.max_y);
		local newlock = null_surface(
			constrain[3] - constrain[1],
			constrain[4] - constrain[2]);
		mstate.lockvid = newlock;
		move_image(newlock, constrain[1], constrain[2]);
		table.insert(mstate.in_select.autodelete, lockvid);
	end

-- set order
	link_image(vid, mstate.cursor);
	image_mask_clear(vid, MASK_POSITION);
	image_mask_set(vid, MASK_UNPICKABLE);
	image_inherit_order(vid, true);
	order_image(vid, -1);
	resize_image(vid, 1, 1);
	move_image(vid, mstate.x, mstate.y);
	table.insert(mstate.in_select.autodelete, vid);

-- normal constrain- handler will deal with clamping etc.
	mstate.lockvid = null_surface(MAX_SURFACEW, MAX_SURFACEH);
	mstate.lockfun = function()
		local x1, y1, x2, y2 = select_regupd();
		local w = x2 - x1;
		local h = y2 - y1;
		if (w <= 0 or h <= 0) then
			return;
		end
		move_image(vid, x1, y1);
		resize_image(vid, w, h);
	end

	return true;
end

function mouse_select_set(vid)
	if (not mstate.lockfun or not mstate.in_select) then
		return;
	end

	if (valid_vid(vid)) then
		local props = image_surface_resolve_properties(vid);
		mstate.x = props.x + props.width;
		mstate.y = props.y + props.height;
		mstate.in_select.x = props.x;
		mstate.in_select.y = props.y;
		mouse_cursorupd(0, 0);
		mstate.lockfun();
	else
		local mx, my = mouse_xy();
		mstate.in_select.x = mx;
		mstate.in_select.y = my;
		mouse_cursorupd(0, 0);
		mstate.lockfun();
	end
end

-- explicit end, handler will return region
function mouse_select_end(handler)
	if (not mstate.in_select) then
		return;
	end

	if (mstate.hidden) then
		mouse_hide();
	end

	delete_image(mstate.lockvid);
	mstate.lockfun = mstate.in_select.lockfun;
	mstate.lockvid = mstate.in_select.lockvid;

	for i,v in ipairs(mstate.in_select.autodelete) do
		delete_image(v);
	end

	if (handler) then
		handler(select_regupd());
	end

	mstate.in_select = nil;
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

