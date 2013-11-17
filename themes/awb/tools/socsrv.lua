--
-- Networking features, for both client and server.
--

local function popup_chatwnd(btn)
		
end

local function popup_userlist(btn)
	
end

local function popup_browsewin(btn, dst)
end

local function serverwin_logmsg(wnd, msg)
	table.insert(wnd.messages, 
		string.format("%d : %s", CLOCK, string.gsub(msg, "\\", "\\\\")));

	if (#wnd.messages > 10) then
		table.remove(wnd.messages, 1);
	end

	if (valid_vid(wnd.message_vid)) then
		delete_image(wnd.message_vid);
	end

	local list = table.concat(wnd.messages, "\\n\\r");
	local vid, lines = desktoplbl(list);

	link_image(vid, wnd.canvas.vid);
	image_inherit_order(vid, true);
	image_clip_on(vid, CLIP_SHALLOW);
	show_image(vid);
end

local function add_serverbuttons(wnd, bar)

end

local function serverwin(wnd)
	if (wnd ~= nil) then 
		wnd:destroy();
	end

	local wnd = awbwman_spawn(
		menulbl(MESSAGE["TOOL_NETWORK_SERVER"]), 
		{refid = "network_server"}
	);
	wnd.messages = {};

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", cfg.ttactiveres, cfg.ttactiveres,
		wnd.dir.t.rsize, wnd.dir.t.bsize);

	wnd.log_message = serverwin_logmsg;
	wnd.srvid = net_listen(server_callback);

	if (wnd.srvid ~= BADID) then
		link_image(wnd.srvid, wnd.canvas.vid);
		image_clip_on(wnd.srvid, CLIP_SHALLOW);
		image_inherit_order(wnd.srvid, true);
		wnd:log_message("Server active.");
		add_serverbuttons(wnd, tt);
	else
		wnd:log_message("Couldn't spawn server session.");
	end
end

--
-- Starts out as just connect button and information caption
--
function spawn_socsrv()
	local wnd = awbwman_spawn(
		menulbl(MESSAGE["TOOL_NETWORK"]), {refid = "network"});

	local cfg = awbwman_cfg();
	local bar = wnd:add_bar("tt", cfg.ttactiveres, cfg.ttinactiveres,
		wnd.dir.t.rsize, wnd.dir.t.bsize);

	bar:add_icon("connectpop", "l", cfg.bordericns["settings"], function(self)
		local lbls = {
			MESSAGE["NET_BROWSE"],
			MESSAGE["NET_CONNECT"],
			MESSAGE["NET_DISCOVER"],
			MESSAGE["NET_LISTEN"],
		};

		local cbtbl = {
			function(self) popup_browsewin(wnd, ""); end,
			function(self) connectwin(wnd); end,
			function(self) popup_browsewin(wnd, ""); end,
			function(self) serverwin(wnd); end
		};

		local vid, lines = desktoplbl(table.concat(lbls, "\\n\\r"));
		awbwman_popup(vid, lines, cbtbl, {ref = self.vid}); 
	end);

	table.insert(wnd.handlers, bar);
	wnd.name = MESSAGE["TOOL_NETWORK"];
end

