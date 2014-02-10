--
-- TVIST - Script for video-feed subregion analysis
--

trigger_y = 0;
start_analyse = nil;

--
-- TODO:
--
-- a. option to click / manipulate the defined trigger regions;
-- set detector, filter function etc. to better tune outputs.
-- (use the mouse helper scripts)
--
-- b. convert the trails- part and add as a possible prefilter 
--
-- The default shader for passive monitoring regions 
--
-- Simple gating function to convert to a 2-bit source,
-- note that the conversion (r+g+b)/3 is a bad way of otherwise
-- working on 'luminance' and this goes for other parts of the 
-- tool as well. To better select regions and convert, 
-- consider switching to a model like:
-- Y = .2126 * R^gamma + .7152 * G^gamma + .0722 * B^gamma
-- L = 116 * Y^1/3 - 16
-- 
local passf = [[
	uniform sampler2D map_diffuse;
	uniform vec2 bounds;
	varying vec2 texco;

	void main()
	{
		vec4 col = texture2D(map_diffuse, texco);
		float intens = (col.r + col.g + col.b) / 3.0;

		if (intens > bounds.x)
			intens = 1.0;

		if (intens < bounds.y)
			intens = 0.0;

		gl_FragColor = vec4(intens, intens, intens, 1.0);
	}
]];

--
-- Edge detection pre-filter, 
-- need to have source dimensions string.format:ed inside
--
local edt = [[
uniform sampler2D map_diffuse;
varying vec2 texco;

float c2luma(vec3 inv)
{
	float y = 0.2126 * inv.r + 0.7152 * inv.g + 0.0722 * inv.b;
	return y; 
}

void main()
{
	float dx = 1.0 / %f; /* populate with width */ 
  float dy = 1.0 / %f; /* populate with height */
	float s = texco.s;
	float t = texco.t;

	float p[9];
  float delta;

/* populate buffer with neighbour samples,
 * assuming 8bit packed in RGBA texture */

	p[0] = c2luma(texture2D(map_diffuse, vec2(s - dx, t - dy)).rgb);
	p[1] = c2luma(texture2D(map_diffuse, vec2(s     , t - dy)).rgb);
	p[2] = c2luma(texture2D(map_diffuse, vec2(s + dx, t - dy)).rgb);
	p[3] = c2luma(texture2D(map_diffuse, vec2(s - dx, t     )).rgb);
	p[4] = c2luma(texture2D(map_diffuse, vec2(s     , t     )).rgb);
	p[5] = c2luma(texture2D(map_diffuse, vec2(s + dx, t     )).rgb);
	p[6] = c2luma(texture2D(map_diffuse, vec2(s - dx, t + dy)).rgb);
	p[7] = c2luma(texture2D(map_diffuse, vec2(s     , t + dy)).rgb);
	p[8] = c2luma(texture2D(map_diffuse, vec2(s + dx, t + dy)).rgb);

	delta = (abs(p[1]-p[7])+
           abs(p[5]-p[3])+
           abs(p[0]-p[8])+
           abs(p[2]-p[6]))/ 4.0;

	delta = clamp(delta, 0.0, 1.0);

	gl_FragColor = vec4( delta, delta, delta, 1.0 ); 
}
]];

