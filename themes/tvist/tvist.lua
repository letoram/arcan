--
-- TVIST - Script for video-feed subregion analysis
--

trigger_y = 0;

--
-- TODO:
-- a. loading / saving presets (could quite possibly just be set 
-- from commandline)
--
-- b. adding an option to start on the next frameserver_loop
-- (for easier synchronization)
--
-- c. option to click / manipulate the defined trigger regions;
-- set detector, filter function etc. to better tune outputs.
-- (use the mouse helper scripts)
--
-- d. video-source global pre-processing,
-- use something like the trails- scripts from AWB/gridle to 
-- delta- previous frames as input to the trigger regions
--
-- e. debug-plotting (a simulated go-run where you also
-- can tune / see the effects of the filter stages) 
-- and some in-script helper
--

--
-- The default shader for passive monitoring regions (e.g.
-- where we just want a simple 1/0 binary signal)
--
local passf = [[
	uniform sampler2D map_diffuse;
	varying vec2 texco;

	void main()
	{
		vec4 col = texture2D(map_diffuse, texco);
		float intens = (col.r + col.g + col.b) / 3;

		if (intens > 0.5)
			intens = 1.0;

		if (intens < 0.2)
			intens = 0.0;

		gl_FragColor = vec4(intens, intens, intens, 1.0);
	}
]];

function tvist()
	keysym = system_load("scripts/symtable.lua")();

	if (arguments[1] == nil or not resource(arguments[1])) then
		shutdown("Usage: arcan tvist moviename");
		return;
	end

	pass_filter = build_shader(nil, passf, "pass_filter");
	movieref = load_movie(arguments[1], FRAMESERVER_NOLOOP, video_trigger);
	target_verbose(movieref);

	triggers = {};

-- setup mouse cursor and place it at the middle of the screen
	local cursor = load_image("cursor.png");
	show_image(cursor);
	mx = VRESW * 0.5;
	my = VRESH * 0.5;
	mouse = null_surface(1,1);
	move_image(mouse, mx, my);
	link_image(cursor, mouse);
	show_image({mouse, cursor});
	move_image(cursor, -15, -15);	
	image_inherit_order(cursor, true);
end

function video_trigger(source, status)
	if (status.kind == "resized") then
		play_movie(source);
		resize_image(source, VRESW, VRESH);
		show_image(source);

	elseif (status.kind == "frame") then
		last_frame = status.number;
		last_pts = status.pts;
	end
end

function add_trigger_region(x1, y1, x2, y2, subtype)
	local props = image_surface_initial_properties(movieref);
	local newtrig = {};

	newtrig.vid = instance_image(movieref);
	newtrig.x1 = x1;
	newtrig.x2 = x2;
	newtrig.y1 = y1;
	newtrig.y2 = y2;
	newtrig.w  = x2 - x1;
	newtrig.h  = y2 - y1;
	newtrig.ind = #triggers; 

-- since we're operating on a window that's "zoomed" (for some 
-- extra free bilinear filtering and easier picking in low-res video)
-- we need to translate the sampled texture coordinates into the
-- relative coordinate space of the source material
	local scalefw = props.width / VRESW;
	local scalefh = props.height / VRESH;

	local neww = newtrig.w * scalefw;
	local newh = newtrig.h * scalefh;
	local newx = x1 * scalefw;
	local newy = y1 * scalefh;

	local s1 = newx / props.width;
	local t1 = newy / props.height;
	local s2 = (newx + neww) / props.width;
	local t2 = (newy + newh) / props.height;

	move_image(newtrig.vid, 0, trigger_y); 
	resize_image(newtrig.vid, x2 - x1, y2 - y1);
	show_image(newtrig.vid);
	image_set_txcos(newtrig.vid, {s1, t1, s2, t1, s2, t2, s1, t2});

	image_shader(newtrig.vid, pass_filter);

-- just add all trigger points in the first row
	trigger_y = trigger_y + (y2 - y1);
	table.insert(triggers, newtrig);
end

