-- define_calctarget
-- @short: Create an offscreen rendering pipeline with a readback to a callback function.
-- @inargs: dstvid, vidary, detacharg, scalearg, samplerate, callback
-- @outargs:
-- @longdescr: This function creates a separate rendering pipeline populated with the set
-- of VIDs passed in the indexed table *vidary*. The output of processing this pipeline
-- will be stored in *dstvid* and issue a readback at *samplerate*. A positive samplerate
-- will retrieve a sample every 'n' logical ticks, a negative samplerate will retrieve a
-- sample every abs(n) rendered frames. If samplerate is set to the special constant
-- READBACK_MANUAL, the stepframe_target function has to be invoked for each time
-- a readback should be issued.
--
-- The callback will be invoked with three arguments: image, width, height
-- the following metamethods are valid on image:
-- get(x, y, [nchannels=3]) => r, g, b
-- nchannels=1 => lum
-- histogram_storage(dstvid, [noreset])
--  updated the textured storage of dstvid (must be allocated with
--  a width of >= 256. If noreset is !0, an update on a dirty histogram
--  calculation will not reset the individual bins, thus values will accumulate.
-- frequency(bin, [noreset]) => r,g,b,a
--  return non-normalized, per / channel count for a specific bin (0..255)
--
-- @note: The callback will be executed as part of the main loop,
-- it is paramount that the processing done is kept to a minimum.
-- @note: While WORLDID cannot be used directly, creating an indirect association
-- through a null_surface and then image_sharestorage(WORLDID, null_surface) and
-- using that as a source in vidary is entirely possible.
-- @note: setting RENDERTARGET_DETACH as detacharg means that the object will no-longer
-- be associated with the main rendering pipeline.
-- @note: setting RENDERTARGET_SCALE will calculate a transform to maintain relative
-- size and positioning to the main pipeline, even if the storage *dstvid* has different
-- dimensions.
-- @note: Using the same object for *dstvid* and as member of *vidary* results
-- in undefined contents in the offscreen target.
-- @group: targetcontrol
-- @cfunction: procset
-- @examples: histoview
-- @related: define_rendertarget, define_recordtarget, fill_surface
function cbfun(source, w, h)
	print(srcary:get(0, 0));
end

function main()
	dstvid = fill_surface(64, 64, 0, 0, 0, 64, 64);
	srcvid = color_surface(64, 64, 255, 128, 64);

#ifdef MAIN
	define_calctarget(dstvid, {srcvid}, RENDERTARGET_DETACH,
		RENDERTARGET_SCALE, 10, cbfun);

	show_image(srcvid);
	show_image(dstvid);
#endif

#ifdef ERROR1
	define_calctarget(WORLDID, {srcvid}, RENDERTARGET_DETACH,
	RENDERTARGET_SCALE, 10, cbfun);
#endif

#ifdef ERROR2
	define_calctarget(dstvid, {srcvid, WORLDID}, RENDERTARGET_DETACH,
	RENDERTARGET_SCALE, 10, cbfun);
#endif

#ifdef ERROR3
	define_calctarget(dstvid, {srcvid}, RENDERTARGET_DETACH,
		RENDERTARGET_SCALE, 10, define_calctarget);
#endif
end
