--
-- Copyright 2014-2020, Björn Ståhl
-- License: 3-Clause BSD.
-- Reference: http://arcan-fe.com
--
-- All functions are prefixed with mouse_ and ignores devid. This means we
-- only support one global mouse cursor currently, though this should really be
-- factored out to have a version that takes an explicit context that replaces
-- calls to mstate. Such a revision should also drop the own function and the
-- corresponding finders for an 'own_vid' hash map.
--
-- setup (takes control of vid):
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
--  mouse_rawxy() : "raw" last coordinates, ignoring hotspot
--  mouse_cursorhook() : updated whenever the cursor changes shape or position
---
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
	rclick = {},

-- actually for touch events, but we want to piggyback on the rest of the
-- infrastructure as well, the other events can be emulated, but invisible
-- 'tap on a thing' is different
	tap = {},
};

MOUSE_LABELLUT = {
"left", "right", "middle", "wheel y+", "wheel y-", "wheel x+", "wheel -"
};

-- convention established mapping for forwarding to game/terminal/...
MOUSE_LBUTTON = 1;
MOUSE_RBUTTON = 2;
MOUSE_MBUTTON = 3;
MOUSE_WHEELPY = 4;
MOUSE_WHEELNY = 5;
MOUSE_WHEELPX = 6;
MOUSE_WHEELNX = 7;
MOUSE_AUXBTN  = 8; -- >= 8 really

local mstate = {
-- tables of event_handlers to check for match when
	handlers = mouse_handlers,
	blocked = false,
	btns = {},
	btns_clock = {},
	btns_bounce = {},
	btns_remap = {},
	cur_over = {},
	hover_track = {},
	active_list = {},
	fastmap = {},
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
	click_timeout = 14, -- maximum number of ticks before we won't emit click
	animation_speed = 20, -- used for cursor-tag and hide/reveal
	long_press   = "rclick", -- emit gesture on holding > click_timeout
	click_cnt    = 0,
	counter      = 0,
	hover_count  = 0,
	x_ofs        = 0,
	y_ofs        = 0,
	last_hover   = 0,
	dev = 0,
	x = 0,
	y = 0,
	rel_x = 0,
	rel_y = 0,
	min_x = 0,
	min_y = 0,
	inertia_x = 0,
	inertia_y = 0,
	inertia_acc_x = 0,
	inertia_acc_y = 0,
	max_x = VRESW,
	max_y = VRESH,
	hotspot_x = 0,
	hotspot_y = 0,
	scale_w = 1, -- scale factors for cursor drawing
	scale_h = 1,
	scale_i = true, -- force rounding to nearest integral factor
};

-- arbitrary "how many mouse buttons are there today", we just
-- waste a few k to fill the 8-bit spectrum + the possible axis remap
-- that the evdev platform does
local cursors = {
};

local linear_find_vid

for i=1,255 do
	mstate.btns_remap[i] = i;
	mstate.btns[i] = false;
	mstate.btns_clock[i] = CLOCK;
	mstate.btns_bounce[i] = 0;
end

mstate.btns_remap[256] = MOUSE_WHEELPY;
mstate.btns_remap[257] = MOUSE_WHEELNY;
mstate.btns_remap[258] = MOUSE_WHEELPX;
mstate.btns_remap[259] = MOUSE_WHEELNX;

function mouse_inertia(x, y)
	mstate.inertia_x = x;
	mstate.inertia_y = y;
	mstate.inertia_acc_x = 0;
	mstate.inertia_acc_y = 0;
end

local function mouse_cursor_draw(nofwd)
	local x, y = mouse_hotxy();
	move_image(mstate.cursor, x + mstate.x_ofs, y + mstate.y_ofs);

	if not nofwd and mstate.cursor_hook then
		for k,v in ipairs(mstate.cursor_hook) do
			v(mstate.cursor, x + mstate.x_ofs, y + mstate.y_ofs, mstate.active_label);
		end
	end
end

