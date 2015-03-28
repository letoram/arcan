-- raw_surface
-- @short: Create a new surface using a table as input.
-- @inargs: width, height, bytes_per_pixel, input_table, *out_file*
-- @outargs: vid
-- @longdescr: This function creates a new 'raw' surface using user-supplied
-- values for pixel data. The internal representation is set to a compile-
-- time system default (typically RGBA888). If the optional *out_file*
-- argument is set, a PNG image will also be stored in the APPL_TEMP namespace.
-- Using an *out_file* is primarily intended as a debugging/developer feature
-- and the actual encode/store operation is synchronous.
-- @note: There might be a loss of precision imposed by the texture format
-- native to the system that is running.
-- @note: *width* and *height* should be within the compile-time constraints of
-- MAX_SURFACEW and MAX_SURFACEH, exceeding those dimensions is a terminal
-- state transition.
-- @note: Only acceptable *bytes_per_pixel* values are 1, 3 and 4. All others
-- are terminal state transitions.
-- @note: All *input_table* values will be treated as 8-bit unsigned integers.
-- @note: *input_table* is expected to have exactly width*height*bytes_per_pixel
-- values, starting at index 1. Any deviation is a terminal state transition.
-- @group: image
-- @cfunction: rawsurface
function main()
#ifdef MAIN
	local rtbl = {};
	local ofs = 1;

	for row=1,64 do
		for col=1,64 do
			rtbl[ofs+0] = math.random(255);
			rtbl[ofs+1] = math.random(255);
			rtbl[ofs+2] = math.random(255);
			ofs = ofs + 3;
		end
	end

	local vid = raw_surface(64, 64, 3, rtbl);
	show_image(vid);
#endif

#ifdef ERROR1
	local rtbl = {};
	raw_surface(32, 32, 3, rtbl);
#endif

#ifdef ERROR2
	local rtbl = {};
	raw_surface(MAX_SURFACEW * 2, MAX_SURFACEH * 2, 4);
#endif
end
