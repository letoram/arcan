local time = 10;

if (appl_arguments) then

	for i,v in ipairs(appl_arguments()) do
		if string.sub(v, 1, 11) == "debugstall=" then
			local rem = string.sub(v, 12)
			local num = tonumber(rem)
			if num and num > 0 then
				left = num
			end
		end
	end

end

frameserver_debugstall(time);
warning("debugstall set to " .. tostring(time));
