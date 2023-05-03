function rtdensity()
	symtable = system_load("builtin/keyboard.lua")();
	rt_1 = alloc_surface(VRESW, VRESH * 0.5);
	rt_2 = alloc_surface(VRESW, VRESH * 0.5);
	move_image(rt_2, 0, VRESH * 0.5);
	img_1 = render_text([[\fdefault.ttf,20 Hi There, Lolita.]]);
	img_2 = render_text([[\fdefault.ttf,20 Hi There, Fat Man.]]);
	show_image({rt_1, rt_2, img_1, img_2});
	define_rendertarget(rt_1, {img_1});
	define_rendertarget(rt_2, {img_2});
	set_context_attachment(rt_2);
	start = true;
end

delta = 0;
function rtdensity_input(iotbl)
	if (iotbl.digital and iotbl.active) then
		local label = symtable.tolabel(iotbl.keysym)
		if (iotbl.translated and label) then
			if (label == "m") then
				print("switching to 1");
				local lst = rendertarget_vids(rt_2);
				for k,v in ipairs(lst) do
					rendertarget_attach(rt_1, v, RENDERTARGET_DETACH);
				end
				return;
			end
		end
		delta = delta + 2;
		local rtd1w = math.random(20, 40);
		local rtd1h = math.random(20, 40);
		local rtd2w = math.random(60, 90);
		local rtd2h = math.random(60, 90);
		rendertarget_reconfigure(rt_1, rtd1w, rtd1h);
		rendertarget_reconfigure(rt_2, rtd2w, rtd2h);
		print("new densities: rt1: ", rtd1w, rtd1h, " rt2: ", rtd2w, rtd2h);
		if (start) then
			start = false;
			rendertarget_attach(rt_1, img_2, RENDERTARGET_DETACH);
			rendertarget_attach(rt_2, img_1, RENDERTARGET_DETACH);
			else
			start = true;
			rendertarget_attach(rt_1, img_1, RENDERTARGET_DETACH);
			rendertarget_attach(rt_2, img_2, RENDERTARGET_DETACH);
		end
		local img, lh, w, h = render_text([[\fdefault.ttf,20 ]] .. tostring(CLOCK));
		move_image(img, math.random(1, VRESW - w), math.random(1, VRESH - h));
		show_image(img);
	end
end