function mouse_cursorhook(newhook)
	if not mstate.cursor_hook then
		mstate.cursor_hook = {}
	end

	if table.remove_match(mstate.cursor_hook, newhook) then
		if #mstate.cursor_hook == 0 then
			mstate.cursor_hook = nil
		end
		return
	end

	table.insert(mstate.cursor_hook, newhook)
end

local function lock_constrain()
-- locking to surface is slightly odd in that we still need to return
-- valid relative motion which may or may not come from a relative source
-- and still handle constraints e.g. warp/clamp
	if (not valid_vid(mstate.lockvid)) then
		return;
	end

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

-- resolve properties is expensive so return the values in the hope that
-- they might be re-usable by some other part
	return ul_x, ul_y, lr_x, lr_y;
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
	mouse_cursor_draw();
	return relx, rely;
end

-- global event handlers for things like switching cursor on press
mstate.lmb_global_press = function()
	mstate.y_ofs = 2;
	mstate.x_ofs = 2;
	mouse_cursorupd(0, 0);
	mstate.lmb_pressed = true;
end

mstate.lmb_global_release = function()
	mstate.x_ofs = 0;
	mstate.y_ofs = 0;
	mouse_cursorupd(0, 0);
	mstate.lmb_pressed = false;

	local pr = mstate.pending_release
	if pr then
		mstate.pending_release = nil
		local res = linear_find_vid(mstate.handlers.release, pr, "release")
		if res then
			res:release(pr, mstate.x, mstate.y)
		end
	end
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
		move_image(surf, mstate.x, mstate.y);
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

linear_find_vid = function(table, vid, state)
-- we filter here as some scans (over, out, ...) may query state
-- for objects that no longer exists
	if (not valid_vid(vid)) then
		return;
	end

-- the 'fastmap' is a workaround for this script living long past the
-- 'rewrite/refactor/rethink' stage, it was never intended for hundreds
-- of objects, and most of the time the 'own' handler is actually static
	local fast = mstate.fastmap[vid]
	if fast then
		return fast[state] and fast or nil
	end

	for a,b in ipairs(table) do
		if (type(b.own) == "function") then
			if (b:own(vid, state)) then
				return b;
			end
		elseif b.own == vid then
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

function mouse_destroy()
	mouse_handlers = {
		click = {},
		drag = {},
		drop = {},
		over = {},
		out = {},
		motion = {},
		dblclick = {},
		rclick = {},
		tap = {}
	};

	mstate.handlers = mouse_handlers;
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

function mouse_load_theme(path, name)
-- safe-load that first uses configured set, fallback to default,
-- and fail-safe with a green box cursor
	local load_cursor;
	load_cursor =
	function(set, name, fname, hot_x, hot_y)
		local fn = string.format("%s/%s/%s", path, set, fname);
		local vid = load_image(fn);

		if not valid_vid(vid) then
			warning("cursor set broken, couldn't load " .. fn);
			vid = fill_surface(8, 8, 0, 255, 0);
			hot_x = 0
			hot_y = 0
		end

		mouse_add_cursor(name, vid, hot_x, hot_y)
		return vid;
	end

-- then load the real-set but allow broken scripts
	local fn = string.format("%s/%s/%s.lua", path, name, name);
	local set = system_load(fn, false);

	if type(set) == "function" then
		local ok, ret = pcall(set)
		if ok and type(ret) == "table" then
			for k, v in pairs(ret) do
				load_cursor(name, k, v[1], v[2], v[3])
			end
		else
			warning("bad cursor-set definition: " .. fn)
		end
	else
		warning("couldn't load cursor-set: " .. name)
	end
end

