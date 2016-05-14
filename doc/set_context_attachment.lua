-- set_context_attachment
-- @short: change the active attachment point for the current context
-- @inargs: *newty*
-- outargs: *vid*
-- @longdescr: By default, every newly created object is attached to the
-- world rendertarget that is refered to using WORLDID and newly created
-- rendertargets explicitly adopts source objects and attaches to itself.
-- For later changes to a rendertarget, there are manual attach and detach
-- commands, but those become excessively verbose when a lot of new objects
-- are to be assigned to a rendertarget dynamically. For such purposes,
-- it is possible to change the default rendertarget for the current
-- context using this function.
-- @note: providing a bad, missing or non-rt designated vid will
-- not change any default attachment state, only return the current
-- @note: the default attachment is local to every context.
-- @group: vidsys
-- @cfunction: setdefattach
-- @related:
function main()
#ifdef MAIN
-- create an object that will be attached to world
	green = color_surface(64, 64, 0, 255, 0);
	show_image(green);

-- create the rendertarget that will be our new default
	rtgt = alloc_surface(VRESW, VRESH);
	define_rendertarget(rtgt, {null_surface(32, 32)});
	set_context_attachment(rtgt);

-- make the new rendertarget slowly spinning and scaled
-- to show that newly created are in fact attached correctly
	show_image(rtgt);
	resize_image(rtgt, VRESW * 0.5, VRESH * 0.5);
	move_image(rtgt, VRESW * 0.25, VRESH * 0.25);
	rotate_image(rtgt, 90, 500);

-- spawn some random blocks
	for i=1,10 do
		local b = color_surface(32, 32, 64, math.random(255), 64);
		show_image(b);
		move_image(b, math.random(VRESW - 32), math.random(VRESH - 32), 500);
	end
#endif

#ifdef ERROR1
	set_context_attachment(BADID);
#endif
end
