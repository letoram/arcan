-- define_calctarget
-- @short: Create an offscreen rendering pipeline with a readback to a callback function.
-- @inargs: dstvid, vidary, detacharg, scalearg, samplerate, callback
-- @outargs:
-- @longdescr: This function creates a separate rendering pipeline populated with the set
-- of VIDs passed in the indexed table *vidary*. The output of processing this pipeline
-- will be stored in *dstvid* and issue a readback at *samplerate*. A positive samplerate
-- will retrieve a sample every 'n' logical ticks, a negative samplerate will retrieve a
-- sample every abs(n) rendered frames.
--
-- The callback will be invoked with three arguments: image, width, height
-- the following metamethods are valid on image:
-- get(x, y, [nchannels=3]) => r, g, b,
-- nchannels=1 => lum
--
-- @note: The callback will be executed as part of the main loop, it is paramount that
-- the processing done is kept to a minimum.
-- @note: setting RENDERTARGET_DETACH as detacharg means that the object will no-longer
-- be associated with the main rendering pipeline.
-- @note: setting RENDERTARGET_SCALE will calculate a transform to maintain relative
-- size and positioning to the main pipeline, even if the storage *dstvid* has different
-- dimensions.
-- @group: targetcontrol
-- @cfunction: procset
-- @related: define_rendertarget, define_recordtarget, fill_surface
function main()
#ifdef MAIN
	dstvid = fill_surface(64, 64, 0, 0, 0, 64, 64);
	srcvid = color_surface(64, 64, 255, 128, 64);

	define_calctarget(dstvid, {srcvid}, RENDERTARGET_DETACH,
		RENDERTARGET_SCALE, 10,
	function(srcary, w, h)
		print(srcary:get(0, 0));
	end);

	show_image(srcvid);
	show_image(dstvid);
#endif

#ifdef ERROR1
#endif
end