function mouse_setup(cvid, ...)
-- trick to migrate away from the old overcomplicated setup versus named options
	local a = {...}
	local opts =
	{
		pickdepth = 1,
		layer = 65535,
		cachepick = true,
		hidden = false
	}

	if type(a[1]) == "table" then
		for k,v in pairs(a[1]) do
			if type(opts[k]) == type(v) then
				opts[k] = v
			else
				warning("mouse_setup:unknown/mismatched key:" .. k)
			end
		end
	else
		opts.layer = type(a[2]) == "number" and a[2] or opts.layer
		opts.pickdepth = type(a[3]) == "number" and a[3] or opts.pickdepth
		opts.cachepick = type(a[4]) == "boolean" and a[4] or opts.cachepick
		opts.hidden = type(a[5]) == "boolean" and a[5] or opts.hidden
	end

	mstate.hidden = opts.hidden;
	mstate.x = math.floor(mstate.max_x * 0.5);
	mstate.y = math.floor(mstate.max_y * 0.5);

	mstate.cursor = null_surface(1, 1);
	image_mask_set(mstate.cursor, MASK_UNPICKABLE);

	if not valid_vid(cvid) then
		cvid = fill_surface(32, 32, 0, 127, 0);
	end

	mouse_add_cursor("default", cvid, 0, 0);
	local props = image_surface_properties(cvid);
	mstate.size = {props.width, props.height};

	mstate.rt = rt;
	mouse_switch_cursor();

	if (not hidden) then
		show_image(mstate.cursor);
	end

	mouse_cursor_draw();
	mstate.pickdepth = opts.pickdepth;
	order_image(mstate.cursor, opts.layer);
	image_mask_set(mstate.cursor, MASK_UNPICKABLE);
	if (opts.cachepick) then
		mouse_pickfun = cached_pick;
	else
		mouse_pickfun = pick_items;
	end

	mouse_cursorupd(0, 0);

-- use default keynames and try to load from config store
	local set = {
		"accel_x",
		"accel_y",
		"dblclickstep",
		"drag_delta",
		"hover_ticks",
		"hover_thresh",
		"click_timeout",
		"animation_speed",
		"long_press",
	}

	for _, v in ipairs(set) do
		local key = get_key("mouse_" .. v)
		if key then
			local okt = type(mstate[v])
			if okt == "number" then
				local val = tonumber(okt)
				if val then
					mstate[v] = val
				end
			elseif okt == "string" then
				mstate[v] = key
			end
		end
	end
end

--
-- similar to absinput but try and block/mask event and hide/reveal triggers
--
function mouse_absinput_masked(x, y, nofwd)
	mouse_hidemask(true);
	mouse_absinput(x, y, nofwd);
	mouse_hidemask(false);
end

function mouse_warp(x, y, nofwd)
	mstate.x = x;
	mstate.y = y;
	mstate.press_x = x;
	mstate.press_y = y;
	mouse_cursor_draw(nofwd);
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
	lock_constrain();
	mouse_cursor_draw(nofwd);

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
	local olw = mstate.warp;
	local ols = mstate.lockstate;

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

	return olv, olf, olw, ols;
end

function mouse_hotxy()
	return (mstate.x - mstate.hotspot_x * mstate.scale_w),
		(mstate.y - mstate.hotspot_y * mstate.scale_h);
end

function mouse_xy()
	return mstate.x, mstate.y;
end

function mouse_cursortag_drop(accept, state)
	if (mstate.cursortag) then
		mstate.cursortag.handler(mstate.cursortag.ref, accept, state);
		if (valid_vid(mstate.cursortag.vid)) then
			expire_image(mstate.cursortag.vid, mstate.animation_speed);
			local lb, _, _ = reset_image_transform(mstate.cursortag.vid);
			blend_image(mstate.cursortag.vid,
				0.0, mstate.animation_speed - lb, INTERP_EXPOUT);
			delete_image(mstate.cursortag.vid);
		end
		mstate.cursortag = nil;
	end
end

-- primitive for drag and drop style behavior, tag the cursor with
-- a container and a vid that will be destroyed when the tag have been
-- provided as a 'drop'
function mouse_cursortag(ref, src, handler, vid)
	if (type(handler) ~= "function") then
		return;
	end

	mouse_cursortag_drop();

	if (not valid_vid(vid)) then
		return;
	end

	image_mask_set(vid, MASK_UNPICKABLE);
	link_image(vid, mstate.cursor, ANCHOR_LR);
	image_inherit_order(vid, true);
	order_image(vid, -1);
	local props = image_surface_properties(vid);

	mstate.cursortag = {
		src = src,
		vid = vid,
		ref = ref,
		handler = handler
	};
