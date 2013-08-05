--
-- Recorder Built-in Tool
-- Some regular configuration popups, e.g. resolution, framerate, 
-- and a drag-n-drop composition canvas
--

local function sweepcmp(vid, tbl)
	for k,v in ipairs(tbl) do
		if (v == vid) then
			return true;
		end
	end

	return false;
end


local function add_rectarget(wnd, tag)
	local tmpw, tmph = wnd.w * 0.2, wnd.h * 0.2;
	local source = {};

	source.data  = tag.source;
	source.dmode = nil;
	source.vid   = null_surface(tmpw, tmph);
	source.own   = function(self, vid) return vid == source.vid; end
	source.drag  = function(self, vid, dx, dy)

--
-- Add mouse handlers for moving / scaling, which one it'll be depends
-- on if the click point is closer to the center or the edge of the object
		if (source.dmode == nil) then
			local props = image_surface_properties(source.vid);
			source.start = props;
			local mx, my = mouse_xy();
			local rprops = image_surface_resolve_properties(source.vid);
			rprops.width = rprops.width * 0.5;
			rprops.height= rprops.height * 0.5;
			local cata  = math.abs(rprops.x + rprops.width - mx);
			local catb  = math.abs(rprops.y + rprops.height - my);
			local dist  = math.sqrt( cata * cata + catb * catb );
			local hhyp  = math.sqrt( rprops.width * rprops.width +
				rprops.height * rprops.height ) * 0.5;

			if (dist < hhyp) then
				source.dmode = "move";
			else
				source.dmode = "scale"; 
			end
		elseif (source.dmode == "move") then
			source.start.x = source.start.x + dx;
			source.start.y = source.start.y + dy;
			move_image(source.vid, source.start.x, source.start.y);

		elseif (source.dmode == "scale") then
			source.start.width  = source.start.width  + dx;
			source.start.height = source.start.height + dy;
			resize_image(source.vid, source.start.width, source.start.height);
		end
	end

-- update selected for wnd so 'del' input key works
	source.click = function(self, vid)
	end

	source.drop = function(self, vid)
		source.dmode = nil;
		source.start = nil;
	end

	image_sharestorage(tag.source.canvas.vid, source.vid);
	table.insert(wnd.sources, source);
	show_image(source.vid);
	image_inherit_order(source.vid, true);
	link_image(source.vid, wnd.canvas.vid);
	image_clip_on(source.vid);

	mouse_addlistener(source, {"click", "drag", "drop"});
	tag:drop();
end

local function change_selected(vid)
	print("change selected");
end

function spawn_vidrec()
	local wnd = awbwman_spawn(menulbl("Recorder"));
	wnd.sources = {};

	if (wnd == nil) then 
		return;
	end

-- add ttbar, icons for; 
-- resolution (popup, change vidres, preset values)
-- framerate
-- codec
-- vcodec
-- muxer
-- possibly name
-- start recording (purge all icons, close button stops.)
	wnd:update_canvas(fill_surface(32, 32, 60, 60, 60), false); 

	local mh = {
	own = function(self, vid)
		return vid == wnd.canvas.vid or sweepcmp(vid, wnd.sources); 
	end,

	over = function(self, vid)
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			tag:hint(true);
		end
	end,

	out = function(self, vid)
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			tag:hint(false);
		end
	end,

	click = function(self, vid)
		local tag = awbwman_cursortag();
		if (tag and tag.kind == "media") then
			add_rectarget(wnd, tag);
		else
			change_selected(vid);
		end
	end,
	}

	mouse_addlistener(mh, {"click", "over", "out"});
	mouse_droplistener(wnd);
	wnd.on_destroy = function()
		mouse_droplistener(mh);
	end
end
