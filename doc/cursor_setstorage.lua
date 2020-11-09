-- cursor_setstorage
-- @short: Use the storage defined by one video object as an accelerated mouse
-- cursor.
-- @inargs: vid, *txcos*
-- @longdescr: This function works like ref:image_sharestorage but with the
-- target destination being the accelerated overlay cursor render path.
-- The optional *txcos* argument should (if present) be an integer indexed
-- table with exactly 8 elements where each element (n) is 0 <= n <= 1
-- specifying [ul_x, ul_y, ur_x, ur_y, lr_x, lr_y, ll_x, ll_y]. This can be
-- used as a cheaper way of animating cursors or packing many cursors in the
-- same vid.
-- @note: using cursor_setstorage(WORLDID) will disable the accelerated
-- cursor path.
-- @group: image
-- @cfunction: cursorstorage
-- @related: cursor_position, nudge_cursor, resize_cursor, move_cursor
function main()
#ifdef MAIN
	curs = fill_surface(8, 8, 255, 0, 0);
	cursor_setstorage(curs);
	resize_cursor(16, 16);
	move_cursor(VRESW * 0.5, VRESH * 0.5);
#endif
end
