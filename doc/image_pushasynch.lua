-- image_pushasynch
-- @short: Blocks on an asynchronous load operation until it has completed.
-- @inargs: vid
-- @note: Since the exact point where an asynch image is transformed to an
-- image type isn't known in advance, this operation is allowed, but doesn't
-- perform any internal state changes for arguments other than VIDs in an
-- asynchronous loading state.  @group: image
-- @related: load_image_asynch, load_image
-- @cfunction: pushasynch
function main()
#ifdef MAIN
	b = load_image_asynch("test_big.png");
	a = load_image_asynch("test_small.png");
	show_image({a, b});
	image_pushasynch(a);
#endif
end
