function gappl()
	listen();
end

function send_displays(source)
	local ramps = {};
	for i=0.1,1.0,0.1 do
		table.insert(ramps, i + 0.02);
		table.insert(ramps, i + 0.04);
		table.insert(ramps, i + 0.06);
	end

	local edid = {};
	for i=1,128 do
		table.insert(edid, i);
	end

	ramps.edid = edid;

	video_displaygamma(source, ramps);
end

function listen()
	target_alloc("gamma", function(source, status)
		print(status.kind);
		if (status.kind == "terminated") then
			delete_image(source);
		elseif (status.kind == "preroll") then
			print("enabled CM for source");
			target_flags(source, TARGET_ALLOWCM);
			listen();
		elseif (status.kind == "ramp_update") then
			print("new ramps from ", source, status.index);
			local ramp = video_displaygamma(source, status.index);
			if (ramp) then
				print("retrieved ramp, sending back");
				video_displaygamma(source, ramp)
			end
		elseif (status.kind == "proto_change") then
			if (status.cm) then
				send_displays(source);
			end
		elseif (status.kind == "resized") then
		end
	end);
end

function gappl_clock_pulse()
end
