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
	order_image(vid, 2);
	image_clip_on(vid, CLIP_SHALLOW);
	image_mask_set(vid, MASK_UNPICKABLE);
	show_image(vid);
end

local function add_serverbuttons(wnd, bar)
-- toggle graphing
-- userlist
	local cfg = awbwman_cfg();
	bar:add_icon("graph", "l", cfg.bordericns["settings"], function(self)
		if (wnd.graphing) then
			wnd.graphing = nil;
			image_shader(self.vid, "DEFAULT");
			hide_image(wnd.srvid);
		else
			wnd.graphing = true;
			image_shader(self.vid, "awb_selected");
			show_image(wnd.srvid);
		end
		end);
	bar:add_icon("users", "l", cfg.bordericns["settings"], function(self)
		end);
end

local function server_callback(source, msg)
		
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
	wnd.clock_pulse = function(wnd, nt)
		if (wnd.graphing) then
			net_refresh(wnd.srvid);	
		end
	end

	if (wnd.srvid ~= BADID) then
		link_image(wnd.srvid, wnd.canvas.vid);
		image_clip_on(wnd.srvid, CLIP_SHALLOW);
		image_mask_set(wnd.srvid, MASK_UNPICKABLE);
		image_inherit_order(wnd.srvid, true);
		wnd:log_message("Server active.");
		add_serverbuttons(wnd, bar);
		order_image(wnd.srvid, 1);
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

local descrtbl = {
	name = "network",
	caption = "Network",
	icon = "network",
	trigger = spawn_socsrv
};

return descrtbl;
