function set3_2()

end

function set3_2_clock_pulse(tickv, tickc)
	if (math.fmod(tickv, 2)) then
		local col = color_surface(16 + math.random(64),
			16 + math.random(64),
			64 + math.random(191),
			64 + math.random(191),
			64 + math.random(191)
		);

		local props = image_surface_properties(col);

		show_image(col);
		move_image(col,
			math.random(VRESW - props.width),
			math.random(VRESH - props.height)
		);
		expire_image(col, math.random(10));
	end
end
