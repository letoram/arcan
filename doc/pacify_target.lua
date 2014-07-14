-- pacify_target
-- @short: Frees frameserver related resources.
-- @inargs: vid
-- @longdescr: By default, frameservers are freed when the
-- associated VID is deleted. In some circumstances however,
-- one might want to keep the VID and its internal state around,
-- but drop the frameserver related resources. For this purpose,
-- pacify_target can be used.
-- @note: calling pacify_target on a VID that is not associated
-- with an active frameserver is a terminal state transition.
-- @group: targetcontrol
-- @cfunction: targetpacify
-- @related:
function main()
#ifdef MAIN
	a = launch_avfeed("", "avfeed", function(source, status)
		if (status.kind == "resized") then
			show_image(source);
			resize_image(source, status.width, status.height);
			pacify_target(source);
		end
	end);
#endif

#ifdef ERROR1
	a = null_surface(64, 64);
	pacify_target(a);
#endif
end
