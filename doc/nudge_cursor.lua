-- nudge_cursor
-- @short: Move the mouse cursor relative to its current position.
-- @inargs: d_x, d_y, *clamp*
-- @longdescr: if *clamp* is set to a non- zero value (default: 0)
-- the coordinates will NOT be clamped to fit the screen.
-- @group: image
-- @cfunction: cursornudge
-- @related:
-- @flags:
function main()
#ifdef MAIN
	move_cursor(VRESW * 0.5, VRESH * 0.5);
	print(cursor_position());
	nudge_cursor(15, -15);
	print(cursor_position());
#endif
end
