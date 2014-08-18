--
-- This test is invoked from failover,
-- when the command is set to either explicitly
-- transfer or when a purposefully broken lua
-- statement is over, this script should be
-- executing.
--
function failadopt()
	print("failadopt running");
end

function failadopt_adopt(id, kind)
	print("adopting ", id);
	local props = image_surface_initial_properties(id);
	show_image(id);
	resize_image(id, props.width, props.height);
	move_image(id, math.random(VRESW * 0.5), math.random(VRESH * 0.5));
end

