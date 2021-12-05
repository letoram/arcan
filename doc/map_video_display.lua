-- map_video_display
-- @short: Specify virtual object to output mapping.
-- @inargs: vid:src, number:display
-- @inargs: vid:src, number:display, number:blithint, number:layer_index
-- @inargs: vid:src, number:display, number:blithint, number:layer_index, number:x, number:y
-- @outargs: bool:success, number:free_layers
-- @longdescr: This functions updates the mapping between a higher level
-- visual object *src* and an output *display*. This includes the currently
-- set shader, custom texture coordinates and so on.
-- The optional *blithint* argument (default: HINT_NONE) can be one of the
-- following: HINT_FIT, HINT_CROP, HINT_ROTATE_CW_90, HINT_ROTATE_CCW_90,
-- HINT_YFLIP. It is also possible to OR it with the optional HINT_PRIMARY.
-- FIT and CROP determine the strategy to deal with for the case where the
-- current mode on the *display* fail to match the storage dimensions of *src*.
-- YFLIP, ROTATE_CW_90, ROTATE_CCW_90 deals with outputs that can have a
-- varying physical rotation and supports accelerated mapping.
-- HINT_PRIMARY tells the platform layer that the synchronisation to the
-- display SHOULD be prioritized in the case of multiple displays.
-- The function returns *true* if the object was successfully mapped to
-- the display, and *false* if the underlying platform rejected it for some
-- reason, as not all outputs can accept all kinds of sources or an arbitrary
-- number of layers.
-- It will also return the maximum number of currently free mapping layers,
-- this is not a guarantee that a certain object can be mapped to a higher layer,
-- the combination need to be tested for the current combination of screens,
-- resolutions and mappings.
-- Providing a *layer_index* along with an *x* and *y* coordinate allows
-- multiple objects to be mapped to the same logical output and composited
-- accordinly.
-- For layers higher than zero, additional hint flags can be set:
--
-- HINT_CURSOR - the layer will be treated as a cursor layer and implies
-- alpha blending. This may be updated out of the normal processing pipeline
-- and as part of a raw input handler where other graphics functions might
-- be unavailable.
--
-- There is also an experimental HINT_DIRECT flag that, if set, will disable
-- any platform controlled heuristic between direct scanout and forced
-- composition. This is an optimization that has a number of driver and backend
-- bugs still. For normal/simple display configurations it is likely to work,
-- but with edge cases for multi-display hotplug, rotated secondary displays
-- and so on. This is marked experimental, but if the feature is deprecated
-- that flag will simply resolve to 0 so it is API-wise safe for use. The
-- caveats should be conveyed to a user.
--
-- @note: A *src* referencing an object with a feed- function, such as
-- one coming from ref:define_recordtarget, ref:define_calctarget and so
-- on, is a terminal state transition.
-- @note: Multiple output paths with varying performance characteristics
-- may apply here, including forced repacking stages that are very costly.
-- Avoid using custom texture coordinate sets, custom shaders or using the
-- *src* object as part of other rendering operations to ensure that any
-- fast scanout path can be applied.
-- @note: A rendertarget as *src* has a different coordinate transform
-- when going from 'as a texture' to 'as an output' behavior and may end
-- up inverted. The engine will attempt to account for this, but only if
-- no custom texture coordinate set has been defined for the object.
-- @note: When calling ref:map_video_display with a rendertarget as src, its
-- projection transform may be rebuilt. This will override any coordinate
-- system changes made by ref:image_resize_storage which then needs to be
-- repeated.
-- @note: Mapping the same rendertarget to multiple displays is undefined
-- behaviour. The reason is that the backing store of *src* might need to
-- mutate to fit the scanout characteristics of *display*. Even for the same
-- display, these ted to have slight changes that make sharing semantics have
-- subtle edge cases that are hard to predict. The best workaround for this is
-- to create additional rendertargets through ref:define_linktarget.
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