end

-- visually update the accept or no-accept state
function mouse_cursortag_state(accept)
	if not mstate.cursortag then
		return
	end

	if valid_vid(mstate.cursortag.vid) then
		local lb, _, _ = reset_image_transform(mstate.cursortag.vid);
		blend_image(mstate.cursortag.vid,
			accept and 0.5 or 1.0, mstate.animation_speed - lb);
	end

	mstate.cursortag.accept = accept
end

local function mouse_drag(x, y)
	local hitc = 0;
	for key, val in pairs(mstate.drag.list) do
		local res = linear_find_vid(mstate.handlers.drag, val, "drag");
		if (res) then
			res:drag(val, x, y, mstate.drag.id);
			hitc = hitc + 1;
		end
	end

	return hitc;
end

local function bhandler(hists, press, id)
	if (press) then
		if id ~= MOUSE_RBUTTON or mstate.rdrag then
			mstate.press_x = mstate.x;
			mstate.press_y = mstate.y;
			mstate.predrag = {
				list = hists,
				count = mstate.drag_delta,
				id = id
			};
		end
		mstate.click_cnt = mstate.click_timeout;

		mstate.lmb_global_press();

		for key, val in ipairs(hists) do
			local res = linear_find_vid(mstate.handlers.press, val, "press");
			if (res) then
-- we need to track this so some event handler isn't stuck waiting for a release
-- this is flushed if we enter a drag state, but since that is thresholded it is
-- possible to press -> move to other vid -> release -> no release sent
				mstate.pending_release = val
				if (res:press(val, mstate.x, mstate.y)) then
					break;
				end
			end
		end

	else -- release
		if val == mstate.pending_release then
			mstate.pending_release = nil
		end
		mstate.lmb_global_release();
		for key, val in ipairs(hists) do
			local res = linear_find_vid(mstate.handlers.release, val, "release");
			if (res) then
				if (res:release(val, mstate.x, mstate.y)) then
					break;
				end
			end
		end

		if (mstate.drag) then -- already dragging, check if dropped
			for key, val in pairs(mstate.drag.list) do
				local res = linear_find_vid(mstate.handlers.drop, val, "drop");
				if (res) then
					if (res:drop(val, mstate.x, mstate.y, mstate.cursor_tag)) then
						return;
					end
				end
			end
-- only click if we havn't started dragging or the button was released quickly
		else
			if (mstate.click_cnt > 0) then
				for key, val in ipairs(hists) do
					local res = linear_find_vid(
						mstate.handlers.click, val,
						id == MOUSE_RBUTTON and "rclick" or "click");
					if (res) then
						if (res:click(val, mstate.x, mstate.y)) then
							break;
						end
					end
				end
			end

-- double click is based on the number of ticks since the last click
			if (mstate.counter > 0 and mstate.counter <= mstate.dblclickstep) then
				for key, val in ipairs(hists) do
					local res = linear_find_vid(mstate.handlers.dblclick, val,"dblclick");
					if (res) then
						if (res:dblclick(val, mstate.x, mstate.y, id)) then
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
-- safeguard from deletions that don't clean up after themselves
	if (not valid_vid(mstate.lockvid)) then
		mouse_lockto();
	elseif (mstate.lockfun) then
		local x, y = mouse_xy();
		mstate.lockfun(relx, rely, x, y, mstate.lockstate);
	end
end

local function mouse_btnlock(ind, active)
	local x, y = mouse_xy();
	if (not valid_vid(mstate.lockvid)) then
		mouse_lockto(nil, nil);
	elseif (mstate.lockfun) then
			mstate.lockfun(0, 0, x, y, mstate.lockstate, ind, active);
	end
end

--
-- we kept mouse_input that supported both motion and
-- button update at once for backwards compatibility.
--
function mouse_button_input(ind, active)
	ind = mstate.btns_remap[ind];
	if (not ind or mstate.btns[ind] == active) then
		return;
	end

