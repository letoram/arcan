-- define_calctarget
-- @short: Create a rendertarget with a periodic readback into a Lua callback
-- @inargs: dest_buffer, vid_table, detach, scale, samplerate, callback
-- @outargs:
-- @longdescr: This function inherits some of its behavior from
-- ref:define_rendertarget. Please refer to the description of that function
-- for assistance with the *detach*, *scale* and *samplerate* functions.
--
-- The *callback* will follow the prototype function(image, width, height)
-- where *image* is a table with the following functions:
--
-- . get (x, y, [nchannels=1]) => r, [g, b, a]
-- . histogram_impose (destination, *int:mode*, *bool:norm*, *int:dst_row*)
-- . frequency (bin, *int:mode*, *bool:normalize*) => r,g,b,a
--
-- The *get* function can be used to sample the value at the specified
-- coordinates (x,y) that must be 0 <= x < width, 0 <= y < height. Other
-- values will result in a terminal state transition. For the *nchannels*
-- argument, the permitted values 1,3,4 and will determine the number
-- of returned channels.
--
-- The *histogram_impose* function will generate a histogram and store
-- in the first row (or, if provided, *dst_row*) of *destination*,
-- which subsequently must have at least a width of 256 pixels and at
-- least *dst_row* number of rows, 0-indexed.
--
-- The *frequency* function will return the number of occurences from
-- a specific histogram bin and *bin* should be 0 <= n < 256. The optional
-- *normalize* argument, default to true, will normalize against the
-- max- bin value per channel.
--
-- For both *histogram_impose* and *frequency* the possible *mode* values
-- are HISTOGRAM_SPLIT (treat R, G, B, A channels as separate),
-- HISTOGRAM_MERGE (treat R, G, B, A as packed and merge into one bin)
-- or HISTOGRAM_MERGE_NOALPHA (treat R, G, B as packed and ignore A)
-- @note: The *callback* will be executed as part of the main loop
-- and it is paramount that the processing done is kept to a minimum.
-- @note: When the *samplerate* is set to 0 for a calctarget, both
-- ref:rendertarget_forceupdate and ref:stepframe target need to be called
-- in order to update the contents and issue a readback.
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

#ifdef ERROR
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
