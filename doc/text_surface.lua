-- text_surface
-- @short: Create a simplified text video object
-- @inargs: int:rows, int:cols, vid:inplace, table:rowtable
-- @inarg: int:rows, int:cols, table:rowtable
-- @outargs: vid
-- @longdescr: This creates a surface that is backed by a TUI screen of *rows* and *cols*
-- maximum dimensions. It works as a cheaper form of ref:render_text as a way of retaining
-- text contents for later querying and modification, without the parsing complexity and
-- volatility of ref:render_text.
--
-- The contents of *rowtable* is a table for each row to populate, with an optional int:y
-- and int:x to skip to specific positions to avoid having a number of empty cells.
-- Each n-indexed entry in the *rowtable* can be either a string or an attribute table
-- which are covered below.
--
-- This is marked experimental still as some details are yet to be fleshed out and subject
-- to change, mainly how one can alter the internal font representation (currently uses
-- the set default system font), get feedback on shaped line offsets, query for picking,
-- shaping, processing direction and ligature substitutions.
--
-- @tblent: bool:bold, bool:underline, bool:italic, bool:inverse, bool:underline,
-- bool:underline_alt, bool:strikethrough, bool:blink alters how the glyph visual appearance.
--
-- @tblent: int:id is a custom number for encoding reference to user data structures.
--
-- @tblent: int:fr, int:fg, int:fb, int:br, int:bg, int:bb changes the fg/bg colour.
--
-- @tblent: int:fc, int:fb switches to palette indexed colours which takes priority over
-- the rgb forms. The palette indices match those used in TUI.
--
-- @experimental
-- @group: image
-- @cfunction: textsurface
-- @related: render_text
function main()
#ifdef MAIN
	show_image(text_surface(1, 10, {{"hi there"}}))
#endif

#ifdef MAIN2
	show_image(text_surface(1, 10, {{"hi", {bold = true, fr = 255, fg = 0, fb = 0}, "there"}})
#endif

#ifdef ERROR1
#endif
end
