-- relink_image
-- @short: Reassign and translate the property-space to be relative another object
-- @inargs: vid:id, vid:newparent
-- @inargs: vid:id, vid:newparent, int:panchor
-- @inargs: vid:id, vid:newparent, int:panchor, int:anchor_opt
-- @longdescr: This function is a specialized variant of ref:link_image, please
-- read the documentation for that function for a full description of the
-- arguments. The difference between the two is that this one preserves the
-- relative resolved world-space position between *id* and *newparent*.
-- With ref:link_image, if *id* is at 100,100 and *newparent* is at 100,100
-- the post-link world coordinate of *id* will be 200,200.
-- With *relink_image* the post-link world coordinate will be 100,100 and its
-- local properties will put it at 0,0. This is rougly equivalent to resolving
-- *id* and *newparent* before linking, calculating the relative position
-- difference and moving the object to the new position.
-- @group: image
-- @cfunction: linkimage
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	move_image(a, 100, 100)
	move_image(b, 110, 110)
	relink_image(b, a);
	show_image(b);
	blend_image(a, 1.0, 50);
	move_image(a, VRESW, VRESH, 100);
	rotate_image(a, 100, 100);
	expire_image(a, 100);
#endif
end
