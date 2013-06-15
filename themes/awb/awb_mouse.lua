--
-- Mouse- gesture / collision triggers
--
local mouse_handlers = {
	click = {},
	over  = {},
	out   = {}, 
  drag  = {},
	drop  = {},
	dblclick = {},
	rclick = {}
};

local mstate = {
-- tables of event_handlers to check for match when
	handlers = mouse_handlers,
	btns = {false, false, false}, -- always LMB, MMB, RMB 
	cur_over = {},

-- mouse event is triggered
	accel        = 1, -- factor to x,y movements
	dblclickstep = 6, -- maximum number of ticks between clicks for dblclick 
	drag_dx      = 4, -- pixel-movement after click to begin drag     
	drag_dy      = 4,
	counter      = 0
};

local function linear_find(table, label)
	for a,b in pairs(table) do
		if (b == label) then return a end
	end

	return nil;  
end

local function linear_find_vid(table, vid)
	for a,b in pairs(table) do
		if (b.vid ~= nil and b.vid == vid) then
			return b;
		end
	end
end

local function mouse_cursorupd()
	local x = mstate.x < 0 and 0 or mstate.x;
	local y = mstate.y < 0 and 0 or mstate.y;
	
	mstate.x = mstate.x > VRESW and VRESW-1 or mstate.x; 
	mstate.y = mstate.y > VRESH and VRESH-1 or mstate.y; 
	
	move_image(mstate.cursor, mstate.x, mstate.y);
end

--
-- Load / Prepare cursor, read default acceleration and 
-- filtering settings.
-- cicon(string) : path to valid resource for cursor 
-- clayer(uint)  : which ordervalue for cursor to have
--
function mouse_setup(cvid, clayer)
	mstate.cursor = cvid; 
	mstate.x = math.floor(VRESW * 0.5);
	mstate.y = math.floor(VRESH * 0.5);
	order_image(cvid, clayer);
	image_mask_set(cvid, MASK_UNPICKABLE);
	print(cvid);
	mouse_cursorupd();
end

--
-- Some devices just give absolute movements, convert
-- these to relative before moving on
--
function mouse_absinput(x, y, state)
	mouse_input(
		mstate.x - x,
		mstate.y - y
	);
end

local function rmbhandler(hists, press)
	if (press) then
		mstate.rpress_x = mstate.x;
		mstate.rpress_y = mstate.y;
	else
		for key, val in pairs(hists) do
			local res = linear_find_vid(mstate.handlers.rclick, val);
			if (res) then
				res:rclick(mstate.x, mstate.y);
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
		mstate.predrag.x = mstate.drag_dx;
		mstate.predrag.y = mstate.drag_dy;

	else -- release
		if (mstate.drag) then -- already dragging, check if dropped
			for key, val in pairs(mstate.drag.list) do
				local res = linear_find_vid(mstate.handlers.drag, val);
				if (res) then
					res:drop(mstate.x, mstate.y);
				end
			end
-- only click if we havn't started dragging
		else
			for key, val in pairs(hists) do
				local res = linear_find_vid(mstate.handlers.click, val);
				if (res) then
					res:click(mstate.x, mstate.y);
				end
			end

-- double click is based on the number of ticks since the last click
			if (mstate.counter > 0 and mstate.counter <= mstate.dblclickstep) then
				for key, val in pairs(hists) do
					local res = linear_find_vid(mstate.handlers.dblclick, val);
					if (res) then
						res:dblclick(mstate.x, mstate.y);
					end
				end
			end
		end

		mstate.counter   = 0; 
		mstate.predrag   = nil;
		mstate.drag      = nil;	
	end 
end

function mouse_input(x, y, state)
	mstate.x = mstate.x + (x * mstate.accel);
	mstate.y = mstate.y + (y * mstate.accel);
	mouse_cursorupd();

-- look for new mouse over objects
-- not that over/out do not filter drag/drop targets, that's up to the owner
	local hists = pick_items(mstate.x, mstate.y, 100, 1);
	for i=1,#hists do
		if (linear_find(mstate.cur_over, hists[i]) == nil) then
			table.insert(mstate.cur_over, hists[i]);

			for key,val in pairs(mstate.handlers.over) do
				if (val.vid == hists[i]) then
					val:over(mstate.x, mstate.y);
				end
			end
		end
	end

-- drop ones no longer selected
	for i=#mstate.cur_over,1,-1 do
		vid = linear_find(hists, mstate.cur_over[i]);
		if (vid == nil) then
				for key, val in pairs(mstate.handlers.out) do
					if (val.vid == mstate.cur_over[i]) then
						val:out(mstate.x, mstate.y);
					end
				end
			table.remove(mstate.cur_over, i);
		end
	end

-- change in left mouse-button state?
	if (state[1] ~= mstate.btns[1]) then
		lmbhandler(hists, state[1]);
	elseif (state[3] ~= mstate.btns[3]) then
		rmbhandler(hists, state[3]);
	else 
-- otherwise we have motion, if we havn't exceeded predrag threshold,
-- start with that
		if (mstate.predrag) then
				mstate.predrag.x = mstate.predrag.x - math.abs(
					mstate.predrag.x - x);
				mstate.predrag.y = mstate.predrag.y - math.abs(
				mstate.predrag.y - y);

			if (mstate.predrag.x <= 0 and mstate.predrag.y <= 0) then
				mstate.drag = mstate.predrag;
				mstate.predrag = nil;
			end
		end
		
		if (mstate.drag) then
			for key, val in pairs(mstate.drag.list) do
				local res = linear_find_vid(mstate.handlers.drag, val);
				if (res) then
					res:drag(mstate.x, mstate.y);
				end
			end
		end
	end	

-- remember the button states for next time
	mstate.btns[1] = state[1];
	mstate.btns[2] = state[2];
	mstate.btns[3] = state[3];
end	

-- 
-- triggers callbacks in tbl when desired events are triggered.
-- expected members of tbl;
-- own (function(vid)) true | tbl / false if tbl is considered the owner of vid
-- 
function mouse_addlistener(tbl, events)
	if (tbl.own == nil) then
		warning("mouse_addlistener(), missing own function in argument.\n");
	end

	for ind, val in ipairs(events) do
		if (mstate.handlers[val] ~= nil and 
			linear_find(mstate.handlers[val], tbl) == nil) then
			table.insert(mstate.handlers[val], tbl);
		else
			warning("mouse_addlistener(), unknown event function: " .. val ..".\n");
		end
	end
end

--
-- Removes tbl from all callback tables
--
function mouse_droplistener(tbl)
	for ind, val in ipairs( mstate.handlers ) do
		for key, vtbl in pairs( val ) do
			if (tbl == vtbl) then 
				val[key] = nil;
				break;
			end
		end
	end
end

function mouse_tick(val)
	mstate.counter = mstate.counter + val;
end 	

function mouse_acceleration(newv)
	mstate.accel = math.abs(newv);
	-- save / store
end

