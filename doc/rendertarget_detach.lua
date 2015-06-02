-- rendertarget_detach
-- @short: Remove any secondary specific-object attachments from a rendertarget
-- @inargs: rtgt, vid
-- @longdescr: Functions that attach video objects to rendertargets through
-- rendertarget creation or dynamically allow the primary attachment
-- (responsible for life-cycle management and similar properties) of an object
-- to be modified. Using the RENDERTARGET_NODETACH, the same functions can
-- create secondary attachments wherein a video object will be processed for
-- multiple rendertargets. This function can be used to dynamically undo
-- secondary attachments.
-- @note: Attempting to modify primary rendertargets this way will fail
-- silently, use ref:rendertarget_attach or ref:delete_image functions for
-- dynamic primary rendertarget manipulation.
-- @note: Attempting to detach from rendertargets where the specified object
-- does not exist will not result in any state transitions.
-- @group: targetcontrol
-- @cfunction: renderdetach
-- @related:
function main()
#ifdef MAIN
	local rtgt = alloc_surface(64, 64);
	local obj_a = color_surface(32, 32, 0, 255, 0);
	rendertarget_attach(rtgt, obj_a, RENDERTARGET_NODETACH);
	show_image({rtgt, obj_a});
	move_image(rtgt, 64, 0);

	rendertarget_detach(rtgt, obj_a);
#endif
end
