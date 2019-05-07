local left = 500
local reset = 0
local seqn = 0
local prefix = "timed"

-- not present in older engine versions
if (appl_arguments) then
	for i,v in ipairs(appl_arguments()) do
		if string.sub(v, 1, 11) == "dump_timer=" then
			local rem = string.sub(v, 12)
			local num = tonumber(rem)
			if num and num > 0 then
				left = num
			end
		elseif string.sub(v, 1, 12) == "dump_period=" then
			local rem = string.sub(v, 13)
			local num = tonumber(rem)
			if num and num > 0 then
				reset = num
			end
		elseif string.sub(v, 1, 12) == "dump_prefix=" then
			local rem = string.sub(v, 13)
			if rem and #rem > 0 then
				prefix = rem
			end
		end
	end
end

local old_tick = _G[APPLID .. "_clock_pulse"]
if not old_tick then
	old_tick = function()
	end
end

_G[APPLID .. "_clock_pulse"] = function(...)
	if left > 0 then
		left = left - 1
		if left == 0 then
			local fname = string.format("%s%s.lua",
				prefix, seqn > 0 and "_" .. tostring(seqn) or "")
			zap_resource(fname)
			system_snapshot(fname)

-- we can't safely deregister after we are done with the snapshot due to the
-- whole 'battling chains' problem that we don't have a good fix other than
-- policy (i.e. not a fix) for, so retain and hope the JIT eventually figures
-- it out.
			left = reset
		end
	end

	old_tick(...)
end
