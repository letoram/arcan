-- show_image
-- @short: Change image opacity to 1.0
-- @inargs: vid, *time*
-- @longdescr: This is a specific case of the more general blend_image function
-- where the opacity argument has been hard-coded to 1.0 (opaque, visible,
-- default blendmode is disabled). This function accepts either single VIDs
-- or a group of VIDs packed in a n-indexed table.
-- @group: image
-- @cfunction: showimage
-- @alias: blend_image, hide_image
function main()
	a = fill_surface(128, 128, 255, 0, 0);
#ifdef MAIN
	show_image({a,b}, 100);
#endif

#ifdef ERROR
	show_image(a, 0.5, 100);
#endif
end
