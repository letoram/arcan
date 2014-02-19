--
-- TVIST - Script for video-feed subregion analysis
--

trigger_y = 0;
start_analyse = nil;
def_thresh = 20;
def_ub = 128;
def_lb = 60;
start_framenumber = 0;
last_frame = 0;
last_pts = 0;
dryrun = true;

--
-- TODO:
-- a. convert the trails- part and add as a possible prefilter 
-- b. add a text region that maps to OCRing
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
		shutdown("Usage: arcan tvist moviename OR :avfeed arg [prefilt=fltname] " ..
			"[outcfg=fname] [run=fname]");
		return;
	end

	moviename = arguments[1];
	savecfg_name = "default";
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
			dryrun = false;
		end
	end
	
	triggers = {};

	if (arguments[1] == ":avfeed") then
		movieref = launch_avfeed(arguments[2], video_trigger);
	else
		movieref = load_movie(arguments[1], FRAMESERVER_LOOP, video_trigger);
	end

	image_tracetag(movieref, "input_raw");
	image_mask_set(movieref, MASK_UNPICKABLE);

	target_verbose(movieref);
-- setup mouse cursor and place it at the middle of the screen
	local cursor = load_image("cursor.png");
	show_image(cursor);
	mouse = null_surface(1,1);
	image_tracetag(mouse, "mouse_anchor");
	move_image(mouse, mx, my);
	link_image(cursor, mouse);
	show_image({mouse, cursor});
	move_image(cursor, -15, -15);	
	image_inherit_order(cursor, true);
	order_image(mouse, 255);
	mouse_setup(mouse, 255, 1, true);
	image_mask_set(cursor, MASK_UNPICKABLE);
	image_mask_set(mouse, MASK_UNPICKABLE);

	if (cmdfile ~= nil) then
		print(string.format("Using cfgfile=%s",cmdfile));
		system_load(cmdfile)();
		start_analyse = 1;
	else
		show_help();
	end

	hooktbl["TAB"]();
end

function video_trigger(source, status)
	if (status.kind == "resized") then
		play_movie(source);
		movieref = prefilters[prefilter](source, VRESW, VRESH);

	elseif (status.kind == "frame") then
		last_frame = status.number;
		last_pts = status.pts;

	elseif (status.kind == "frameserver_loop") then
		if (start_analyse) then
			shutdown();
		end
	end
end

function trig_dragh(self, vid, dx, dy)
	if (control_held) then
		self.lb = self.lb + dx;
		self.ub = self.ub + dy;
		self.lb = self.lb < 0 and 0 or self.lb;
		self.lb = self.lb > 255 and 255 or self.lb;
		self.ub = self.ub < 0 and 0 or self.ub;
		self.ub = self.ub > 255 and 255 or self.ub;
		self.lb = self.lb > self.ub and (self.ub - 1) or self.lb;
		self.ub = self.ub < self.lb and (self.lb + 1) or self.ub;

		self:shupdate();
		print(string.format("bounds (%d:%d)", self.lb, self.ub));

	elseif (shift_held) then
		self.thresh = (self.thresh + dx) % 255;
		self.thresh = self.thresh < 0 and 0 or self.thresh;
		self.thresh = self.thresh > 255 and 255 or self.thresh;

		print("threshold:", self.thresh);
	else
		if (self.dmode == nil) then
			local mx, my = mouse_xy();
			local rprops = image_surface_resolve_properties(vid);
			rprops.width = rprops.width * 0.5;
			rprops.height= rprops.height * 0.5;

			local cata  = math.abs(rprops.x + rprops.width - mx);
			local catb  = math.abs(rprops.y + rprops.height - my);
			local dist  = math.sqrt( cata * cata + catb * catb );
			local hhyp  = math.sqrt( rprops.width * rprops.width +
				rprops.height * rprops.height ) * 0.5;

			if (dist < hhyp) then
				self.dmode = "move";
			else
				self.dmode = "scale"; 
			end
		elseif (self.dmode == "move") then
			nudge_image(self.vid, dx, dy);
		elseif (self.dmode == "scale") then
			local props = image_surface_properties(self.vid);
			resize_image(self.vid, props.width + dx, props.height + dy);
		end
	end
end

