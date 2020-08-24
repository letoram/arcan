--
-- No Copyright Claimed, Public Domain
-- See:
--  Trace(cb), Untrace() - toggle tracing to output cb(msg)
--  benchmark_setup() (destroys current context)
--  benchmark_create(min_samples, thresh, ramp, increment_function)
--
local function GetInfo(StackLvl, WithLineNum)
-- StackLvl is reckoned from the caller's level:
  StackLvl = StackLvl + 1
  local Ret
  local Info = debug.getinfo(StackLvl, "nlS")
  if Info then
    local Name, What, LineNum, ShortSrc =
    Info.name, Info.what, Info.currentline, Info.short_src
    if What == "tail" then
      Ret = "overwritten stack frame"
    else
      if not Name then
        if What == "main" then
          Name = "chunk"
        else
          Name = What .. "function"
        end
      end

      if Name == "C function" then
        Ret = Name
      else
        -- Only use real line numbers:
        LineNum = LineNum >= 1 and LineNum
        if WithLineNum and LineNum then
          Ret = Name .. " (" .. ShortSrc .. ", line " .. LineNum .. ")"
        else
          Ret = Name .. " (" .. ShortSrc .. ")"
        end
      end
    end
  else
    -- Below the bottom of the stack:
    Ret = "nowhere"
  end
  return Ret
end

-- Returns a string of N spaces:
local function Indent(N)
  return string.rep(" ", N)
end

-- The hook function set by Trace:
local function Hook(tracer, Event)
  -- Info for the running function being called or returned from:
  local Running = GetInfo(2)
  -- Info for the function that called that function:
  local Caller = GetInfo(3, true)
  if not string.find(Running..Caller, "modules") then
    if Event == "call" then
      Depth = Depth + 1
      tracer(string.format("%s %s <- %s\n", Indent(Depth), Running, Caller));
    else
      local RetType
      if Event == "return" then
        RetType = "returning from "
      elseif Event == "tail return" then
        RetType = "tail-returning from "
      end
--(uncomment to trace returns)      io.stderr:write(Indent(Depth), RetType, Running, " to ", Caller,"\n")
      Depth = Depth - 1
    end
  end
end

-- start tracing and send all data to stdout or provide a function scope to
-- trace and a report function to send the data to
function Trace(scope, reportfn)
	tracer = reportfn and reportfn or print;

	if type(scope) == "function" then
		Trace(nil, reportfn)
			scope()
		Untrace()
		return;
	end

  if not Depth then
    -- Before setting the hook, make an iterator that calls
    -- debug.getinfo repeatedly in search of the bottom of the stack:
    Depth = 1
    for Info in
      function()
      return debug.getinfo(Depth, "n")
      end
    do
      Depth = Depth + 1
    end

    -- Don't count the iterator itself or the empty frame counted at
    -- the end of the loop:
    Depth = Depth - 2
    debug.sethook(function(...) return Hook(tracer, ...) end, "cr")
  else
    -- Do nothing if Trace() is called twice.
  end
end

-- Unsets the hook function set by Trace:
function Untrace()
  debug.sethook()
  Depth = nil
end
--
-- Collection of debugging, benchmarking and performance helpers
--

-- Run benchmark_setup( argstr ) for a shared interface for setting
-- system-wide properties that affect benchmarking, e.g. canvas size,
-- number of objects limit etc.
--
-- Run benchmark_create(min_samples, threshold, rampup,
-- 	increment_function) => table
-- Note that multiple benchmark- invocations interfere with each-other
-- due to shared state in the benchmark_ class engine functions.
--
-- @min_samples: wait until we have @min_samples successful ticks
-- before checking against threshold.
--
-- @threshold: minimum number of average frames per second to continue.
--
-- @rampup: pre-invoke n increments before starting.
--
-- @increment_function: callback that will be used to increase the load,
-- should return a video object if those should be tracked and removed
-- when calling destroy.
--
-- Table Methods:
--    tick() - invoke at monotonic rates,
--             return true (pass) or false (fail)
--
--    destroy() - reset global states, delete possible list of vobjects
--
--    warning() - default stub, will be invoked if a long number of
--         increments have passed without a notable drop in framerate
--         signifying a compatibility / engine problem or that
--         the increment- function should be more aggressive.
--
-- repeat table:tick at monotonic rates until it fails
--
-- Table Properties:
--   rebench (default, false) -- reset internal benchmarking values
--                               between runs.

local function calc_avg(frames)
	local val = 0;
	local min = frames[1];
	local max = frames[1];

	for i = 1, #frames do
		val = val + frames[i];
		min = frames[i] < min and frames[i] or min;
		max = frames[i] > max and frames[i] or max;
	end

	local avg = val / #frames;
	val = 0;

	for i = 1, #frames do
		local dist = frames[i] - avg;
		val = val + (dist * dist);
	end

	local stddev = math.sqrt(val / #frames);

	return avg, min, max, stddev;
end

local function bench_tick(tbl)
	local tckcnt, ticks, framecnt, frames, costcnt, cost = benchmark_data();

	if (framecnt > tbl.min) then
		local avg, min, max, stddev = calc_avg(frames);
		avg = 1000.0 / avg;

		if (avg > tbl.thresh) then
			tbl.rep(tbl.count, min, max, avg, stddev);
			tbl.last_avg = avg;
			tbl.count = tbl.count + 1;

			if (tbl.rebench) then
				benchmark_enable(true);
			end

			local tot, free = current_context_usage();
			if ( (tot-free) <= 1) then
				tbl:warning();
				return false;
			else
				tbl:incr();
			end

			return true;
		else
			return false;
		end

	else
		return true;
	end
end

local function default_rep(count, min, max, avg, stddev)
	print(string.format("%d;%d;%d;%d;%d", count, min, max, avg, stddev));
end

local function bench_destr(tbl)
	for i=1,#tbl.list do
		if (valid_vid(tbl.list[i])) then
			delete_image(tbl.list[i]);
		end
	end

	tbl.list = {};
	tbl.tick = empty_fun;
	tbl.rep = empty_fun;
	tbl.incr = empty_fun;
	tbl.destroy = empty_fun;

	benchmark_enable(false);
end

function benchmark_setup( arguments )
	system_context_size(65535);
	pop_video_context();
	if (arguments == nil) then
		return;
	end
end

local function empty_warn(tbl)
	warning("limit reached during testing, values inconclusive.\n");
end

function benchmark_create(min_samples, threshold, ramp, increment_function)
	local res = {
		tick = bench_tick,
		rep = default_rep,
    incr = incr,
		min = min_samples,
		thresh = threshold,
		destroy = bench_destr,
		incr = increment_function,
		rebench = false,
		warning = empty_warn,
		count = 0,
		list = {}
	};

	for i=0,ramp,1 do
		res.count = res.count + 1;
		local img = increment_function();
		if (valid_vid(img)) then
			table.insert(res.list, img);
		end
	end

	benchmark_enable(true);

	return res;
end
