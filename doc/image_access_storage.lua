-- image_access_storage
-- @short: Access the underlying backing store of a textured video object.
-- @inargs: vid, callback(tbl, w, h)
-- @outargs: true or false
-- @longdescr: This function permits limited, blocking, access to a backing
-- store. The primary purpose is to provide quick access to trivial measurements
-- without the overhead of setting up a calctarget and performing readbacks.
-- The function returns false if the backing store was unavailable.
-- @note: Specifying a vid with a non-textured backing store (color_surfaces,
-- ...) is a terminal state transition.
-- @note: For details on the format and use of *callback*,
-- see *define_calctarget*
-- @note: The table provided in callback is only valid during the execution of
-- the callback, providing references to it *will* result in a terminal state
-- transition that may be hard to debug properly.
-- @note: Most frameserver connections do not maintain a synch with the backing
-- store due to the increase in bandwidth. This can be changed by calling
-- target_flags and enable TARGET_VSTORE_SYNCH for the specific frameserver.
-- @note: The backing store of a texture video object is not always available,
-- particularly when the engine is running in conservative mode. Make sure that
-- appl behavior is not dependant on *callback* being triggered.
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
	img = color_surface(32, 32, 255, 0, 0);
	image_access_storage(img, function(tbl, w, h)
	end);
#endif

#ifdef ERROR3
	img = fill_surface(32, 32, 255, 0, 0);
	image_access_storage(a, image_access_storage);
#endif
end
