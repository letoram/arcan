--
-- Monitor script based on the AWB- style window management
-- somwhat messy, but it isn't exactly a trivial datamodel 
-- that we're working with ...
--
-- 
--

state = {
	process_sample = false,
	delta_sample = false
};

deffont = "fonts/default.ttf";

kbdbinds = {};
sample_triggers = {};

function menulbl(text)
	return render_text(string.format("\\#0055a9\\f%s,%d %s", 
		deffont, 10, text));
end

function desktoplbl(text)
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 10, text));
end

function monitor_awb()
	system_context_size(65535);
	pop_video_context();

	for i=1,#arguments do
		if (string.sub(arguments[i], 1, 5) == "file:") then
			samplefile = string.sub(arguments[i], 6);
		end
	end

	system_load("scripts/mouse.lua")();

	system_load("awbwnd.lua")();
	system_load("awbwman.lua")();
	symtable = system_load("scripts/symtable.lua")();

	cursor = load_image("cursor.png");
	mouse_setup(cursor, 255, 1, true);
	mouse_acceleration(0.5);

	awbwman_init(menulbl, desktoplbl);

	kbdbinds["F11"]  = awbmon_help;
	kbdbinds["CTRL"] = toggle_mouse_grab;
	kbdbinds["ALTF4"] = shutdown;
	kbdbinds["F6"] = spawn_benchmark;

	kbdbinds[" "] = function()
		if (LAST_SAMPLE ~= nil) then
			spawn_sample(LAST_SAMPLE, 1, 1); 
		end
	end

--
-- "Offline" mode
--
	if (samplefile ~= nil) then
		LAST_SAMPLE = system_load(samplefile)();
		sample(LAST_SAMPLE, 1, 1);
	end

	awbmon_help();
end

function awbmon_help()
	local wnd = awbwman_spawn(menulbl("Help"));
	helpimg = desktoplbl([[Default Monitor Script Helper\n\r\n\r
(global)\n\r
CTRL\t Grab/Release Mouse\n\r
SPACE\t Latest Sample\n\r 
F6\tBenchmark View\n\r
ALT+F4\t Shutdown\n\r
F11\t Help Window\n\r\nr\r
(window-input)\n\r
ESC\tDestroy Window\n\r
F1\tGenerate Tree View\n\r
F2\tGenerate Allocation Map\n\r
SHFT+F2\tContinuous Allocation Map\n\r
F3\tSwitch Context Up\n\r
SHIFT+F3\tSwitch Context Down\n\r
F4\tContext Info\n\r
F5\tVideo Subsystem Info\n\r
Up/Down\t Move to Parent/Child\n\r
Left/Right\t Step to Prev/Next Object\n\r
Shift+L/R\t Step to Prev/Next Sibling\n\r
Shift+Enter\t Copy to new Window]]);
	link_image(helpimg, wnd.canvas.vid);
	show_image(helpimg);
	image_clip_on(helpimg, CLIP_SHALLOW);
	image_mask_set(helpimg, MASK_UNPICKABLE);
	image_inherit_order(helpimg, true);
	order_image(helpimg, 1);
	local props =	image_surface_properties(helpimg);
	wnd:resize(props.width, props.height, true, true);
	default_mh(wnd);
end

function context_vid(smpl, contn)
	local ctx = smpl.vcontexts[contn];

