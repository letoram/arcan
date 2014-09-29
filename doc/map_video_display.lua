-- map_video_display
-- @short: Specify virtual displays to physical displays mapping.
-- @inargs: vid, dispid
-- @outargs: success_bool
-- @longdescr: video_displaymodes provides a list of devices, outputs
-- and modes. This function provides the option to specify which
-- higher-level abstractions (video-objects) that are mapped to
-- each output. Note that vid can be any video object with a valid,
-- textured, backing store (including rendertargets, WORLDID or a
-- null_surface that subsamples a region of WORLDID).
-- @group: vidsys
-- @cfunction: videomapping
-- @related:
function main()
#ifdef MAIN
	resize_video_canvas(640, 480);

	img_1 = fill_surface(320, 200, 255, 0, 0);
	img_2 = fill_surface(320, 200, 0, 255, 0);
	img_3 = fill_surface(320, 200, 0, 0, 255);
	img_4 = fill_surface(320, 200, 255, 0, 255);
	show_image({img_1, img_2, img_3, img_4});
	move_image(img_2, 320, 0);
	move_image(img_3, 0, 200);
	move_image(img_4, 320, 200);

	a = null_surface(640, 480);
	move_image(a, 320, 240, 1000);
	image_sharestorage(WORLDID, a);

	outputs = {};
	list = video_displaymodes();

	uniq = 0;
	for i,v in ipairs(list) do
		if (outputs[v.displayid] == nil) then
			outputs[v.displayid] = v;
			uniq = uniq + 1;
		end
	end

	if (uniq < 2) then
		return shutdown("insufficient outputs");
	end

	local first = nil;
	local second = nil;

	for k,v in pairs(list) do
		if (first == nil) then
			first = k;
		elseif (second == nil and k ~= first) then
			second = k;
			break;
		end
	end

	if (second == nil) then
		return shutdown("no secondary display output found.");
	end

	map_video_display(first, WORLDID);
	map_video_display(second, next_a);
#endif

#ifdef ERROR1
	map_video_display("random", WORLDID);
#endif
end
