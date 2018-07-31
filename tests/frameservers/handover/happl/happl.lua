--
-- appl to go with handover frameserver test.
--
-- spawns a connection point ("handover") and waits for a subsegment request
-- (handover type), grants it, sends suspend to the old and shows the new.
--
local off_w = 0;
function happl()
	parent = target_alloc("handover",
		function(source, status)
			if (status.kind == "resized") then
				show_image(source);
				resize_image(source, status.width, status.height);
				off_w = status.width;
			elseif (status.kind == "preroll") then
				target_displayhint(source, 64, 64);
			elseif (status.kind == "segment_request") then
				if (status.segkind == "handover") then
					accept_target(128, 128, happl_hover);
				else
					print("ignoring unsupported subsegment kind", status.kind);
				end
			elseif (status.kind == "terminated") then
				print("parent, terminated");
				delete_image(source);
			else
				print("ignore", status.kind);
			end
		end
	);
end

function happl_hover(source, status)
	print("subsegment handler");
	for k,v in pairs(status) do print("subsegment:", k,v); end
	if (status.kind == "resized") then
		show_image(source);
		order_image(source, 10);
		resize_image(source, status.width, status.height);
		move_image(source, off_w, 0);
		print("got frame", status.width, status.height);
		if (valid_vid(parent)) then
			delete_image(parent);
		end

	elseif (status.kind == "terminated") then
		delete_image(source);
	end
end
