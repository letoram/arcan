-- image_mipmap
-- @short: Forcetoggle image mipmap storage
-- @inargs: vid, state
-- @outargs:
-- @longdescr: Mipmapping is the common procedure of generating
-- multiple versions of the same image (typically at lower resolutions
-- for each "level") and letting the rendering subsystem determine
-- which version is the most suitable for the rendering operation at hand.
-- This usually saves on memory bandwidth at the cost of approximately
-- a third more memory consumption. This function enforces a certain
-- mipmap state for a video object. Some filtering methods,
-- FILTER_TRILINEAR in particular, relies on access to lower mipmap levels.
-- @note: This is a no-operation in memory conservative mode.
-- @note: The default mipmap state for all objects is determined
-- at compile time (ARCAN_VIDEO_DEFAULT_MIPMAP_STATE), with hardcoded
-- mipmap disable defaults for frameservers and for rendertarget storage.
-- @note: The engine does not currently support manually
-- generated mipmaps. These can be useful in some contexts,
-- particularly when dealing with texture compression or
-- when optimizing memory use through pre-pass analysis of
-- visibility with color-coded mipmap levels.
-- @note: This state transformation is costly with
-- non-trivially determined benefits. In order to reliably switch
-- openGL backend state, a new GL store needs to be created, thus
-- the raw texture data is copied and uploaded again.
-- @group: image
-- @cfunction: imagemipmap
-- @related:
function main()
#ifdef MAIN
	icon = load_image("test.png");
	props = image_surface_properties(icon);
	icon2 = null_surface(props.width, props.height);
	icon2 = image_sharestorage(icon, icon2);
	show_image({icon, icon2});

	resize_image(icon, props.width * 0.5, props.height * 0.5);
	resize_image(icon2, props.width * 0.5, props.height * 0.5);

	move_image(icon2, props.width, 0);
	image_mipmap(icon2, false);
	image_mipmap(icon, true);
#endif

#ifdef ERROR
	image_mipmap(WORLDID, "potatoe");
#endif
end
