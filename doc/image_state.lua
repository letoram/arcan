-- image_state
-- @short: Get a string representing the internal subtype of a video object.
-- @inargs: vid
-- @outargs: typestr
-- @longdescr: This is primarily intended for debugging / troubleshooting
-- purposes. Will output (frameserver, 3d object,
-- asynchronous state, 3d camera, unknown)
-- @group: image
-- @cfunction: imagestate
-- @related:

function main()
#ifdef MAIN
	local img = load_image("test.png");
	print(image_state(img));
#endif

#ifdef MAIN2
	local cam = null_surface(32, 32);
	camtag_model(cam);
	print(image_state(img));
#endif
end
