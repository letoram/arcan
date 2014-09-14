-- cursor_setstorage
-- @short: Use the storage defined by one video object as
-- an accelerated mouse cursor.
-- @inargs: vid
-- @longdescr: There are two options for maintaing a mouse cursor.
-- One is to manually manipulate an image, with the problem of
-- adding additional 'dirty updates' (and a mouse can be a high-
-- frequency sample-rate input device) that causes a full and
-- expensive redraw, and the image also needs to be manually kept
-- on top. The other is a specialized engine path, which this
-- class of functions is used for.
-- @note: The selection criterion for the object used as
-- cursor storage is similar to that of image_sharestorage.
-- @group: image
-- @cfunction: cursorstorage
-- @related: cursor_position, nudge_cursor, resize_cursor, move_cursor
function main()
#ifdef MAIN
	curs = fill_surface(8, 8, 255, 0, 0);
	cursor_setstorage(curs);
#endif
end
