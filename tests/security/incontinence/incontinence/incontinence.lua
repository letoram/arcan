function incontinence()
	local vid = target_alloc("incontinence", target_con);
	feed = launch_avfeed("", "avfeed", nullh);
end

function nullh(source, status)
end

function target_con(source, status)
	if (status == nil or status.kind == "connected") then
		target_alloc("incontinence", target_con);

	elseif (status.kind == "terminated") then
		delete_image(source);
	end
end

function incontinence_clock_pulse()
	if (CLOCK % 100 == 0) then
		delete_image(feed);
		feed = launch_avfeed("", "avfeed", nullh);
	end
end
