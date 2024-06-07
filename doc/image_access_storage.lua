-- image_access_storage
-- @short: Access the underlying backing store of a textured video object.
-- @inargs: vid, callback(table, width, height)
-- @inargs: vid, callback(table, width, height, cols, rows)
-- @outargs: true or false
-- @longdescr: This function permits limited, blocking, access to a backing
-- store. The primary purpose is to provide quick access to trivial measurements
-- without the overhead of setting up a calctarget and performing readbacks.
-- The function returns false if the backing store was unavailable.
--
-- If the second callback form provides cols and rows the backing store has
-- a text representation available. In that case there is an additional
-- :read(x, y) = string, format_table function and a :cursor() = x, y for
-- querying the cursor.
--
-- The format_table returned by read uncludes colors as "fr, fg, fb" and "br,
-- bg, bb" as well as one or more of "bold", "italic", "inverse", "underline",
-- "underline_alt", "protect", "blink", "strikethrough", "break",
-- "border_left", "border_right", "border_down", "border_top", "id".
--
-- @note: methods and properties in *table* are described in define_calctarget.
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