-- reject on debounce protection
	if (active and mstate.btns_bounce[ind] > 0 and
		CLOCK - mstate.btns_clock[ind] < mstate.btns_bounce[ind]) then
		return;
	end

-- protect against shadow releases
	if (mstate.btns[ind] == active) then
		return;
	end

-- reset auto-hide counter/timer
	mstate.hide_count = mstate.hide_base;

	if (mstate.lockvid) then
		mstate.btns[ind] = active;
		mstate.btns_clock[ind] = CLOCK;
		return mouse_btnlock(ind, active);
	end

	local hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1, mstate.rt);

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
		for key, val in ipairs(hists) do
			local res = linear_find_vid(mstate.handlers.button, val, "button");
			if (res) then
				if (active) then
					if (not mstate.active_list[ind]) then
						mstate.active_list[ind] = {};
					end
					table.insert(mstate.active_list[ind], {res, val});
				elseif (mstate.active_list[ind]) then
					for i,v in ipairs(mstate.active_list[ind]) do
						if (v[2] == val) then
							table.remove(mstate.active_list[ind], i);
							break;
						end
					end
				end

-- uncertain, but possible that we should not emit the release event on surfaces
-- where we don't also have the 'press' event, most layers just ignore this
				res:button(val, ind, active, mstate.x, mstate.y);
			end
		end

-- make sure that the 'release' side of buttons gets sent to all sources that
-- received a 'press' even if they are not in the currently 'over' list.
		if (not active) then
			if (mstate.active_list[ind]) then
				for i,v in ipairs(mstate.active_list[ind]) do
					if (v[1].button) then
						v[1]:button(v[2], ind, false, mstate.x, mstate.y);
					end
				end
				mstate.active_list[ind] = {};
			end
		end
	end

	mstate.in_handler = true;
	if (ind == MOUSE_LBUTTON and active ~= mstate.btns[MOUSE_LBUTTON]) then
		bhandler(hists, active, MOUSE_LBUTTON);
	end

	if (ind == MOUSE_RBUTTON and active ~= mstate.btns[MOUSE_RBUTTON]) then
		bhandler(hists, active, MOUSE_RBUTTON);
	end

	mstate.btns[ind] = active;
	mstate.btns_clock[ind] = CLOCK;

	mstate.in_handler = false;
end

local function mbh(hists, state)
-- change in left mouse-button state?
	if (state[MOUSE_LBUTTON] ~= mstate.btns[MOUSE_LBUTTON]) then
		bhandler(hists, state[MOUSE_LBUTTON], MOUSE_LBUTTON);

	elseif (state[MOUSE_RBUTTON] ~= mstate.btns[MOUSE_RBUTTON]) then
		bhandler(hists, state[MOUSE_RBUTTON], MOUSE_RBUTTON);
	end

-- remember the button states for next time
	mstate.btns[MOUSE_LBUTTON] = state[MOUSE_LBUTTON];
	mstate.btns[MOUSE_MBUTTON] = state[MOUSE_MBUTTON];
	mstate.btns[MOUSE_RBUTTON] = state[MOUSE_RBUTTON];
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

function mouse_over(vid)
	for i,v in ipairs(mstate.cur_over) do
		if (v == vid) then
			return true;
		end
	end
end

local mid_c = 0;
local mid_v = {0, 0};

function mouse_iotbl_input(iotbl)
	if (not iotbl.mouse) then
		return false;
	end

	if (iotbl.digital) then
		mouse_button_input(iotbl.subid, iotbl.active);
		return true;
	end

	if (iotbl.relative) then
		if (iotbl.subid == 0) then
			mouse_input(iotbl.samples[1], 0);
		elseif (iotbl.subid == 1) then
			mouse_input(0, iotbl.samples[1]);
		elseif (iotbl.subid == 2) then
			mouse_input(iotbl.samples[1], iotbl.samples[3]);
		end
	else
		if iotbl.subid == 2 then
			mouse_absinput(iotbl.samples[1], iotbl.samples[3]);
		else
			mid_v[iotbl.subid+1] = iotbl.samples[1];
			mid_c = mid_c + 1;
			if (mid_c == 2) then
				mouse_absinput(mid_v[1], mid_v[2]);
				mid_c = 0;
			end
		end
	end

	return true;
