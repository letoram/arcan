-- map_video_display
-- @short: Specify virtual displays to physical displays mapping.
-- @inargs: vid, dispid, *blithint*
-- @outargs: success_bool
-- @longdescr: video_displaymodes provides a list of devices, outputs
-- and modes. This function provides the option to specify which
-- higher-level abstractions (video-objects) that are mapped to
-- each output. Note that vid can be any video object with a valid,
-- textured, backing store (including rendertargets, WORLDID or a
-- null_surface that subsamples a region of WORLDID).
-- Blithint can be any of (HINT_NONE, HINT_FIT, HINT_CROP, HINT_ROTATE_CW_90,
-- HINT_ROTATE_CCW_90, HINT_YFLIP) or:ed with the optional HINT_PRIMARY.
-- If PRIMARY is set, the platform will attempt to wait for synchronization
-- acknowledgement of one submitted update before sending the next. This can
-- reduce effective framerate to the least common denominator of all primary
-- flagged displays. The actual end-behavior is tied to the active synchronization
-- strategy, which is platform-defined.
-- @note: All sources are expected to have their Y coordinates inverted, with
-- origo in LL rather than UL, which is the case with rendertargets by default
-- but special consideration has to be taken for frameservers.
-- @note: Vid referencing an object with a feed- function
-- (recordtarget, frameserver, calctarget etc.) is a
-- terminal state transition
-- @note: Using this on arcan_lwa is a special case primarily intended
-- to test / debug display hotplugging and specific rendering effects
-- e.g. shaders, texture coordinates or blithint will not apply and
-- have to be performed manually through rendertargets. This mode will
-- also resize possible subsegments (which corresponds to displays)
-- to fit the dimensions of the backing store.
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

#ifdef ERROR
	map_video_display("random", WORLDID);
#endif
end
