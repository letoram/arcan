-- system_context_size
-- @short: Change the number of vids allowed at once in new contexts.
-- @inargs: newlim
-- @note: Accepted values for newlim is 0 < n <= 65536
-- @note: These changes will not effect the currently active context,
-- only those that gets activated when the current context is pushed or
-- when the outmost context is poped.
-- @note: Invalid context sizes is a terminal state transition.
-- @note: The default initial context size is set to 1k, which should be enough for everyone.
-- @longdescr: There is a low limit on the amount of video objects that
-- are allowed to be alive in a context. Attempts to allocate beyond this limit
-- is a terminal state transition, as a means of allowing early resource leak detection
-- and as a means of encouraging use of the context- stack to keep resource usage low.
-- @group: system
-- @cfunction: systemcontextsize
-- @flags:
function main()
#ifdef MAIN
	local a, b = current_context_usage();
	warning("current: " .. a);
	warning("requesting new size");
	system_context_size(64);

	a, b = current_context_usage();
	warning("current: " .. a);
	warning("poping");
	pop_video_context();

	a, b = current_context_usage();
	warning("current: " .. a);
#endif

#ifdef ERROR
	system_context_size(-10);
#endif

#ifdef ERROR2
	system_context_size(0);
#endif
end
