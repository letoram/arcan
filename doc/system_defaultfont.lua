-- system_defaultfont
-- @short: Set / Replace the current default font
-- @inargs: fontres, fontsz, fonth, *fallback*
-- @outargs: boolres, height, baseline,
-- @longdescr: For text rendering functions, some kind of font is needed.
-- The default font is set either by using this function, or indirectly
-- through the first ref:render_text call with an explicit font (\f) arg.
-- *fontres* is a string reference to a valid file in the SYS_FONT_RESOURCE
-- namespace, *fontsz* is the size argument as used in render_text and
-- *fonth* specifies anti-aliasing strength (0: disabled, 1: light, ...)
-- It is also possible to specify an additional *fallback* font that will
-- cover missing glyphs not found in *fontres*. The downside is that the
-- glyphs might not visually blend with the primary ones in a visually
-- appealing way, but may still be better than invisible characters.
-- @note: This is also implicitly updated in LWA arcan builds if it
-- receives a FONTHINT event from the display server connection, and
-- there is no event-trigger to detect if that occurs.
-- @group: system
-- @cfunction: setdefaultfont
-- @related:
function main()
#ifdef MAIN
	system_defaultfont("default.ttf", 12, 0);
#endif

#ifdef MAIN2

#endif
end
