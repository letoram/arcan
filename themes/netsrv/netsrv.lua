msglist = {};

function netev(source, status)
	if (status.kind == "frameserver_terminated") then
		add_msg("server died");
	else
		add_msg(status.kind);
	end
end

function netsrv()
	symtbl = system_load("scripts/symtable.lua")();
	local a = net_listen(netev);
	resize_image(a, math.floor(VRESW * 0.5), math.floor(VRESH * 0.5));
	move_image(a, 0, math.floor(VRESH * 0.5));
	show_image(a);
	server = a;	

	b = render_text([[\n\r\ffonts/default.ttf,14\bCommands:\!b\n\r
\ffonts/default.ttf,12\n\r
\b1..9\!b\t send message to client ind (n)\n\r
\bb\!b\t broadcast message to all\n\r
\n\r]]);
	add_msg("server running");
	show_image(b);
end

function add_msg(str)
	local renderstr = [[\ffonts/default.ttf,12\n\r]]
	table.insert(msglist, str);
	if (#msglist > 10) then table.remove(msglist, 1); end
	for i=1,#msglist do
		renderstr = renderstr .. msglist[i] .. [[\n\r]];
	end	
	
	if (valid_vid(msgtbl)) then
		delete_image(msgtbl);
	end
	
	renderstr = render_text(renderstr);
	move_image(renderstr, math.floor(VRESW * 0.5), 0);
	show_image(renderstr);
end

function netsrv_input(iotbl)
	if (iotbl.active and iotbl.kind == "digital" and iotbl.translated) then
		if (symtbl[iotbl.keysym]) then
			print(symtbl[iotbl.keysym]);
		end
	end
end

function netsrv_clock_pulse(tv)
	net_refresh(server);	
end

