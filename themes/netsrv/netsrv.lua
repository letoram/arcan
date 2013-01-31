msglist = {};
ticking = false;

function netev(source, status)
	print("event");
	if (status.kind == "frameserver_terminated") then
		add_msg("server died");
	elseif (status.kind == "message") then
		add_msg(tostring(status.connid) .. ":" .. string.gsub(status.message, "\\", "\\\\"));
	else
		add_msg("unknown:" .. status.kind);
	end
end

function netsrv_status()
	if (status_img ~= nil) then
		delete_image(status_img);
		status_img = nil;
	end
	
	msg = [[\n\r\ffonts/default.ttf,14\bCommands:\!b\n\r
	\ffonts/default.ttf,12\n\r
	\b1..9\!b\t send seq-message to client ind (n)\n\r
	\bb\!b\t broadcast message to all\n\r]]

	msg = msg .. ( ticking and [[\bt\!b\t stop broadcasting tick\n\r]] or [[\bt\!b\t start broadcasting tick\n\r]]);
	status_img = render_text(msg);
	show_image(status_img);
end

function netsrv()
	symtbl = system_load("scripts/symtable.lua")();
	local a = net_listen(netev);
	msgtbl = fill_surface(1, 1, 0, 0, 0);

	resize_image(a, math.floor(VRESW * 0.5), math.floor(VRESH * 0.5));
	move_image(a, 0, math.floor(VRESH * 0.5));
	show_image(a);
	server = a;
	seqn = 0;

	netsrv_status();
	add_msg("server running");
end

function add_msg(str)
	local renderstr = [[\ffonts/default.ttf,12\n\r]]
	table.insert(msglist, str);

	if (#msglist > 10) then table.remove(msglist, 1); end
	for i=1,#msglist do
		renderstr = renderstr .. string.gsub(msglist[i], "\\", "\\\\") .. [[\n\r]];
	end	
	
	delete_image(msgtbl);
	
	msgtbl = render_text(renderstr);
	move_image(msgtbl, math.floor(VRESW * 0.5), 0);
	show_image(msgtbl);
end

function seqmsg(num)
	local smsg = "SEQMSG:" .. tostring( seqn );
	seqn = seqn + 1;
	print("send to slot:", num);
	
	net_push_srv(server, smsg, num);
end

function netsrv_input(iotbl)
	if (iotbl.active and iotbl.kind == "digital" and iotbl.translated and symtbl[iotbl.keysym]) then
		if (symtbl[iotbl.keysym] == "b") then
			seqmsg(0);
			
		elseif (symtbl[iotbl.keysym] == "t") then
			ticking = not ticking;

		elseif (tonumber(symtbl[iotbl.keysym]) ) then
			seqmsg(tonumber(symtbl[iotbl.keysym]))
		else
		end
	end
end

function netsrv_clock_pulse(tv)
	net_refresh(server);

	if (ticking) then
		net_push_srv(server, "TICK:" .. tostring(tv));
	end

end