end

if (API_VERSION_MAJOR == 0 and API_VERSION_MINOR < 11) then
mouse_iotbl_input = function(iotbl)
	if (iotbl.digital) then
		mouse_button_input(iotbl.subid, iotbl.active);
		return;
	end

	if (iotbl.relative) then
		if (iotbl.subid == 0) then
			mouse_input(iotbl.samples[2], 0);
		else
			mouse_input(0, iotbl.samples[1]);
		end
	else
		mid_v[iotbl.subid+1] = iotbl.samples[1];
		mid_c = mid_c + 1;
		if (mid_c == 2) then
			mouse_absinput(mid_v[1], mid_v[2]);
			mid_c = 0;
		end
	end
end
end

function mouse_input(x, y, state, noinp)
	if (type(x) == "table") then
		return mouse_iotbl_input(x)
	end

-- if inertia is set, we first need to overcome that before continuing
	if x ~= 0 or y ~= 0 then
		if mstate.inertia_x > 0 or mstate.inertia_y > 0 then
			mstate.inertia_acc_x = mstate.inertia_acc_x + x;
			mstate.inertia_acc_y = mstate.inertia_acc_y + y;
			if (math.abs(mstate.inertia_acc_x) > mstate.inertia_x and
				math.abs(mstate.inertia_acc_y) > mstate.inertia_y) then
				mstate.inertia_acc_x = 0;
				mstate.inertia_acc_y = 0;
			else
				return 0, 0;
			end
		end

-- hide/reveal
		if (not mstate.revmask and mstate.hidden) then
			instant_image_transform(mstate.cursor);
			blend_image(mstate.cursor, 1.0, 10);
			mstate.hidden = false;

			if (mstate.reveal_hook) then
				mstate.reveal_hook();
		end

		elseif (mstate.hidden) then
			return 0, 0;
		end
	end

-- no input applied, retrieve accumulators
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
				res:over(hists[i], mstate.x, mstate.y, mstate.cursortag);
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
			mstate.pending_release = nil;
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

local mouse_input_ref = mouse_input;
function mouse_block()
	mouse_input = function() end
	mstate.blocked = true;
	mouse_hide();
end

function mouse_unblock()
	mouse_input = mouse_input_ref;
	mstate.blocked = false;
	mouse_show();
end

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

	if (tbl.own == nil and not tbl.own_vid) then
		warning("mouse_addlistener(), missing own function in argument.\n");
		return;
	end

-- For use with the fastmap interface that has precedence - basically
-- 'own' was used to allow dynamically scoped lookup and activation of
-- sets of events. This made some sense when there was a low amount of
-- mouse handlers, but the pragmatic reality in something like durden
-- shows that the most common case is static and there is a high number of
-- them. To keep legacy until the day a mouse2.lua is written, support both.
	if tbl.own_vid then
		local mvid = tbl.own_vid

-- in order to not possibly break code that expects own to be there, create
-- a fake map to the cached static value
		tbl.own = function(ctx, vid)
			return vid == mvid
		end

		mstate.fastmap[mvid] = tbl
	end

-- previously it was permitted to register a table that lacked a user
-- readable identifier, so to spot code that still relies on that behavior,
-- write some warning
	if (tbl.name == nil) then
		warning(" -- mouse listener missing identifier -- ");
		warning( debug.traceback() );
		tbl.name = "__missing__";
	elseif (type(tbl.name) ~= "string") then
		warning(" -- mouse listener invalid field name type : " .. type(tbl.name));
		warning( debug.traceback() );
		tbl.name = "__broken__";
	end

	if (DEBUGLEVEL > 2) then
		warning(string.format("handler count: %d ", mouse_handlercount()));
	end