--
-- dynamic 2D region selector,
-- just feed with mouse input (step on click, move on motion)
-- manipulates to global namespace for 'mouse_recv'
--
function new_rect_pick(cbf, subtype)
	mouse_recv = { 
		step = function(self)
			if (self.x1 ~= nil) then
				cbf(self.x1, self.y1, mx, my);
				order_image(mouse, max_current_image_order() + 1);
				self:destroy();
			else
				self.x1 = mx;
				self.y1 = my;
				self.vid = fill_surface(1, 1, 0, 255, 0);
				blend_image(self.vid, 0.5);
				move_image(self.vid, self.x1, self.y1);
			end
		end,
		destroy = function(self)
			if (self.vid) then
				delete_image(self.vid);
			end
			mouse_recv = nil;
		end,
		move = function(self, newx, newy)
			if (self.x1 == nil) then
				return newx, newy;
			end

			if (newx < self.x1 + 1) then newx = self.x1 + 1; end
			if (newy < self.y1 + 1) then newy = self.y1 + 1; end

			if (self.vid) then
				resize_image(self.vid, newx - self.x1, newy - self.y1);	
			end

			return newx, newy;
		end
	};
end

function avg_trigfun(indata, threshold, tag)
	local sum = 0;
	local pxc = 0;

--
-- This is a painfully inefficient way of accessing,
-- the problem lies in how the datablock is pushed from C to LUA at
-- the moment, the only approach that doesn't require you to populate
-- a new table is through "userdata" which is code-wise quite complicated
-- to get right. To be able to do this real-time for advanced sources,
-- something else is needed, but for the analysis done here, it's "ok".
--
	for i=1,#indata,4 do
		local r = string.byte(indata, i);
		local g = string.byte(indata, i+1);
		local b = string.byte(indata, i+2);
		local a = string.byte(indata, i+3);

		sum = sum + (r + g + b) / 3;
		pxc = pxc + 1;
	end

	local avg = sum / pxc;

--
-- The video playback callback sets the globals last_framenumber, last_pts
-- the 'g' activation sets the start_framenumber
--
	if (avg > threshold) then
		print( string.format("%d:1:%d:%d", tag, last_pts,
			last_frame - start_framenumber));
	else
		print( string.format("%d:0:%d:%d", tag, last_pts,
			last_frame - start_framenumber));
	end
end

-- setup a calc-target for each trigger region
function activate_regions()
	start_framenumber = last_frame;

	for i, v in ipairs(triggers) do
		local newsrf = fill_surface(v.w, v.h, 0, 0, 0, v.w, v.h);

--
-- every tick (25Hz), read-back the contents of the region, run the avg_trigfun
-- (change to something of your liking depending on method of analysis)
--
		define_calctarget(newsrf, {v.vid}, 
			RENDERTARGET_NODETACH, RENDERTARGET_NOSCALE, 1, function(datablock)
				avg_trigfun(datablock, 128, tostring(v.ind)); 
		end);

		show_image(newsrf);
-- properties are not bound to rendertargets, so either instance
-- the source material and attach to the calctarget, or stack them.
		move_image(v.vid, 0, 0);
	end			

-- disable all UI elements, setup actual readbacks and filters then go
	tvist_input = function(iotbl)
		if (iotbl.kind == "digital" and iotbl.active) then
			if (keysym[iotbl.keysym] == "ESCAPE") then
				shutdown();

			elseif (keysym[iotbl.keysym] == "LCTRL") then
				toggle_mouse_grab();
			end
		end
	end
end

function tvist_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then

		if (iotbl.translated) then
			if (keysym[iotbl.keysym] == "p") then
				if (mouse_recv) then
					mouse_recv:destroy();
				end
				new_rect_pick(add_trigger_region, "binary");

			elseif (keysym[iotbl.keysym] == "g") then
				activate_regions();

			elseif (keysym[iotbl.keysym] == "LCTRL") then
				toggle_mouse_grab();

			elseif (keysym[iotbl.keysym] == "ESCAPE") then
				if (mouse_recv) then
					mouse_recv:destroy();
				else
					shutdown();
				end
			end

		elseif (iotbl.source == "mouse") then
			if (mouse_recv) then
				mouse_recv:step();
			end
		end

-- update cursor and clamp inside window constraints (+ possible
-- constraints from the current mouse target)
	elseif (iotbl.kind == "analog" and iotbl.source == "mouse") then
		if (iotbl.subid == 0) then
			mx = mx + iotbl.samples[2];
		else
			my = my + iotbl.samples[2];
		end
		
		if (mouse_recv) then
			mx, my = mouse_recv:move(mx, my);
		end

		if (mx < 0) then mx = 0; end
		if (my < 0) then my = 0; end
		if (mx > VRESW) then mx = VRESW; end
		if (my > VRESH) then my = VRESH; end
		
		move_image(mouse, mx, my);
	end
end
