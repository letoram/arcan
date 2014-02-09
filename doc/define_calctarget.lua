-- define_calctarget
-- @short: Create an offscreen rendering pipeline with a readback to a callback function. 
-- @inargs: dstvid, vidary, detacharg, scalearg, samplerate, callback
-- @outargs: 
-- @longdescr: This function creates a separate rendering pipeline populated with the set 
-- of VIDs passed in the indexed table *vidary*. The output of processing this pipeline
-- will be stored in *dstvid* and issue a readback at *samplerate*. A positive samplerate
-- will retrieve a sample every 'n' logical ticks, a negative samplerate will retrieve a 
-- sample every abs(n) rendered frames.
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
	function(srcary)
		print(string.format("%d, %d, %d, %d"),
			string.byte(srcary,1), 
			string.byte(srcary,2), 
			string.byte(srcary, 3),
			string.byte(srcary, 4));
	end);

	show_image(srcvid);
	show_image(dstvid);
#endif

#ifdef ERROR1
#endif
end