prefilters = {
	edge = function(source, w, h)
		resize_image(source, w, h);
		local outp = fill_surface(w, h, 0, 0, 0, w, h);
		define_rendertarget(outp, {source}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
		image_shader(source, build_shader(nil, string.format(edt, w, h), "edge"));
		show_image({source, outp});
		return outp;
	end,
	gaussian = function(source, w, h)
	end,
	trails = function(source, w, h)
	end,
	normal = function(source, w, h)
		show_image(source);
		resize_image(source, w, h);
		return source;
	end
};

function string.split(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
        
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end

	table.insert(res, string.sub(instr, strt));
	return res;
end

function tvist()
	keysym = system_load("scripts/symtable.lua")();
	mouse = system_load("scripts/mouse.lua")();
	prefilter = "normal";

	if (arguments[1] == nil or not resource(arguments[1])) then
		shutdown("Usage: arcan tvist moviename [prefilt=fltname] " ..
			"[outcfg=fname] [run=fname]");
		return;
	end

	moviename = arguments[1];
	savecfg_name = nil;
	local cmdfile;

	for i=2,#arguments do
		local v = string.split(arguments[i], "=");
		local cmd = v[1] ~= nil and v[1] or "";
		local val = v[2] ~= nil and v[2] or "";
		
		if (cmd == "prefilt") then
			if (prefilters[val] ~= nil) then
				prefilter = val;
			else
				warning("unknown or missing prefilter, ignored.");
			end
		elseif (cmd == "outcfg") then
			savecfg_name = val;
		elseif (cmd == "run") then
			cmdfile = val;
		elseif (cmd == "src") then
			
		end
	end
	
	triggers = {};

	movieref = load_movie(arguments[1], FRAMESERVER_LOOP, video_trigger);
	target_verbose(movieref);
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
	order_image(mouse, 255);

	if (cmdfile ~= nil) then
		print(string.format("Using cfgfile=%s",cmdfile));
		system_load(cmdfile)();
		start_analyse = 1;
	end
end

function video_trigger(source, status)
	if (status.kind == "resized") then
		play_movie(source);
		prefilters[prefilter](source, VRESW, VRESH);

	elseif (status.kind == "frame") then
		last_frame = status.number;
		last_pts = status.pts;
		if (last_frame == 0 and start_analyse) then
			activate_regions();
		end

	elseif (status.kind == "frameserver_loop") then
		if (start_analyse) then
			shutdown();
		end
	end
end

function add_trigger_region(x1, y1, x2, y2, lb, ub, thresh, subtype)
	local props = image_surface_initial_properties(movieref);
	local newtrig = {};

	newtrig.vid = instance_image(movieref);
	newtrig.x1 = x1;
	newtrig.x2 = x2;
	newtrig.y1 = y1;
	newtrig.y2 = y2;
	newtrig.w  = x2 - x1;
	newtrig.h  = y2 - y1;
	newtrig.ub = ub; 
	newtrig.lb = lb;
	newtrig.thresh = thresh;
	newtrig.subtype = subtype;
	newtrig.ind = #triggers; 
	last_elem = newtrig;

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
	
	newtrig.flt = build_shader(nil, passf, "pass_filter" .. tostring(#triggers));
	image_shader(newtrig.vid, newtrig.flt);

-- Note; due to our serialization format, and not having to deal with
-- localization issues from radix_point problems, we just 8-bit limit 
-- our ub/lb values ..
	newtrig.shupdate = function()
		shader_uniform(newtrig.flt, "bounds", "ff", PERSIST, 
		newtrig.ub / 255.0, newtrig.lb / 255.0); 
	end

	newtrig.shupdate();
-- just add all trigger points in the first row
	trigger_y = trigger_y + (y2 - y1);
	table.insert(triggers, newtrig);
end

--
-- dynamic 2D region selector,
-- just feed with mouse input (step on click, move on motion)
-- manipulates to global namespace for 'mouse_recv'
--
function new_rect_pick(cbf, subtype, r, g, b)
	mouse_recv = { 
		step = function(self)
			if (self.x1 ~= nil) then
				cbf(self.x1, self.y1, mx, my, 20, 200, 128, subtype);
				order_image(mouse, max_current_image_order() + 1);
				self:destroy();
			else
				self.x1 = mx;
				self.y1 = my;
				self.vid = fill_surface(1, 1, r, g, b); 
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

function avg_trigfun(source, indata, threshold, tag)
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
		print( string.format("avg:%d:1:%d:%d", tag, last_pts,
			last_frame - start_framenumber));
	else
		print( string.format("avg:%d:0:%d:%d", tag, last_pts,
			last_frame - start_framenumber));
	end
end

-- 
-- The difference between avg and avgrow is that avgrow triggers its
-- output on the first row that exceeds the threshold, rather than
-- the whole of the image block. -1 marks a failure (no row found).
--
-- For "spot" detection, there should also be a second stage where 
-- the row in question is used as a starting point, then for each
-- bright point in the row, scan [n x m] downwards and check if 
-- they exceed some value.
--
function avgrow_trigfun(source, indata, threshold, tag)
	local props = image_surface_properties(source);

	local ofs = 1;

	for row=1, props.height do
		local rsum = 0;

		for col=1, props.width do
			local r = string.byte(indata, ofs);
			local g = string.byte(indata, ofs+1);
			local b = string.byte(indata, ofs+2);
			local a = string.byte(indata, ofs+3);

			rsum = rsum + (r + g + b) / 3;
			ofs = ofs + 4;
		end

		rsum = rsum / props.width;

		if (rsum > threshold) then
			print(string.format("avgrow:%d:%d:%d:%d", tag, row - 1,
				last_pts, last_frame - start_framenumber));
			return;
		end
	end

	print(string.format("avgrow:%d:-1:%d:%d", tag, last_pts, 
		last_frame - start_framenumber));
end

function activate_region(v)
	local newsrf = fill_surface(v.w, v.h, 0, 0, 0, v.w, v.h);

--
-- every tick (25Hz), read-back the contents of the region, run the avg_trigfun
-- (change to something of your liking depending on method of analysis)
-- it might be useful to configure this rate for higher-rate video sources
--
	define_calctarget(newsrf, {v.vid}, 
		RENDERTARGET_NODETACH, RENDERTARGET_NOSCALE, 1, function(datablock)
			if (v.subtype == "avg") then 
				avg_trigfun(newsrf, datablock, v.thresh, tostring(v.ind)); 
			elseif (v.subtype == "avg_row") then
				avgrow_trigfun(newsrf, datablock, v.thresh, tostring(v.ind));
			end
	end);

	show_image(newsrf);

-- properties are not bound to rendertargets, so either instance
-- the source material and attach to the calctarget, or stack them.
	move_image(v.vid, 0, 0);
end

-- setup a calc-target for each trigger region
function activate_regions()
	start_framenumber = last_frame;

	if (savecfg_name ~= nil) then
		zap_resource(savecfg_name);
		open_rawresource(savecfg_name);
		write_rawresource(
			string.format("-- arcan arguments: -w %d -h %d\n", VRESW, VRESH));
	end

	for i, v in ipairs(triggers) do
		if (savecfg_name ~= nil) then
			write_rawresource(
				string.format("add_trigger_region(%d, %d, %d, %d, %d, " .. 
				"%d, %d, %s)\n", v.x1, v.y1, v.x2, v.y2, v.lb, v.ub, 
				v.thresh, v.subtype)
			);
		end
		activate_region(v);
	end

	if (savecfg_name ~= nil) then
		close_rawresource();
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

hooktbl = {};
hooktbl["g"] = function()
	start_analyse = 1;
	activate_regions();
end

hooktbl["p"] = function()
	if (mouse_recv) then
		mouse_recv:destroy();
	end

	new_rect_pick(add_trigger_region, "avg", 0, 255, 0); 
end

hooktbl["y"] = function()
	if (mouse_recv) then
		mouse_recv:destroy();
	end

	new_rect_pick(add_trigger_region, "avg_row", 255, 0, 0);
end

hooktbl["LCTRL"] = function()
	toggle_mouse_grab();
end

hooktbl["ESCAPE"] = function() 
	if (mouse_recv) then
		mouse_recv:destroy();
	else
		shutdown();
	end
end

function tvist_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then
		if (iotbl.translated) then	
			local cfun = hooktbl[ keysym[iotbl.keysym] ];
			if (cfun ~= nil) then
				cfun();
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
