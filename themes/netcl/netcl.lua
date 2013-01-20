--
-- Network- frameserver graphical tester
--
-- [ (Basic) Scenarios ] 
-- 1. Spawn server (light, localhost)
-- 2. Connect client (no discovery destination)
-- 3. Spawn server (psk / NaCL crypto)

-- 4. Spawn server (directory mode)
-- 5. Register server to directory

-- 6. Spawn server (NaCL mode)
-- 7. Connect client to discovery (directory OR broadcast)
--
-- 8. For each connected client, allow message push
-- 9. For each server session, allow message broadcast
--
-- 10. For each server, set to spam broadcast
-- 11. For each client, set to spam messages
-- 12. Spawn a client connection every tick
--
-- [ (advanced) Scenario ]
-- 1. Server sets to listen
--    Client (a) connects, Client (b) connects, Client (c) connects
--    Server launches internal, clients launches internal
--    Server broadcasts states
--    Client (a) (b) sends keypresses to server
--
-- 2. Server sets to listen
--    Client (a) launches internal, connects to server
--    Client (b) launches internal, connects to server
--    Server launches internal, sends seed states    
--    Client (a) applies seed state, Client (b) as well
--    (local playback on client a / b, streams keypresses and states)
--    Server swaps state between a and B
--

history = {};
function push_message(msg)
	table.insert(history, msg);

	if (#history > 10) then
		table.remove(history, 1);
	end

	delete_image(messagelist);
	messagelist = render_text([[\ffonts/default.ttf,12 ]] .. table.concat(history, "\\n\\r"));
	show_image(messagelist);
end


function netcl()
	if (#arguments > 0) then
		print("Disabling discovery mode, connecting directly.\n");
	end
	
	cli = net_open(argl, function(source, data)
		if (data.kind == "message") then
			push_message(data.message);
		else
			print("event:", data.kind);
		end
	end );

	messagelist = fill_surface(1, 1, 0, 0, 0);
	resize_image(cli, VRESW * 0.5, 0);
	move_image(cli, VRESW * 0.5, 0);
	show_image(cli);
end

function netcl_clock_pulse(tv)
	net_refresh(cli);
end

function netcl_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then
		print("sending message");
		net_push(cli, "TESTING");
	end
end
