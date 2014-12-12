-- fill_surface
-- @short: Allocate a new video object and fill with a single colour.
-- @inargs: objw, objh, r, g, b, *storew, *storeh
-- @outargs: vid
-- @longdescr: fill_surface act as a memory allocation function in the sense
-- that it creates a fully qualified video object, including texture store,
-- and is identical in capability to an image acquired from other sources,
-- e.g. load_image, but particularly useful for rendertargets, recordtargets
-- and similar functions that operate on an intermediate storage.
-- Current width/height and initial width/height will be set to
-- *objw* and *objh*. The range for r, g, b are unsigned 8-bit (0..255) and
-- the optional *storew* and *storeh* arguments define the actual storage
-- dimensions.
-- @note: storew and storeh are subject to the limit of MAX_SURFACEW and
-- MAX_SURFACEH, these are compile-time constants and attempting to exceed
-- these values is a terminal state transition.
-- @note: objw and objh are expected to be > 0, setting these to an invalid
-- value, i.e. <= 0 is a terminal state transition.
-- @related: null_surface, raw_surface, color_surface
-- @group: image
-- @cfunction: fillsurface
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0, 32, 64);
	b = fill_surface( 1,  1,   0, 0, 0);
	c = fill_surface( 1,  1,   0, 0, 0, 32);
#endif

#ifdef WARNING
	a = fill_surface(32, 32, 0.45, 0, 0);
#endif

#ifdef ERROR
	a = fill_surface(-1, 32, 255, 0, 0);
#endif

#ifdef ERROR2
	a = fill_surface(32, 32,  0, 0, 0, 65535, 65535);
#endif
end
