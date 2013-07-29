--
-- Minimalistic example monitor script for debugging
-- another arcan instance from the prelaunch/monitorstep
-- -M 100 -O monitor.lua
--
-- For a more advanced use awbmon.lua
--

ignore_samples = false;

function monitor()
	symtable = system_load("scripts/symtable.lua")();
	sample_root = fill_surface(1,1,0,0,0);
end

function setup_sample_view(smpl)
	delete_image(sample_root);
	ignore_samples = true;
	csample = smpl;

-- reset these
	context = 1;
	rtarget = 1;
	vobj    = 1;
		
-- global display settings
	img = render_text(string.format("\\ffonts/default.ttf,12" .. 
" Ticks:\\t%d\\n\\r" .. 
" Display:\\t%d x %d\\n\\r" ..
" Conserv:\\t%d\\n\\r" ..
" Vsync:\\t%d\\n\\r" ..
" MSA:\\t%d\\n\\r" ..
" Vitem:\\t%d\\n\\r" ..
" Imageproc:\\t%d\\n\\r" ..
" Scalemode:\\t%d\\n\\r" ..
" Filtermode:\\t%d\\n\\r" .. 
"", smpl.display.ticks, smpl.display.width, smpl.display.height,
smpl.display.conservative, smpl.display.vsync, smpl.display.msasamples,
smpl.display.ticks, smpl.display.default_vitemlim, smpl.display.imageproc,
smpl.display.scalemode, smpl.display.filtermode));
	local props = image_surface_properties(img);
	move_image(img,VRESW - props.width, 0);
	show_image(img);
	sample_root = img;

	do_context();
	do_vobj();
end 

function do_context()
	if (valid_vid(cimg)) then
		delete_image(cimg);
	end

-- contexts
	cimg = render_text(string.format("\\ffonts/default.ttf,12" ..
" Context:\\t%d / %d\\n\\r" ..
" Rtargets:\\t%d\\n\\r" ..
" Vobjects:\\t%d (%d) / %d\\n\\r" ..
" Last Tick:\\t%d\\n\\r" ..
"", context, #csample.vcontexts, 
#csample.vcontexts[context].rtargets,
csample.vcontexts[context].alive,
#csample.vcontexts[context].vobjs,
csample.vcontexts[context].limit,
csample.vcontexts[context].tickstamp));
	
	if (valid_vid(helpimg)) then
		move_image(cimg, image_surface_properties(helpbg).width, 0);
	end

	show_image(cimg);
end

function sample(sampletbl)
	if (ignore_samples == true) then
		return;
	end

	setup_sample_view(sampletbl);
end

function toggle_help()
	if (valid_vid(helpimg)) then
		delete_image(helpimg);
		delete_image(helpbg);
		helpimg = nil;
		if (valid_vid(cimg)) then
			move_image(cimg, 0, 0);
		end
		return;
	end
	
	helpimg = render_text([[\ffonts/default.ttf,12 Default Monitor Script Helper
\n\rn\r
F1\tToggle help\n\r
F2\tWait for new sample\n\r
F3\tDelta sample\n\r
F4\tShow tree view\n\r
F5\tShow allocation map\n\r
F6\tSwitch context up\n\r
F7\tSwitch context down\n\r
Up/Down\t move to parent / child \n\r
Left/Right\t step to previous/next object in context \n\r 
Shift+L/R\t step to previous/next sibling to obj \n\r 
Escape\t shut down\n\r
]]);
	local props = image_surface_properties(helpimg);
	helpbg = fill_surface(props.width * 1.1, props.height * 1.1, 20, 20, 20);
	link_image(helpimg, helpbg);
	image_inherit_order(helpimg);
	order_image(helpbg, max_current_image_order());
	order_image(helpimg, 1);
	show_image({helpimg, helpbg});

	if (valid_vid(cimg)) then
		move_image(cimg, props.width * 1.1, 0);
	end
end

