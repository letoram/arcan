--
-- Testing CLOCKREQ events, to be coupled with the clockreq frameserver
--

local timers = {
};

function clockreq(args)
	warning("connect clockreq frameserver with clockreq connpath");
	warning("start with arg[1] to noauto to disable built-in handler");

	local vid = target_alloc("clockreq", function(source, status)
		if (status.kind == "clock") then
			if (status.once) then
				timers[source] = timers[source] and timers[source] or {};
				table.insert(timers[source], {
					id = status.id,
					left = status.value
				});
			end
			print("got clock event", status.dynamic, status.once, status.id, status.value);
		end
	end);

	if (args[1] and args[1] == "noauto") then
		target_flag(vid, TARGET_AUTOCLOCK, 0);
		warning("autoclock disabled");
	end
end

-- basic implementation for supporting timer clock requests
function clockreq_clock_pulse()
	for k,v in pairs(timers) do
		if (not valid_vid(k, TYPE_FRAMESERVER)) then
			timers[k] = nil;
		end

		local r = {};
		for i, j in ipairs(v) do
			j.left = j.left - 1;
			if (j.left <= 0) then
				stepframe_target(k, 1, j.id);
			else
				table.insert(r, j);
			end
		end
		timers[k] = r;
	end
end