function add_trigger_region(x1, y1, x2, y2, lb, ub, thresh, subtype)
	local props = image_surface_initial_properties(movieref);
	local newtrig = {};

	newtrig.x1 = x1;
	newtrig.x2 = x2;
	newtrig.y1 = y1;
	newtrig.y2 = y2;
	newtrig.w  = x2 - x1;
	newtrig.h  = y2 - y1;
	newtrig.w  = newtrig.w < 1 and 1 or newtrig.w;
	newtrig.h  = newtrig.h < 1 and 1 or newtrig.h;
	newtrig.vid = null_surface(newtrig.w, newtrig.h);
	image_sharestorage(movieref, newtrig.vid);
	image_tracetag(newtrig.vid, "trigger_region_" .. tostring(#triggers));
	
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
	
	newtrig.txcos = {s1, t1, s2, t1, s2, t2, s1, t2};

	move_image(newtrig.vid, 0, trigger_y); 
	resize_image(newtrig.vid, x2 - x1, y2 - y1);
	show_image(newtrig.vid);
	image_set_txcos(newtrig.vid, newtrig.txcos);
	
	newtrig.flt = build_shader(nil, passf, "pass_filter" .. tostring(#triggers));
	image_shader(newtrig.vid, newtrig.flt);

-- Note; due to our serialization format, and not having to deal with
-- localization issues from radix_point problems, we just 8-bit limit 
-- our ub/lb values ..
	newtrig.shupdate = function()
		shader_uniform(newtrig.flt, "bounds", "ff", PERSIST, 
		newtrig.ub / 255.0, newtrig.lb / 255.0); 
	end

	newtrig.own = function(self, vid) return vid == self.vid; end
	newtrig.drag = trig_dragh;
	newtrig.drop = function() newtrig.dmode = nil; end
	newtrig.name = "region_" .. tostring(newtrig.ind);

	newtrig.shupdate();
-- just add all trigger points in the first row
	trigger_y = trigger_y + (y2 - y1);
	table.insert(triggers, newtrig);

	mouse_addlistener(newtrig, {"drag", "drop"});
	activate_region(newtrig, true);
end

--
-- dynamic 2D region selector,
-- just feed with mouse input (step on click, move on motion)
-- manipulates to global namespace for 'mouse_recv'
--
function new_rect_pick(cbf, subtype, r, g, b)
	mouse_recv = { 
		step = function(self)
			local mx, my = mouse_xy();

			if (self.x1 ~= nil) then
				cbf(self.x1, self.y1, mx, my, 
					def_thresh, def_ub, def_lb, subtype);
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

function avg_trigfun(source, indata, trigtbl)
	local sum = 0;
	local pxc = 0;

-- don't repeat calls on the same video frame
	if (trigtbl.last_frame ~= nil and 
		last_frame - start_framenumber == trigtbl.last_frame) then
		return;
	end
	trigtbl.last_frame = last_frame - start_framenumber;

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

	return (avg > trigtbl.thresh) and 1 or 0;
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
function avgrow_trigfun(source, indata, trigtbl)
-- don't repeat calls on the same video frame
	if (trigtbl.last_frame ~= nil and 
		last_frame - start_framenumber == trigtbl.last_frame) then
		return;
	end
	trigtbl.last_frame = last_frame - start_framenumber;

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

		if (rsum > trigtbl.thresh) then
			return (row - 1);
		end
	end

	return -1;
end

function activate_region(v)
	local calcdst = fill_surface(v.w, v.h, 0, 0, 0, v.w, v.h);
	local nsrf = null_surface(v.w, v.h);
	image_tracetag(calcdst, "calc_destination");
	image_tracetag(nsrf, "calc_input");

	image_sharestorage(movieref, nsrf);
	image_shader(nsrf, v.flt);
	show_image(nsrf);
	image_set_txcos(nsrf, v.txcos);

	if (dryrun) then
		v.signalchld = color_surface(64, 64, 0, 0, 0);
		link_image(v.signalchld, v.vid);
		image_inherit_order(v.signalchld, true);
		show_image(v.signalchld);
		move_image(v.signalchld, -64, 0);
	end

--
-- every tick (25Hz), read-back the contents of the region, run the avg_trigfun
-- (change to something of your liking depending on method of analysis)
-- it might be useful to configure this rate for higher-rate video sources
-- as well as experiment with target_synchronous on the movieref and 
-- possible recordtargets
--
	define_calctarget(calcdst, {nsrf}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, function(datablock)
			if (v.subtype == "avg") then 
				local signal = avg_trigfun(calcdst, datablock, v);

				if (signal ~= nil and dryrun) then
					image_color(v.signalchld, 0, signal == 1 and 255 or 0, 0);
				elseif (signal ~= nil) then
					print(string.format("avg(%d):%d:%d:%d", 
						v.ind, last_frame, last_pts, signal));
				end

			elseif (v.subtype == "avg_row") then
				local row = avgrow_trigfun(calcdst, datablock, v);

				if (row ~= nil and dryrun) then
					if (row == -1) then
						image_color(v.signalchld, 255, 0, 0);
					else
						image_color(v.signalchld, 0, math.floor((row / v.h) * 255), 0);
					end
				elseif (row ~= nil) then
					print(string.format("avg_row(%d):%d:%d:%d/%d", 
						v.ind, last_frame, last_pts, row, v.h));
				end
			end
	end);
end

-- setup a calc-target for each trigger region
function save_configuration()
	start_framenumber = last_frame;

	if (savecfg_name ~= nil) then
		zap_resource(savecfg_name);
		print("saving configuration to: ", savecfg_name);
		open_rawresource(savecfg_name);
		write_rawresource(
			string.format("-- arcan arguments: -w %d -h %d\n", VRESW, VRESH));

		for i, v in ipairs(triggers) do
				write_rawresource(
					string.format("add_trigger_region(%d, %d, %d, %d, %d, " .. 
					"%d, %d, [[%s]]);\n", v.x1, v.y1, v.x2, v.y2, v.lb, v.ub, 
					v.thresh, v.subtype
				));
		end

		close_rawresource();
	end
end

hooktbl = {};
hooktbl["g"] = function()
	save_configuration();
end

hooktbl["p"] = function()
	if (mouse_recv) then
		mouse_recv:destroy();
	end

	new_rect_pick(add_trigger_region, "avg", 0, 255, 0); 
end

function show_help()
	if (valid_vid(helpvis)) then
		delete_image(helpvis);
		helpvis = nil;
		return;
	end

	helpvis = render_text(string.format([[\ffonts/default.ttf,18
		\bLeft/Right\!b \tSeek +- 5 seconds\n\r
		\bUp/Down\!b    \tSeek +- 10 seconds\n\r
		\bp\!b          \tDefine new binary trigger\n\r
		\by\!b          \tDefine new line trigger\n\r
		\bg\!b          \tSave Config to (%s)\n\r
		\bTab\!b        \tToggle input grab on/off\n\r
		\bESCAPE\!b     \tShutdown\n\r
		\bF1\!b         \tShow/Hide Help\n\r\n\r\n\r
		(on trigger image)\n\r
		\bcenter drag\!b\t dX / dY move image\n\r
		\bcorner drag\!b\t resize image\n\r
		\blctrl + drag\!b\t dX change gate func. lower\n\r
		\blctrl + drag\!b\t dY change gate func. upper\n\r
		\blshift + drag\!b\t dX change trigger threshold\n\r
	]], savecfg_name));

	move_image(helpvis, VRESW - image_surface_properties(helpvis).width - 10, 10);
	show_image(helpvis);
	order_image(helpvis, 200);
end

hooktbl["y"] = function()
	if (mouse_recv) then
		mouse_recv:destroy();
	end

	new_rect_pick(add_trigger_region, "avg_row", 255, 0, 0);
end

hooktbl["LEFT"] = function()
	target_seek(movieref, -5, 0);
end

hooktbl["RIGHT"] = function()
	target_seek(movieref,  5, 0);
end

hooktbl["UP"] = function()
	target_seek(movieref, 30, 0);
end

hooktbl["DOWN"] = function()
	target_seek(movieref, -30, 0);
end

hooktbl["TAB"] = function()
	toggle_mouse_grab();
end

hooktbl[" "] = function()
	if (paused) then
		paused = nil;
		resume_movie(movieref);
	else
		pause_movie(movieref);
		paused = true;
	end
end

hooktbl["F1"] = function()
	show_help();
end

hooktbl["ESCAPE"] = function() 
	if (mouse_recv) then
		mouse_recv:destroy();
	else
		shutdown();
	end
end

function tvist_clock_pulse()
	mouse_tick(1);
end

minputtbl = {false, false, false, false, false};
function tvist_input(iotbl)
	if (iotbl.kind == "digital") then
		local sym = keysym[iotbl.keysym];
		if (sym == "LCTRL") then
			control_held = iotbl.active;

		elseif (sym == "LSHIFT") then
			shift_held = iotbl.active;
		end

		if (iotbl.translated and iotbl.active) then	
		local cfun = hooktbl[ sym ]; 
			if (cfun ~= nil) then
				cfun();
			end

		elseif (iotbl.source == "mouse") then
			if (mouse_recv and iotbl.active) then
				mouse_recv:step();
			else
				minputtbl[iotbl.subid] = iotbl.active;
				mouse_input(0, 0, minputtbl);
			end
		end

-- update cursor and clamp inside window constraints (+ possible
-- constraints from the current mouse target)
	elseif (iotbl.kind == "analog" and iotbl.source == "mouse") then
		mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0,
			iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);

		if (mouse_recv) then
			mx, my = mouse_xy();
			mouse_recv:move(mx, my);
		end
	end
end
