-- image_access_storage
-- @short: Access the underlying backing store of a textured video object.
-- @inargs: vid, callback(table, width, height)
-- @outargs: true or false
-- @longdescr: This function permits limited, blocking, access to a backing
-- store. The primary purpose is to provide quick access to trivial measurements
-- without the overhead of setting up a calctarget and performing readbacks.
-- The function returns false if the backing store was unavailable.
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
