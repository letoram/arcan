--
-- Monitor script based on the AWB- style window management
-- somwhat messy, but it isn't exactly a trivial datamodel 
-- that we're working with ...
--

state = {
	process_sample = false,
	delta_sample = false
};

deffont = "fonts/default.ttf";

kbdbinds = {};

function menulbl(text)
	return render_text(string.format("\\#0055a9\\f%s,%d %s", 
		deffont, 10, text));
end

function desktoplbl(text)
	return render_text(string.format("\\#ffffff\\f%s,%d %s",
		deffont, 10, text));
end

function awbmon()
	system_context_size(65535);
	pop_video_context();

	system_load("scripts/mouse.lua")();
	system_load("scripts/monitor/awbmon/awbwnd.lua")();
	system_load("scripts/monitor/awbmon/awbwman.lua")();
	symtable = system_load("scripts/symtable.lua")();

	cursor = fill_surface(16, 16, 128, 255, 0);
	mouse_setup(cursor, 255, 1);
	mouse_acceleration(0.5);

	awbwman_init(menulbl, desktoplbl);

	kbdbinds["F11"]  = awbmon_help;
	kbdbinds["CTRL"] = toggle_mouse_grab;
	kbdbinds["ALTF4"] = shutdown;
	kbdbinds[" "] = function() state.process_sample = true; end

	awbmon_help();
end

function awbmon_help()
	local wnd = awbwman_spawn(menulbl("Help"));
	helpimg = desktoplbl([[Default Monitor Script Helper\n\r\n\r
(global)\n\r
CTRL\t Grab/Release Mouse\n\r
SPACE\t Wait for new Sample\n\r
ALT+F4\t Shutdown\n\r
F11\t Help Window\n\r\nr\r
(window-input)\n\r
ESC\tDestroy Window\n\r
F1\tGenerate Tree View\n\r
F2\tGenerate Allocation Map\n\r
F3\tSwitch Context Up\n\r
SHIFT+F3\tSwitch Context Down\n\r
F4\tContext Info\n\r
F5\tVideo Subsystem Info\n\r
F6\tBenchmark View\n\r
Up/Down\t Move to Parent/Child\n\r
Left/Right\t Step to Prev/Next Object\n\r
Shift+L/R\t Step to Prev/Next Sibling\n\r
Shift+Enter\t Copy to new Window]]);
	link_image(helpimg, wnd.canvas.vid);
	show_image(helpimg);
	image_clip_on(helpimg, CLIP_SHALLOW);
	image_inherit_order(helpimg, true);
	order_image(helpimg, 1);
	local props =	image_surface_properties(helpimg);
	wnd:resize(props.width + 20, props.height + 20);
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

function badsample(context, startid)
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

