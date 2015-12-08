-- persist_image
-- @short: Flag the video object as video context persistant.
-- @inargs: vid
-- @outargs: bool
-- @longdescr: Some objects, and especially those linked to frameservers,
-- may need to survive otherwise aggressive operations like
-- ref:push_video_context. This function attempts to promote the
-- referenced object to such a state. This ability comes with several
-- restrictions however. In practice, objects that are linked, has a
-- frameset or in other ways maintain horizontal references (within
-- the same context) are prohibited from being flagged as persistant.
-- @group: image
-- @related: push_video_context, pop_video_context
-- @cfunction: imagepersist
function main()
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	show_image({a, b});

#ifdef MAIN
	assert(persist_image(a) == true);
	push_video_context();
#endif

#ifdef ERROR
	persist_image(a);
	push_video_context();
	delete_image(a);
#endif

#ifdef ERROR2
	persist_image(a);
	link_image(a, b);
#endif

#ifdef ERROR3
	persist_image(a);
	link_image(b, a);
#endif

#ifdef ERROR4
	persist_image(a);
	c = instance_image(a);
	push_video_context();
#endif
end
