ignore_samples = false;

function monitor()
	symtable = system_load("scripts/symtable.lua")();
	sample_root = fill_surface(1,1,0,0,0);
end

function setup_sample_view(smpl)
	delete_image(sample_root);
	ignore_samples = true;

-- global display settings
	img = render_text(string.format("\\ffonts/default.ttf,12" .. 
" Ticks:\\t%d\\n\\r" .. 
" Dimensions:\\t%d x %d\\n\\r" ..
"", smpl.display.ticks, smpl.display.width, smpl.display.height));
	local props = image_surface_properties(img);
	move_image(img,VRESW - props.width, 0);
	show_image(img);
	sample_root = img;
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
end


function step_vobj(num)
end

function cycle_rtarget(num)
end

function step_context(num)
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

