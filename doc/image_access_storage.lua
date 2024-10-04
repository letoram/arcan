-- image_access_storage
-- @short: Access the underlying backing store of a textured video object.
-- @inargs: vid, callback(vtbl:context, int:width, int:height)
-- @inargs: vid, callback(vtbl:context, int:width, int:height, int:cols, int:rows)
-- @outargs: true or false
-- @longdescr: This function permits limited, blocking, access to a backing
-- store. The primary purpose is to provide quick access to trivial measurements
-- without the overhead of setting up a calctarget and performing readbacks.
-- The function returns false if the backing store was unavailable.
--
-- The *context* argument is described in ref:define_calctarget.
--
-- If the callback provides *cols* and *rows* it means that the table represents
-- a textual backing store rather than a pixel one. In that case the following
-- extra functions are available in *context*:
--
-- @tblent: read(int:col, int:row) = string:ch, table:format
-- @tblent: translate(int:x, int:y) = int:col, int:row
-- @tblent: cursor() = int:col, int:row
--
-- The read_px variant takes surface-local pixels with origo in upper-left
-- corner and resolves the corresponding row, col before forwarding to :read
--
-- The format_table returned by read contains the following:
-- @tblent: int:colors as "fr, fg, fb" and "br,
-- bg, bb" as well as one or more of "bold", "italic", "inverse", "underline",
-- "underline_alt", "protect", "blink", "strikethrough", "break",
-- "border_left", "border_right", "border_down", "border_top", "id".
-- It also contains "row_height" and "cell_width" for approximate rasterised
-- dimensions of the referenced cell.
--
-- @note: The table provided in the callback is only valid during the scope of
-- the callback, creating aliases outside this scope and trying to use any table
-- method is a terminal state transition that may be difficult to debug.
-- @note: Most frameserver connections do not synchronize the contents of the
-- backing store buffer due to the added bandwidth cost of performing an extra
-- copy each update. This behavior can be changed by calling target_flags and
-- enable TARGET_VSTORE_SYNCH for the specific frameserver.
-- @note: The backing store of a texture video object is not always available,
-- particularly when the engine is running in conservative mode. Make sure that
-- your appl can handle scenarios where the backing store cannot be read.
-- @note: :read is only permitted on a tui backed store. Calling it on a regular
-- one is a terminal state transition.
-- @group: image
-- @cfunction: imagestorage
-- @related: define_calctarget
function main()
#ifdef MAIN
	img = fill_surface(32, 32, 255, 0, 0);
	image_access_storage(a, function(tbl, w, h)
		print(w, h, tbl:get(1, 1));
	end);
#endif

#ifdef ERROR1
	img = fill_surface(32, 32, 255, 0, 0);
	image_access_storage(a, function(tbl, w, h)
		alias = tbl;
	end);
	alias:get(1, 1);
#endif

#ifdef ERROR2
	img = fill_surface(32, 32, 255, 0, 0);
	image_access_storage(a, image_access_storage);
#endif
end
