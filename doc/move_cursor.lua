-- move_cursor
-- @short: Set an absolute position for the mouse cursor.
-- @inargs: x, y, *clamp*
-- @longdescr: If clamp is set to a non-zero value (default, 0)
-- x and y will NOT be clamped to fit the screen.
-- @group: image
-- @cfunction: cursormove
-- @related: nudge_cursor, resize_cursor, cursor_setstorage, cursor_position
function main()
#ifdef MAIN
	print(cursor_position());
	local img = fill_surface(32, 32, 255, 0, 0);
	move_cursor(img, VRESW * 0.5, VRESH * 0.5);
	print(cursor_position());
#endif
end