function do_vobj()
	if (valid_vid(vobjimg)) then
		delete_image(vobjimg);
	end

	local lv = csample.vcontexts[context].vobjs[vobj];

	if (lv == nil) then
		return;
	end

	vobjimg = render_text(string.format(
"\\ffonts/default.ttf,12 Vobj(%d)=>(%d), Parent: %d Tag: %s\\n\\r" ..
"GL(Id: %d, W: %d, H: %d, BPP: %d, TXU: %d, TXV: %d, Refcont: %d\\n\\r" ..
"Frameset( %d, %d / %d:%d )\\n\\r" ..
"Scale: %s\\tFilter: %s\\tProc: %s\\tProgram: %s\\n\\r" ..
"#FrmRef: %d\\t#Inst: %d\\t#Attach: %d\\t#Link: %d\\n\\r" ..
"Flags: %s\\n\\r" .. 
"Mask: %s\\n\\r" .. 
"Order: %d\\tLifetime: %d\\tOrigW: %d\\tOrigH: %d\\n\\r" ..
"Source: %s\\n\\r" ..
"Opacity: %.2f\\n\\r" ..
"Position: %.2f, %.2f\\tSize: %.2f %.2f\\tOrientation: %.2f degrees\\n\\r",
lv.cellid, lv.cellid_translated, lv.parent, lv.tracetag, 
lv.glstore_glid and lv.glstore_glid or 0, lv.glstore_w, lv.glstore_h, lv.glstore_bpp, lv.glstore_txu, lv.glstore_txv, lv.glstore_refc and lv.glstore_refc or 0, 
lv.frameset_mode, lv.frameset_counter, lv.frameset_capacity, lv.frameset_current,
lv.scalemode, lv.filtermode, lv.imageproc, lv.glstore_prg,
lv.extrefc_framesets, lv.extrefc_instances, lv.extrefc_attachments, lv.extrefc_links,
lv.flags,
lv.mask,
lv.order, lv.lifetime, lv.origw, lv.origh,
string.gsub(lv.storage_source, "\\", "\\\\"),
lv.props.opa,
lv.props.position[1], lv.props.position[2], 
lv.origw * lv.props.scale[1], lv.origh * lv.props.scale[2], 
lv.props.rotation[1]
));

	show_image(vobjimg);

	print(lv.parent);

	local yofs = image_surface_properties(img).height;
	move_image(vobjimg, 0, math.floor(VRESH * 0.5));
end

function step_vobj(num)
	count = csample.vcontexts[context].limit;

-- linear search for next allocated vobj as we might have holes 
	while (count > 0) do
		vobj = vobj + num;
		vobj = vobj > csample.vcontexts[context].limit and 1 or vobj;
		vobj = vobj < 1 and csample.vcontexts[context].limit or vobj;
		count = count - 1;
		if (csample.vcontexts[context].vobjs[vobj] ~= nil) then
			break;
		end
	end

	do_vobj();
end

function step_sibling(num)
	local lim    = csample.vcontexts[context].limit;
	local cur    = vobj + num;
	local count  = lim;
	local parent = csample.vcontexts[context].vobjs[vobj].parent;

	while (vobj ~= cur and count > 0) do
		cur = cur + num;
		count = count - 1;

		if (cur <= 0) then
			cur = lim;
		elseif (cur > lim) then
			cur = 1;
		end

		local cvo = csample.vcontexts[context].vobjs[cur];
		if (cvo and cvo.parent == parent) then 
			vobj = cur;
			do_vobj();
			return;
		end
	end

end

function step_parent()
	if (csample.vcontexts[context].vobjs[vobj].parent ~= 0) then
		vobj = csample.vcontexts[context].vobjs[vobj].parent;
		do_vobj();
	end
end

function step_child()
	local lim    = csample.vcontexts[context].limit;
	local cur    = vobj + 1;
	local count  = lim;
	local parent = csample.vcontexts[context].vobjs[vobj].parent;

	while (vobj ~= cur and count > 0) do
		cur = cur + 1;
		count = count - 1;

		if (cur > lim) then
			cur = 1;
		end

		local cvo = csample.vcontexts[context].vobjs[cur];
		if (cvo and cvo.parent == vobj) then 
			vobj = cur;
			do_vobj();
			return;
		end
	end
end

function cycle_rtarget(num)
end

function step_context(num)
	context = context + num;
	context = context > #csample.vcontexts and 1 or context
	context = context < 1 and #csample.vcontexts or context
	do_context();
	step_vobj(1);
end

shift_state = false;

keyhandler = {};

keyhandler["F1"] = toggle_help;
keyhandler["F2"] = function() ignore_samples = false; end
keyhandler["F3"] = function() print("implement delta frame"); end
keyhandler["F4"] = function() print("delta plot"); end
keyhandler["F5"] = function() allocation_map(); end  
keyhandler["F6"] = function() step_context(-1); end
keyhandler["F7"] = function() step_context(1);  end

keyhandler["RIGHT"] = function() 
	if (shift_state) then
		step_sibling(1);
	else
		step_vobj(1);
	end
end

keyhandler["LEFT"] = function()
	if (shift_state) then
		step_sibling(-1);
	else
		step_vobj(-1);
	end
end

keyhandler["UP"] = function()
	step_parent();
end

keyhandler["DOWN"] = function()
	step_child();
end

keyhandler["ESCAPE"] = shutdown;

function monitor_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.translated) then
		local sym = symtable[iotbl.keysym];

		if (sym == "LSHIFT" or sym == "RSHIFT") then
			shift_state = iotbl.active;

		elseif (iotbl.active and keyhandler[sym]) then
			keyhandler[sym]();
		end
	end
end

