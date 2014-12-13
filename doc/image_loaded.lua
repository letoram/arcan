-- image_loaded
-- @short: Query the status of an asynchronous video object source.
-- @inargs: vid
-- @outargs: 0 or 1
-- @longdescr: For asynchronous image operations, the completion of a load can
-- potentially stall for an infinite time. This function queries the status of the
-- asynchronous load, and returns true (1) if the image has loaded and decoded successfully
-- or 0 if it is still in the process of being loaded.
-- @group: image
-- @cfunction: imageloaded
-- @related: load_image_asynch, image_pushasynch
-- @flags:
function main()
#ifdef MAIN
	a = load_image_asynch("test.png", function(source, status)
		print(status.kind, image_loaded(source)); end);
	print(a, image_loaded(source));
#endif
end
