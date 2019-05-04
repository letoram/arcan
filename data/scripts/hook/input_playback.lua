--
-- No Copyright Claimed, Public Domain
--

--
-- This hook-script overrides user-provided input
-- with that of a preset recording.
--
-- create a derivative without the _G[ .. input] override
-- to permit user input.
--

local fname = APPLID .. ".irec";

if (open_rawresource(fname)) then
	local baseclock = 0;
	local iotable = {};

	local split = function(instr, delim)
		local res = {};
		local strt = 1;
		local delim_pos, delim_stp = string.find(instr, delim, strt);

		while delim_pos do
			table.insert(res, string.sub(instr, strt, delim_pos-1));
			strt = delim_stp + 1;
			delim_pos, delim_stp = string.find(instr, delim, strt);
		end

		table.insert(res, string.sub(instr, strt));
		return res;
	end

	local line = read_rawresource();

	while (line ~= nil) do
		local tbl = split(line, ":");
		local ntbl = {
			pulse = tonumber(tbl[1]),
			devid = tonumber(tbl[3]);
			subid = tonumber(tbl[4]);
		};

		if (tbl[2] == "mouse") then
			ntbl.kind = "analog";
			ntbl.mouse = true;
			ntbl.samples = {
				tonumber(tbl[5]),
				tonumber(tbl[6])
			};
		elseif (tbl[2] == "key") then
			ntbl.kind = "digital";
			ntbl.modifiers = tonumber(tbl[5]);
			ntbl.translated = true;
			ntbl.keysym = tonumber(tbl[6]);
			ntbl.active = tonumber(tbl[7]) == 1;

		elseif (tbl[2] == "btn") then
			ntbl.kind = "digital";
			ntbl.active = tonumber(tbl[5]) == 1;
		end

		table.insert(iotable, ntbl);
		line = read_rawresource();
	end

-- disable user input
	local ifun = _G[APPLID .. "_input"];
	local cp = _G[APPLID .. "_clock_pulse"];
	_G[APPLID .. "_input"] = nil;
	cp = cp ~= nil and cp or function() end;

	_G[APPLID .. "_clock_pulse"] = function(tick, step)
		if (baseclock == 0) then
			baseclock = CLOCK;
		end

		if (ifun == nil) then
			return cp(tick, step);
		end

		local ct = CLOCK - baseclock;

		while (iotable[1] ~= nil and iotable[1].pulse <= ct) do
			iotable[1].pulse = nil;
			ifun(iotable[1]);
			table.remove(iotable, 1);
		end

		return cp(tick, step);
	end
end
