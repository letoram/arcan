-- rendertarget_bind
-- @short: Rebind the association between encode segment and rendertarget
-- @inargs: vid:rt, vid:fsrv
-- @outargs:
-- @longdescr: A segment that is in output mode is normally tied to a rendertarget,
-- with the output buffer being populated by a readback/renderpass of the rendertarget.
-- For segments that have been allocated outside the normal ref:define_recordtarget
-- through explicitly allowing ref:target_alloc and ref:accept_target to create
-- output segments, these lack a rendertarget association and will thus not produce
-- any output, only work as event queues. For these edge cases, they can be rebound
-- to a rendertarget allocation.
-- @note: Rebinding a rendertarget to a non-encode segment is a terminal state
-- transition.
-- @note: After rebinding, the *fsrv* vid can be deleted as the underlying
-- frameserver connection is now bound to *rt*.
-- @group: targetcontrol
-- @cfunction: renderbind
-- @related:
function main()
#ifdef MAIN
	buf = alloc_surface(320, 200);
	a = color_surface(64, 64, 255, 0, 0);
	show_image(a);
	move_image(a, 64, 64, 100);
	move_image(a, 0, 0, 100);
	image_transform_cycle(a, true);
	define_rendertarget(buf, {a});

	cp = target_alloc("test",
	function(source, status)
		if status.kind == "registered" and status.segkind == "encoder" then
			rendertarget_bind(buf, source);
			delete_image(source);
		end
	end);
#endif

#ifdef ERROR1
	buf = alloc_surface(320, 200);
	cp = target_alloc("test", function() end);
	define_rendertarget(buf, cp);
#endif
end
