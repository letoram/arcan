local function datashare(wnd)
	local res = awbwman_setup_cursortag(sysicons.floppy);
	res.kind = "media";
	res.source = wnd;
	return res;
end

local function inputlay_sel(wnd)
	local lst = inputed_configlist();
	local str = table.concat(lst, [[\n\r]]);
	local vid, lines = desktoplbl(str);
	
	awbwman_popup(vid, lines, function(ind)
		wnd.inp_cfg = inputed_getcfg(lst[ind]); 
	end);
end

--
-- Target window
-- Builds upon a spawned window (pwin) and returns a 
-- suitable callback for use in launch_target- style commands.
-- Assumes a bar already existing in the "tt" spot to add icons to.
--
function awbwnd_target(pwin)
	local loading = fill_surface(pwin.w, pwin.h, 100, 100, 100);
	local cfg = awbwman_cfg();

	pwin:update_canvas(loading, false);

	pwin.dir.tt:add_icon("r", cfg.bordericns["clone"], 
		function() datashare(pwin); 
	end);

	pwin.dir.tt:add_icon("l", cfg.bordericns["pause"], function(self) 
		if (pwin.paused) then
			pwin.paused = nil;
			resume_target(pwin.canvas.vid);
			image_sharestorage(cfg.bordericns["pause"], self.vid);
		else
			pwin.paused = true;
			suspend_target(pwin.canvas.vid);
			image_sharestorage(cfg.bordericns["play"], self.vid);
		end
	end);

	pwin.dir.tt:add_icon("l", cfg.bordericns["input"],
		function() inputlay_sel(pwin); end);

	pwin.input = function(self, iotbl)
		local restbl = inputed_translate(iotbl, pwin.inp_cfg);

		if (restbl) then 
			for i,v in ipairs(restbl) do
				target_input(pwin.canvas.vid, v);
			end
		else -- hope that the hijacked target can do something with it anyway
			target_input(pwin.canvas.vid, iotbl);
		end
	end

-- add_icon play/pause
-- add_icon filter
-- add_icon fast-forward
-- add_icon save(slot) 

	local callback = function(source, status)
		if (status.kind == "frameserver_terminated") then
			pwin:update_canvas( 
				fill_surface(pwin.w, pwin.h, 100, 100, 100), false);

		elseif (status.kind == "loading") then
			print("show loading info..");
		elseif (status.kind == "resized") then
			pwin:update_canvas(source, false);
		end
	end

	pwin.click = function()
	end

	mouse_addlistener(pwin, {"click"});
	return callback;
end
