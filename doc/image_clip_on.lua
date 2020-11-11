-- image_clip_on
-- @short: Control clipping for a video object.
-- @inargs: vid:image
-- @inargs: vid:image, int:mode
-- @inargs: vid:image, int:mode=CLIP_SHALLOW, vid:cliptgt
-- @outargs:
-- @longdescr: This changes the clipping mode for the video object referenced
-- by *image*. By default the mode is CLIP_ON, which is the more expensive one.
-- It uses a stencil buffer to draw the entire hierarchy built using
-- ref:link_image. It is thus useful for complex hierarchies with possibly
-- rotated objects.
-- Another option is CLIP_SHALLOW. This only uses the immediate parent, and
-- will get a fast-path assuming that both objects are rotated as that can
-- be solved by adjusting object size and texture coordinates alone.
-- If a *cliptgt* is provided with the CLIP_SHALLOW clipping mode, a specific
-- object will be used for calculating the clipping bounds rather than using
-- the ref:link_image specified one. This is useful when a transform hierarchy
-- is needed, but with specific clipping anchors.
-- @note: If a clip target is set to a non-existing or otherwise bad object
-- or becomes invalid through deletion, clipping will revert to the image parent
-- as if no clip target had been specified.
-- @group: image
-- @cfunction: clipon
-- @related: image_clip_off
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(64, 64, 0, 255, 0);
	link_image(b, a);
	move_image(b, 32, 32);
	show_image({a,b});
	image_clip_on(b, CLIP_SHALLOW);
#endif
#ifdef ERROR
	image_clip_on(BADID);
#endif
end
