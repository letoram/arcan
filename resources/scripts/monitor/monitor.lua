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
F1\ttoggle help\n\r
F2\twait for new sample\n\r
Up/Down\t switch active context\n\r
Shift\t cycle rendertarget\n\r
Left/Right\t switch current video object\n\r
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
"\\ffonts/default.ttf,12 Vobj(%d)=>(%d), Tag: %s\\n\\r" ..
"GL(Id: %d, W: %d, H: %d, BPP: %d, TXU: %d, TXV: %d\\n\\r" ..
"Frameset( %d, %d / %d:%d )\\n\\r" ..
"Scale: %s\\tFilter: %s\\tProc: %s\\tProgram: %s\\n\\r" ..
"#FrmRef: %d\\t#Inst: %d\\t#Attach: %d\\t#Link: %d\\n\\r" ..
"Flags: %s\\n\\r" .. 
"Mask: %s\\n\\r" .. 
"Order: %d\\tLifetime: %d\\tOrigW: %d\\tOrigH: %d\\n\\r" ..
"Source: %s\\n\\r" ..
"Opacity: %d\\n\\r",  lv.cellid, lv.cellid_translated, lv.tracetag,
lv.glstore_id, lv.glstore_w, lv.glstore_h, lv.glstore_bpp, lv.glstore_txu, lv.glstore_txv,
lv.frameset_mode, lv.frameset_counter, lv.frameset_capacity, lv.frameset_current,
lv.scalemode, lv.filtermode, lv.imageproc, lv.glstore_prg,
lv.extrefc_framesets, lv.extrefc_instances, lv.extrefc_attachments, lv.extrefc_links,
lv.flags,
lv.mask,
lv.order, lv.lifetime, lv.origw, lv.origh,
string.gsub(lv.storage_source, "\\", "\\\\"),
lv.props.opa
));

	show_image(vobjimg);

	local yofs = image_surface_properties(img).height;
	move_image(vobjimg, 0, math.floor(VRESH * 0.5));
end

function step_vobj(num)
	count = #csample.vcontexts[context].vobjs;

-- linear search for next allocated vobj 
	while (count > 0) do
		vobj = vobj + num;
		vobj = vobj > #csample.vcontexts[context].vobjs and 1 or vobj;
		vobj = vobj < 1 and #csample.vcontexts[context].vobjs or vobj;
		count = count - 1;
		if (csample.vcontexts[context].vobjs[vobj] ~= nil) then
			break;
		end
	end

	do_vobj();
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

function monitor_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.translated and iotbl.active) then
		local sym = symtable[iotbl.keysym];
		if (sym == "F1") then
			toggle_help();
		elseif (sym == "F2") then
			ignore_samples = false;
		elseif (sym == "ESCAPE") then
			shutdown();
		elseif (sym == "LSHIFT" or sym == "RSHIFT") then
			cycle_rtarget();
		elseif (sym == "RIGHT") then
			step_vobj(1);
		elseif (sym == "LEFT") then
			step_vobj(-1);
		elseif (sym == "UP") then
			step_context(-1);
		elseif (sym == "DOWN") then
			step_context(1);
		end
	end
end

