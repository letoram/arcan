-- imagetest
-- whole bunch of features we want to run through here.
--
-- Basic image loading and deletion are tested in the others, so skip that.
-- Same with picking (internaltest)
--
-- Advanced features, e.g. multiple frames, vid stack push / pop
-- Transformation chains
-- Safety harness for unreasonably sized images (> 8kx8k pixels, 0x0 and negative dimensions)
-- Instancing (huge numbers)
-- Linking objects and inherited coordinate spaces
-- Z ordering
-- Override translation origo
-- Shaders
--

aimg = BADID;
text_vid = BADID;
imagefun = load_image;
stacksize = 1024;

function imagetest()
	local symfun = system_load("builtin/keyboard.lua");
	symtable = symfun();
	drawmenu();

--	system_load("scripts/3dsupport.lua")();
--	load_shader("test.vShader", "test.fShader", "test", {});
end

-- Using persist, so draw once and present in all contexts.
function drawmenu()
	local total, used = current_context_usage();
	system_load("builtin/legacy.lua")();
	text_vid = render_text( [[\ffonts/default.ttf,14\#ffffff\bImagetest:\n\r]] ..
	[[\b\!i(1)\t\!binstancing test\n\r]] ..
	[[\b\!i(2)\t\!border + transform-stress test\n\r]] ..
	[[\b\!i(3)\t\!bvid limit test\n\r]] ..
	[[\b\!i(4)\t\!bdouble stacksize (current: ]] .. used+1 .. " / " .. total .. [[\n\r]] ..
	[[\b\!i(s)\t\!bstack push\n\r]] ..
	[[\b\!i(p)\t\!bstack pop\n\r]] ..
	[[\b\!i(r)\t\!bandom surface\n\r]] ..
	[[\b\!i(l)\t\!bload image into context\n\r]] ..
	[[\b\!i(a)\t\!btoggle asynchronous image_load\n\r]] ..
	[[\b\!i(d)\t\!bstack push store\n\r]] ..
	[[\b\!i(f)\t\!bstack pop store\n\r]] ..
	[[\iESCAPE\t\!ishutdown\n\r]] );

	sprop = image_surface_properties(text_vid);
	move_image(text_vid, VRESW - sprop.width - 10, 0, 0);
	show_image(text_vid);
	order_image(text_vid, 255);

	print("persisting menu, status: ", tostring(persist_image(text_vid)));
end

function zordervidlim(load)
	local step = 254.0 / stacksize;

	for i=1,stacksize-10 do
		print (" --> generated # " .. tostring(i));

		local newid;
		if (load) then
			 newid = imagefun("imagetest.png", 0);
			 image_tracetag(newid, "new_image");
			 move_image(newid, math.random( VRESW - 16), math.random( VRESH - 16), 0);
			 resize_image(newid, 64, 64, 0);
		else
			newid = fill_surface(64, 64, step * i, step * i, 255);

			order_image(newid, math.floor ( i * step ));
			for j=1,254 do
				rotate_image(newid, math.random(360), 10);
			end
		end

		move_image(newid, math.random( VRESW - 16), math.random( VRESH - 16), 0);

		if (newid == BADID) then
			break;
		end

		show_image(newid);
	end
end

local function instance_image(newid)
	local res = image_surface_resolve(newid);
	local new = null_surface(res.width, res.height);
	image_sharestorage(newid, new);
	return new;
end

function instancing_test()
	local newid = fill_surface(64, 64, 0, 255, 0);
	move_image(newid, 0.5*VRESW - 32, 0.5*VRESH - 32, 0);
	show_image(newid);
	order_image(newid, 255);

	for  j=1,20 do
		local instid = instance_image(newid);
		order_image(instid, 254);
		scale_image(instid, 0.5, 0.5, 0);
		image_mask_clear(instid, MASK_SCALE);
		blend_image(instid, 0.5);

		if (instid == BADID) then
			break;
		end

		for j=1,254 do
			move_image(instid, math.random(-128, 128), math.random(-128, 128), 20);
		end
	end

	for j=1,254 do
		move_image(newid, math.random(VRESW), math.random(VRESH), 20);
	end
end

function imagetest_input(inputtbl)
	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		local label = symtable.tolabel(inputtbl.keysym)
		if (label == "ESCAPE") then
			shutdown();
		elseif (label == "1") then
			print("Running instancing test");
			instancing_test();
		elseif (label == "2") then
			print("Running Z order/limit test");
			zordervidlim(false);
		elseif (label == "3") then
			print("Running image loading stress");
			zordervidlim(true);
		elseif (label == "4") then
			print("Double stacksize for next layer");
			stacksize = stacksize * 2;
			system_context_size(stacksize);
		elseif (label == "l") then
			print("Loading image into context");
			local vid = imagefun("imagetest.png");
			resize_image(vid, 64, 64);
			move_image(vid, math.random(VRESW - 64), math.random(VRESH - 64), 0);
			order_image(vid, 0);
			show_image(vid);
		elseif (label == "s") then
			text_vid = BADID;
			print("Stack push => " .. tostring ( push_video_context() ) );
		elseif (label == "d") then
			num, vid = storepush_video_context();
			show_image(vid);

			print("Stack push store => " .. tostring(num) .. " => " .. tostring(vid));
		elseif (label == "f") then
			num, vid = storepop_video_context();
			show_image(vid);
			print("Stack pop store => " .. tostring(num) .. " => "  .. tostring(vid));
		elseif (label == "p") then
			print("Stack pop => " .. tostring ( pop_video_context() ) );
		elseif (label == "a") then
			print("Switching image mode\n");
			imagefun = imagefun == load_image and load_image_asynch or load_image
		elseif (label == "r") then
			local tbl = {};
			for i=1,(256 * 256) do
				table.insert(tbl, math.random(255));
				table.insert(tbl, math.random(255));
				table.insert(tbl, math.random(255));
			end
				vid = raw_surface(256, 256, 3, tbl);
				show_image(vid);
		end
	end
end

function imagetest_video_event(source, evtbl)
	if (evtbl.kind == "loaded") then
		resize_image(source, 64, 64);
		image_tracetag(source, "asynch_image");
	end

	print( "-- video event : " .. tostring(source) .. " => " .. evtbl.kind);
end