-- implicit list of events? then use the ones that has matching functions
-- in the table rather than a possible caller provided subset
	if not events then
		events = {}
		for k,_ in pairs(mouse_handlers) do
			if tbl[k] then
				table.insert(events, k)
			end
		end
	end

	for ind, val in ipairs(events) do
		if (mstate.handlers[val] ~= nil and
			linear_find(mstate.handlers[val], tbl) == nil and tbl[val] ~= nil) then
			insert_unique(mstate.handlers[val], tbl);
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

local function drop_match(intbl, match)
	for ind, val in ipairs(intbl) do
		if (val == match) then
			table.remove(intbl, ind);
			break;
		end
	end
end

function mouse_droplistener(tbl)
	for key, val in pairs( mstate.handlers ) do
		drop_match(val, tbl);
	end

	for i,v in pairs(mstate.active_list) do
		drop_match(v, tbl);
	end

	if tbl.own_vid then
		mstate.fastmap[tbl.own_vid] = nil
	end
end

function mouse_add_cursor(label, img, hs_x, hs_y, opts)
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
	opts = opts and opts or {};

	local props = image_storage_properties(img);
	cursors[label] = {
		vid = img,
		hotspot_x = hs_x,
		hotspot_y = hs_y,
		width = opts.width and opts.width or props.width,
		height = opts.height and opts.height or props.height,
		shader = opts.shader
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

function mouse_touch_at(x, y, kind)
	local forward = true

	kind = kind and kind or "tap";
	local hists = mouse_pickfun(x, y, mstate.pickdepth, 1);
	local taph = mstate.handlers.tap;
	for i=1,#hists do
		local res = linear_find_vid(taph, hists[i], "tap");
		if res then
			forward = res:tap(x, y, kind);
		end
	end

	return forward
end

function mouse_cursor_sf(fx, fy)
	mstate.scale_w = fx and fx or 1.0;
	mstate.scale_h = fy and fy or 1.0;
	if (mstate.scale_i) then
		local i, f = math.modf(mstate.scale_w);
		mstate.scale_w = (f > 0.5)
			and math.ceil(mstate.scale_w) or math.floor(mstate.scale_w);
		i, f = math.modf(mstate.scale_h);
		mstate.scale_h = (f > 0.5)
			and math.ceil(mstate.scale_h) or math.floor(mstate.scale_h);
		i, f = math.modf(mstate.scale_h);
	end

	local new_w = math.ceil(mstate.size[1] * mstate.scale_w);
	local new_h = math.ceil(mstate.size[2] * mstate.scale_h);

	if (valid_vid(mstate.cursor)) then
		resize_image(mstate.cursor, new_w, new_h);
	end
end

-- assumed: .vid(valid), .hotspot_x, .hotspot_y
function mouse_custom_cursor(ct)
	image_sharestorage(ct.vid, mstate.cursor);

	mstate.size = {ct.width, ct.height};
	mouse_cursor_sf(mstate.scale_w, mstate.scale_h);
	if (ct.shader) then
		image_shader(mstate.cursor, ct.shader);
	else
		image_shader(mstate.cursor, "DEFAULT");
	end

	mstate.hotspot_x = ct.hotspot_x;
	mstate.hotspot_y = ct.hotspot_y;
	mstate.active_label = "";
	mstate.custom_cursor = ct;

	mouse_cursor_draw();
end

function mouse_switch_cursor(label, force)
	if (label == nil) then
		label = "default";
	end

	if (label == mstate.active_label and not force) then
		return;
	end

	if (cursors[label] == nil) then
		hide_image(mstate.cursor);
		return;
	end

	local ct = cursors[label];
	mouse_custom_cursor(ct);
	mstate.active_label = label;
end

function mouse_cursors()
	return cursors;
end

function mouse_hide()
	instant_image_transform(mstate.cursor);
	blend_image(mstate.cursor, 0.0,
		mstate.revmask and 0 or 20, INTERP_EXPOUT);
end

function mouse_autohide(state)
	mstate.autohide = (state and state or not mstate.autohide);
	return mstate.autohide;
end

function mouse_hidemask(st)
	mstate.revmask = st;
end

function mouse_blocked()
	return mstate.blocked;
end

function mouse_show()
	if (mstate.blocked) then
		return;
	end

	instant_image_transform(mstate.cursor);
	blend_image(mstate.cursor, 1.0, 20, INTERP_EXPOUT);
end

system_load("builtin/debug.lua")()

function mouse_tick(val)
	mstate.counter = mstate.counter + val;
	mstate.hover_count = mstate.hover_count + 1;

-- let click time-out, and if we haven't started a drag, trigger long press
	if mstate.click_cnt > 0 then
		mstate.click_cnt = mstate.click_cnt - 1

		if mstate.click_cnt == 0 and mstate.lmb_pressed and not mstate.drag then
-- the two possible gestures both have the same function prototype
			local lpa = mstate.long_press

			if lpa == "rclick" or lpa == "dblclick" then
				local hists = mouse_pickfun(mstate.x, mstate.y, mstate.pickdepth, 1, mstate.rt);
				mstate.predrag = nil;

				for _, val in ipairs(hists) do
					local res = linear_find_vid(mstate.handlers[lpa], val, lpa);
					if res and res[lpa](res, val, mstate.x, mstate.y) then
						break;
					end
				end

			end
		end
	end

-- do we have auto-hide on idle?
	if (not mstate.drag and mstate.autohide and mstate.hidden == false) then
		mstate.hide_count = mstate.hide_count - val;
		if (mstate.hide_count <= 0) then
			mstate.hidden = true;
			instant_image_transform(mstate.cursor);
			mstate.hide_count = mstate.hide_base;
			blend_image(mstate.cursor, 0.0, mstate.animation_speed, INTERP_EXPOUT);
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
	rendertarget_attach(rt, mstate.cursor, RENDERTARGET_DETACH);
	if (mstate.cursortag and mstate.cursortag.vid) then
		rendertarget_attach(rt, mstate.cursortag.vid, RENDERTARGET_DETACH);
	end

	mstate.max_x = props.width;
	mstate.max_y = props.height;
	if (mstate.rt ~= rt) then
		mstate.rt = rt;
		mouse_select_end();
	end
end

-- needed when we temporary want to undo custom cursor and locked
-- target, but need to return to it shortly and don't trigger any of
-- the usual events
function mouse_state_save()
	mstate.save = {
		label = mstate.active_label,
		lockvid = mstate.lockvid,
		lockfun = mstate.lockfun,
		lockwarp = mstate.warp,
		lockstate = mstate.lockstate,
		active_label = mstate.active_label,
		custom_cursor = mstate.custom_cursor
	};
	mstate.save.x, mstate.save.y = mouse_xy();
	mouse_lockto();
	mstate.active_label = nil;
	mouse_switch_cursor("default");
end

function mouse_state_restore(warp)
	if (not mstate.save) then
		return;
	end
	local save = mstate.save;
	mstate.save = nil;

	if (valid_vid(save.lockvid)) then
		mouse_lockto(save.lockvid, save.lockfun, save.lockwarp, save.lockstate);
	end

	if (warp) then
		mouse_absinput_masked(save.x, save.y, true);
	end

	if (save.custom_cursor) then
		mouse_custom_cursor(save.custom_cursor);
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
		autohide = mstate.autohide,
		lockvid = mstate.lockvid,
		lockfun = mstate.lockfun
	};
	mstate.autohide = false;

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
		mstate.in_select.x = mstate.x;
		mstate.in_select.y = mstate.y;
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

	if (valid_vid(mstate.lockvid)) then
		delete_image(mstate.lockvid);
	end

	mstate.lockfun = mstate.in_select.lockfun;
	mstate.lockvid = mstate.in_select.lockvid;
	mstate.autohide = mstate.in_select.autohide;

	for i,v in ipairs(mstate.in_select.autodelete) do
		if (valid_vid(v)) then
			delete_image(v);
		end
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

