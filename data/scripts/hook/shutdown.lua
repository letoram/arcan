local left = 500;

-- not present in older engine versions
if (appl_arguments) then

	for i,v in ipairs(appl_arguments()) do
		if string.sub(v, 1, 9) == "shutdown=" then
			local rem = string.sub(v, 10)
			local num = tonumber(rem)
			if num and num > 0 then
				left = num
			end
		end
	end
end

warning("shutdown in " .. tostring(left) .. " ticks")
local old_tick = _G[APPLID .. "_clock_pulse"]

_G[APPLID .. "_clock_pulse"] = function(...)
	if left > 0 then
		left = left - 1
	elseif left == 0 then
		return shutdown("autoshutdown.lua finished", EXIT_SUCCESS)
	elseif old_tick then
		old_tick(...)
	end
end
