-- pacify_target
-- @short: Sever frameserver connection from a video object
-- @inargs: vid:src
-- @inargs: vid:src, bool:mask
-- @longdescr: By default, frameservers are freed when the
-- associated video object is deleted. This behavior can be altered
-- through the use of this function in two different ways. One of
-- them is by converting the frameserver-tied object into a normal
-- one. In that case the client side is terminated, the event loop
-- handler is detached and nothing frameserver related functions
-- will cease to work. The other way is by setting the *mask* argument
-- to false (default is true). This will emulate a client initiated
-- termination, triggering the 'terminated' event handler. This can
-- be useful to trick the rest of your scripts that the client exited
-- normally, even if it did not.
-- @note: calling pacify_target on a vid that is not associated
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

#ifdef ERROR
	a = null_surface(64, 64);
	pacify_target(a);
#endif
end