function render_sample(lv)
	print(lv.props.position[1], lv.props.position[2]);
	return desktoplbl(string.format(
[[Vobj(%d)=>(%d), Parent: %d Tag: %s\n\r
GL(Id: %d, W: %d, H: %d, BPP: %d, TXU: %d, TXV: %d, Refcont: %d\n\r
Frameset( %d, %d / %d:%d )\n\r
Scale: %s\tFilter: %s\tProc: %s\tProgram: %s\n\r
#FrmRef: %d\t#Inst: %d\t#Attach: %d\t#Link: %d\n\r
Flags: %s\n\r
Mask: %s\n\r
Order: %d\tLifetime: %d\tOrigW: %d\tOrigH: %d\n\r
Source: %s\n\r
Opacity: %.2f\n\r
Position: %.2f, %.2f, %.2f\n\r
Size: %.2f %.2f, %.2f\n\r
Orientation: %.2f, %.2f, %.2f degrees\n\r]],
lv.cellid, lv.cellid_translated, lv.parent, lv.tracetag,
lv.glstore_glid and lv.glstore_glid or 0, lv.glstore_w, lv.glstore_h, 
lv.glstore_bpp, lv.glstore_txu, lv.glstore_txv, 
lv.glstore_refc and lv.glstore_refc or 0, 
lv.frameset_mode, lv.frameset_counter, lv.frameset_capacity, 
lv.frameset_current,
lv.scalemode, lv.filtermode, lv.imageproc, lv.glstore_prg,
lv.extrefc_framesets, lv.extrefc_instances, lv.extrefc_attachments, 
lv.extrefc_links,lv.flags, lv.mask,lv.order, lv.lifetime, lv.origw, lv.origh,
lv.storage_source and string.gsub(lv.storage_source, "\\", "\\\\") or "",
lv.props.opa,
lv.props.position[1], lv.props.position[2], lv.props.position[3], 
lv.origw * lv.props.scale[1], lv.props.scale[2], lv.origh * lv.props.scale[3], 
lv.props.rotation[1], lv.props.rotation[2], lv.props.rotation[3]
));
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
	
	wnd:resize(props.width + 20, props.height + 20);
end

function samplewnd_update(self, smpl)
	delete_image(self.smplvid);
	if (smpl == nil) then
		smpl = badsample( self.lastid );
	end

	self.smplvid = render_sample(smpl);
	wnd_link(self, self.smplvid);
end

--
-- Set a representative color based on the complexity of the object
--
function vobjcol(smpl)
	if (smpl == nil) then
		return 0, 255, 0;
	else
		return 255, 0, (string.find(smpl.flags, "clone") ~= nil and 255 or 0);
	end
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
	local wnd = awbwman_spawn(menulbl("AllocMap:" .. tostring(context) .. 
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
end

function spawn_benchmark(smpl)
	local wnd = awbwman_spawn(menulbl("Benchmark:" .. tostring(context) ..
	tostring(smpl.display.ticks)));

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
end

function spawn_allocmap(smpl, context)
	local wnd = awbwman_spawn(menulbl("AllocMap:" .. tostring(context) .. 
		tostring(smpl.display.ticks)));

	local bitmap = {};
	local ul     = smpl.vcontexts[context].limit;
	local npix   = math.floor(math.sqrt(ul));
	local ofs    = 1;
	local smplofs= 1;
	local rows   = 0;
	local odd    = false;

	while (smplofs <= ul) do
		for col=1,npix*2 do
			if (col % 2 == 0 or odd == true) then
				bitmap[ofs  ] = 0;
				bitmap[ofs+1] = 0;
				bitmap[ofs+2] = 0;
				ofs = ofs + 3;
			else
				local r, g, b = vobjcol(smpl.vcontexts[context].vobjs[smplofs]);
				bitmap[ofs   ] = r;
				bitmap[ofs +1] = g;
				bitmap[ofs +2] = b;
				ofs = ofs + 3;
				smplofs = smplofs + 1;
			end
		end

		odd  = not odd;
		rows = rows + 1;
	end

	local vid = raw_surface(npix * 2, rows, 3, bitmap);
	image_texfilter(vid, FILTER_NONE);
	if (vid ~= BADID) then
		wnd:update_canvas(vid, false);
	end
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
	elseif (sym == "F3") then
		print("switch context down");
	elseif (sym == "SHIFTF3") then
		print("switch context down");
	elseif (sym == "F4") then
		spawn_context(self.smpl, self.context);
	elseif (sym == "F5") then
		spawn_vidinf(self.smpl, self.smpl.display);
	elseif (sym == "F6") then
		print("benchmark");
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
end

--
-- Whenever we want a new sample, set process_sample to true
-- When parent sends one, it gets rendered to an image and set
-- as the canvas of a new window
--
function sample(smpl)
	if (state.process_sample == false) then
		return;
	end

	if (state.delta_sample) then
	else
		spawn_sample(smpl, 1, 0);
	end

	state.process_sample = false;
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
function awbmon_input(iotbl)
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
