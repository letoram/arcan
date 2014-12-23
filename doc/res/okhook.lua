local fun = _G[APPLID .. "_clock_pulse"]
local counter = 25

_G[APPLID .. "_clock_pulse"] = function()
	counter = counter - 1
	if (counter == 0) then
		return shutdown("");
	elseif fun ~= nil then
		fun()
	end
end