-- contexts
	local cimg = desktoplbl(string.format([[
Context:\t%d / %d\n\r
Rtargets:\t%d\n\r
Vobjects:\t%d (%d) / %d\n\r
Last Tick:\t%d\n\r]] , contn, #csample.vcontexts, 
#ctx.rtargets, ctx.alive, ctx.vobjs, ctx.limit, ctx.tickstamp));

	return cimg;
end

function badsample(startid)
	return {
		cellid = startid,
		cellid_translated = 0,
		parent = 0,
		tracetag = "empty",
		glstore_w = 0,
		glstore_h = 0,
		glstore_bpp = 0,
		glstore_txu = 0,
		glstore_txv = 0,
		glstore_refc = 0,
		frameset_mode = 0,
		frameset_counter = 0,
		frameset_capacity = 0,
		frameset_current = 0,
		scalemode = "none",
		filtermode = "none",
		imageproc = "none",
		glstore_prg = "none",
		extrefc_framesets = 0,
		extrefc_instances = 0,
		extrefc_attachments = 0,
		extrefc_links = 0,
		flags = "none",
		mask = "none",
		order = 0,
		lifetime = 0,
		origw = 0,
		origh = 0,
		source = "none",
		props = {
			opa = 0,
			position = {0, 0, 0},
			scale = {0, 0, 0},
			rotation = {0, 0, 0}
		}
	};
end

--
-- Bunch of LUTs to make comparison, color hilights etc.
-- Easier and less error-prone than a gigantic string.format
--

-- key order
local keytbl = {
	"cellid", "cellid_translated", "parent", "tracetag", "glstore_glid",
	"glstore_w", "glstore_h", "glstore_bpp", "glstore_refc", "glstore_txu",
	"glstore_txv", "frameset_mode", "frameset_counter", "frameset_capacity",
	"frameset_current", "scalemode", "filtermode", "imageproc", "blendmode",
	"clipmode", "glstore_prg", "extrefc_framesets", "extrefc_instances",
	"extrefc_attachments", "extrefc_links", "flags", "valid_cache", "rotate_state",
	"childslots", "mask", "order", "lifetime", "origw", "origh", "storage_source",
	"kind", "opa", "position", "scale", "rotation"
};

-- format string profile
local typetbl = {
	cellid             = "Cellid: %d ",
	cellid_translated  = "Translated: %d\\t",
	parent             = "Parent: %d\\n\\r", 
	tracetag           = "\\n\\rTracetag: %s\\n\\r",

	glstore_glid = "GL(id: %d",
	glstore_w    = " w: %d",
	glstore_h    = " h: %d", 
	glstore_bpp  = " bpp: %d",
	glstore_refc = " refc: %d", 
	glstore_txu  = " txu: %f",
	glstore_txv  = " txv: %f)\\n\\r",

	frameset_mode      = "\\n\\r(Frameset mode: %s ", 
	frameset_counter   = " counter: %d ",
	frameset_capacity  = " capacity: %d ", 
	frameset_current   = " current: %d )\\n\\r",

	scalemode   = "scalemode: %s ",
	filtermode  = "filtermode: %s ",
	imageproc   = "postprocess: %s\\n\\r",
	blendmode   = "blendmode: %s ",
	clipmode    = "clipmode: %s ",
	glstore_prg = "\\n\\rprogram: %s\\n\\r",  

	extrefc_framesets   = "Refc(Framesets: %d ", 
	extrefc_instances   = "Inst: %d ", 
	extrefc_attachments = "Attach: %d ",
	extrefc_links       = "Links: %d ",

	flags = "\\n\\rflags: %s\\n\\r",

	valid_cache   = "Valid Cache: %d ", 
	rotate_state  = "Rotation: %d ",
	childslots    = "Children: %d ",

	mask     = "\\n\\r%s\\n\\r",
	order    = "Order: %d",
	lifetime = "Lifetime: %d ",
	origw    = "Orig.W: %d ",
	origh    = "Orig.H: %d ",

	storage_source = "Source: %s ",
	kind = "Kind: %s \\n\\r",

	opa      = "Opacity: %s ",
	position = "Position: %s ",
	scale    = "Scale: %s ",
	rotation = "Rotation: %s "
};

function default_mh(wnd, vid)
	local mh = {
		own = function(self, vid) return vid == wnd.canvas.vid; end,
		click = function() wnd:focus(); end
	};
	table.insert(wnd.handlers, mh);
	mouse_addlistener(mh, {"click"});
end

function render_sample(smpl)
	if (smpl.cellid == nil) then
		return;
	end
	local strtbl = {};

	for i,v in ipairs(keytbl) do
		if (smpl[v] ~= nil) then
			table.insert(strtbl, 
				string.format(typetbl[v], string.gsub(smpl[v], '\\', '\\\\')));
		end
	end

	return render_text(table.concat(strtbl, ""));
end

function samplewnd_step(self, dir)
	count = self.smpl.vcontexts[self.context].limit;
	while (count > 0) do
		self.lastid = self.lastid + dir;
		self.lastid = self.lastid > self.smpl.vcontexts[self.context].limit 
			and 1 or self.lastid;
		self.lastid = self.lastid < 1 
			and self.smpl.vcontexts[self.context].limit or self.lastid;
		if (self.smpl.vcontexts[self.context].vobjs[self.lastid] ~= nil) then
			break;
		end
		count = count - 1;
	end

	self:update_smpl(self.smpl.vcontexts[self.context].vobjs[self.lastid]);
end

function samplewnd_stepsibling(self, num)
	local lim    = self.smpl.vcontexts[self.context].limit;
	local cur    = self.lastid + num;
	local count  = lim;
	local parent = self.smpl.vcontexts
		[self.context].vobjs[self.lastid].parent;

	while (vobj ~= cur and count > 0) do
		cur = cur + num;
		count = count - 1;

		if (cur <= 0) then
			cur = lim;
		elseif (cur > lim) then
			cur = 1;
		end

		local cvo = self.smpl.vcontexts[self.context].vobjs[cur];
		if (cvo and cvo.parent == parent) then
			self.lastid = cur;
			self:update_smpl(self.smpl.vcontexts[self.context].vobjs[self.lastid]);
			return;
		end
	end

end

function samplewnd_stepparent(self)
	if (self.smpl.vcontexts[self.context].vobjs[self.lastid].parent ~= 0) then
		self.lastid = self.smpl.vcontexts[self.context].vobjs[self.lastid].parent;
		self:update_smpl(self.smpl.vcontexts[self.context].vobjs[self.lastid]);
	end
end

function samplewnd_stepchild(self)
	local lim    = self.smpl.vcontexts[self.context].limit;
	local cur    = self.lastid + 1;
	local count  = lim;
	local parent = self.smpl.vcontexts[self.context].vobjs[self.lastid].parent;

	while (self.lastid ~= cur and count > 0) do
		cur = cur + 1;
		count = count - 1;

		if (cur > lim) then
			cur = 1;
		end

		local cvo = self.smpl.vcontexts[self.context].vobjs[cur];
		if (cvo and cvo.parent == self.lastid) then 
			self.lastid = cur;
			self:update_smpl(self.smpl.vcontexts[self.context].vobjs[self.lastid]);
			return;
		end
	end
end

function wnd_link(wnd, vid)
	link_image(vid, wnd.canvas.vid);
	show_image(vid);
	image_clip_on(vid, CLIP_SHALLOW);
	image_inherit_order(vid, true);
	order_image(vid, 1);
	
	local props = image_surface_properties(vid);
	props.width = props.width > (0.5 * VRESW) and math.floor(0.5 * VRESW) or
		props.width;
	
	wnd:resize(props.width, props.height, true, true);
end

function samplewnd_update(self, smpl)
	delete_image(self.smplvid);
	if (smpl == nil) then
		smpl = badsample( self.lastid );
	end

	self.smplvid = render_sample(smpl);
	wnd_link(self, self.smplvid);
	image_mask_set(self.smplvid, MASK_UNPICKABLE);
end

--
-- Set a representative color based on the complexity of the object
-- (dark grey : free)
-- color; kind
-- intensity; cost
--
function vobjcol(smpl)
	if (smpl == nil) then
		return 20, 20, 20;
	end

	local base_r, base_g, base_b;
	local intensity = 0.5;

	if (string.find(smpl.flags, "clone") ~= nil) then
		base_r = 255;
		base_g = 0;
		base_b = 204;
	elseif (smpl.kind == "3dobj") then
		base_r = 0;
		base_g = 0;
		base_b = 255;
	elseif (smpl.kind == "frameserver") then
		intensity = 1.0;
		base_r = 0;
		base_g = 255;
		base_b = 0;
	elseif (smpl.kind == "textured_loading") then
		base_r = 255;
		base_g = 200;
		base_b = 100;
	elseif (smpl.kind == "color") then
		base_r = 150;
		base_g = 150;
		base_b = 100;
	elseif (smpl.kind == "textured") then
		base_r = 255;
		base_g = 255;
		base_b = 200;
	elseif (smpl.kind == "dead") then
		base_r = 255;
		base_g = 0;
		base_b = 0;
	end

	return (intensity * base_r), (intensity * base_g), (intensity * base_b); 
end

local function lineobj(src, x1, y1, x2, y2)
	local dx  = x2 - x1 + 1;
	local dy  = y2 - y1 + 1;
	local len = math.sqrt(dx * dx + dy * dy);

	resize_image(src, len, 2);

	show_image(src);
	rotate_image(src, math.deg( math.atan2(dy, dx) ) );
	move_image(src, x1, y1);
	image_origo_offset(src, -1 * (0.5 * len), -0.5);

	return line;
end

--
-- To generate a tree, first create a list of samples
-- where each element is sorted based on the number of parents it has (level)
-- This gives us the Y value and allocate X on a first come first serve basis.
-- Path the smpl table to track references to cells in this new tree,
-- and use lineobj calls to plot out the relation.
--
function spawn_tree(smpl, context)
	local wnd = awbwman_spawn(menulbl("TreeView:" .. tostring(context) .. 
		tostring(smpl.display.ticks)));

	lvls = {};

	local nparents = function(vobj)
		local cur = vobj;
		local cnt = 0;

		while (cur and cur.cellid ~= 0) do
			cnt = cnt + 1;
			cur = smpl.vcontexts[context].vobjs[cur.parent];
		end

		return cnt;
	end

	for i,j in pairs(smpl.vcontexts[context].vobjs) do
	end

	default_mh(wnd);
end

function bench_update(wnd, smpl)
	if (smpl.benchmark == nil) then
		return;
	end
	
	local bench = smpl.benchmark;
	local bitmap = {};

	local split1 = #bench.ticks;
	local split2 = #bench.frames;
	local split3 = #bench.framecost;
	local w = split1 + split2 + split3;

-- Replace this one to get bars instead of points
	local plot_sample = function(dst, col, value, r, g, b)
		value = value > wnd.maxv and wnd.maxv or value;
		local row = wnd.maxv - value;

		local cell = ( (row - 1) * w + col ) * 3;
		
		dst[cell + 1] = r;
		dst[cell + 2] = g;
		dst[cell + 3] = b;
	end

--
-- Fill with black
--
	local npx = wnd.maxv * w;
	for i=1,npx do
		bitmap[(i-1)*3+1] = 0;
		bitmap[(i-1)*3+2] = 0;
		bitmap[(i-1)*3+3] = 0;
	end
	
	for i=1,#bench.ticks do
		plot_sample(bitmap, i - 1, bench.ticks[i], 255, 0, 0);
	end

	for i=1,#bench.frames do
		plot_sample(bitmap, i + split1 - 2, bench.frames[i], 0, 255, 0);
	end

	for i=1,#bench.framecost do
		plot_sample(bitmap, i + split1 + split2 - 3, 
		bench.framecost[i], 0, 200, 255);	
	end

	local vid = raw_surface(w, wnd.maxv, 3, bitmap);
	image_texfilter(vid, FILTER_NONE);
	wnd:update_canvas(vid);
end

function spawn_benchmark()
	if (sample_triggers["benchmark"] == nil) then
		local wnd  = awbwman_spawn(menulbl("Benchmark"));
		wnd.update = bench_update;
		wnd.maxv   = 50;

		sample_triggers["benchmark"] = wnd;
		wnd.on_destroy = function()
			sample_triggers["benchmark"] = nil;
		end
		default_mh(wnd);
	end

end

function spawn_continous(smpl, context)
	if (sample_triggers["allocmon"] == nil) then
		local wnd = awbwman_spawn(menulbl("Allocation Monitor"));

		wnd.update = function(self, smpl)
			if (smpl == nil) then
				smpl = LAST_SAMPLE;
			end
			local vid = build_allocmap(smpl, context);
			wnd:update_canvas(vid);
		end

		wnd.maxv = 50;
		sample_triggers["allocmon"] = wnd;
		wnd.on_destroy = function()
			sample_triggers["benchmark"] = nil;
		end
		default_mh(wnd);
	end
end

function spawn_context(smpl, context)
	local wnd = awbwman_spawn(menulbl("Context:" .. tostring(context) .. ":" ..
		tostring(smpl.display.ticks)));

	local ctx = smpl.vcontexts[context];
	local cimg = desktoplbl(string.format([[
Context:\t%d / %d\n\r
Rtargets:\t%d\n\r
Vobjects:\t%d (%d) / %d\n\r
Last Tick:\t%d\n\r]], context, #smpl.vcontexts, #ctx.rtargets, ctx.alive,
#ctx.vobjs, ctx.limit, ctx.tickstamp));

	image_mask_set(cimg, MASK_UNPICKABLE);
	wnd_link(wnd, cimg);
	default_mh(wnd);
end

function spawn_vidinf(smpl, disp)
	local wnd = awbwman_spawn(menulbl("Video:" .. tostring(disp.ticks)));
	local cimg = desktoplbl(string.format([[
Ticks:\t%d\n\r
Display:\t%d\n\r
Conserv:\t%d\n\r
Vsync:\t%d\n\r
MSA:\t%d\n\r
Vitem:\t%d\n\r
Imageproc:\t%d\n\r
Scalemode:\t%d\n\r
Filtermode:\t%d\n\r]],
disp.ticks, disp.width, disp.height,
disp.conservative, disp.vsync, disp.msasamples,
disp.ticks, disp.default_vitemlim, disp.imageproc,
disp.scalemode, disp.filtermode));

	image_mask_set(cimg, MASK_UNPICKABLE);
	wnd_link(wnd, cimg);
	default_mh(wnd);
end

function build_allocmap(smpl, context)
	local ofs    = 1;
	local smplofs= 1;
	local rows   = 0;
	local odd    = false;
	local bitmap = {};
	local ul     = smpl.vcontexts[context].limit;
	local npix   = math.floor(math.sqrt(ul));
	local rowvs  = {};

	while (smplofs <= ul) do
		for col=1,npix*2 do
			if (col % 2 == 0 or odd == true) then
				bitmap[ofs  ] = 0;
				bitmap[ofs+1] = 0;
				bitmap[ofs+2] = 0;
				ofs = ofs + 3;
			else
				local r, g, b = vobjcol(smpl.vcontexts[context].vobjs[smplofs]);
				bitmap[ofs  ] = r;
				bitmap[ofs+1] = g;
				bitmap[ofs+2] = b;
				ofs = ofs + 3;
				smplofs = smplofs + 1;
			end
		end

		odd  = not odd;
		rows = rows + 1;
	end

	local vid = raw_surface(npix * 2, rows, 3, bitmap);
	image_texfilter(vid, FILTER_NONE);
	return vid, rowvs;	
end

local function get_cellid(canvasvid, mx, my) 
	local p = image_surface_resolve_properties(canvasvid);
	local o = image_surface_initial_properties(canvasvid);
	local sx = p.width / o.width;
	local sy = p.height / o.height;
	local rv = o.width / 2;
	if (o.width % 2 == 0) then
		rv = rv - 1;
	end

	local mx = math.floor((mx - p.x) / (sx * 2));
	local my = math.floor((my - p.y) / (sy * 2));
	local cellid = my * rv + mx + my + 1;
	return cellid;
end

function spawn_allocmap(smpl, context)
	local wnd = awbwman_spawn(menulbl("AllocMap:" .. tostring(context) .. 
		tostring(smpl.display.ticks)));
	
	if (smpl == nil) then
		smpl = LAST_SAMPLE;
	end

	local vid = build_allocmap(smpl, context);
	wnd:update_canvas(vid);
	wnd:resize(wnd.w, wnd.h, true, true);

-- figure out what is clicked, and spawn a sample video 
-- navigated to that particular sample
	local mh = {
		own = function(self, vid) 
			return vid == wnd.canvas.vid; 
		end,

		motion = function(self, vid, mx, my, relx, rely)
-- scale to the dimensions provided by the vcontext
			local ind = get_cellid(wnd.canvas.vid, mx, my);
			local vobj = smpl.vcontexts[context].vobjs[ind];
			local tag = vobj ~= nil and vobj.tracetag or "no object";
			tag = tag .. "(" .. tostring(ind) .. ")";

			local l = desktoplbl(string.gsub(tag, "\\", "\\\\"));
			if (wnd.lasthint ~= nil) then
				delete_image(wnd.lasthint);
				wnd.lasthint = nil;
			end

			link_image(l, wnd.dir.b.vid);
			show_image(l);
			image_inherit_order(l, true);
			order_image(l, 1);
			wnd.lasthint = l;
		end,

		click = function(self, vid, mx, my)
			wnd:focus();
			print(mx, my);
			local ind = get_cellid(wnd.canvas.vid, mx, my);
			if (smpl.vcontexts[context].vobjs[ind] ~= nil) then
				spawn_sample(smpl, context, ind - 1);
			end
		end
	};

	table.insert(wnd.handlers, mh);
	mouse_addlistener(mh, {"motion", "click", "dblclick"});
end

function window_input(self, iotbl)
	local sym = iotbl.prefix .. iotbl.keysym;
	
	if (iotbl.active == false) then
		return;
	end
	if (sym == "RIGHT") then
		self:step(1);
	elseif (sym == "LEFT") then
		self:step(-1);
	elseif (sym == "SHIFTRIGHT") then
		self:step_sibling(1);
	elseif (sym == "SHIFTLEFT") then
		self:step_sibling(-1);
	elseif (sym == "SHIFTENTER") then
		spawn_sample(self.smpl, self.context, self.activeid);
	elseif (sym == "UP") then
		self:step_parent();
	elseif (sym == "DOWN") then
		self:step_child();
	elseif (sym == "ESCAPE") then
		self:destroy(10);
	elseif (sym == "F1") then
		spawn_tree(self.smpl, self.context);
	elseif (sym == "F2") then
		spawn_allocmap(self.smpl, self.context);
	elseif (sym == "SHIFTF2") then
		spawn_continous(self.smpl, self.context);
	elseif (sym == "F3") then
		print("switch context down");
	elseif (sym == "SHIFTF3") then
		print("switch context down");
	elseif (sym == "F4") then
		spawn_context(self.smpl, self.context);
	elseif (sym == "F5") then
		spawn_vidinf(self.smpl, self.smpl.display);
	end
end

function spawn_sample(smpl, context, startid)
	local wnd = awbwman_spawn(menulbl(tostring(context) .. ":" .. 
		tostring(smpl.display.ticks)));

	wnd.step = samplewnd_step;
	wnd.update_smpl = samplewnd_update;
	wnd.smplvid = null_surface(1, 1);
	wnd.lastid  = startid;
	wnd.context = context;
	wnd.smpl = smpl;
	wnd.step_parent  = samplewnd_stepparent;
	wnd.step_sibling = samplewnd_stepsibling;
	wnd.step_child   = samplewnd_stepchild;
	wnd.input = window_input; 
	wnd:step(1);
	default_mh(wnd);
end

function sample(smpl)
	LAST_SAMPLE = smpl;

	for k,v in pairs(sample_triggers) do
		if (v.update) then
			v:update(smpl);
		end
	end
end

modtbl = {false, false, false, false};
function update_modifiers(sym, active)
	local ret = "";

	if (sym == "LSHIFT" or sym == "RSHIFT") then
		modtbl[1] = active;
	elseif (sym == "LCTRL" or sym == "RCTRL") then
		modtbl[2] = active;
	elseif (sym == "LALT" or sym == "RALT") then
		modtbl[3] = active;
	elseif (sym == "RMETA" or sym == "LMETA") then
		modftbl[4] = active;
	else
		ret = sym;
	end

	return "" .. (modtbl[1] and "SHIFT" or "") .. (modtbl[2] and "CTRL" or "") ..
		(modtbl[3] and "ALT" or "") .. (modtbl[4] and "META" or ""), ret;
end

minputtbl = {false, false, false};
function monitor_awb_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0,
			iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);

	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		if (iotbl.subid > 0 and iotbl.subid <= 3) then
			minputtbl[iotbl.subid] = iotbl.active;
			mouse_input(0, 0, minputtbl);
		end
	
	elseif (iotbl.kind == "digital" and iotbl.translated) then
		iotbl.keysym = symtable[iotbl.keysym] and symtable[iotbl.keysym] or "";
		iotbl.prefix, iotbl.keysym = update_modifiers(iotbl.keysym, iotbl.active);

		if (iotbl.active and kbdbinds[ iotbl.prefix .. iotbl.keysym ]) then
			kbdbinds[ iotbl.prefix .. iotbl.keysym ]();
		else
			awbwman_input(iotbl);
		end
	end
end
