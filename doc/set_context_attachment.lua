-- set_context_attachment
-- @short: change the active attachment point for the current context
-- @inargs:
-- @inargs: vid
-- outargs: vid
-- @longdescr: By default, every newly created object is attached to the
-- world rendertarget that is refered to using WORLDID and newly created
-- rendertargets explicitly adopts source objects and attaches to itself.
-- In later stages of the lifecycle, objects can also be dynamically
-- attached and detached to one or more rendertargets
-- via the ref:attach_rendertarget and ref:detach_rendertarget commands
-- respectively. This may be overly verbose when many objects are to be
-- created and bound to an existing rendertarget and for those cases,
-- switching out the active context with this function is useful.
-- The returned vid is that of the previously active context video.
-- @note: Another case where the default attachment is important is when
-- different rendertargets have different target densities. Some objects
-- like text or vector images will have a backing store that is tied to the
-- density of its current primary attachment. By first having an implicit
-- attachment to WORLDID only to switch with ref:attach_rendertarget will cause
-- costly rerasterization which can be avoided with this function.
-- @note: The attachment is defined per context, so if the context stack is
-- switched using ref:push_video_context or ref:pop_video_context, the
-- attachment point will switch as well.
-- @note: providing a bad, missing or non-rt designated vid will
-- not change any default attachment state, only return the current one.
-- @errata(<0.6): Wrong vid was returned in the (vid) inargs form.
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
end
