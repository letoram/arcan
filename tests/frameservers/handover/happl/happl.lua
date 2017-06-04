--
-- appl to go with handover frameserver test.
--
-- spawns a connection point ("handover") and waits for a subsegment request
-- (handover type), grants it, sends suspend to the old and shows the new.
--
function happl()
	target_alloc("handover",
		function(source, status)
			if (status.kind == "resized") then
				show_image(source);
				resize_image(source, status.width, status.height);
			elseif (status.kind == "segment_request") then
				if (status.segkind == "handover") then
					accept_target(happl_hover);
				else
					print("ignoring unsupported subsegment kind", status.kind);
				end
			else
				print("ignore", status.kind);
			end
		end
	);
end

function happl_hover(source, status)
	print("subsegment handler");
	for k,v in pairs(status) do print(k,v); end
	if (status.kind == "resized") then
		show_image(source);
		order_image(source, 10);
		resize_image(source, status.width, status.height);
	elseif (status.kind == "terminated") then
		delete_image(source);
	end
end
