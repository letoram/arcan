-- resize_video_canvas
-- @short: Resize the virtual canvas drawing area
-- @inargs: neww, newh
-- @outargs:
-- @longdescr: By default, the drawing canvas is set to match the video
-- platform default output display (which, in turn, is controlled by the
-- command-line arguments) in a 1:1 ratio.
--
-- For multiple-screen configurations or situations where you want higher
-- rendering resolution than the default display, the canvas can be resized.
--
-- @note: This will affect any accelerated- mouse cursor as well,
-- where size and projection will be related to the ratio between the
-- canvas dimensions and those of the actual main output display,
-- use resize_cursor if this behavior is an issue.
-- @note: The global canvas size constants VRESW, VRESH will be changed
-- accordingly.
-- @note: If the canvas has previously been destroyed via delete_image(WORLID)
-- this function will restore/reallocate it.
-- @note: There are two major caveats with setting this property to large
-- values. One is that the canvas is used as a primary rendering target
-- that is then mapped to one or several output displays. There are, however,
-- hardware limitations on how large such surfaces can be and in such
-- cases, the resize operation will fail silently. The other is that this
-- can be used to circumvent texture size restrictions through creative
-- use of extpop/extpush contexts and image_sharestorage. If this is an issue,
-- dimension restrictions should be added in this function as well.
-- @group: vidsys
-- @cfunction: videocanvasrsz
-- @related: video_displaymodes, map_video_display
-- @flags:
function main()
#ifdef MAIN
	local img_1 = fill_surface(VRESW, VRESH, 255, 0, 0);
	local img_2 = fill_surface(100, 100, 0, 255, 0);

	move_image(img_2, VRESW * 2, VRESH * 2, 400);

	show_image({img_11, img_2});
	resize_video_canvas(VRESW * 4, VRESH * 4);
#endif

#ifdef ERROR
	resize_video_canvas(1024 * 1024 * 1024, 0);
#endif

#ifdef ERROR2
	resize_video_canvas(-1, -1);
#endif
end
