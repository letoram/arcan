--
-- Simple test that runs for a bit and pushes random values to
-- each of the leds of a led device every 10 ticks
--
counter = 10;
local death = 500;
local leds = {};

function ledtest()

end

function ledtest_clock_pulse(src, status)
	death = death - 1;
	counter = counter - 1;
	if (death == 0) then
		return shutdown();
	end

	if (counter == 0) then
		local ctr = controller_leds(); -- rescan
		counter = 10;

-- update all known controllers
		for k,v in pairs(leds) do
			for i=1,v[2] do
				if (v[4]) then -- rgb
					set_led_rgb(v[1], i-1, math.random(255), math.random(255), math.random(255));
				elseif (v[3]) then
					led_intensity(v[1], i-1, math.random(255));
				else
					set_led(v[1], i-1, math.random(0, 1));
				end
			end
		end
	end
end

function ledtest_input(status)
	if (status.action == "added" and status.devkind == "led") then
		local nled, intens, rgb = controller_leds(status.devid);
		print("found led device", status.label,
			"rgb:", rgb, "intens:", intens, "nleds", nled);
		leds[status.devid] = {status.devid, nled, intens, rgb};
	elseif (status.action == "removed" and status.devkind == "led") then
		leds[status.devid] = nil;
		print("lost led device", status.devid);
	end
end
